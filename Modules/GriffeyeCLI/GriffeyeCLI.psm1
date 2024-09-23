#Require -Version 7.3

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
    Justification='Mirrors the design of the Griffeye Connect CLI',
    Scope='Function',
    Target='Invoke-ConnectCLI*')]
param()


$script:ConnectCLIExeName = "magnet-griffeye-connect-cli.exe"


function Get-ConnectCLIException {
    param (
        [Diagnostics.Process]$Process
    )
    process {
        $Message = "Error {0}: {1}" -f $Process.ExitCode, $Process.StandardError.ReadToEnd()

        switch -exact ($Process.ExitCode) {
            100 {
                [System.ArgumentException] $Message
            }
            200 {
                [System.IO.FileNotFoundException] $Message
            }
            300 {
                [System.IO.IOException] $Message
            }
            default {
                [Exception] $Message
            }
        }
    }
}


<#
  .Synopsis
  Get the version information of Griffeye Connect CLI as a PSCustomObject.

  .Description
  Tests for existence and tries to execute Griffeye Connect CLI binary
  to find the version string and parse it into a PSCustomObject.

  .Parameter GriffeyeConnectPath
  Path to Griffeye Connect installation folder.
#>
function Get-ConnectCLIVersion {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory)]
        [ValidateScript({
            Test-Path (Join-Path $_ $ConnectCLIExeName) -PathType Leaf
        }, ErrorMessage="Griffeye Connect CLI not found in path {0}")]
        [string] $GriffeyeConnectPath
    )

    process {
        $Arguments = @{
            GriffeyeConnectPath = $GriffeyeConnectPath
            Command = "test"
            Verbose = $VerbosePreference -eq "Continue"
        }

        if (-not ((Invoke-ConnectCLI @Arguments) -match ".*Starting .* (?<Major>[0-9]*)\.(?<Minor>[0-9]*)\.(?<Fix>[0-9]*)\.(?<Build>[0-9]*).*")) {
            throw "Unable to parse output of Griffeye Connect CLI to find version"
        }
        [pscustomobject]@{
            Major = $Matches.Major
            Minor = $Matches.Minor
            Fix = $Matches.Fix
            Build = $Matches.Build
        }
    }
}


<#
  .Synopsis
  Wrapper for Griffeye Connect connect-cli.exe.

  .Description
  Powershell wrapper for connect-cli.exe. Takes the path to the Griffeye Connect
  installation folder, the command and corresponding parameters as a list.

  .Parameter GriffeyeConnectPath
  Path to the Griffeye Connect installation.

  .Parameter Command
  The Connect CLI command

  .Parameter ArgumentList
  List of strings to pass ass argument to Connect CLI.

  .Parameter GriffeyeUsername
  Use this as Username when connecting to Griffeye. If not specified, the username
  of the current user as found in the environment will be used.

  .Parameter GriffeyePassword
  Use this as password when connecting to Griffeye. If not specified, the credentials
  of the current user will be used (SPNEGO SSO).
#>
function Invoke-ConnectCLI {
    [CmdLetBinding(SupportsShouldProcess)]
    param(
        [parameter(Mandatory)]
        [ValidateScript({
            Test-Path (Join-Path $_ $ConnectCLIExeName) -PathType Leaf
        }, ErrorMessage="Griffeye Connect CLI not found in path {0}")]
        [string] $GriffeyeConnectPath,

        [string] $GriffeyeUsername,

        [string] $GriffeyePassword,

        [parameter(Mandatory)]
        [ValidateSet("test", "import")]
        [string] $Command,

        [string[]] $ArgumentList
    )

    process {
        $ProcessStartInfo = [Diagnostics.ProcessStartInfo]@{
            FileName               = Join-Path $GriffeyeConnectPath $ConnectCLIExeName
            UseShellExecute        = $false
            RedirectStandardError  = $true
            RedirectStandardOutput = $true
        }

        if ($Command -ne "test") {
            $ProcessStartInfo.Arguments = ($Command, ($ArgumentList -join " ")) -join " "
            $Target = ($ProcessStartInfo.FileName, $ProcessStartInfo.Arguments) -join " "
        } else {
            $Target = $ProcessStartInfo.FileName
        }

        if ($PSCmdlet.ShouldProcess($Target, "Execute")) {
            Write-Verbose ("Executing: {0}" -f $Target)

            if ($GriffeyeUsername) {
                $env:GRIFFEYE_USERNAME = $GriffeyeUsername
            } else {
                $env:GRIFFEYE_USERNAME = $env:USERNAME
            }

            if ($GriffeyePassword) {
                $env:GRIFFEYE_PASSWORD = $GriffeyePassword
            }

            $Process = [Diagnostics.Process]::new()
            $Process.StartInfo = $ProcessStartInfo
            $Process.Start() | Out-Null

            $Stdout = ""
            while ($Output = $Process.StandardOutput.ReadLine()) {
                $StdOut += $Output
                Write-Information $Output
            }

            $Process.WaitForExit()

            if ($Process.ExitCode -ne 0) {
                Write-Verbose ("Connect CLI exited with error code: {0}." -f $Process.ExitCode)
                throw (Get-ConnectCLIException $Process)
            }

            Write-Verbose "Connect CLI exited successfully."

            $StdOut
        }
    }
}


<#
  .Synopsis
  Run Griffeye CLI import.

  .Description
  Runs Griffeye CLI Import with given parameters. Help on parameters
  is included here but grabbed mostly from connect-cli import --help.

  .Parameter GriffeyeConnectPath
  Path to folder where Griffeye Connect is installed.

  .Parameter CaseIdentifier
  Name of the case.

  .Parameter ServerAdress
  Address, including port, of server to import case to. (I.e. an URL)

  .Parameter SourceId
  Source ID. For VICS cases, the source id will not be visible in the created
  case as the source ids from the VICS case will be used instead.

  .Parameter SourceType
  Source type.

  .Parameter SourcePath
  Path to source where file is located.

  .Parameter UploadFiles
  Upload media files to server before starting import.
  Not possible to use with Forensics Images.

  .Parameter SourceFiles
  Names of the files to import from path. Only for importing individual
  files from source-type "file".

  .Parameter IncludeVicsData
  What data to include from the vics export. Required for each vics source
  in import. Valid input is all, none or the data that should be included
  separated with comma. An example including all available data:
  tag,series,victimidentified,offenderidentified,distributed,comment,metadata,mediadescriptions

  .Parameter IncludeForensicImageDeletedFiles
  Required for each forensic image import. Boolean to set if deleted files
  on image should be included or not.

  .Parameter IncludeForensicImageOverwrittenFiles
  Required for each forensic image import. Boolean to set if overwritten
  files on image should be included or not.

  .Parameter VideoRecognitionService
  The name of the recognition service (as it is named on the server) to use for videos.

  .Parameter ImageRecognitionServices
  The names of the recognition services (as they are named on the server) to use
  for images. Names should be separated with comma, for example: "GFMS1,GFMS2"

  .Parameter ParallelUploads
  Allows you to upload files in parallel, using multiple threads.

  .Parameter PushToExisting
  If set to true, will update an existing case instead of creating a new one.

  .Parameter GriffeyeUsername
  Use this as Username when connecting to Griffeye. Defaults to the username
  of the current user.

  .Parameter GriffeyePassword
  Use this as password when connecting to Griffeye. If not specified, the credentials
  of the current user will be used (SPNEGO SSO).
#>
function Invoke-ConnectCLIImport {
    [CmdLetBinding(SupportsShouldProcess)]
    param(
        [parameter(Mandatory)]
        [string] $GriffeyeConnectPath,

        [parameter(Mandatory)]
        [string] $CaseIdentifier,

        [parameter(Mandatory)]
        [string] $ServerAddress,

        [parameter(Mandatory)]
        [string] $SourceId,

        [ValidateSet(
            "file",
            "folder",
            "forensic-image",
            "vics")]
        [string] $SourceType,

        [string] $SourcePath,

        [switch] $UploadFiles,

        [string[]] $SourceFiles,

        [ValidateSet(
            "none",
            "all",
            "tag",
            "series",
            "victimidentified",
            "offenderidentified",
            "distributed",
            "comment",
            "metadata",
            "mediadescriptions")]
        [string[]] $IncludeVicsData,

        [switch] $IncludeForensicImageDeletedFiles,

        [switch] $IncludeForensicImageOverwrittenFiles,

        [string] $VideoRecognitionService,

        [string[]] $ImageRecognitionServices,

        [int]$ParallelUploads = 1,

        [switch] $PushToExisting,

        [string] $GriffeyeUsername,

        [string] $GriffeyePassword
    )

    process {
        $ArgumentList = @()

        # Mandatory
        $ArgumentList += ("--server-address {0}" -f $ServerAddress)
        $ArgumentList += ("--case-identifier {0}" -f $CaseIdentifier)
        $ArgumentList += ("--source-id {0}" -f $SourceId)

        # Optional
        if ($UploadFiles) {
            $ArgumentList += "--upload-files"
        }

        if ($IncludeForensicImageDeletedFiles) {
            $ArgumentList += "--include-forensic-image-deleted-files"
        }

        if ($IncludeForensicImageOverwrittenFiles) {
            $ArgumentList += "--include-forensic-image-overwritten-files"
        }

        if ($PushToExisting) {
            $ArgumentList += "--push-to-existing true"
        }

        if ($SourceType) {
            $ArgumentList += ("--source-type {0}" -f $SourceType)
        }

        if ($SourcePath) {
            $ArgumentList += ("--source-path {0}" -f $SourcePath)
        }

        if ($VideoRecognitionService) {
            $ArgumentList += ("--video-recognition-service {0}" -f $VideoRecognitionService)
        }

        if ($ParallelUploads) {
            $ArgumentList += ("--parallel-uploads {0}" -f $ParallelUploads)
        }

        # Lists
        if ($SourceFiles) {
            $ArgumentList += ("--source-files {0}" -f ($SourceFiles -join ","))
        }

        if ($IncludeVicsData) {
            $ArgumentList += ("--include-vics-data {0}" -f ($IncludeVicsData -join ","))
        }

        if ($ImageRecognitionServices) {
            $ArgumentList += ("--source-files {0}" -f ($ImageRecognitionServices -join ","))
        }

        $Arguments = @{
            GriffeyeConnectPath = $GriffeyeConnectPath
            ArgumentList = $ArgumentList
            Command = "import"
        }

        if ($GriffeyeUsername) {
            $Arguments.GriffeyeUsername = $GriffeyeUsername
        }

        if ($GriffeyePassword) {
            $Arguments.GriffeyePassword = $GriffeyePassword
        }

        Invoke-ConnectCLI @Arguments | Out-Null
    }
}


Export-ModuleMember -Function Get-ConnectCLIVersion
Export-ModuleMember -Function Invoke-ConnectCLI
Export-ModuleMember -Function Invoke-ConnectCLIImport
