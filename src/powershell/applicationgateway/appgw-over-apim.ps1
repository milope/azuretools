param (
    [String][Parameter(Mandatory=$true)]$apiManagementServiceName,
    [String][Parameter(Mandatory=$true)]$resourceGroupName,
    [String][Parameter(Mandatory=$true)]$vnetName,
    [String][Parameter(Mandatory=$false)]$VNETResourceGroupName,
    [String][Parameter(Mandatory=$true)]$SubnetName,
    [String][Parameter(Mandatory=$true)]$GatewayHostname,
    [String][Parameter(Mandatory=$true)]$DeveloperPortalHostname,
    [String][Parameter(Mandatory=$true)]$LegacyPortalHostname,
    [String][Parameter(Mandatory=$true)]$SCMHostname,
    [String][Parameter(Mandatory=$true)]$ManagementHostname,
    [String][Parameter(Mandatory=$true)]$GatewaySslCertificatePfxPath,
    [String][Parameter(Mandatory=$true)]$DeveloperPortalSslCertificatePfxPath,
    [String][Parameter(Mandatory=$true)]$LegacyPortalSslCertificatePfxPath,
    [String][Parameter(Mandatory=$true)]$SCMSslCertificatePfxPath,
    [String][Parameter(Mandatory=$true)]$ManagementSslCertificatePfxPath,
    [SecureString][Parameter(Mandatory=$true)]$GatewaySslCertificatePfxPassword,
    [SecureString][Parameter(Mandatory=$true)]$DeveloperPortalSslCertificatePfxPassword,
    [SecureString][Parameter(Mandatory=$true)]$LegacyPortalSslCertificatePfxPassword,
    [SecureString][Parameter(Mandatory=$true)]$SCMSslCertificatePfxPassword,
    [SecureString][Parameter(Mandatory=$true)]$ManagementSslCertificatePfxPassword,
    [String][Parameter(Mandatory=$true)]$GatewaySslCertificateCerPath,
    [String][Parameter(Mandatory=$true)]$DeveloperPortalSslCertificateCerPath,
    [String][Parameter(Mandatory=$true)]$LegacyPortalSslCertificateCerPath,
    [String][Parameter(Mandatory=$true)]$SCMSslCertificateCerPath,
    [String][Parameter(Mandatory=$true)]$ManagementSslCertificateCerPath,
    [String][Parameter(Mandatory=$true)]$AppGWName,
    [String][Parameter(Mandatory=$true)]$DNSLabel,
    [String][Parameter(Mandatory=$true)][ValidateSet("Standard_Large", "Standard_Medium", "Standard_Small", "WAF_Large", "WAF_Medium")]$AppGatewaySKUName,
    [String][Parameter(Mandatory=$true)][ValidateSet("Standard", "WAF")]$AppGatewaySKUTier,
    [Int32][Parameter(Mandatory=$true)]$AppGatewayCapacity
)

<#
THIS IS PROVIDED AS IS WITHOUT ANY WARRANTY FOR EDUCATIONAL PURPOSES. I MAY NOT BE HELD LIABLE FOR ANY DAMAGES THIS MAY CAUSE.

This is used to front-end all API Management endpoints using an Application Gateway.
Script assumes:

  • The VNET exists.
  • The APIM exists.
  • A Subnet for the App Gateway exists.
  • APIM is VNET-joined and using an internal configuration.
#>

if($null -eq $VNETResourceGroupName) {
    $VNETResourceGroupName = $resourceGroupName
}

$context = Get-AzContext
if($null -eq $context -or $null -eq $context.Account) {
    throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : Run Connect-AzAccount to login."
}


$apim = Get-AzApiManagement -ResourceGroupName $resourceGroupName -Name $apiManagementServiceName -ErrorAction SilentlyContinue
if($null -eq $apim) {
    throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : API Management $($apiManagementServiceName) was not found in resource group $($resourceGroupName). This script requires APIM to exist"
}

$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $VNETResourceGroupName -ErrorAction SilentlyContinue
if($null -eq $vnet) {
    throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : VNET $($vnetName) was not found in resource group $($VNETResourceGroupName). This script requires the VNET to exist"
}

$subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
if($null -eq $vnet) {
    throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : VNET Subnet $($SubnetName) was not found in vnet $($vnet). This script requires the VNET subnet to exist to create the AppGW"
}

if($null -eq $apim.VirtualNetwork -or $null -eq $apim.VirtualNetwork.SubnetResourceId) {
    throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : API Management $($apiManagementServiceName) is not associated to a VNET. This script requires API Management to be on a VNET with an Internal configuration,"
}

if($null -eq $apim.PrivateIPAddresses -or $apim.PrivateIPAddresses.Count -eq 0) {
    throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : API Management $($apiManagementServiceName) is not in a VNET with Internal configuration. This script requires API Management to be on a VNET with an Internal configuration,"
}

$apimILBIP = $apim.PrivateIPAddresses | Select -First 1

$GatewayHostnameConfiguration = New-AzApiManagementCustomHostnameConfiguration -Hostname $GatewayHostname -HostnameType Proxy -PfxPath $GatewaySslCertificatePfxPath -PfxPassword $GatewaySslCertificatePfxPassword
$DeveloperPortalHostnameConfiguration = New-AzApiManagementCustomHostnameConfiguration -Hostname $DeveloperPortalHostname -HostnameType DeveloperPortal -PfxPath $DeveloperPortalSslCertificatePfxPath -PfxPassword $DeveloperPortalSslCertificatePfxPassword
$LegacyPortalHostnameConfiguration = New-AzApiManagementCustomHostnameConfiguration -Hostname $LegacyPortalHostname -HostnameType Portal -PfxPath $LegacyPortalSslCertificatePfxPath -PfxPassword $LegacyPortalSslCertificatePfxPassword
$SCMHostnameConfiguration = New-AzApiManagementCustomHostnameConfiguration -Hostname $SCMHostname -HostnameType Scm -PfxPath $SCMSslCertificatePfxPath -PfxPassword $SCMSslCertificatePfxPassword
$ManagementHostnameConfiguration = New-AzApiManagementCustomHostnameConfiguration -Hostname $ManagementHostname -HostnameType Management -PfxPath $GatewaySslCertificatePfxPath -PfxPassword $ManagementSslCertificatePfxPassword

$apim.ProxyCustomHostnameConfiguration = $GatewayHostnameConfiguration
$apim.DeveloperPortalHostnameConfiguration = $LegacyPortalHostnameConfiguration
$apim.PortalCustomHostnameConfiguration = $LegacyPortalHostnameConfiguration
$apim.ScmCustomHostnameConfiguration = $SCMHostnameConfiguration
$apim.ManagementCustomHostnameConfiguration = $ManagementHostnameConfiguration

$setAPIMJob = Set-AzApiManagement -InputObject $apim -AsJob

#SKU
$sku = New-AzApplicationGatewaySku -Name $AppGatewaySKUName -Tier $AppGatewaySKUName -Capacity $AppGatewayCapacity

#GATEWAY IP
$gatewayIP = New-AzApplicationGatewayIPConfiguration -Name gateway-ip -Subnet $subnet

#BACKEND POOL
$backendAddressPool = New-AzApplicationGatewayBackendAddressPool -Name "apim-pool" -BackendIPAddresses $apimILBIP

#AUTHCERT

$gatewayBackendCert = New-AzApplicationGatewayAuthenticationCertificate -Name "apim-gateway-cert-auth" -CertificateFile $GatewaySslCertificateCerPath
$developerPortalBackendCert = New-AzApplicationGatewayAuthenticationCertificate -Name "apim-developer-auth-cert" -CertificateFile $GatewaySslCertificateCerPath
$legacyPortalBackendCert = New-AzApplicationGatewayAuthenticationCertificate -Name "apim-portal-auth-cert" -CertificateFile $GatewaySslCertificateCerPath
$scmBackendCert = New-AzApplicationGatewayAuthenticationCertificate -Name "apim-scm-auth-cert" -CertificateFile $GatewaySslCertificateCerPath
$managementBackendCert = New-AzApplicationGatewayAuthenticationCertificate -Name "apim-management-auth-cert" -CertificateFile $GatewaySslCertificateCerPath

$authenticationCertificates = @($gatewayBackendCert, $developerPortalBackendCert, $legacyPortalBackendCert, $scmBackendCert, $managementBackendCert)

#PROBES
$gatewayProbe = New-AzApplicationGatewayProbeConfig -Name "apim-gateway-probe" -Protocol Https -HostName $GatewayHostname -Path "/status-0123456789abcdef" -Interval 30 -Timeout 120 -UnhealthyThreshold 8
$developerPortalProbe = New-AzApplicationGatewayProbeConfig -Name "apim-developer-probe" -Protocol Https -HostName $DeveloperPortalHostname -Path "/signin" -Interval 60 -Timeout 230 -UnhealthyThreshold 8
$legacyPortalProbe = New-AzApplicationGatewayProbeConfig -Name "apim-portal-probe" -Protocol Https -HostName $LegacyPortalHostname -Path "/status-signin" -Interval 60 -Timeout 230 -UnhealthyThreshold 8
$scmProbe = New-AzApplicationGatewayProbeConfig -Name "apim-scm-probe" -Protocol Https -HostName $SCMHostname -Path "/" -Interval 60 -Timeout 230 -UnhealthyThreshold 8
$managementProbe = New-AzApplicationGatewayProbeConfig -Name "apim-management-probe" -Protocol Https -HostName $ManagementHostname -Path "/servicestatus" -Interval 30 -Timeout 230 -UnhealthyThreshold 8

$probes = @($gatewayProbe,$developerPortalProbe,$legacyPortalProbe,$scmProbe,$managementProbe)

#BACKENDHTTPSETTINGS
$gatewayBackendHttpSettings = New-AzApplicationGatewayBackendHttpSetting -Name "apim-gateway-http-settings" -Port 443 -Protocol Https -CookieBasedAffinity Disabled -RequestTimeout 120 `
    -Probe $gatewayProbe -AuthenticationCertificates $gatewayBackendCert
$developerPortalBackendHttpSettings = New-AzApplicationGatewayBackendHttpSetting -Name "apim-developer-http-settings" -Port 443 -Protocol Https -CookieBasedAffinity Disabled -RequestTimeout 120 `
    -Probe $developerPortalProbe -AuthenticationCertificates $developerPortalBackendCert
$legacyPortalBackendHttpSettings = New-AzApplicationGatewayBackendHttpSetting -Name "apim-portal-http-settings" -Port 443 -Protocol Https -CookieBasedAffinity Disabled -RequestTimeout 120 `
    -Probe $legacyPortalProbe -AuthenticationCertificates $legacyPortalBackendCert
$scmBackendHttpSettings = New-AzApplicationGatewayBackendHttpSetting -Name "apim-scm-http-settings" -Port 443 -Protocol Https -CookieBasedAffinity Disabled -RequestTimeout 120 `
    -Probe $scmProbe -AuthenticationCertificates $scmBackendCert
$managementBackendHttpSettings = New-AzApplicationGatewayBackendHttpSetting -Name "apim-management-http-settings" -Port 443 -Protocol Https -CookieBasedAffinity Disabled -RequestTimeout 120 `
    -Probe $managementProbe -AuthenticationCertificates $managementBackendCert

$backendHttpSettings = @($gatewayBackendHttpSettings,$developerPortalBackendHttpSettings,$legacyPortalBackendHttpSettings,$scmBackendHttpSettings,$managementBackendHttpSettings)

#FRONTENDPORTS
$port80 = New-AzApplicationGatewayFrontendPort -Name "http-port" -Port 80
$port443 = New-AzApplicationGatewayFrontendPort -Name "https-port" -Port 443

$frontendPorts = @($port80, $port443)

#FRONTENDIP
$publicIP =  (New-AzPublicIpAddress -Name "$($AppGWName)-public-ip" -ResourceGroupName $VNETResourceGroupName -Location $apim.Location -Sku Basic -AllocationMethod Dynamic -IpAddressVersion IPv4 -DomainNameLabel $DNSLabel)
$frontendIP = New-AzApplicationGatewayFrontendIPConfig -Name "frontend-ip" -PublicIPAddress $publicIP

#SSL CERTIFICATES
$gatewaySslCert = New-AzApplicationGatewaySslCertificate -Name "apim-gateway-ssl-cert" -CertificateFile $GatewaySslCertificatePfxPath -Password $GatewaySslCertificatePfxPassword
$developerPortalSslCert = New-AzApplicationGatewaySslCertificate -Name "apim-developer-ssl-cert" -CertificateFile $DeveloperPortalSslCertificatePfxPath -Password $DeveloperPortalSslCertificatePfxPassword
$legacyPortalSslCert = New-AzApplicationGatewaySslCertificate -Name "apim-portal-ssl-cert" -CertificateFile $LegacyPortalSslCertificatePfxPath -Password $LegacyPortalSslCertificatePfxPassword
$scmSslCert = New-AzApplicationGatewaySslCertificate -Name "apim-scm-ssl-cert" -CertificateFile $SCMSslCertificatePfxPath -Password $SCMSslCertificatePfxPassword
$managementSslCert = New-AzApplicationGatewaySslCertificate -Name "apim-management-ssl-cert" -CertificateFile $ManagementSslCertificatePfxPath -Password $ManagementSslCertificatePfxPassword

$sslCertificates = @($gatewaySslCert,$developerPortalSslCert,$legacyPortalSslCert,$scmSslCert,$managementSslCert)

#HTTPLISTENERS
$gatewayHTTPListener = New-AzApplicationGatewayHttpListener -Name "apim-gateway-listener-http" -Protocol Http -FrontendIPConfiguration $frontendIP -FrontendPort $port80 -HostName $GatewayHostname
$developerPortalHTTPListener = New-AzApplicationGatewayHttpListener -Name "apim-developer-listener-http" -Protocol Http -FrontendIPConfiguration $frontendIP -FrontendPort $port80 -HostName $DeveloperPortalHostname
$legacyPortalHTTPListener = New-AzApplicationGatewayHttpListener -Name "apim-portal-listener-http" -Protocol Http -FrontendIPConfiguration $frontendIP -FrontendPort $port80 -HostName $LegacyPortalHostname
$scmHTTPListener = New-AzApplicationGatewayHttpListener -Name "apim-scm-listener-http" -Protocol Http -FrontendIPConfiguration $frontendIP -FrontendPort $port80 -HostName $SCMHostname
$managementHTTPListener = New-AzApplicationGatewayHttpListener -Name "apim-management-listener-http" -Protocol Http -FrontendIPConfiguration $frontendIP -FrontendPort $port80 -HostName $ManagementHostname


$gatewayHTTPSListener = New-AzApplicationGatewayHttpListener -Name "apim-gateway-listener-https" -Protocol Https -FrontendIPConfiguration $frontendIP -FrontendPort $port443 -HostName $GatewayHostname `
    -SslCertificate $gatewaySslCert -RequireServerNameIndication true
$developerPortalHTTPSListener = New-AzApplicationGatewayHttpListener -Name "apim-developer-listener-https" -Protocol Https -FrontendIPConfiguration $frontendIP -FrontendPort $port443 -HostName $DeveloperPortalHostname `
    -SslCertificate $developerPortalSslCert -RequireServerNameIndication true
$legacyPortalHTTPSListener = New-AzApplicationGatewayHttpListener -Name "apim-portal-listener-https" -Protocol Https -FrontendIPConfiguration $frontendIP -FrontendPort $port443 -HostName $LegacyPortalHostname `
    -SslCertificate $legacyPortalSslCert -RequireServerNameIndication true
$scmHTTPSListener = New-AzApplicationGatewayHttpListener -Name "apim-scm-listener-https" -Protocol Https -FrontendIPConfiguration $frontendIP -FrontendPort $port443 -HostName $SCMHostname `
    -SslCertificate $scmSslCert -RequireServerNameIndication true
$managementHTTPSListener = New-AzApplicationGatewayHttpListener -Name "apim-management-listener-https" -Protocol Https -FrontendIPConfiguration $frontendIP -FrontendPort $port443 -HostName $ManagementHostname `
    -SslCertificate $managementSslCert -RequireServerNameIndication true

$httpListeners = @($gatewayHTTPListener,$developerPortalHTTPListener,$legacyPortalHTTPListener,$scmHTTPListener,$managementHTTPListener,$gatewayHTTPSListener,$developerPortalHTTPSListener,$legacyPortalHTTPSListener,$scmHTTPSListener,$managementHTTPSListener)

#REDIRECT CONFIGURATION
$gatewayRedirectConfiguration = New-AzApplicationGatewayRedirectConfiguration -Name "apim-gateway-redirect-configuration" -RedirectType Permanent -TargetListener $gatewayHTTPListener -IncludePath $true -IncludeQueryString $true
$developerPortalRedirectConfiguration = New-AzApplicationGatewayRedirectConfiguration -Name "apim-developer-redirect-configuration" -RedirectType Permanent -TargetListener $developerPortalHTTPListener -IncludePath $true -IncludeQueryString $true
$legacyPortalRedirectConfiguration = New-AzApplicationGatewayRedirectConfiguration -Name "apim-portal-redirect-configuration" -RedirectType Permanent -TargetListener $legacyPortalHTTPListener -IncludePath $true -IncludeQueryString $true
$scmRedirectConfiguration = New-AzApplicationGatewayRedirectConfiguration -Name "apim-scm-redirect-configuration" -RedirectType Permanent -TargetListener $scmHTTPListener -IncludePath $true -IncludeQueryString $true
$managementRedirectConfiguration = New-AzApplicationGatewayRedirectConfiguration -Name "apim-management-redirect-configuration" -RedirectType Permanent -TargetListener $managementHTTPListener -IncludePath $true -IncludeQueryString $true


$redirectConfigurations = @($gatewayRedirectConfiguration,$developerPortalRedirectConfiguration,$legacyPortalRedirectConfiguration,$scmRedirectConfiguration,$managementRedirectConfiguration)

#RULES

$gatewayRedirectRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-gateway-http-to-https" -RuleType Basic -RedirectConfiguration $gatewayRedirectConfiguration
$developerPortalRedirectRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-developer-http-to-https" -RuleType Basic -RedirectConfiguration $developerPortalRedirectConfiguration
$legacyPortalRedirectRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-portal-http-to-https" -RuleType Basic -RedirectConfiguration $legacyPortalRedirectConfiguration
$scmRedirectRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-scm-http-to-https" -RuleType Basic -RedirectConfiguration $scmRedirectConfiguration
$managementRedirectRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-management-http-to-https" -RuleType Basic -RedirectConfiguration $managementRedirectConfiguration

$gatewayRoutingRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-gateway-routing-rule" -RuleType Basic -BackendHttpSettings $gatewayBackendHttpSettings -HttpListener $gatewayHTTPSListener -BackendAddressPool $backendAddressPool
$developerPortalRoutingRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-developer-routing-rule" -RuleType Basic -BackendHttpSettings $developerPortalBackendHttpSettings `
    -HttpListener $developerPortalHTTPSListener -BackendAddressPool $backendAddressPool
$legacyPortalRoutingRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-portal-routing-rule" -RuleType Basic -BackendHttpSettings $legacyPortalBackendHttpSettings `
    -HttpListener $legacyPortalHTTPSListener -BackendAddressPool $backendAddressPool
$scmRoutingRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-scm-routing-rule" -RuleType Basic -BackendHttpSettings $scmBackendHttpSettings -HttpListener $scmHTTPSListener -BackendAddressPool $backendAddressPool
$managementRoutingRule = New-AzApplicationGatewayRequestRoutingRule -Name "apim-management-routing-rule" -RuleType Basic -BackendHttpSettings $managementBackendHttpSettings -HttpListener $managementHTTPSListener `
    -BackendAddressPool $backendAddressPool

$requestRoutingRules = @($gatewayRedirectRule,$developerPortalRedirectRule,$legacyPortalRedirectRule,$scmRedirectRule,$managementRedirectRule,$gatewayRoutingRule,$developerPortalRoutingRule,$legacyPortalRoutingRule,$scmRoutingRule,$managementRoutingRule)


New-AzApplicationGateway -Name $AppGWName -ResourceGroupName $VNETResourceGroupName -Location $apim.Location -Sku $sku -GatewayIPConfigurations $gatewayIP -SslCertificates $sslCertificates `
    -AuthenticationCertificates $authenticationCertificates -FrontendIPConfigurations $frontendIP -FrontendPorts $frontendPorts -Probes $probes -BackendAddressPools $backendAddressPool `
    -BackendHttpSettingsCollection $backendHttpSettings -HttpListeners $httpListeners -RequestRoutingRules $requestRoutingRules -RedirectConfigurations $redirectConfigurations
