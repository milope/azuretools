function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][String]$Message,
        [Parameter(Mandatory=$true)][String]$LogFile
    )
    $msg = "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] $($Message)"
    Write-Host $msg
    $msg | Out-File -FilePath $LogFile -Append
}

# PYTHON
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$logFile = "$([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))_pysdk_nmon.log"
Write-Log -Message "Forcing TLS 1.2"-LogFile $logFile
Write-Log -Message "Disabling Progress"-LogFile $logFile
$temp = $ProgressPreference
$ProgressPreference="SilentlyContinue"
#$uri = "https://www.python.org/ftp/python/3.8.2/python-3.8.2.exe"
$uri = "https://www.python.org/ftp/python/3.8.2/python-3.8.2-amd64.exe"
$filename = [Uri]::new($uri).Segments | Select-Object -Last 1 | % {$_}
$installer = Join-Path -Path $($env:TEMP) -ChildPath $filename
Write-Log -Message "Downloading Python for Windows 3.8.2"-LogFile $logFile
[IO.File]::WriteAllBytes($installer, (Invoke-WebRequest -Uri $uri).Content)
Write-Log -Message "Installing Python for Windows 3.8.2"-LogFile $logFile
&$installer -ArgumentList("/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_test=0", "Include_pip=1") | Out-File -FilePath $logFile -Append

while($true) {
	$test = [Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User")
	$test = ($test.Split(";") | Where {$_ -eq (Join-Path -Path "$($env:ProgramFiles)" -ChildPath "Python38\")}).Count
	if($test -gt 0) {
		break
	}
	Start-Sleep -Seconds 5
}
Write-Log -Message "Resetting environment variables."-LogFile $logFile
$env:PATH = [Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User")

# NETMON
$uri = "https://download.microsoft.com/download/7/1/0/7105C7FF-768E-4472-AFD5-F29108D1E383/NM34_x64.exe"
$filename = [Uri]::new($uri).Segments | Select-Object -Last 1 | % {$_}
$installer = Join-Path -Path $($env:TEMP) -ChildPath $filename
Write-Log -Message "Downloading Network Monitor."-LogFile $logFile
[IO.File]::WriteAllBytes($installer, (Invoke-WebRequest -Uri $uri).Content)
Write-Log -Message "Installing Network Monitor."-LogFile $logFile
&$installer "/Q" | Out-File -FilePath $logFile -Append

# EVENT HUB PYTHON SDK
Write-Log -Message "Installing Event Hubs Python SDK."-LogFile $logFile
pip install azure-eventhub --pre | Out-File -FilePath $logFile -Append
Write-Log -Message "Restoring Progress."-LogFile $logFile
$ProgressPreference = $temp
Write-Log -Message "Complete."-LogFile $logFile 

[Environment]::Exit(0)
