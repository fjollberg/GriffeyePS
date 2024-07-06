#Require -Version 7.3
#Require -Module GriffeyeJsonParser

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
    Justification='Some api endpoints use plural',
    Scope='Function',
    Target='Invoke-Griffeye*')]
param()


# Try to make sure an entry is in Vics 2.0 format.
function ConvertTo-Vics20Case {
    [OutputType([System.Collections.Specialized.OrderedDictionary])]

    [cmdletbinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline = $true)]
        [PSCustomObject]$Case
    )

    process {
        [ordered]@{
            '@odata.context' = 'http://github.com/VICSDATAMODEL/ProjectVic/DataModels/2.0.xml/CUSTOM/$metadata#Cases'
            value = @(
                @{
                    CaseID = $Case.CaseID
                    CaseNumber = $Case.CaseNumber
                    ContactEmail = $Case.ContactEmail ? $Case.ContactEmail : ""
                }
            )
        }
    }
}

# Try to make sure an entry is in Vics 2.0 format.
function ConvertTo-Vics20Media {
    [OutputType([System.Collections.Specialized.OrderedDictionary])]

    [cmdletbinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline = $true)]
        [PSCustomObject]$Media
    )
    process {
        [ordered]@{
            '@odata.context' = 'http://github.com/VICSDATAMODEL/ProjectVic/DataModels/2.0.xml/CUSTOM/$metadata#Media'
            value = @(
                @{
                    MediaID = $Media.MediaID
                    MD5 = $Media.MD5
                    SHA1 = $Media.SHA1 ? $Media.SHA1 : ""
                    PhotoDNA = $Media.PhotoDNA ? $Media.PhotoDNA : ""
                    RelativeFilePath = $Media.RelativeFilePath
                    MediaFiles = $Media.MediaFiles
                }
            )
        }
    }
}


<#
  .Synopsis
  Convert a Griffeye API token to a secure token to use with this API.

  .Description
  Convenience method to convert a token from a Griffeye ApiToken response to a
  token with securestrings as suiting for Invoke-RestRequest calls.

  .Parameter PlainToken
  Plain text token as returned by the Griffeye server.

  .Outputs
  A PSCustomObject with a representation of the token using SecureStrings.
#>
function ConvertTo-SecureToken {
    [cmdletbinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline = $true)]
        [PSCustomObject]$PlainToken
    )
    process {
        [PScustomObject]@{
            TokenType = $PlainToken.token_type
            AccessToken = $PlainToken.access_token | ConvertTo-SecureString -AsPlainText
            Expires = (Get-Date).AddSeconds($PlainToken.expires_in)
            RefreshToken = $PlainToken.refresh_token | ConvertTo-SecureString -AsPlainText
        }
    }
}


<#
  .Synopsis
  Get Griffeye server information.

  .Description
  Get Griffeye server information. This is an unauthenticated request
  and can be used to test connectivity.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Outputs
  A PSCustomObject with server information.

  .Example
    $ApiBaseURL = https://myserver.mydomain:17000/api
    Invoke-GriffeyeServerInfo -ApiBaseURL $ApiBaseURL
#>
function Invoke-GriffeyeServerInfo {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL
    )
    process {
        $URL = $ApiBaseURL + "/serverinfo"
        Write-Verbose ("Calling: {0}" -f $URL)
        Invoke-RestMethod -Method GET $URL
    }
}


<#
  .Synopsis
  Get a Griffeye API Oauth token.

  .Description
  Get a Griffeye API Oauth token to use with subsequent requests. This method
  currently only supports the 'password' grant type of the Griffeye API.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter PasswordGrant
  Make a password grant request with username and password supplied as a Credential.

  .Parameter Credential
  A PSCredential object with user name and password as created with New-Credential.

  .Parameter Refresh
  Refresh an existing token.

  .Parameter Token
  A token object to refresh, as previously return by Invoke-GriffeyeToken.

  .Parameter ClientCredentialsGrant
  Make a client_credentials grant request. Client tokens have longer lifetime but are
  not renewable.

  .Parameter ClientID
  The client ID to use with a client_credentials grant request.

  .Parameter ClientSecret
  The client secret to use with a client_credentials grant request.

  .Outputs
  A PSCustomObject containing the token to use in API requests.

  .Example
    $Credential = Get-Credential
    $ApiBaseURL = https://myserver.mydomain:17000/api
    Invoke-GriffeyeToken -ApiBaseURL $ApiBaseUrl -PasswordGrant -Credential $Credential
#>
function Invoke-GriffeyeToken {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL,

        [parameter(Mandatory, ParameterSetName = 'password')]
        [switch]$PasswordGrant,

        [parameter(Mandatory, ParameterSetName = 'password')]
        [PSCredential]$Credential,

        [parameter(Mandatory, ParameterSetName = 'refresh')]
        [switch]$Refresh,

        [parameter(Mandatory, ParameterSetName = 'refresh')]
        [PSCustomObject]$Token,

        [parameter(Mandatory, ParameterSetName = 'client_credentials')]
        [switch]$ClientCredentialsGrant,

        [parameter(Mandatory, ParameterSetName = 'client_credentials')]
        [String]$ClientID,

        [parameter(Mandatory, ParameterSetName = 'client_credentials')]
        [String]$ClientSecret
    )

    process {
        $URL = $ApiBaseURL + "/oauth2/token"
        if ($PasswordGrant) {
            $Body = @{
                grant_type = "password"
                username = [System.Web.HttpUtility]::UrlEncode($Credential.Username)
                password = [System.Web.HttpUtility]::UrlEncode(($Credential.Password | ConvertFrom-SecureString -AsPlainText))
            }
        } elseif ($Refresh) {
            $Body = @{
                grant_type = "refresh_token"
                refresh_token = $Token.RefreshToken | ConvertFrom-SecureString -AsPlainText
            }
        } elseif ($ClientCredentialsGrant) {
            # Note: this code is not verified.
            $Body = @{
                grant_type = "client_credentials"
                client_id = [System.Web.HttpUtility]::UrlEncode($ClientID)
                client_secret = [System.Web.HttpUtility]::UrlEncode($ClientSecret)
            }
        } else {
            throw "Unknown authentication method."
        }
        Write-Verbose ("Calling: {0}" -f $URL)
        Write-Verbose ("Body: {0}" -f $Body)
        Invoke-RestMethod -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded' $URL | ConvertTo-SecureToken
    }
}


<#
  .Synopsis
  Get a, possibly filtered, list of Griffeye cases on server.

  .Description
  See Griffeye API documentation for specifics about the behavior of
  matching cases for this api.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter Token
  A Token object as retrieved by Invoke-GriffeyeToken.

  .Parameter FilterField
  The name of the field to filter on.

  .Parameter FilterValue
  The value of the field for matching cases.

  .Parameter Include
  List of fields to include in reponse.

  .Outputs
  A list of matching cases with parameters as specified.

  .Example
    $Credential = Get-Credential
    $ApiBaseURL = https://myserver.mydomain:17000/api
    $Token = Invoke-GriffeyeToken -ApiBaseURL $ApiBaseUrl -Credential $Credential
    Invoke-GriffeyeCases -ApiBaseURL $ApiBaseURL -Token $Token -Include id, name, identifier, status

    Id Name            Identifier                           Status
    -- ----            ----------                           ------
    3  5000-K123456-24 712ff83c-3123-4fab-8ff6-33532f4915c2 Ready
    4  Björklöven      a77ff3f2-205d-4230-854d-d915c890c91c Ready
    ...
#>
function Invoke-GriffeyeCases {
    [cmdletbinding(DefaultParameterSetName = 'Common')]
    param (
        [parameter(Mandatory, ParameterSetName = 'Common')]
        [parameter(Mandatory, ParameterSetName = 'Filter')]
        [string]$ApiBaseURL,

        [parameter(Mandatory, ParameterSetName = 'Common')]
        [parameter(Mandatory, ParameterSetName = 'Filter')]
        [PSCustomObject]$Token,

        [parameter(Mandatory, ParameterSetName = 'Filter')]
        [ValidateSet("name", "identifier", "status", "id", "accessrights")]
        [string]$FilterField,

        [parameter(Mandatory, ParameterSetName = 'Filter')]
        [ValidateNotNullOrEmpty()]
        [string]$FilterValue,

        [parameter(Mandatory = $false, ParameterSetName = 'Common')]
        [parameter(Mandatory = $false, ParameterSetName = 'Filter')]
        [ValidateSet("name", "identifier", "status", "id", "accessrights", "*")]
        [string[]]$Include = ("name", "identifier")
    )
    process {
        $URL = $ApiBaseURL + ("/cases?include={0}{1}" -f
            [System.Web.HttpUtility]::UrlEncode($Include -join ","),
            ($FilterField ? ('&filter={0}' -f [System.Web.HttpUtility]::UrlEncode(('equals({0}, "{1}")' -f $FilterField, $FilterValue))) : "")
        )

        Write-Verbose ("Calling: {0}" -f $URL)
        Invoke-RestMethod -Method GET -Authentication Bearer -Token $Token.AccessToken $URL
    }
}


<#
  .Synopsis
  Initialize a case on the server.

  .Description
  Intializes a case for upload of media files etc.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter Token
  A Token object as retrieved by Invoke-GriffeyeToken.

  .Parameter Case
  A PSCustomObject with properties corresponding to case metadata
  as in the VICS 2.0 format, e.g. created from a Vics JSON file by
  GriffeyeJsonParser::Get-GriffeyeMetadataObjectFromVics
  http://github.com/VICSDATAMODEL/ProjectVic/DataModels/2.0.xml/CUSTOM/$metadata#Cases

  .Parameter Reopen
  Reopens an existing case for updates.

  .Parameter ParseUserFromCaseContactEmail
  If true, the user who should create the case will be parsed from the email address
  specified in the ContactEmail property.

  .Example
    $Credential = Get-Credential
    $ApiBaseURL = https://myserver.mydomain:17000/api
    $Token = Invoke-GriffeyeToken -ApiBaseURL $ApiBaseUrl -Credential $Credential
    $Case = @{
    CaseID = "c18c57e5-f67f-4ec6-8c8b-0ab65a654a23"
    CaseNumber = "Demoärende3"
    ContactEmail = ""
    }
    Invoke-GriffeyeInitializeCase -ApiBaseURL $ApiBaseURL -Token $Token -Case $Case -Reopen
#>
function Invoke-GriffeyeInitializeCase {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL,

        [parameter(Mandatory)]
        [PSCustomObject]$Token,

        [parameter(Mandatory)]
        [PSCustomObject]$Case,

        [parameter(Mandatory = $false)]
        [switch]$Reopen,

        [parameter(Mandatory = $false)]
        [switch]$ParseUserFromCaseContactEmail
    )
    process {
        $URL = $ApiBaseURL + ("/upload/initializecase?version=2.0{0}{1}" -f
            ($Reopen ? "&reopen=true" : ""),
            ($ParseUserFromCaseContactEmail ? "&parseUserFromCaseContactEmail=true" : "")
        )
        $Body = $Case | ConvertTo-Vics20Case | ConvertTo-Json -Depth 10 -Compress
        Write-Verbose ("Calling: {0}" -f $URL)
        Write-Verbose ("Body: {0}" -f $Body)
        Invoke-RestMethod -Method Post -Authentication Bearer -Token $Token.AccessToken -Body $Body -ContentType "application/json; charset=utf-8" $URL | Out-Null
    }
}


<#
  .Synopsis
  Initialize a file upload to a case on the server.

  .Description
  Intializes a file upload to a case on the server for subsequent
  upload of actual file data.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter Token
  A Token object as retrieved by Invoke-GriffeyeToken

  .Parameter Media
  A PSCustomObject with properties corresponding to Media metadata, e.g.,
  created from a Vics JSON file by GriffeyeJsonParser::Get-GriffeyeMediaFromVics.

  .Parameter CaseID
  CaseID (guid) that the file should be associated with. If not
  specified the file will be uploaded as unattached media and the
  returned FileID should be used in the subsequent upload.

  .Example
    $Credential = Get-Credential
    $ApiBaseURL = https://myserver.mydomain:17000/api
    $Token = Invoke-GriffeyeToken -ApiBaseURL $ApiBaseUrl -Credential $Credential
    $Media = Get-GriffeyeMediaFromVics -Path "c:\some-path\file.json" | Select-Object -First 1
    Invoke-GriffeyeInitializeFile -APIBaseUrl $APIBaseUrl -Token $Token -Media $Media -CaseId "c18c57e5-f67f-4ec6-8c8b-0ab65a654a23"
#>
function Invoke-GriffeyeInitializeFile {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL,

        [parameter(Mandatory)]
        [PSCustomObject]$Token,

        [parameter(Mandatory)]
        [PSCustomObject]$Media,

        [parameter(Mandatory = $false)]
        [string]$CaseID
    )
    process {
        if ($CaseID) {
            $URL = $ApiBaseURL + ("/upload/initializefile?version=2.0&md5={0}&caseIdentifier={1}" -f
                [System.Web.HttpUtility]::UrlEncode($Media.MD5),
                [System.Web.HttpUtility]::UrlEncode($CaseID))
        } else {
            $URL = $ApiBaseURL + ("/upload/initializefile?version=2.0&md5={0}" -f
                [System.Web.HttpUtility]::UrlEncode($Media.MD5))
        }
        $Body = $Media | ConvertTo-Vics20Media | ConvertTo-Json -Depth 10 -Compress
        Write-Verbose ("Calling: {0}" -f $URL)
        Write-Verbose ("Body: {0}" -f $Body)
        Invoke-RestMethod -Method Post -Authentication Bearer -Token $Token.AccessToken -Body $Body -ContentType "application/json; charset=utf-8" $URL | Out-Null
    }
}


<#
  .Synopsis
  Finalize upload of file.

  .Description
  Cleans up after upload of file.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter Token
  Authentication token as returned by Invoke-GriffeyeToken.

  .Parameter MD5
  MD5 checksum of file.

  .Parameter CaseID
  CaseID (guid) of case file is associated with.

  .Parameter FileID
  FileID (guid) of file if not associated with a case.

  .Parameter GetResponse
  Forces server to synchronosly calculate results and return them.

  .Parameter version
  Version of format of response if GetResponse is set.
#>
function Invoke-GriffeyeFinalizeFile {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL,

        [parameter(Mandatory)]
        [PSCustomObject]$Token,

        [parameter(Mandatory)]
        [string]$MD5,

        [parameter(Mandatory, ParameterSetName = 'CaseId')]
        [string]$CaseID,

        [parameter(Mandatory, ParameterSetName = 'FileId')]
        [string]$FileID,

        [parameter(Mandatory = $false)]
        [switch]$GetResponse,

        [parameter(Mandatory = $false)]
        [string]$version = "2.0"
    )
    process {
        $URL = $ApiBaseURL + ("/upload/finalizefile?md5={0}{1}{2}{3}" -f
            [System.Web.HttpUtility]::UrlEncode($MD5),
            ($CaseID ? ("&caseIdentifier={0}" -f [System.Web.HttpUtility]::UrlEncode($CaseID)) : ""),
            ($FileID ? ("&fileIdentifier={0}" -f [System.Web.HttpUtility]::UrlEncode($FileID)): ""),
            ($GetResponse ? ("&getResponse=true&version={0}" -f [System.Web.HttpUtility]::UrlEncode($version)) : "")
        )
        Write-Verbose ("Calling: {0}" -f $URL)
        Invoke-RestMethod -Method Post -Authentication Bearer -Token $Token.AccessToken $URL | Out-Null
    }
}


<#
  .Synopsis
  Finalize upload of case.

  .Description
  Cleans up after upload of case.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter Token
  Authentication token as returned by Invoke-GriffeyeToken.

  .Parameter CaseID
  CaseID (guid) of case to finalize
#>
function Invoke-GriffeyeFinalizeCase {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL,

        [parameter(Mandatory)]
        [PSCustomObject]$Token,

        [parameter(Mandatory)]
        [string]$CaseID
    )
    process {
        $URL = $ApiBaseURL + ("/upload/finalizecase?caseIdentifier={0}" -f
            [System.Web.HttpUtility]::UrlEncode($CaseID)
        )
        Write-Verbose ("Calling: {0}" -f $URL)
        Invoke-RestMethod -Method Post -Authentication Bearer -Token $Token.AccessToken $URL | Out-Null
    }
}


<#
  .Synopsis
  Clear unfinalized uploads for specified case.

  .Description
  Clear unfinalized uploads for specified case using the Griffeye REST API.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter Token
  Authentication token as returned by Invoke-GriffeyeToken.

  .Parameter CaseID
  CaseID (guid) of case to clear uploads for.

  .Example
    $Credential = Get-Credential
    $ApiBaseURL = https://myserver.mydomain:17000/api
    $Token = Invoke-GriffeyeToken $ApiBaseURL $Credential
    Invoke-GriffeyeClearUnfinalizedUploads -ApiBaseURL $ApiBaseURL -Token $Token -CaseID 302f0955-b852-448f-a995-4d075219fc18
#>
function Invoke-GriffeyeClearUnfinalizedUploads {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL,

        [parameter(Mandatory)]
        [PSCustomObject]$Token,

        [parameter(Mandatory)]
        [string]$CaseID
    )
    process {
        $URL = $ApiBaseURL + ("/cases/{0}/clearunfinalizeduploads" -f
            [System.Web.HttpUtility]::UrlEncode($CaseID))
        Write-Verbose ("Calling: {0}" -f $URL)
        Invoke-RestMethod -Method Put -Authentication Bearer -Token $Token.AccessToken $URL | Out-Null
    }
}


<#
  .Synopsis
  Upload a data chunk of a file.

  .Description
  Uploads a single chunk of a file. Must be called as many times
  as necessary in order to complete the file upload depending on
  the chosen Chunksize, see Invoke-GriffeyeUploadMedia.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter Token
  Authentication token as returned by Invoke-GriffeyeToken.

  .Parameter MD5
  MD5 checksum of file.

  .Parameter CaseID
  CaseID (guid) of case file is associated with.

  .Parameter FileID
  FileID (guid) of file if not associated with a case.

  .Parameter Offset
  The byte offset of the uploaded chunk.

  .Parameter Chunk
  The byte array with the actual file data.

  .Example
    $File = Get-Item (Join-Path $Path $Media.RelativeFilePath) -ErrorAction Stop
    $Chunk = New-Object byte[] $Chunksize
    [long]$BytesRead = 0

    try {
        $FileStream = [System.IO.File]::OpenRead($File)
        while ([long]$Bytes = $FileStream.Read($Chunk, 0, $Chunksize) ){
            Invoke-GriffeyeFileChunk -ApiBaseURL $ApiBaseURL -Token $Token -CaseID $CaseID -MD5 $Media.MD5 -Offset $BytesRead -Chunk $Chunk[0..($Bytes-1)]
            $BytesRead += $Bytes
        }
    }
    finally {
        $FileStream.Close()
    }

#>
function Invoke-GriffeyeFileChunk {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL,

        [parameter(Mandatory)]
        [PSCustomObject]$Token,

        [parameter(Mandatory, ParameterSetName = 'CaseId')]
        [string]$CaseID,

        [parameter(Mandatory, ParameterSetName = 'FileId')]
        [string]$FileID,

        [parameter(Mandatory)]
        [string]$MD5,

        [parameter(Mandatory)]
        [long]$Offset,

        [parameter(Mandatory)]
        [byte[]]$Chunk
    )
    process {
        if ($CaseID) {
            $URL = $ApiBaseURL + ("/upload/filechunk?caseIdentifier={0}&md5={1}&offset={2}" -f
                [System.Web.HttpUtility]::UrlEncode($CaseID),
                [System.Web.HttpUtility]::UrlEncode($MD5),
                [System.Web.HttpUtility]::UrlEncode($Offset)
            )
        } else {
            $URL = $ApiBaseURL + ("/upload/filechunk?fileIdentifier={0}&md5={1}&offset={2}" -f
                [System.Web.HttpUtility]::UrlEncode($FileID),
                [System.Web.HttpUtility]::UrlEncode($MD5),
                [System.Web.HttpUtility]::UrlEncode($Offset)
        )
        }
        Write-Verbose ("Calling: {0}" -f $URL)
        Invoke-RestMethod -Method Post -Authentication Bearer -Token $Token.AccessToken -Body $Chunk -ContentType "application/binary" $URL | Out-Null
    }
}


<#
  .Synopsis
  Uploads the file defined by a Griffeye VICS media entry.

  .Description
  This is a wrapper method that does not correspond directly to an interface method
  of the Griffeye API.

  It intializes with Invoke-GriffeyeInitializeFile, uploads a file by reapeatedly
  calling Invoke-GriffeyeFileChunk as many times as needed to upload the entire
  file, and finally finalizes the file upload with Invoke-GriffeyeFinalizeFile.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter Token
  Authentication token as returned by Invoke-GriffeyeToken.

  .Parameter CaseID
  CaseID (guid) of case to clear uploads for.

  .Parameter Media
  An object describing the media to upload in VICS Json 2.0 format:
  http://github.com/VICSDATAMODEL/ProjectVic/DataModels/2.0.xml/CUSTOM/$metadata#Media

  .Parameter Path
  The base path of the media folder in which to find file data using
  the relative path information in the Media object.

  .Parameter Chunksize
  The size in bytes of chunks to upload.

  .Parameter ShowStats
  Emits an object with size and duration of the upload.
    MediaId: id of media entry.
    Bytes: size of media in bytes.
    DurationMillis: duration of upload in milliseconds.
    BytesPerSecond: speed of transfer in bytes per second.
#>
function Invoke-GriffeyeUploadMedia {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL,

        [parameter(Mandatory)]
        [PSCustomObject]$Token,

        [parameter(Mandatory)]
        [string]$CaseID,

        [parameter(Mandatory)]
        [PSCustomObject]$Media,

        [parameter(Mandatory)]
        [string]$Path,

        [parameter(Mandatory = $false)]
        [long]$Chunksize = 1MB,

        [parameter(Mandatory = $false)]
        [switch]$ShowStats
    )
    process {
        $File = Get-Item (Join-Path $Path $Media.RelativeFilePath) -ErrorAction Stop
        $Chunk = [System.Byte[]]::new($Chunksize)
        [long]$BytesRead = 0

        try {
            $Start = Get-Date
            $FileStream = New-Object -TypeName IO.FileStream -ArgumentList ($File, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, $Chunksize)

            Invoke-GriffeyeInitializeFile -ApiBaseURL $ApiBaseURL -Token $Token -CaseId $CaseID -Media $Media

            while ([long]$Bytes = $FileStream.Read($Chunk, 0, $Chunksize)){
                Invoke-GriffeyeFileChunk -ApiBaseURL $ApiBaseURL -Token $Token -CaseID $CaseID -MD5 $Media.MD5 -Offset $BytesRead -Chunk $Chunk[0..($Bytes-1)] -ErrorAction Stop
                $BytesRead += $Bytes
            }

            Invoke-GriffeyeFinalizeFile -ApiBaseURL $ApiBaseURL -Token $Token -MD5 $Media.MD5 -CaseID $CaseID -ErrorAction Stop

            if ($ShowStats) {
                $Duration = (New-Timespan -Start $Start -End (Get-Date)).TotalMilliseconds
                [PSCustomObject]@{
                    MediaId = $Media.MediaID
                    Bytes = $BytesRead
                    DurationMillis = [Math]::round($Duration)
                    BytesPerSecond = [Math]::round(1000 * $Bytes / $Duration)
                }
            }
        }
        finally {
            $FileStream.Close()
            $FileStream.Dispose()
        }
    }
}


<#
  .Synopsis
  Uploads a complete VICS report to a Griffeye Analyze CS server.

  .Description
  This is a wrapper method that does not correspond directly to an interface method
  of the Griffeye API. It opens or creates a case as specified in the VICS JSON
  metadata file and uploads all the media found to a Griffeye Analyze CS server.

  A fair WARNING; The method uses the GriffeyeJsonParser module to effectively parse
  large VICS JSON files. It makes some assumptions about VICS report formats that
  may, or may not be correct. I have not made a thorough analyzis of the
  specifications, and I obviously don't use the XML DTDs to generate format handlers,
  as you might do in some other programming languages, but it appears to work with
  the real word examples I have so far.

  Chunksize and threads of uploads can be tuned with parameters.

  .Parameter ApiBaseURL
  Base URL for the Griffeye API (up to and including /api).

  .Parameter Credential
  A username/password credential to use when authenticating to the server.

  .Parameter Path
  Path to the VICS JSON metadata file.

  .Parameter Chunksize
  The size in bytes of chunks for uploads.

  .Parameter Threads
  Maximum number of threads to use for parallell uploads. Useful
  to set to a single thread when debugging.

  .Parameter ShowStats
  Emits an object with several measurements regarding size and time:
    Count: number of objects.
    Bytes: total number of bytes uploaded.
    MinimumBytes: smallest item uploaded in bytes.
    MaximumBytes: largest item uploaded in bytes.
    AverageBytes: average size in bytes.
    DurationMillis: sum of all upload durations in milliseconds.
    MinimumDurationMillis: shortest duration of an upload in milliseconds.
    MaximumDurationMillis: longest duration of an upload in milliseconds.
    AverageDurationMillis: average duration of uploads in milliseconds.
    TotalDurationMillis: total duration from start to end in milliseconds.
    TotalBytesPerSecond: total transfer speed in bytes per seconds.

  .Outputs
  Object with statistics as described above if -Showstats is set.

  .Example
    $ApiBaseURL = https://myserver.mydomain:17000/api
    $Credential = Get-Credential `
        -Title "Griffeye API Authentication" `
        -Message "Please enter the password grant username and password"

    Invoke-GriffeyeVicsReportUpload -ApiBaseURL $ApiBaseURL -Credential $Credential -Path "c:\somepath\some-vics.json"
#>
function Invoke-GriffeyeVicsReportUpload {
    [cmdletbinding()]
    param (
        [parameter(Mandatory)]
        [string]$ApiBaseURL,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential] $Credential,

        [parameter(Mandatory)]
        [string]$Path,

        [parameter(Mandatory = $false)]
        [int]$Chunksize = 10MB,

        [parameter(Mandatory = $false)]
        [int]$Threads = 10,

        [parameter(Mandatory = $false)]
        [switch]$ShowStats
    )

    Import-Module GriffeyeJsonParser -ErrorAction Stop

    $VicsJsonFile = Get-Item $Path -ErrorAction Stop

    function PercentComplete([hashtable]$Context) {
        if ($Context.TotalMediaFiles) {
            [Math]::floor(($Context.UploadedFiles / $Context.TotalMediaFiles) * 100)
        } else {
            0
        }
    }


    try {
        # Synchronized context to share in threads.
        $Context = [hashtable]::Synchronized(@{
            Token = Invoke-GriffeyeToken -ApiBaseURL $ApiBaseURL -PasswordGrant -Credential $Credential
            TotalMediaFiles = [long]0
            UploadedFiles = [long]0
            CurrentMedia = $null
        })

        $ServerInfo = Invoke-GriffeyeServerInfo -ApiBaseURL $ApiBaseURL
        Write-Information ("Server version: {0}.{1}.{2}" -f $ServerInfo.serverVersion.major, $ServerInfo.serverVersion.minor, $ServerInfo.serverVersion.build)

        Write-Information "Starting token refresh job."
        $RefreshTokenJob = Start-ThreadJob -ScriptBlock {
            # PS scope issue work around
            $DebugPreference = $using:DebugPreference
            $VerbosePreference = $using:VerbosePreference
            $InformationPreference = $using:InformationPreference

            do {
                Start-Sleep -Duration (New-TimeSpan -End (($using:Context).token.Expires).AddSeconds(-60))
                Write-Information "Refreshing authentication token."
                ($using:Context).token = Invoke-GriffeyeToken -ApiBaseURL $using:ApiBaseURL -Refresh -Token ($using:Context).token
            } while ($true)
        }

        Write-Progress -Activity "Griffeye Vics Report Upload" -Status "Initializing" -CurrentOperation "Getting case metadata" -PercentComplete (PercentComplete($Context))
        Write-Information "Getting Case metadata from Vics JSON."
        $vicsCase = Get-GriffeyeMetadataObjectFromVics -Path $VicsJsonFile.FullName CaseID, CaseNumber, TotalMediaFiles, ContactEmail -ErrorAction Continue
        $Context.TotalMediaFiles += $vicsCase.TotalMediaFiles

        Write-Information "Initializing or reopening case."
        Write-Progress -Activity "Griffeye Vics Report Upload" -Status "Initializing" -CurrentOperation "Initializing case" -PercentComplete (PercentComplete($Context))
        try {
            if ($vicsCase.ContactEmail) {
                Invoke-GriffeyeInitializeCase -ApiBaseURL $ApiBaseURL -Token $Context.token -Case $vicsCase -Reopen -ParseUserFromCaseContactEmail
            } else {
                Invoke-GriffeyeInitializeCase -ApiBaseURL $ApiBaseURL -Token $Context.token -Case $vicsCase -Reopen
            }
        } catch {
            if ($_.Exception.Response?.StatusCode -in (409)) {
                Write-Verbose ("Case already exists.")
            } else {
                throw $_
            }
        }

        Write-Progress -Activity "Griffeye Vics Report Upload" -Status "Intializing" -CurrentOperation "Retrieving Case ID" -PercentComplete (PercentComplete($Context))

        Write-Information "Getting case identifier."
        $Case = Invoke-GriffeyeCases -ApiBaseURL $ApiBaseURL -Token $Context.token -FilterField "name" -FilterValue $vicsCase.CaseNumber
        if (-not $Case) {
            $ConflictingCase = Invoke-GriffeyeCases -ApiBaseURL $ApiBaseURL -Token $Context.token -FilterField "identifier" -FilterValue $vicsCase.CaseID -Include identifier, name
            if ($ConflictingCase) {
                throw ("Conflict when intializing case. CaseNumber '{0}' has same CaseID as '{1}'." -f $vicsCase.CaseNumber, $ConflictingCase.Name)
            } else {
                throw ("Case '{0}' cannot be found, unknown reason." -f $vicsCase.CaseNumber)
            }
        }

        # Clean up any previous remains of broken imports.
        Invoke-GriffeyeClearUnfinalizedUploads -ApiBaseURL $ApiBaseURL -Token $Context.token -CaseID $Case.Identifier -ErrorAction Ignore

        $Start = Get-Date

        $Res = New-Object System.Collections.ArrayList

        Write-Progress -Activity "Griffeye Vics Report Upload" -Status "Uploading" -CurrentOperation "Starting" -PercentComplete (PercentComplete($Context))
        Write-Information ("Uploading media data with {0} threads in {1} byte chunks." -f $Threads, $Chunksize)

        $UploadJob = Get-GriffeyeMediaFromVics $VicsJsonFile | Foreach-Object -AsJob -ThrottleLimit $Threads -Parallel {
            $Media = $_

            Import-Module GriffeyeAPI

            # PS scope issue work around
            $DebugPreference = $using:DebugPreference
            $VerbosePreference = $using:VerbosePreference
            $InformationPreference = $using:InformationPreference

            try {
                $File = Get-Item (Join-Path ($using:VicsJsonFile).Directory $Media.RelativeFilePath)
                $Chunk = [System.Byte[]]::new($using:Chunksize)
                [long]$BytesRead = 0

                ($using:Context).CurrentMedia = $Media.MediaID

                $Start = Get-Date
                $FileStream = New-Object -TypeName IO.FileStream -ArgumentList ($File, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, $using:Chunksize)

                Invoke-GriffeyeInitializeFile -ApiBaseURL $using:ApiBaseURL -Token ($using:Context).token -CaseId ($using:Case).Identifier -Media $Media

                while ([long]$Bytes = $FileStream.Read($Chunk, 0, $using:Chunksize)){
                    Invoke-GriffeyeFileChunk -ApiBaseURL $using:ApiBaseURL -Token ($using:Context).token -CaseID ($using:Case).Identifier -MD5 $Media.MD5 -Offset $BytesRead -Chunk $Chunk[0..($Bytes-1)] -ErrorAction Stop
                    $BytesRead += $Bytes
                }

                Invoke-GriffeyeFinalizeFile -ApiBaseURL $using:ApiBaseURL -Token ($using:Context).token -MD5 $Media.MD5 -CaseID ($using:Case).Identifier -ErrorAction Stop

                $Duration = (New-Timespan -Start $Start -End (Get-Date)).TotalMilliseconds
                [PSCustomObject]@{
                    Bytes = $BytesRead
                    DurationMillis = [Math]::round($Duration)
                    BytesPerSecond = [Math]::round(1000 * $Bytes / $Duration)
                }
            } catch {
                if ($_.Exception.Response?.StatusCode -in (400, 409)) {
                    Write-Verbose ("Media {0} already initialized in case." -f $Media.MediaID)
                } else {
                    Write-Error ("Error while uploading data for media id {0}, path {1}; {2}" -f $Media.MediaID, $Media.RelativeFilePath, $_)
                    throw $_
                }
            } finally {
                if ($FileStream) {
                    $FileStream.Close()
                    $FileStream.Dispose()
                }
                ($using:Context).UploadedFiles++
            }
        }

        while ($UploadJob.State -eq "Running") {
            Start-Sleep -Seconds 1
            Write-Progress -Activity "Griffeye Vics Report Upload" -Status "Working" -CurrentOperation ("Uploading MediaID {0} to Griffeye" -f $Context.CurrentMedia) -PercentComplete (PercentComplete($Context))
            $Res += Receive-Job $UploadJob
            Receive-Job $RefreshTokenJob
        }
        while ($UploadJob.HasMoreData) {
            $Res += Receive-Job $UploadJob
        }

        $Duration = (New-Timespan -Start $Start -End (Get-Date)).TotalMilliseconds

        Write-Information "Finalizing case."
        Write-Progress -Activity "Griffeye Vics Report Upload" -Status "Finalizing"  -CurrentOperation "Finalizing case" -PercentComplete (PercentComplete($Context))
        try {
            Invoke-GriffeyeFinalizeCase -ApiBaseURL $ApiBaseURL -Token $Context.token -CaseID $case.Identifier
        } catch {
            if ($_.Exception.Response?.StatusCode -in (409)) {
                Write-Verbose ("Case already finalized.")
            } else {
                throw $_
            }
        }

        Write-Information "Upload complete."

        if ($ShowStats) {
            $SizeStats = $Res | Measure-Object -Property Bytes -AllStats
            $TimeStats = $Res | Measure-Object -Property DurationMillis -AllStats

            [PSCustomObject]@{
                Count = $SizeStats.Count
                Bytes = $SizeStats.Sum ? $SizeStats.Sum : 0
                MinimumBytes = $SizeStats.Minimum ? $SizeStats.Minimum : 0
                MaximumBytes = $SizeStats.Maximum ? $SizeStats.Maximum : 0
                AverageBytes = $SizeStats.Average ? $SizeStats.Average : 0
                DurationMillis = $TimeStats.Minimum ? $TimeStats.Minimum : 0
                MinimumDurationMillis = $TimeStats.Minimum ? $TimeStats.Minimum : 0
                MaximumDurationMillis = $TimeStats.Maximum ? $TimeStats.Maximum : 0
                AverageDurationMillis = $TimeStats.Average ? $TimeStats.Average : 0
                TotalDurationMillis = [Math]::round($Duration)
                TotalBytesPerSecond = [Math]::round(1000 * $SizeStats.Sum / $Duration)
            }
        }
    }
    finally {
        Write-Progress -Activity "Griffeye Vics Report Upload" -Status "Completed" -CurrentOperation "Finalizing complete" -Completed
        Write-Information "Cleaning up."
        Invoke-GriffeyeClearUnfinalizedUploads -ApiBaseURL $ApiBaseURL -Token $Context.token -CaseID $Case.Identifier -ErrorAction Ignore

        if ($UploadJob) {
            Stop-Job -Job $UploadJob -ErrorAction Ignore
        }
        if ($RefreshTokenJob) {
            Stop-Job -Job $RefreshTokenJob -ErrorAction Ignore
        }
    }
}


Export-ModuleMember -Function Invoke-GriffeyeServerInfo
Export-ModuleMember -Function Invoke-GriffeyeToken
Export-ModuleMember -Function Invoke-GriffeyeCases
Export-ModuleMember -Function Invoke-GriffeyeInitializeCase
Export-ModuleMember -Function Invoke-GriffeyeInitializeFile
Export-ModuleMember -Function Invoke-GriffeyeFinalizeFile
Export-ModuleMember -Function Invoke-GriffeyeFinalizeCase
Export-ModuleMember -Function Invoke-GriffeyeClearUnfinalizedUploads
Export-ModuleMember -Function Invoke-GriffeyeFileChunk
Export-ModuleMember -Function Invoke-GriffeyeUploadMedia
Export-ModuleMember -Function Invoke-GriffeyeVicsReportUpload
