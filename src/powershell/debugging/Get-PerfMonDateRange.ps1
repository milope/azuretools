<#
Copyright © 2022 Michael Lopez

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the “Software”), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>
<#
.SYNOPSIS

Use this cmdlet to check what date ranges are observed in PerfMon blg files.

.DESCRIPTION

Use this cmdlet to check what date ranges are observed in PerfMon blg files.

.PARAMETER Path

The path to the .blg files to display their start and end date.

.PARAMETER DoNotTrack

Disable sending custom event to Application Insights

.INPUTS

String or the results from any cmdlet that returns enumerable of FileInfo types.
Example: Get-ChildItem

.OUTPUTS

Returns an pipable enumeration of the where the objects have the following properties:

- Path: Filename of the blg file analyzed.
- StartTime: The earliest time observed in the given file.
- EndTime: The latest time observed in the given file.

.EXAMPLE

Get-PerfMonDateRange -File "C:\Temp\File1.blg"

.EXAMPLE

Get-PerfMonDateRange -File "C:\Temp\File1.blg", "C:\Temp\File2.blg"

.EXAMPLE

"C:\Temp\File1.blg", "C:\Temp\File2.blg" | Get-PerfMonDateRange

.EXAMPLE

Get-ChildItem | Get-PerfMonDateRange

#>
function Get-PerfMonDateRange {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][Alias("FullName")][String[]]$Path,
        [Switch]$DoNotTrack
    )
    begin {

        function Send-TrackEvent (
            [Parameter(Mandatory=$true,HelpMessage="Specify the App Insights Instrumentation Key",Position=0)][ValidateScript({ $_ -ne [Guid]::Empty})][Guid] $iKey,
            [Parameter(Mandatory=$true,HelpMessage="Specify the Event to send to App Insights",Position=1)][String]$EventName,
            [Parameter(Mandatory=$false, HelpMessage="Specify custom properties", Position=2)][Hashtable]$CustomProperties
        )
        {    
            $sendEvent = {
                param (
                    [Guid]$piKey,
                    [String]$pEventName,
                    [Hashtable]$pCustomProperties
                )
                $appInsightsEndpoint = "https://dc.services.visualstudio.com/v2/track"        
                $body = (@{
                    name = "Microsoft.ApplicationInsights.$iKey.Event"
                    time = [DateTime]::UtcNow.ToString("o")
                    iKey = $piKey
                    tags = @{
                        "ai.device.id" = $env:COMPUTERNAME
                        "ai.device.locale" = $env:USERDOMAIN
                        "ai.user.id" = $env:USERNAME
                        "ai.user.authUserId" = "$($env:USERDOMAIN)\$($env:USERNAME)"
                        "ai.cloud.roleInstance" = $env:COMPUTERNAME
                    }
                    "data" = @{
                        baseType = "EventData"
                        baseData = @{
                            ver = "2"
                            name = $pEventName
                            properties = ($pCustomProperties | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
                        }
                    }
                }) | ConvertTo-Json -Depth 10 -Compress
    
                $temp = $ProgressPreference
                $ProgressPreference = "SilentlyContinue"
                Invoke-WebRequest -Method POST -Uri $appInsightsEndpoint -Headers @{"Content-Type"="application/x-json-stream"} -Body $body -TimeoutSec 3 | Out-Null
                $ProgressPreference = $temp
            }
    
            Start-Job -ScriptBlock $sendEvent -ArgumentList @($iKey, $EventName, $CustomProperties) | Out-Null
        }

        if(-not $DoNotTrack) {
            $iKey = (Invoke-RestMethod -UseBasicParsing -Uri https://raw.githubusercontent.com/milope/azuretools/master/api/appinsights/instrumentationKey).InstrumentationKey
            Send-TrackEvent -iKey $iKey -EventName "Get-PerfMonDateRange" 
            $iKey = $null
        }
    }
    process {
        $Path | ForEach-Object {
            if(Test-Path $_) {
                $data = Import-Counter -Path $_ -ErrorAction SilentlyContinue
                $lastTimestamps = $data | ForEach-Object { $_.CounterSamples | Where-Object { $_.Timestamp100NSec -gt 0 } | Sort-Object -Descending -Property Timestamp100NSec | Select-Object -First 1 -Property Timestamp100NSec }
                $lastTimestamp = $lastTimestamps | Sort-Object -Property Timestamp100NSec -Descending | Select-Object -First 1
                $firstTimestamp = $lastTimestamps | Sort-Object -Property Timestamp100NSec | Select-Object -First 1

                [PSCustomObject]@{Path=[IO.Path]::GetFileName($Path);StartTime = [System.DateTime]::FromFileTime($firstTimestamp.Timestamp100NSec).ToUniversalTime(); EndTime=[DateTime]::FromFileTime($lastTimestamp.Timestamp100NSec).ToUniversalTime()}
            }
        }
    }
    end {

    }
}