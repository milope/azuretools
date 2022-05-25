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

.PARAMETER StorageContainerSASUrl

Specify a Storage Contaienr SAS URL to upload a file.
Navigate to the Container and generate a SAS with
Write, Create type of permissions.

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
        [String][Parameter(Mandatory=$false)]$StorageContainerSASUrl,
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

        $etl2pcapnglocation = Join-Path -Path $traceDirectory -ChildPath "etl2pcapng\x64\etl2pcapng.exe"
        $pcapngPath = Join-Path -Path $traceDirectory -ChildPath ([String]::Concat([System.IO.Path]::GetFileNameWithoutExtension($TraceFile), ".pcapng"))
        if(Test-Path -Path $TraceFile) {
            $temp = $ProgressPreference
            try {
                $ProgressPreference = "SilentlyContinue"
                if(-not (Test-Path $etl2pcapnglocation)) {
                    Write-Host "[$([DateTime]::UtcNow.ToString("o"))] Downloading etl2pcapng.zip from repository."
                    $zipFile = (Join-Path $traceDirectory "etl2pcapng.zip")
                    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/microsoft/etl2pcapng/releases/download/v1.7.0/etl2pcapng.zip" -OutFile $zipFile
                    Write-Host "[$([DateTime]::UtcNow.ToString("o"))] Extracting etl2pcapng.zip."
                    Expand-Archive -Path $zipFile -DestinationPath $traceDirectory
                }
                
                Write-Host "[$([DateTime]::UtcNow.ToString("o"))] Converting capture to WireShark pcapng format."
                &$etl2pcapnglocation $TraceFile $pcapngPath
            }
            finally {
                $ProgressPreference = $temp
            }
        }

        if($PSBoundParameters["StorageContainerSASUrl"]) {
            [System.Uri]$sas = [System.Uri]::new("http://localhost")
            try {
                $sas = [System.Uri]::new($StorageContainerSASUrl)
            }
            catch {
                Write-Warning "[$([DateTime]::UtcNow.ToString("o"))] SAS URL is not a valid URL syntactically. Will not upload to storage."
            }

            if($sas.Segments.Length -ne 2) {
                Write-Warning "[$([DateTime]::UtcNow.ToString("o"))] SAS URL is not a Container SAS URL. Please generate a contaienr SAS URL. Will not upload to storage."
                Write-Warning "[$([DateTime]::UtcNow.ToString("o"))] Below is an example."
                Write-Warning "[$([DateTime]::UtcNow.ToString("o"))] https://storage.blob.core.windows.net/container?sp=cw&st=2022-05-25T05:31:23Z&se=2022-05-25T13:31:23Z&spr=https&sv=2020-08-04&sr=c&sig=******"
            }

            if(Test-Path $TraceFile) {
                $traceFileName = [System.IO.Path]::GetFileName($TraceFile)
                Write-Host "[$([DateTime]::UtcNow.ToString("o"))] Uploading $traceFileName to specified Azure Storage."
                $newSAS = "$($sas.Scheme)://$($sas.Host)/$($sas.Segments[1])/$($traceFileName)$($sas.Query)"
                try {
                    Invoke-WebRequest -Uri $newSAS -UseBasicParsing -Method Put -InFile $TraceFile `
                        -Headers @{
                            Date=[DateTime]::UtcNow.ToString("s")
                            "x-ms-version"="2015-02-21"
                            "x-ms-blob-type"="BlockBlob"
                        } | Out-Null
                }
                catch {
                    Write-Warning "[$([DateTime]::UtcNow.ToString("o"))] Could not upload $traceFileName to specified Azure Storage."
                }
            }

            if(Test-Path $pcapngPath ) {
                $traceFileName = [System.IO.Path]::GetFileName($pcapngPath)
                Write-Host "[$([DateTime]::UtcNow.ToString("o"))] Uploading $traceFileName to specified Azure Storage."
                $newSAS = "$($sas.Scheme)://$($sas.Host)/$($sas.Segments[1])/$($traceFileName)$($sas.Query)"
                try {
                    Invoke-WebRequest -Uri $newSAS -UseBasicParsing -Method Put -InFile $pcapngPath `
                        -Headers @{
                            Date=[DateTime]::UtcNow.ToString("s")
                            "x-ms-version"="2015-02-21"
                            "x-ms-blob-type"="BlockBlob"
                        } | Out-Null
                }
                catch {
                    Write-Warning "[$([DateTime]::UtcNow.ToString("o"))] Could not upload $traceFileName to specified Azure Storage."
                }
            }

            $cabFile = Join-Path -Path (Split-Path $traceFile) -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($traceFile) + ".cab")

            if(Test-Path $cabFile ) {
                $traceFileName = [System.IO.Path]::GetFileName($cabFile)
                Write-Host "[$([DateTime]::UtcNow.ToString("o"))] Uploading $traceFileName to specified Azure Storage."
                $newSAS = "$($sas.Scheme)://$($sas.Host)/$($sas.Segments[1])/$($traceFileName)$($sas.Query)"
                try {
                    Invoke-WebRequest -Uri $newSAS -UseBasicParsing -Method Put -InFile $cabFile `
                        -Headers @{
                            Date=[DateTime]::UtcNow.ToString("s")
                            "x-ms-version"="2015-02-21"
                            "x-ms-blob-type"="BlockBlob"
                        } | Out-Null
                }
                catch {
                    Write-Warning "[$([DateTime]::UtcNow.ToString("o"))] Could not upload $traceFileName to specified Azure Storage."
                }
            }
        }

        Write-Host "[$([DateTime]::UtcNow.ToString("o"))] Operation completed."
    }
    process {

    }
    end {

    }
}