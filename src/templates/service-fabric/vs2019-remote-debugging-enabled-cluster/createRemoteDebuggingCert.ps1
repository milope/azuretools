[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][String]$ResourceGroupName,
    [Parameter(Mandatory=$true)][String]$ClusterName,
    [Parameter(Mandatory=$true)][String]$Location,
    [Parameter(Mandatory=$false)][String]$VaultName,
    [Parameter(Mandatory=$false)][String]$RemoteDebugServerCertificateName="RemoteDebugServerCertificate",
    [Parameter(Mandatory=$false)][String]$RemoteDebugClientCertificateName="RemoteDebugClientCertificate",
    [Parameter(Mandatory=$false)][String]$SubscriptionId,
    [Parameter(Mandatory=$false)][String]$Environment="AzureCloud",
    [Switch]$ResetLogin
)
function LoginToAzure([string]$Environment,[string]$SubscriptionId) {
    $envIsNull = [String]::IsNullOrEmpty($Environment)
    $subIsNull = [String]::IsNullOrEmpty($SubscriptionId)
    $context = $null
    if($envIsNull -and $subIsNull) {
        $context = Connect-AzAccount
    }
    elseif($envIsNull) {
        $context = Connect-AzAccount -Subscription $SubscriptionId
    }
    elseif($subIsNull) {
        $context = Connect-AzAccount -Environment $Environment
    }
    else {
        $context = Connect-AzAccount -Environment $Environment -Subscription $SubscriptionId
    }
    return $context
}
function SetupContext([String]$Environment,[string]$SubscriptionId, [bool]$ResetLogin) {
    $context = Get-AzContext
    if(
        $ResetLogin `
        -or ($null -eq $context -or $null -eq $context.Account) `
        -or ($context.Environment.Name -ne $Environment)
    ) {
        $context = LoginToAzure $Environment $SubscriptionId
    } elseif($null -eq $context -or $null -eq $context.Account) {
        $context = LoginToAzure $Environment $SubscriptionId
    }
    elseif($context.Environment.Name -ne $Environment) {
        $context = LoginToAzure $Environment $SubscriptionId
    }
    else {
        # This part is running a simple command to check if context isn't expired
        try {
            Get-AzLocation | Out-Null
        }
        catch
        {
            # Context has likely expired
            $context = LoginToAzure $Environment $SubscriptionId
        }
        if(-not [String]::IsNullOrEmpty($SubscriptionId) `
            -and $context.Subscription.Id -ne $SubscriptionId) {
            $context = Select-AzSubscription -Subscription $SubscriptionId
        }
    }
    return $context
}
function GetOrSetResourceGroup([String]$ResourceGroupName, [String]$Location) {
    if([String]::IsNullOrEmpty($ResourceGroupName)) {
        throw [System.ArgumentNullException]::new("ResourceGroupName")
    }
    if([String]::IsNullOrEmpty($Location)) {
        throw [System.ArgumentNullException]::new("Location")
    }
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if($null -eq $rg) {
        $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
    }
    
    if($null -eq $rg) {
        throw [Exception]::new("Could not create resource group '$ResourceGroupName' in '$($Location)'.")
    }
    return $rg
}
function GetOrSetKeyVault([String]$ResourceGroupName,[String]$VaultName,
    [String]$Location) {
    if([String]::IsNullOrEmpty($ResourceGroupName)) {
        throw [System.ArgumentNullException]::new("ResourceGroupName")
    }
    if([String]::IsNullOrEmpty($Location)) {
        throw [System.ArgumentNullException]::new("Location")
    }
    if([String]::IsNullOrEmpty($VaultName)) {
        throw [System.ArgumentNullException]::new("VaultName")
    }
    $keyVault = Get-AzKeyVault -VaultName $VaultName -ResourceGroupName $ResourceGroupName `
        -ErrorAction SilentlyContinue
    if($null -eq $keyVault) {
        $keyVault = New-AzKeyVault -Name $VaultName -ResourceGroupName $ResourceGroupName `
            -Location $Location -EnabledForDeployment -EnabledForTemplateDeployment `
            -Sku Standard
    }
    if($null -eq $keyVault) {
        throw [Exception]::new("Could not create key vault '$VaultName' in resource group '$ResourceGroupName' in '$($Location)'.")
    }
    return $keyVault
}
function GetKeyVaultCertificate([String]$VaultName, [String]$CertificateName) {
    if([String]::IsNullOrEmpty($VaultName)) {
        throw [System.ArgumentNullException]::new("VaultName")
    }
    if([String]::IsNullOrEmpty($CertificateName)) {
        throw [System.ArgumentNullException]::new("CertificateName")
    }
    $cert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -ErrorAction SilentlyContinue
    return $cert
}
function NewKeyVaultCertificate([String]$VaultName, [String]$CertificateName,
    [Microsoft.Azure.Commands.KeyVault.Models.PSKeyVaultCertificatePolicy]$Policy
) {   
    if([String]::IsNullOrEmpty($VaultName)) {
        throw [System.ArgumentNullException]::new("VaultName")
    }
    if([String]::IsNullOrEmpty($CertificateName)) {
        throw [System.ArgumentNullException]::new("CertificateName")
    }
    if($null -eq $Policy) {
        throw [System.ArgumentNullException]::new("Policy")
    }
    $cert = Add-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName `
        -CertificatePolicy $Policy
    $firstTime = $true
    do {
        if(-not $firstTime) { Start-Sleep -Seconds 5 }
        $cert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName `
            -ErrorAction SilentlyContinue
        $firstTime = $false
    } while ($null -eq $cert -or $null -eq $cert.Thumbprint -or $null -eq $cert.SecretId)
    return $cert
}
function NewRemoteDebugServerCert([String]$VaultName, [String]$CertificateName,
    [String]$ClusterName) {
    if([String]::IsNullOrEmpty($VaultName)) {
        throw [System.ArgumentNullException]::new("VaultName")
    }
    if([String]::IsNullOrEmpty($CertificateName)) {
        throw [System.ArgumentNullException]::new("CertificateName")
    }
    if([String]::IsNullOrEmpty($ClusterName)) {
        throw [System.ArgumentNullException]::new("ClusterName")
    }
    $keyUsage = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment
    #NOTE: Basic Constraints are not present
    $policy = New-AzKeyVaultCertificatePolicy `
        -SubjectName "CN=$($ClusterName.ToLowerInvariant())" `
        -IssuerName Self -ValidityInMonths 12 `
        -KeyUsage $keyUsage
    return NewKeyVaultCertificate $VaultName $CertificateName $policy
}
function NewRemoteDebugClientCert([String]$VaultName, [String]$CertificateName) {
    if([String]::IsNullOrEmpty($VaultName)) {
        throw [System.ArgumentNullException]::new("VaultName")
    }
    if([String]::IsNullOrEmpty($CertificateName)) {
        throw [System.ArgumentNullException]::new("CertificateName")
    }
    $keyUsage = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment
    #NOTE: Basic Constraints are not present
    $policy = New-AzKeyVaultCertificatePolicy `
        -SubjectName "CN=AzureTools" `
        -IssuerName Self -ValidityInMonths 12 `
        -KeyUsage $keyUsage
    return NewKeyVaultCertificate $VaultName $CertificateName $policy
}
#BEG Main Code
if([String]::IsNullOrEmpty($Environment)) {
    $Environment = "AzureCloud"
}
if([String]::IsNullOrEmpty($VaultName)) {
    $VaultName = "{0}rdkv" -f $ClusterName
}
#Step 1: Ensure environment is as passed
$context = SetupContext $Environment $SubscriptionId $ResetLogin
#Step 2: Create Resource Group
$resouceGroup = GetOrSetResourceGroup $ResourceGroupName $Location
#Step 3: Create Key Vault
$keyVault = GetOrSetKeyVault $ResourceGroupName $VaultName $Location
#Step 4: Create Certificates
$rDebugServeCert = GetKeyVaultCertificate $VaultName $RemoteDebugServerCertificateName
if($null -eq $rDebugServeCert) {
    $rDebugServeCert = NewRemoteDebugServerCert $VaultName $RemoteDebugServerCertificateName $ClusterName
}
$rDebugClientCert = GetKeyVaultCertificate $VaultName $RemoteDebugClientCertificateName
if($null -eq $rDebugClientCert) {
    $rDebugClientCert = NewRemoteDebugClientCert $VaultName $RemoteDebugClientCertificateName
}
#Step 5: Return Properties
[PSCustomObject]@{
    ResourceGroupName=$resouceGroup.ResourceGroupName;
    TenantID=$context.Tenant.Id;
    Location=$resouceGroup.Location;
    KeyVaultID=$keyVault.ResourceId;
    KeyVaultURL=$keyVault.VaultUri;
    RemoteDebuggingServerCertificateThumbprint=$rDebugServeCert.Thumbprint;
    RemoteDebuggingServerCertificateSecretID=$rDebugServeCert.SecretId;
    RemoteDebuggingClientCertificateThumbprint=$rDebugClientCert.Thumbprint;
    RemoteDebuggingClientCertificateSecretID=$rDebugClientCert.SecretId;
}
#END Main Code
