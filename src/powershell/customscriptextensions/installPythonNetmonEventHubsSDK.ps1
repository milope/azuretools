# PYTHON
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$logFile = "$([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))_pysdk_nmon.log"
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Forcing TLS 1.2" | Out-File -FilePath $logFile
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Disabling Progress" | Out-File -FilePath $logFile
$temp = $ProgressPreference
$ProgressPreference="SilentlyContinue"
#$uri = "https://www.python.org/ftp/python/3.8.2/python-3.8.2.exe"
$uri = "https://www.python.org/ftp/python/3.8.2/python-3.8.2-amd64.exe"
$filename = [Uri]::new($uri).Segments | Select-Object -Last 1 | % {$_}
$installer = Join-Path -Path $($env:TEMP) -ChildPath $filename
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Downloading Python for Windows 3.8.2" | Out-File -FilePath $logFile
[IO.File]::WriteAllBytes($installer, (Invoke-WebRequest -Uri $uri).Content)
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Installing Python for Windows 3.8.2" | Out-File -FilePath $logFile
&$installer -ArgumentList("/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_test=0", "Include_pip=1")

while($true) {
	$test = [Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User")
	$test = ($test.Split(";") | Where {$_ -eq (Join-Path -Path "$($env:ProgramFiles)" -ChildPath "Python38\")}).Count
	if($test -gt 0) {
		break
	}
	Start-Sleep -Seconds 5
}
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Resetting environment variables." | Out-File -FilePath $logFile
$env:PATH = [Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User")

# NETMON
$uri = "https://download.microsoft.com/download/7/1/0/7105C7FF-768E-4472-AFD5-F29108D1E383/NM34_x64.exe"
$filename = [Uri]::new($uri).Segments | Select-Object -Last 1 | % {$_}
$installer = Join-Path -Path $($env:TEMP) -ChildPath $filename
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Downloading Network Monitor." | Out-File -FilePath $logFile
[IO.File]::WriteAllBytes($installer, (Invoke-WebRequest -Uri $uri).Content)
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Installing Network Monitor." | Out-File -FilePath $logFile
&$installer "/Q"

# EVENT HUB PYTHON SDK
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Installing Event Hubs Python SDK." | Out-File -FilePath $logFile
pip install azure-eventhub --pre
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Restoring Progress." | Out-File -FilePath $logFile
$ProgressPreference = $temp
Write-Host "[$([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fff"))] Complete." | Out-File -FilePath $logFile
