/*
Copyright © 2021 Michael Lopez
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

*/

@description('Must fit inside the VnetAddresRange value but not overlap with the ApplicationGatewaySubnetAddressRange value.')
param ApiManagementSubnetAddressRange string = '10.0.1.0/24'
@description('DNS label for API Management.')
param ApiManagementDnsLabel string
@description('DNS label for application gateway.')
param ApplicationGatewayDnsLabel string
@description('Specify the Application Gateway SSL certificate in base-64 encoded data.')
param ApplicationGatewaySslCertificate string
@secure()
@description('Specify the Application Gateway SSL certificate password.')
param ApplicationGatewaySslCertificatePassword string
@description('Must fit inside the VnetAddresRange value but not overlap with the ApiManagementSubnetAddressRange value.')
param ApplicationGatewaySubnetAddressRange string = '10.0.0.0/24'
@description('Array of base-64 encoded trusted client certificates.')
param ApplicationGatewayTrustedClientCerts array
@description('Specify your IP to be allowed to send HTTP/S requests to Application Gateway.')
param MyIP string
@description('Specify a location for the resources.')
param Location string = resourceGroup().location
@description('API Management Publisher E-mail.')
param PublisherEmail string
@description('API Management Publisher Name.')
param PublisherName string
@minLength(2)
@maxLength(7)
@description('ResourcePrefix will be a prefix for all main resources.')
param ResourcePrefix string
@description('Specify the VNET address range, keeping in mind they will be split between an Application Gateway and API Management subnets.')
param VnetAddressRange string = '10.0.0.0/23'

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2021-11-13'
  LabVersion: '1.0'
  LabCategory: 'API Management'
}

var environmentSuffix = {
  AzureCloud: 'azure-api.net'
  AzureUSGovernment: 'azure-api.us'
  AzureChinaCloud: 'azure-api.cn'
  AzureGermanCloud: 'azure-api.de'
}

var trustedClientCertsCount = length(ApplicationGatewayTrustedClientCerts)
var trustedClientCerts = [for i in range(0, trustedClientCertsCount): {
  name: 'trusted-client-cert-${i + 1}'
  properties: {
    data: ApplicationGatewayTrustedClientCerts[i]
  }
}]

var appGwId = '${resourceGroup().id}/providers/Microsoft.Network/applicationGateways/${ResourcePrefix}-appgw'
var sslPolicyTrustedCerts = [for i in range(0, trustedClientCertsCount): {
  id: '${appGwId}/trustedClientCertificates/trusted-client-cert-${i + 1}'
}]


resource ApimNsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: '${ResourcePrefix}-apim-nsg'
  location: Location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-appgw-http-in'
        properties: {
          priority: 100
          access: 'Allow'
          protocol: 'Tcp'
          direction: 'Inbound'
          description: 'Allows Application Gateway to forward HTTP requests to APIM.'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: ApplicationGatewaySubnetAddressRange
          destinationAddressPrefix: ApiManagementSubnetAddressRange
        }
      }
      {
        name: 'allow-appgw-https-in'
        properties: {
          priority: 101
          access: 'Allow'
          protocol: 'Tcp'
          direction: 'Inbound'
          description: 'Allows Application Gateway to forward HTTPS requests to APIM.'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: ApplicationGatewaySubnetAddressRange
          destinationAddressPrefix: ApiManagementSubnetAddressRange
        }
      }
      {
        name: 'allow-apim-control-plane-in'
        properties: {
          priority: 102
          access: 'Allow'
          protocol: 'Tcp'
          direction: 'Inbound'
          description: 'Allows the API Management Control Plane to manage API Management.'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: ApiManagementSubnetAddressRange
        }
      }
      {
        name: 'allow-slb-in'
        properties: {
          priority: 103
          access: 'Allow'
          protocol: '*'
          direction: 'Inbound'
          description: 'Allows Azure Software Load Balancer to probe APIM instances.'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: ApiManagementSubnetAddressRange
        }
      }
    ]
  }
}

resource AppGwNsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: '${ResourcePrefix}-appgw-nsg'
  location: Location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-my-http-in'
        properties: {
          priority: 100
          description: 'Allows my IP to send HTTP requests to Application Gateway.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '${MyIP}/32'
          destinationAddressPrefix: ApplicationGatewaySubnetAddressRange
          access: 'Allow'
          direction: 'Inbound'
        }
      }
      {
        name: 'allow-my-https-in'
        properties: {
          priority: 101
          description: 'Allows my IP to send HTTPS requests to Application Gateway.'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '${MyIP}/32'
          destinationAddressPrefix: ApplicationGatewaySubnetAddressRange
          access: 'Allow'
          direction: 'Inbound'
        }
      }
      {
        name: 'allow-healthprobes-in'
        properties: {
          priority: 102
          description: 'Allows Gateway Manager to probe Application Gateway.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*' //This cannot be avoided as anything else would cause an exception stating the ports are blocked
          access: 'Allow'
          direction: 'Inbound'
        }
      }
      {
        name: 'allow-slb-in'
        properties: {
          priority: 103
          description: 'Allows Azure Software Load Balancer to probe Application Gateway.'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: ApplicationGatewaySubnetAddressRange
          access: 'Allow'
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource Vnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: '${ResourcePrefix}-vnet'
  location: Location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        VnetAddressRange
      ]
    }
    subnets: [
      {
        name: 'appgw-subnet'
        properties: {
          addressPrefix: ApplicationGatewaySubnetAddressRange
          networkSecurityGroup: {
            id: AppGwNsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.Storage'
            }
          ]
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'apim-subnet'
        properties: {
          addressPrefix: ApiManagementSubnetAddressRange
          networkSecurityGroup: {
            id: ApimNsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.EventHub'
            }
            {
              service: 'Microsoft.AzureActiveDirectory'
            }
            {
              service: 'Microsoft.Sql'
            }
          ]
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource AppGwPublicIp 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: '${ResourcePrefix}-appgw-pip'
  location: Location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: toLower(ApplicationGatewayDnsLabel)
    }
  }
}

resource ApimPublicIp 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: '${ResourcePrefix}-apim-pip'
  location: Location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: toLower(ApiManagementDnsLabel)
    }
  }
}

resource PrivateDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: environmentSuffix[environment().name]
  location: 'global'
  tags: tags
}

resource PrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${PrivateDns.name}/vnet-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: Vnet.id
    }
  }
}

resource Apim 'Microsoft.ApiManagement/service@2021-04-01-preview' = {
  name: toLower('${ResourcePrefix}-apim')
  location: Location
  tags: tags
  properties: {
    publisherEmail: PublisherEmail
    publisherName: PublisherName
    virtualNetworkConfiguration: {
      subnetResourceId: '${Vnet.id}/subnets/apim-subnet'
    }
    virtualNetworkType: 'Internal'
    publicIpAddressId: ApimPublicIp.id
  }
  sku: {
    name: 'Developer'
    capacity: 1
  }
}

resource PrivateDnsZoneA 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: '${PrivateDns.name}/${Apim.name}'
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: Apim.properties.privateIPAddresses[0]
      }
    ]
  }
}

resource ApimCertApi 'Microsoft.ApiManagement/service/apis@2021-04-01-preview' = {
  name: '${Apim.name}/cert-echo-api'
  properties: {
    displayName: 'cert-echo-api'
    description: 'This API is used to display the passed certificate, if any.'
    subscriptionRequired: false
    serviceUrl: 'https://127.0.0.1/certapi'
    path: 'certapi'
    protocols: [
      'https'
    ]
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key' 
    }
  }
}

resource ApiCertApiOperation 'Microsoft.ApiManagement/service/apis/operations@2021-04-01-preview' = {
  name: '${ApimCertApi.name}/cert-api-op-get'
  properties: {
    urlTemplate: '/'
    method: 'GET'
    displayName: 'Retrieves the provided (if any) certificate\'s properties'
  }
}

resource ApiCertApiOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2021-04-01-preview' = {
  name: '${ApiCertApiOperation.name}/policy'
  properties: {
    format: 'xml'
    value: '''<policies>
    <inbound>
      <base />
      <set-variable name="HasCertificate" value="@(false)" />
      <choose>
        <when condition="@(context.Request.Headers.GetValueOrDefault(&quot;X-ClientCert&quot;, &quot;&quot;).Length &gt; 0)">
          <set-variable name="HasCertificate" value="@(true)" />
          <set-variable name="CertIssuer" value="@(context.Request.Headers.GetValueOrDefault(&quot;X-ClientCert-Issuer&quot;, &quot;&quot;))" />
          <set-variable name="CertNotBefore" value="@(context.Request.Headers.GetValueOrDefault(&quot;X-ClientCert-NotBefore&quot;, &quot;&quot;))" />
          <set-variable name="CertNotAfter" value="@(context.Request.Headers.GetValueOrDefault(&quot;X-ClientCert-NotAfter&quot;, &quot;&quot;))" />
          <set-variable name="CertSubject" value="@(context.Request.Headers.GetValueOrDefault(&quot;X-ClientCert-Subject&quot;, &quot;&quot;))" />
          <set-variable name="CertThumbprint" value="@(context.Request.Headers.GetValueOrDefault(&quot;X-ClientCert-Thumbprint&quot;, &quot;&quot;))" />
          <set-variable name="CertSerialNumber" value="@(context.Request.Headers.GetValueOrDefault(&quot;X-ClientCert-Serial&quot;, &quot;&quot;))" />
        </when>
        <when condition="@(context.Request.Certificate != null)">
          <set-variable name="HasCertificate" value="@(true)" />
          <set-variable name="CertIssuer" value="@(context.Request.Certificate.IssuerName.Name)" />
          <set-variable name="CertNotBefore" value="@(context.Request.Certificate.NotBefore.ToString(&quot;R&quot;))" />
          <set-variable name="CertNotAfter" value="@(context.Request.Certificate.NotAfter.ToString(&quot;R&quot;))" />
          <set-variable name="CertSubject" value="@(context.Request.Certificate.SubjectName.Name)" />
          <set-variable name="CertThumbprint" value="@(context.Request.Certificate.Thumbprint)" />
          <set-variable name="CertSerialNumber" value="@(context.Request.Certificate.SerialNumber)" />
        </when>
      </choose>
      <choose>
        <when condition="@(!context.Variables.GetValueOrDefault&lt;bool&gt;(&quot;HasCertificate&quot;))">
          <return-response>
            <set-status code="401" reason="Unauthorized" />
            <set-header name="Content-Type" exists-action="override">
              <value>text/html</value>
            </set-header>
            <set-body>&lt;!DOCTYPE html&gt;
              &lt;html&gt;
              &lt;head&gt;
              &lt;title&gt;Unauthorized&lt;/title&gt;
              &lt;/head&gt;
              &lt;body&gt;
              &lt;h1&gt;Certificate Echo API Result&lt;/h1&gt;
              &lt;h2&gt;Unauthorized&lt;/h2&gt;
              &lt;/body&gt;
              &lt;/html&gt;</set-body>
          </return-response>
        </when>
        <otherwise>
          <return-response>
            <set-status code="200" reason="OK" />
            <set-header name="Content-Type" exists-action="override">
              <value>text/html</value>
            </set-header>
            <set-body>@{
              return string.Concat("&lt;!DOCTYPE html&gt;&lt;html&gt;&lt;head&gt;&lt;title&gt;",
                "Certificate Echo API",
                "&lt;/title&gt;&lt;/head&gt;&lt;body&gt;&lt;h1&gt;Certificate Echo API Result&lt;/h1&gt;",
                "&lt;table&gt;&lt;thead&gt;&lt;tr&gt;&lt;th&gt;Property Name&lt;/th&gt;&lt;th&gt;Property Value&lt;/th&gt;&lt;/tr&gt;&lt;/thead&gt;&lt;tbody&gt;",
                "&lt;tr&gt;&lt;td&gt;Issuer&lt;/td&gt;&lt;td&gt;", context.Variables["CertIssuer"], "&lt;/td&gt;&lt;/tr&gt;",
                "&lt;tr&gt;&lt;td&gt;Not Before&lt;/td&gt;&lt;td&gt;", context.Variables["CertNotBefore"], "&lt;/td&gt;&lt;/tr&gt;",
                "&lt;tr&gt;&lt;td&gt;Not After&lt;/td&gt;&lt;td&gt;", context.Variables["CertNotAfter"], "&lt;/td&gt;&lt;/tr&gt;",
                "&lt;tr&gt;&lt;td&gt;Serial&lt;/td&gt;&lt;td&gt;", context.Variables["CertSerialNumber"], "&lt;/td&gt;&lt;/tr&gt;",
                "&lt;tr&gt;&lt;td&gt;Subject&lt;/td&gt;&lt;td&gt;", context.Variables["CertSubject"], "&lt;/td&gt;&lt;/tr&gt;",
                "&lt;tr&gt;&lt;td&gt;Thumbprint&lt;/td&gt;&lt;td&gt;", context.Variables["CertThumbprint"], "&lt;/td&gt;&lt;/tr&gt;",
                "&lt;/tbody&gt;&lt;tfoot /&gt;&lt;/table&gt;&lt;/body&gt;&lt;/html&gt;"
              );
            }</set-body>
          </return-response>
        </otherwise>
      </choose>
    </inbound>
    <backend>
      <base />
    </backend>
    <outbound>
      <base />
    </outbound>
    <on-error>
      <base />
    </on-error>
    </policies>'''
  }
}

resource AppGw 'Microsoft.Network/applicationGateways@2021-03-01' = {
  name: '${ResourcePrefix}-appgw'
  location: Location
  tags: tags
  properties: {
    sku: {
      capacity: 2
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
    sslPolicy: {
      policyName: 'AppGwSslPolicy20170401S'
      policyType: 'Predefined'
    }
    gatewayIPConfigurations: [
      {
        name: 'gateway-ip'
        properties: {
          subnet: {
            id: '${Vnet.id}/subnets/appgw-subnet'
          }
        }
      }
    ]
    sslCertificates: [
      {
        name: 'gateway-ssl-cert'
        properties: {
          data: ApplicationGatewaySslCertificate
          password: ApplicationGatewaySslCertificatePassword
        }
      }
    ]
    trustedClientCertificates: trustedClientCerts
    sslProfiles: [
      {
        name: 'gateway-ssl-profile'
        properties: {
          sslPolicy: {
            policyName: 'AppGwSslPolicy20170401S'
            policyType: 'Predefined'
          }
          clientAuthConfiguration: {
            verifyClientCertIssuerDN: true
          }
          trustedClientCertificates: sslPolicyTrustedCerts
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'gateway-frontend-ip'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: AppGwPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'gateway-http-port'
        properties: {
          port: 80
        }
      }
      {
        name: 'gateway-https-port'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'gateway-backend-apim-pool'
        properties: {
          backendAddresses: [
            {
              fqdn: '${Apim.name}.${PrivateDns.name}'
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'apim-proxy-probe'
        properties: {
          protocol: 'Https'
          host: '${Apim.name}.${PrivateDns.name}'
          path: '/status-0123456789abcdef'
          interval: 30
          timeout: 120
          unhealthyThreshold: 8
          pickHostNameFromBackendHttpSettings: false
          minServers: 0
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'gateway-http-settings'
        properties: {
          port: 443
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          probe: {
            id: '${appGwId}/probes/apim-proxy-probe'
          }
          protocol: 'Https'
          requestTimeout: 30
        }
      }
    ]
    httpListeners: [
      {
        name: 'gateway-http-listener'
        properties: {
          frontendIPConfiguration: {
            id: '${appGwId}/frontendIPConfigurations/gateway-frontend-ip'
          }
          frontendPort: {
            id: '${appGwId}/frontendPorts/gateway-http-port'
          }
          protocol: 'Http'
        }
      }
      {
        name: 'gateway-https-listener'
        properties: {
          frontendIPConfiguration: {
            id: '${appGwId}/frontendIPConfigurations/gateway-frontend-ip'
          }
          frontendPort: {
            id: '${appGwId}/frontendPorts/gateway-https-port'
          }
          protocol: 'Https'
          requireServerNameIndication: false
          sslCertificate: {
            id: '${appGwId}/sslCertificates/gateway-ssl-cert'
          }
          sslProfile: {
            id: '${appGwId}/sslProfiles/gateway-ssl-profile'
          }
        }
      }
    ]
    rewriteRuleSets: [
      {
        name: 'gateway-rewrite-rule-set'
        properties: {
          rewriteRules: [
            {
              ruleSequence: 100
              name: 'gateway-rewrite-rule'
              actionSet: {
                requestHeaderConfigurations: [
                  {
                    headerName: 'X-ClientCert'
                    headerValue: '{var_client_certificate}'
                  }
                  {
                    headerName: 'X-ClientCert-Issuer'
                    headerValue: '{var_client_certificate_issuer}'
                  }
                  {
                    headerName: 'X-ClientCert-NotAfter'
                    headerValue: '{var_client_certificate_end_date}'
                  }
                  {
                    headerName: 'X-ClientCert-NotBefore'
                    headerValue: '{var_client_certificate_start_date}'
                  }
                  {
                    headerName: 'X-ClientCert-Subject'
                    headerValue: '{var_client_certificate_subject}'
                  }
                  {
                    headerName: 'X-ClientCert-Thumbprint'
                    headerValue: '{var_client_certificate_fingerprint}'
                  }
                  {
                    headerName: 'X-ClientCert-Serial'
                    headerValue: '{var_client_certificate_serial}'
                  }
                ]
              }
            }
          ]
        }
      }
    ]
    enableHttp2: true
    redirectConfigurations: [
      {
        name: 'gateway-http-to-https'
        properties: {
          redirectType: 'Permanent'
          targetListener: {
            id: '${appGwId}/httpListeners/gateway-https-listener'
          }
          includePath: true
          includeQueryString: true
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'gateway-rule-redirect-to-https'
        properties: {
          httpListener: {
            id: '${appGwId}/httpListeners/gateway-http-listener'
          }
          redirectConfiguration: {
            id: '${appGwId}/redirectConfigurations/gateway-http-to-https'
          }
          ruleType: 'Basic'
        }
      }
      {
        name: 'gateway-rule-mutual-tls-https'
        properties: {
          httpListener: {
            id: '${appGwId}/httpListeners/gateway-https-listener'
          }
          ruleType: 'Basic'
          backendAddressPool: {
            id: '${appGwId}/backendAddressPools/gateway-backend-apim-pool'
          }
          backendHttpSettings: {
            id: '${appGwId}/backendHttpSettingsCollection/gateway-http-settings'
          }
          rewriteRuleSet: {
            id: '${appGwId}/rewriteRuleSets/gateway-rewrite-rule-set'
          }
        }
      }
    ]
  }
}

output ApplicationGatewayEndpoint string = 'https://${AppGwPublicIp.properties.dnsSettings.fqdn}/'
