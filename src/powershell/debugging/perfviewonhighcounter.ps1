<#

MIT License

Copyright (c) 2020 Michael Lopez

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

#>

<# BIG NOTE: This automatically accepts the PerfView EULA, it is highly
encouraged, that you review the PerfView EULA prior to using this script #>

[Cmdletbinding()]
param (
    # Counter to measure, default is total CPU
    [String][Parameter(Mandatory=$false)]$Counter = "\processor(_total)\% processor time", 
    # Max samples to measure
    [Int32][Parameter(Mandatory=$true)]$MaxSamples,
    # The sample interval
    [Int32][Parameter(Mandatory=$true)]$SampleInterval,
    # Where to download perfview and store PerfView (default is %TEMP%)
    [String][Parameter(Mandatory=$false)]$DownloadFolder = "$($env:TEMP)",
    # Threshold to start capture
    [Int32][Parameter(Mandatory=$true)]$Threshold,
    # How much time to capture (default is 5 minutes)
    [Int32][Parameter(Mandatory=$false)]$CaptureTimeInSeconds = 300,
    # Where to dump the ETL and logs (default is %TEMP%)
    [String][Parameter(Mandatory=$true)]$OutputPath = "$($env:TEMP)",
    # Keep the downloaded files and logs
    [Switch]$KeepFiles
)

if (-not ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : This command requires elevation to run."
}

$sw = [System.Diagnostics.Stopwatch]::new()
$sw.Start()

$urls = @(
    "https://github.com/microsoft/perfview/releases/download/P2.0.54/PerfView.exe",
    "https://github.com/microsoft/perfview/releases/download/P2.0.54/PerfView64.exe"
)

$i = 0
$executableIndex = 0

# Retrieve PerfView
for($i = 0; $i -lt $urls.Length; $i++) {
    $test = [System.Uri]::new($urls[$i])
    $downloadLocation = (Join-Path -Path "$($DownloadFolder)" -ChildPath $test.Segments[$test.Segments.Length - 1])
    $httpClient = [System.Net.WebClient]::new()
    try {
        if(-not (Test-Path -Path $downloadLocation)) {
            Write-Host "Downloading from $($urls[$i]) to $($downloadLocation)"
            $httpClient.DownloadFile($test, $downloadLocation)
        }
        else {
            Write-Host "File $($downloadLocation) was already found, we do not need to download it again."
        }
    }
    finally {
        $httpClient.Dispose()
    }
}
$test = [System.Uri]::new($urls[$executableIndex])
$perfViewPath = (Join-Path -Path "$($DownloadFolder)" -ChildPath $test.Segments[$test.Segments.Length - 1])

$averageCPU = 0
# Wait until the Counter threshold condition takes place
while($true)
{
    $averageCPU = (Get-Counter $Counter -MaxSamples $MaxSamples -SampleInterval $SampleInterval `
    | Select-Object -ExpandProperty countersamples `
    | Select-Object -ExpandProperty cookedvalue `
    | Measure-Object -Average).Average
    Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Average CPU time is: $($averageCPU)"

    if($averageCPU -gt $Threshold) {
        break;
    }

    Start-Sleep -Seconds 1
}

# Counter was tirggered, start perfview
$etwPath = Join-Path -Path "$($OutputPath)" -ChildPath "HighCpu_PerfView_$([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmssfff")).etl"
$logFileStart = Join-Path -Path "$($OutputPath)" -ChildPath "HighCpu_PerfView_Start_$([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmssfff")).log"
$logFileStop = Join-Path -Path "$($OutputPath)" -ChildPath "HighCpu_PerfView_Stop_$([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmssfff")).log"
Write-Host "The threshold $($Threshold) was exeeded, running perfview to capture profile trace for $($CaptureTimeInSeconds) seconds"
&$perfViewPath @("start", $etwPath, "/Zip:TRUE", "/Circular:1000", "/ThreadTime", "/AcceptEULA", "/ClrEvents:Default", "/KernelEvents:Default", "/LogFile:$($logFileStart)")
Start-Sleep -Seconds $CaptureTimeInSeconds
&$perfViewPath @("stop", "/LogFile:$($logFileStop)")
Write-Host -NoNewline "The capture was completed, mergin final file, this will take some time..."
$finalFile = [String]::Empty
while($true) {
    try {
        $content = Get-Content -Path $logFilestop -Raw -ErrorAction SilentlyContinue
        if($content.Contains("SUCCESS: PerfView stop")) {

            $strToSearch = "ZIP output file "
            $idx = $content.IndexOf($strToSearch)
            if($idx -gt -1) {
                $idx = $idx + $strToSearch.Length
                $idx2 = $content.IndexOf(".zip", $idx)
                if($idx2 -gt $idx) {
                    $finalFile = $content.Substring($idx, ($idx2 + 4) - $idx)
                }
            }
            Write-Host
            break
        }
        Write-Host -NoNewline "."
    }
    catch {}
    Start-Sleep -Seconds 1
}

if(-not $KeepFiles) {
    Start-Sleep -Seconds 1
    $i = 0
    
    for($i = 0; $i -lt $urls.Length; $i++) {
        $test = [System.Uri]::new($urls[$i])
        $downloadLocation = (Join-Path -Path "$($DownloadFolder)" -ChildPath $test.Segments[$test.Segments.Length - 1])
        Remove-Item -Path $downloadLocation -Force | Out-Null
    }

    Remove-Item -Path $logFileStart -Force
    Remove-Item -Path $logFileStop -Force
}

$sw.Stop()
Write-Host "Data collection as completed. Output File: $($finalFile) Total Execution Time $($sw.Elapsed.ToString())"
