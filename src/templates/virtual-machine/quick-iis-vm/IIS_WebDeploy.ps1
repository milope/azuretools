$temppath = $env:roleroot + "\approot\startuptemp\"
$logpath = $temppath + "startup-script.log"
$templog = "$($temppath)output.txt"

if((Test-Path -PathType Container $temppath) -eq $false)
{
    New-Item -ItemType directory -Path $temppath
}


Add-Content -Path $logpath "Michael Lopez's IIS/Web Deploy configurator script"
Add-Content -Path $logpath "`r`n================================================================================"
Add-Content -Path $logpath "`r`nInstalling IIS..."

Add-Content -Path $logpath "`r`nAssigning Everyone Full control to $temppath`r`n"

(& icacls @("$temppath", "/grant", '"Everyone":(OI)(CI)F', "/T")) | Out-File $templog
Add-Content -Path $logpath ([System.IO.File]::ReadAllText($templog))
Add-Content -Path $logpath "`r`nDone"



Add-WindowsFeature Web-Server
Add-Content -Path "C:\inetpub\wwwroot\Default.htm" -Value $($env:computername)
Add-Content -Path $logpath " Done."
Add-Content -Path $logpath "`r`nInstalling WMSVC..."
Add-WindowsFeature Web-Mgmt-Service
Add-Content -Path $logpath " Done."
Add-Content -Path $logpath "`r`nInstalling ASP.NET 4.5..."
Add-WindowsFeature Web-Asp-Net45
Add-Content -Path $logpath " Done."
Add-Content -Path $logpath "`r`nInstalling IIS Web Management Console..."
Add-WindowsFeature Web-Mgmt-Console
Add-Content -Path $logpath " Done."

$webpifilename = "webdeploy.msi"
$TempWebDeploy = $temppath + $webpifilename
$WebDeployURI = "http://download.microsoft.com/download/0/1/D/01DC28EA-638C-4A22-A57B-4CEF97755C6C/WebDeploy_amd64_en-US.msi"


# Download web deploy
if((Test-Path $TempWebDeploy) -eq $false)
{
    $wc = New-Object System.Net.WebClient
    Add-Content -Path $logpath "`r`nDownloading Web Deploy..."
    $wc.DownloadFile($WebDeployURI, $TempWebDeploy)
    Add-Content -Path $logpath " Done."
}

Add-Content -Path $logpath "`r`nInstalling Web Deploy..."
$argumentsMSI =  "/package $TempWebDeploy ADDLOCAL=ALL /qn /norestart LicenseAccepted=`"0`""

# Install Web Deploy
#& msiexec.exe $argumentsMSI
(Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentsMSI -wait -Passthru).ExitCode
Add-Content -Path $logpath " Done."

# Install WebPI
$WebPIURI = "https://download.microsoft.com/download/8/4/9/849DBCF2-DFD9-49F5-9A19-9AEE5B29341A/WebPlatformInstaller_x64_en-US.msi"
$webpifile = "webpi.msi"
$TempWebPI = $temppath + $webpifile

if((Test-Path $TempWebPI) -eq $false)
{
    Add-Content -Path $logpath "`r`nDownloading Web Platform Installer... "
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($WebPIURI, $TempWebPI)
    Add-Content -Path $logpath "Done."
}

Add-Content -Path $logpath "`r`nInstalling Web Platform Installer... "
$argumentsMSI =  "/package $TempWebPI /quiet"
(Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentsMSI -wait -Passthru).ExitCode
Add-Content -Path $logpath "Done."

# Install ARR
#$wffURI = "http://download.microsoft.com/download/5/7/0/57065640-4665-4980-A2F1-4D5940B577B0/webfarm_v1.1_amd64_en_US.msi"
#$externalCacheURI = "http://download.microsoft.com/download/1/1/a/11a5a75a-5ddc-4821-88ca-2abe02a32ed3/ExternalDiskCache_amd64_en-us.msi"
$urlRewriteURI = "https://webpihandler.azurewebsites.net/web/handlers/webpi.ashx/getinstaller/urlrewrite2.appids"
$ARRURI = "https://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi"

#$wffFile = "wff.msi"
#$externalCacheFile = "externalCache.msi"
$urlRewriteFile = "rewrite.msi"
$arrFile = "arr.msi"

#$tempWFFFile = $temppath + $wffFile
#$tempExternalFile = $temppath + $externalCacheFile
$tempRewriteFile = $temppath + $urlRewriteFile
$tempARRFile = $temppath + $arrFile

# if((Test-Path $tempWFFFile) -eq $false)
# {
#     Add-Content -Path $logpath "`r`nDownloading Web Farm Framework... "
#     $wc = New-Object System.Net.WebClient
#     $wc.DownloadFile($wffURI, $tempWFFFile)
#     Add-Content -Path $logpath "Done."
# }

# if((Test-Path $externalCacheFile) -eq $false)
# {
#     Add-Content -Path $logpath "`r`nDownloading External Cache... "
#     $wc = New-Object System.Net.WebClient
#     $wc.DownloadFile($externalCacheURI, $tempExternalFile)
#     Add-Content -Path $logpath "Done."
# }

$ProgressPreference = "SilentlyContinue"
if((Test-Path $tempRewriteFile) -eq $false)
{
    Add-Content -Path $logpath "`r`nDownloading URL Rewrite... "
    Invoke-WebRequest -Uri $urlRewriteURI -OutFile $tempRewriteFile -UseBasicParsing
    Add-Content -Path $logpath "Done."
}

if((Test-Path $tempARRFile) -eq $false)
{
    Add-Content -Path $logpath "`r`nDownloading Application Request Router... "
    Invoke-WebRequest -Uri $ARRURI -OutFile $tempARRFile -UseBasicParsing
    Add-Content -Path $logpath "Done."
}


Stop-Service -Name WAS -Force
Stop-Service -Name WMSVC -Force

# Add-Content -Path $logpath "`r`nWeb Farm Framework... "
# $argumentsMSI =  "/package $tempWFFFile /quiet"
# (Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentsMSI -wait -Passthru).ExitCode
# Add-Content -Path $logpath "Done."

# Add-Content -Path $logpath "`r`nInstalling External Cache... "
# $argumentsMSI =  "/package $tempExternalFile /quiet"
# (Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentsMSI -wait -Passthru).ExitCode
# Add-Content -Path $logpath "Done."

Add-Content -Path $logpath "`r`nInstalling Rewrite... "
$argumentsMSI =  "/package $tempRewriteFile /quiet"
(Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentsMSI -wait -Passthru).ExitCode
Add-Content -Path $logpath "Done."

Add-Content -Path $logpath "`r`nInstalling ARR... "
$argumentsMSI =  "/package $tempARRFile /quiet"
(Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentsMSI -wait -Passthru).ExitCode
Add-Content -Path $logpath "Done."

Start-Service W3SVC
Start-Service WMSVC


# Open HTTP and HTTPS to the public

Add-Content -Path $logpath "`r`nAdding Firewall rule for HTTP and HTTPS..."
New-NetFirewallRule -DisplayName "HTTP(s) Inbound" -Profile @("Domain", "Public", "Private") -Direction Inbound -Action Allow -Protocol TCP -LocalPort @("80", "443")
Add-Content -Path $logpath " Done."

# Open Web Deploy to Domain and Private
Add-Content -Path $logpath "`r`nAdding Firewall rule for Web Deploy..."
New-NetFirewallRule -DisplayName "WebDeploy" -Profile @("Public", "Domain", "Private") -Direction Inbound -Action Allow -Protocol TCP -LocalPort @("8172")
Add-Content -Path $logpath "` Done."


Add-Content -Path $logpath "`r`nLoading System.Web, Microsoft.Web.Administration, System.Configuration assemblies..."
Add-Type -AssemblyName "System.Web, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a"
Add-Type -AssemblyName "Microsoft.Web.Administration, Version=7.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35"
Add-Content -Path $logpath " Done."

Add-Content -Path $logpath "`r`nGenerating temporary password..."

function HashSHA256 {
    [CmdletBinding()]
    param (
        [String][Parameter(Mandatory=$true)]$Value,
        [String][ValidateSet("Base64","Hex")]$Output = "Hex"
    )
    begin {
        Function ConvertFrom-ByteArrayToString {
            [CmdletBinding()]
	        Param (
		        [Byte[]]$ByteArray
	        )
            process {
	            ForEach ($Byte In $ByteArray) {
		            $String = "$String" + ('{0:X}' -f [int] $Byte).PadLeft(2,"0")
	            }
	            Return $String
            }
        }
    }
    process {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $sha256 = New-Object System.Security.Cryptography.SHA256Cng
        try {
            $hashCipher = $sha256.ComputeHash($bytes)
            $result = "";
            if($Output -eq "Hex") {
                $result = ConvertFrom-ByteArrayToString -ByteArray $hashCipher
            }
            else {
                $result = [System.Convert]::ToBase64String($hashCipher)
            }
            return $result
        }
        finally {
            $sha256.Dispose()
        }
    }
}

$username = '$DeployUser'
$password = [System.Web.Security.Membership]::GeneratePassword(12, 3)
$realPassword = HashSha256 -Value $password -Output Base64
$storedPassword = HashSha256 -Value $realPassword -Output Hex

Add-Content -Path $logpath " Done."
Add-Content -Path $logpath "`r`nAdding IIS User $username and adding it to the site scope..."

function FindElement {
    [CmdletBinding()]
    param (
        [Microsoft.Web.Administration.ConfigurationElementCollection][Parameter(Mandatory=$true)]$Collection,
        [String][Parameter(Mandatory=$true)]$ElementTagName,
        [String][Parameter(Mandatory=$true)]$AttributeName,
        [String][Parameter(Mandatory=$true)]$AttributeValue
    )
    process {
        $i = 0
        $ignoreCase = [System.StringComparison]::OrdinalIgnoreCase

        for($i = 0; $i -lt $collection.Count; $i++) {
            $element = $collection[$i]
            if([String]::Equals($element.ElementTagName, $ElementTagName, $ignoreCase)) {
                $value = $null
                $o = $element.GetAttributeValue($AttributeName)
                if($null -ne $o) {
                    $value = $o.ToString(); 
                }
                if([String]::Equals($value, $AttributeValue, $ignoreCase)) {
                    return $element
                }
            }
        }

        return $null
    }
}

# This section adds an IIS User
$serverManager = New-Object Microsoft.Web.Administration.ServerManager
try {
    $config = $serverManager.GetAdministrationConfiguration()
    $authSection = $config.GetSection("system.webServer/management/authentication")
    $credCollection = $authSection.GetCollection("credentials")
    $addElement = $credCollection.CreateElement("add")
    $addElement["name"] = "$username"
    $addElement["password"] = "$storedPassword"
    $addElement["enabled"] = "True"
    $credCollection.Add($addElement)


    
    $authzSection = $config.GetSection("system.webServer/management/authorization")
    $authzRulesCollection = $authzSection.GetCollection("authorizationRules")
    $scopeElement = FindElement -Collection $authzRulesCollection -ElementTagName "scope" -AttributeName "path" -AttributeValue "/Default Web Site"
    if($null -eq $scopeElement) {
        $scopeElement = $authzRulesCollection.CreateElement("scope")
        $scopeElement["path"] = "/Default Web Site"
        $authzRulesCollection.Add($scopeElement)
    }

    $scopeCollection = $scopeElement.GetCollection();
    $addElement2 = $scopeCollection.CreateElement("add")
    $addElement2["name"] = "$username"
    $scopeCollection.Add($addElement2)

    $serverManager.CommitChanges()

}
finally {
    $serverManager.Dispose()
}

Add-Content -Path $logpath " Done."

# Sets WMSVC for IIS Manager Users
Add-Content -Path $logpath "`r`nStopping WMSVC to reconfigure it..."
Stop-Service -Name WMSVC -Force
Add-Content -Path $logpath " Done."

Add-Content -Path $logpath "`r`nSetting WMSVC to accept IIS Manager credentials..."
$regPath = "HKLM:\Software\Microsoft\WebManagement\Server"
$regName = "RequiresWindowsCredentials"
$regValue = 0

New-ItemProperty -Path $regPath -Name $regName -Value $regValue -PropertyType DWORD -Force | Out-Null

$regName = "TracingEnabled"
$regValue = 1
New-ItemProperty -Path $regPath -Name $regName -Value $regValue -PropertyType DWORD -Force | Out-Null

Add-Content -Path $logpath " Done."

Add-Content -Path $logpath "`r`nStarting WMSVC..."
Start-Service -Name WMSVC
Add-Content -Path $logpath " Done."

Add-Content -Path $logpath "`r`nGranting permissions to Local Service on C:\inetpub\wwwroot..."
# Grant Local Service permissions
& icacls @("C:\inetpub\wwwroot", "/grant", '"Local Service":(OI)(CI)F', "/T")
Add-Content -Path $logpath " Done."

Add-Content -Path $logpath "`r`nOutputting the credentials to $($temppath)DeploymentCredentials.txt"
# output the credentials information to file (Maybe put it in Azure Storage later...)
Add-Content -Path "$($temppath)DeploymentCredentials.txt" "Username: $username, Password: $realPassword"
Add-Content -Path $logpath " Done."

Add-Content -Path $logpath "`r`nRestarting IIS..."
Stop-Service WAS -Force
Stop-Service WMSVC -Force
Stop-Service MSDEPSVC -Force
Start-Service W3SVC
Start-Service WMSVC
Start-Service MSDEPSVC

Add-Content -Path $logpath " Done."
Add-Content -Path $logpath "`r`nScript has completed successfully!"