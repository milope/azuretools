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

Starts a NetSh based network trace.

.DESCRIPTION

Starts a NetSh based network trace.

.PARAMETER TraceFile

Specify where to create the file.

.PARAMETER MaxSize

Specify the max size in megabytes.

.PARAMETER OnlyConvertFile

Only convert the ETL trace to WireShark pcapng

.EXAMPLE

PS> Start-NetworkCapture -TraceFile "C:\Output.etl"

#>
function Start-NetworkCapture {
    [CmdletBinding()]
    param (
        [String][Parameter(Mandatory=$true)]$TraceFile,
        [UInt32][Parameter(Mandatory=$false)]$MaxSize=512,
        [UInt32][Parameter(Mandatory=$false)]$MaxTimeInSeconds,
        [Switch]$OnlyConvertFile
    )
    begin {

        if(-not [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")) {
            $exception = [System.Management.Automation.PSSecurityException]::new("Start-NetworkCapture need to be executed as an Administrator.")
            $errorRecord = New-Object System.Management.Automation.ErrorRecord ($exception, [String]::Empty,
                ([System.Management.Automation.ErrorCategory]::SecurityError), $null)
            Write-Error $errorRecord
            return
        }

        $traceDirectory = Split-Path $TraceFile
        if(-not (Test-Path $traceDirectory)) {
            New-Item -Path $traceDirectory -ItemType Directory
        }

        if(-not $PSBoundParameters["OnlyConvertFile"] -or -not $OnlyConvertFile)  {
            Write-Host "[$([DateTime]::UtcNow.ToString("o"))] Starting Network Capture."
            netsh trace start capture=yes level=5 scenario=netconnection report=no tracefile=$TraceFile maxsize=$MaxSize filemode=circular
            if($PSBoundParameters.ContainsKey("MaxTimeInSeconds") -and $MaxTimeInSeconds -gt 0) {
                Start-Sleep -Seconds $MaxTimeInSeconds
            }
            else {
                pause
            }
            netsh trace stop
        }

        if(Test-Path -Path $TraceFile) {
            $temp = $ProgressPreference
            try {
                $ProgressPreference = "SilentlyContinue"
                $etl2pcapnglocation = Join-Path -Path $traceDirectory -ChildPath "etl2pcapng\x64\etl2pcapng.exe"
                if(-not (Test-Path $etl2pcapnglocation)) {
                    $zipFile = (Join-Path $traceDirectory "etl2pcapng.zip")
                    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/microsoft/etl2pcapng/releases/download/v1.7.0/etl2pcapng.zip" -OutFile $zipFile
                    Expand-Archive -Path $zipFile -DestinationPath $traceDirectory
                    $pcapngPath = Join-Path -Path $traceDirectory -ChildPath ([String]::Concat([System.IO.Path]::GetFileNameWithoutExtension($TraceFile), ".pcapng"))
                }                
                &$etl2pcapnglocation $TraceFile $pcapngPath
            }
            finally {
                $ProgressPreference = $temp
            }
        }
    }
    process {

    }
    end {

    }
}