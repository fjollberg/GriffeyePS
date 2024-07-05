#Require -Version 7.3

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
    Justification='Vics is not really a plural',
    Scope='Function',
    Target='*Vics')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPositionalParameters', '',
    Justification='Not using positional parameters for Join-Path is horrible.')]
param()

<#
  Do basic loading of Newtonsoft JSON DLL.
#>
function NewtonsoftVersion {
    switch (Get-ItemPropertyValue -LiteralPath 'HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release) {
    #   { $_ -ge 533320 } { $version = '4.8.1 or later'; break }
        { $_ -ge 378389 } { 'net45'; break }
        default {'net40'; break }
    }
}

[Reflection.Assembly]::LoadFile((Join-Path $PSScriptRoot "Newtonsoft.JSON" (NewtonsoftVersion) "Newtonsoft.Json.dll"))


enum GriffeyeReaderState {
    Scanning
    Media
    Done
}

<#
  Emit a JSON array as a deserialized stream of objects.
#>
function EmitArray ([object]$JsonReader) {
    while ($JsonReader.read()) {
        Write-Debug ("emitarray: {0}: {1}" -f $JsonReader.TokenType, $JsonReader.Value)
        switch -exact ($JsonReader.TokenType) {
            'EndArray' {
                return
            }
            'StartArray' {
                ReadArray($JsonReader)
                break
            }
            default {
                ReadObject($JsonReader)
                break
            }
        }
    }
}

<#
  Recursively de-serialize a JSON array.
#>
function ReadArray ([object]$JsonReader) {
    $CurrentArray = @()

    while ($JsonReader.read()) {
        Write-Debug ("readarray: {0}: {1}" -f $JsonReader.TokenType, $JsonReader.Value)
        switch -exact ($JsonReader.TokenType) {
            'EndArray' {
                , $CurrentArray
                return
            }
            default {
                $CurrentArray += @(ReadObject($JsonReader))
                break
            }
        }
    }
}

<#
  Recursively de-serialize a JSON object.
#>
function ReadObject ([object]$JsonReader) {
    $CurrentObject = [pscustomobject]@{}

    while ($JsonReader.read()) {
        Write-Debug ("readobject: {0}: {1}" -f $JsonReader.TokenType, $JsonReader.Value)
        switch -exact ($JsonReader.TokenType) {
            'StartArray' {
                ReadArray($JsonReader)
                return
            }
            'StartObject' {
                ReadObject($JsonReader)
                return
            }
            'PropertyName' {
                Add-Member -InputObject $CurrentObject -NotePropertyName $JsonReader.Value -NotePropertyValue (ReadObject ($JsonReader))
                break
            }
            'EndObject' {
                $CurrentObject
                return
            }
            default {
                $JsonReader.Value
                return
            }
        }
    }
}

<#
  .Synopsis
  Emit a stream of Media objects obtained from a VICS JSON file.

  .Description
  Uses Newtonsoft JSON to deserialize a VICS JSON metadata file in
  order to get the media entries as a stream of objects in constant
  memory regardless of the size of the file.

  VICS JSON metadata may be very large and a naive use of
  ConvertFrom-Json in order to parse it may not be feasible due to
  memory constraints.

  .Parameter Path
  Path to VICS json metadata file.

  .Example
  PS> Get-GriffeyeMediaFromVics "\\server.some.domain\some-path\file.json"
#>
function Get-GriffeyeMediaFromVics {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Path
    )

    process {
        $StreamReader = New-Object -TypeName System.IO.StreamReader -ArgumentList (Get-Item $Path -ErrorAction Stop).FullName
        $JsonReader = New-Object -TypeName Newtonsoft.Json.JsonTextReader -ArgumentList $StreamReader
        [GriffeyeReaderState]$GriffeyeReaderState = [GriffeyeReaderState]::Scanning

        while ($JsonReader.read()) {
            switch ($GriffeyeReaderState) {
                ([GriffeyeReaderState]::Scanning) {
                    switch -exact ($JsonReader.TokenType) {
                        'PropertyName' {
                            switch -exact ($JsonReader.Value) {
                                'Media' {
                                   $GriffeyeReaderState = [GriffeyeReaderState]::Media
                                   break
                                }
                                '@odata.context' {
                                    $JsonReader.read() | Out-Null
                                    [string]$VicsContext = $JsonReader.Value
                                    if ($VicsContext.EndsWith("#Media")) {
                                        $GriffeyeReaderState = [GriffeyeReaderState]::Media
                                    }
                                    break
                                }
                            }
                        }
                    }
                }
                ([GriffeyeReaderState]::Media) {
                    switch ($JsonReader.TokenType) {
                        {($_ -eq 'PropertyName') -and ($JsonReader.Value -eq 'value')} {
                            break;
                        }
                        'StartArray' {
                            EmitArray($JsonReader)
                            $GriffeyeReaderState = [GriffeyeReaderState]::Done
                            break
                        }
                        default {
                            Write-Error ("Unexpected data. {0}: '{1}'" -f $JsonReader.TokenType, $JsonReader.Value)
                        }
                    }
                }
            }
        }

        $JsonReader.Close() | Out-Null
        $StreamReader.Close() | Out-Null
    }
}


<#
  .Synopsis
  Emit the value of specified VICS case property from a VICS JSON file.

  .Description
  Uses Newtonsoft JSON to deserialize a VICS JSON metadata file in
  order to get the metadata property in constant memory regardless of
  size of the file.

  VICS metadata may in some cases have the same property name in several
  places, in which this method returns the *first* instance found. It is
  not particular about where in the JSON structure the property is found.

  It is reasonably fast even if the property is found after a large
  number of Media entries, but may still take some time in that case.

  .Parameter Path
  Path to VICS json metadata file.

  .Parameter Property
  Exact name, including case, of the JSON property to return value of.

  .Example
  PS> Get-GriffeyeMetadataPropertyFromVics "\\server.some.domain\some-path\file.json" TotalMediaFiles
  12
#>
function Get-GriffeyeMetadataPropertyFromVics {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Path,
        [Parameter(Mandatory=$true)]
        [string] $Property
    )

    process {
        $StreamReader = New-Object -TypeName System.IO.StreamReader -ArgumentList (Get-Item $Path -ErrorAction Stop).FullName
        $JsonReader = New-Object -TypeName Newtonsoft.Json.JsonTextReader -ArgumentList $StreamReader

        while ($JsonReader.read()) {
            switch -exact ($JsonReader.TokenType) {
                'PropertyName' {
                    switch -exact ($JsonReader.Value) {
                        'Media' {
                            $JsonReader.Skip() | Out-Null
                            break
                        }
                        $Property {
                            $JsonReader.read() | Out-Null
                            $JsonReader.Value
                            $JsonReader.Close() | Out-Null
                            $StreamReader.Close() | Out-Null
                            return
                        }
                    }
                }
            }
        }

        Write-Error ("Property '{0}' not found in '{1}'." -f $Property, $Path)
        $JsonReader.Close() | Out-Null
        $StreamReader.Close() | Out-Null
    }
}


<#
  .Synopsis
  Emit a PSCustomObject with selected metadata properties from a VICS JSON file.

  .Description
  Uses Newtonsoft JSON to deserialize a VICS JSON metadata file in
  order to get the metadata property in constant memory regardless of
  size of the file.

  VICS metadata may in some cases have the same property name in several
  places, in which this method returns the *first* instance found. It is
  not particular about where in the JSON structure the property is found.

  It is reasonably fast even if a property is found after a large
  number of Media entries, but may still take some time in that case.

  .Parameter Path
  Path to VICS json metadata file.

  .Parameter Properties
  Exact name, including case, of the JSON property to return value of.

  .Example
  PS> Get-GriffeyeMetadataObjectFromVics "\\server.some.domain\some-path\file.json" CaseID, TotalMediaFiles
  CaseID                               TotalMediaFiles
  ------                               ---------------
  e6da055a-92bc-48a1-8c41-f2784786c6db              12
#>
function Get-GriffeyeMetadataObjectFromVics {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [Parameter(Mandatory=$true)]
        [System.Collections.ArrayList] $Properties,

        [switch]$RequireAllProperties
    )

    begin {
        $StreamReader = New-Object -TypeName System.IO.StreamReader -ArgumentList (Get-Item $Path -ErrorAction Stop).FullName
        $JsonReader = New-Object -TypeName Newtonsoft.Json.JsonTextReader -ArgumentList $StreamReader
    }
    process {
        $Result = [pscustomobject]@{}

        while ($JsonReader.read()) {
            switch -exact ($JsonReader.TokenType) {
                'PropertyName' {
                    switch ($JsonReader.Value) {
                        'Media' {
                            $JsonReader.Skip() | Out-Null
                            break
                        }
                        {$_ -cin $Properties}  {
                            $JsonReader.read() | Out-Null
                            Add-Member -InputObject $Result -NotePropertyName $_ -NotePropertyValue $JsonReader.Value
                            $Properties.Remove($_)

                            if (-not $Properties.Count) {
                                $JsonReader.Close() | Out-Null
                                $StreamReader.Close() | Out-Null
                                $Result
                                return
                            }
                        }
                    }
                }
            }
        }

        if ($RequireAllProperties) {
            Write-Error ("Property '{0}' not found in '{1}'." -f ($Properties -join ", "), $Path)
        }

        $Result
    }
    end {
        $JsonReader.Close() | Out-Null
        $StreamReader.Close() | Out-Null
    }
}


Export-ModuleMember -Function Get-GriffeyeMediaFromVics
Export-ModuleMember -Function Get-GriffeyeMetadataPropertyFromVics
Export-ModuleMember -Function Get-GriffeyeMetadataObjectFromVics
