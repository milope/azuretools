/*
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
*/

@description('Represents the Storage Account name. Please note Storage Account names must be unique within an Azure Cloud.')
param StorageAccountName string

@description('Specify a location for all the resource. If not specified, the resource group\'s location will be chosen.')
param Location string = resourceGroup().location

@description('Specify an IPv4 to be allowed to connect to the jumpbox VM.')
param AllowedIP string

@description('Specify an administrator username for the jumpbox.')
param JumpboxUsername string

@description('Specify an administrator password for the jumpbox.')
@secure()
param JumpboxPassword string

@description('Specify a wildcard key vault certificate secret URL to deploy to all app gateways.')
param SSLSecretURL string

@description('Specify a user-assigned Managed Identity to associated with App Gateway. Please ensure this identity can access Key Vault\'s secret')
param KeyVaultManagedIdentityId string

@description('Specify a user-assigned Managed Identity to run the Enable Static Websites. Please ensure this identity can perform this task. This template does not grant access to the resources.')
param StorageAccessManagedIdentityId string

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2022-10-15'
  LabVersion: '1.0'
  LabCategory: 'Azure Storage'
}

var bastionSubnet = '10.0.3.0/24'
var vmSubnet = '10.0.2.0/24'
var appGWSubnet = '10.0.1.0/24'
var storagePESubnet = '10.0.0.0/24'
var storagePEGroupIDs = [
  'blob'
  'file'
  'queue'
  'table'
  'web'
  'dfs'
]
var appGWInternalIP = '10.0.1.4'

var httpListeners = [for (grpId, i) in storagePEGroupIDs: {
    name: 'http-listener-${grpId}'
    properties: {
      frontendIPConfiguration: {
        id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', '${StorageAccountName}-appgw', 'frontend-ip')
      }
      frontendPort: {
        id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', '${StorageAccountName}-appgw', 'frontend-port-80')
      }
      hostName: '${grpId}.contoso.com'
      protocol: 'Http'
    }
}]

var httpsListeners = [for (grpId, i) in storagePEGroupIDs: {
  name: 'https-listener-${grpId}'
  properties: {
    frontendIPConfiguration: {
      id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', '${StorageAccountName}-appgw', 'frontend-ip')
    }
    frontendPort: {
      id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', '${StorageAccountName}-appgw', 'frontend-port-443')
    }
    hostName: '${grpId}.contoso.com'
    protocol: 'Https'
    requireServerNameIndication: true
    sslCertificate: {
      id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', '${StorageAccountName}-appgw', 'ssl-cert')
    }
  }
}]

var allHttpListeners = concat(httpListeners, httpsListeners)

var httpToHttpRedirects = [for (grpId, i) in storagePEGroupIDs: {
  name: 'http-to-https-redirect-${grpId}'
  properties: {
    httpListener: {
      id: resourceId('Microsoft.Network/applicationGateways/httpListeners', '${StorageAccountName}-appgw', 'http-listener-${grpId}')
    }
    redirectConfiguration: {
      id: resourceId('Microsoft.Network/applicationGateways/redirectConfigurations', '${StorageAccountName}-appgw', 'http-to-https-${grpId}')
    }
    ruleType: 'Basic'
    priority: 100 + i
  }
}]

var httpsRequestRoutingRules = [for (grpId, i) in storagePEGroupIDs: {
  name: 'main-rule-${grpId}'
  properties: {
    httpListener: {
      id: resourceId('Microsoft.Network/applicationGateways/httpListeners', '${StorageAccountName}-appgw', 'https-listener-${grpId}')
    }
    backendAddressPool: {
      id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', '${StorageAccountName}-appgw', 'backend-pool-${grpId}')
    }
    backendHttpSettings: {
      id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', '${StorageAccountName}-appgw', 'backend-settings-${grpId}')
    }
    ruleType: 'Basic'
    priority: length(storagePEGroupIDs) + i
  }
}]

var allRoutingRules = concat(httpToHttpRedirects, httpsRequestRoutingRules)

var correlationId = guid(uniqueString(deployment().name))

resource TraceEventStart 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}-trackEventStart'
  location: Location
  tags: tags
  kind: 'AzurePowerShell'
  properties: {
    retentionInterval: 'P1D'
    azPowerShellVersion:'3.0'
    arguments: format('-correlationId "{0}"', correlationId)
    scriptContent: '''
      param (
        [Guid]$correlationId
      )
      $iKey = (Invoke-RestMethod -UseBasicParsing -Uri https://raw.githubusercontent.com/milope/azuretools/master/api/appinsights/instrumentationKey).InstrumentationKey
      $EventName = "Template deployment started."
      $CustomProperties = @{Type="Template";Category="Azure Storage";Name="Azure Storage Custom Domain HTTPS";CorrelationId=$correlationId}
      $AuthUserID = [String]::Empty
      if(-not [String]::IsNullOrEmpty($env:USERDOMAIN) -and $env:USERDOMAIN.Length -gt 0) {
        $AuthUserID = "$($env:USERDOMAIN)\$($env:USERNAME)"
      }
      else {
        $AuthUserID = $env:USERNAME
      }
      $body = (@{
          name = "Microsoft.ApplicationInsights.$iKey.Event"
          time = [DateTime]::UtcNow.ToString("o")
          iKey = $iKey
          tags = @{
              "ai.device.id" = $env:COMPUTERNAME
              "ai.device.locale" = $env:USERDOMAIN
              "ai.user.id" = $env:USERNAME
              "ai.user.authUserId" = $AuthUserID
              "ai.cloud.roleInstance" = $env:COMPUTERNAME
          }
          "data" = @{
              baseType = "EventData"
              baseData = @{
                  ver = "2"
                  name = $EventName
                  properties = ($CustomProperties | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
              }
          }
      }) | ConvertTo-Json -Depth 10 -Compress
      $appInsightsEndpoint = "https://dc.services.visualstudio.com/v2/track"    
      $temp = $ProgressPreference
      $ProgressPreference = "SilentlyContinue"
      try {
        Invoke-WebRequest -Method POST -Uri $appInsightsEndpoint -Headers @{"Content-Type"="application/x-json-stream"} -Body $body -TimeoutSec 3 | Out-Null
      }
      catch {}
      finally {
        $ProgressPreference = $temp
      }
    '''
  }
}

resource AppGWNSG 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: '${StorageAccountName}-appgw-nsg'
  dependsOn: [
    TraceEventStart
  ]
  location: Location
  properties: {
    securityRules: [
      {
        name: 'allow-gwm-in'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          description: 'Allow Gateway Manager inbound.'
          destinationAddressPrefix: '*'
          destinationPortRange: '65200-65535'
          priority: 100
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
        }
      }
      {
        name: 'allow-slb-in'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Allow SLB inbound.'
          destinationAddressPrefix: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          sourcePortRange: '*'
          priority: 101

        }
      }
      {
        name: 'allow-jumpbox-in'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Allow Jumpbox inbound.'
          destinationAddressPrefix: '*'
          sourceAddressPrefix: vmSubnet
          destinationPortRanges: [
            '80'
            '443'
          ]
          sourcePortRange: '*'
          priority: 102
        }
      }
      {
        name: 'deny-in'
        properties: {
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          description: 'Deny all inbound.'
          destinationAddressPrefix: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          sourcePortRange: '*'
          priority: 1000
        }
      }
    ]
  }
}

resource StoragePENSG 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: '${StorageAccountName}-pe-nsg'
  dependsOn: [
    TraceEventStart
  ]
  location: Location
  properties: {
    securityRules: [
      {
        name: 'allow-appgw-subnet-in'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Allow Application Gateway subnet inbound.'
          sourceAddressPrefix: appGWSubnet
          destinationAddressPrefix: storagePESubnet
          destinationPortRange: '443'
          sourcePortRange: '*'
          priority: 100
        }
      }
      {
        name: 'allow-slb-in'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Allow SLB inbound.'
          destinationAddressPrefix: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          sourcePortRange: '*'
          priority: 101

        }
      }
      {
        name: 'deny-all-in'
        properties: {
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          description: 'Deny everything else inbound.'
          destinationAddressPrefix: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          sourcePortRange: '*'
          priority: 1000

        }
      }
      {
        name: 'deny-all-out'
        properties: {
          access: 'Deny'
          direction: 'Outbound'
          protocol: '*'
          description: 'Deny everything else outbound.'
          destinationAddressPrefix: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          sourcePortRange: '*'
          priority: 1000
          
        }
      }
    ]
  }
}

resource BastionNSG 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: '${StorageAccountName}-bastion-nsg'
  dependsOn: [
    TraceEventStart
  ]
  location: Location
  properties: {
    securityRules: [
      {
        name: 'allow-https-inbound'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          description: 'Allow ingress traffic from Allowed IP inbound.'
          priority: 100
          sourceAddressPrefix: '${AllowedIP}/32'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-gwm-inbound'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          description: 'Allow ingress traffic from Gateway Manager inbound.'
          priority: 101
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-slb-inbound'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          description: 'Allow ingress traffic from Load Balancer inbound.'
          priority: 102
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-bastion-host-comm-inbound'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Allow Bastion data plane inbound.'
          priority: 103
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
        }
      }
      {
        name: 'deny-all-in'
        properties: {
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          description: 'Deny everything else inbound.'
          destinationAddressPrefix: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          sourcePortRange: '*'
          priority: 1000

        }
      }
      {
        name: 'allow-ssh-rdp-outbound'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'Allow SSH/RDP outbound.'
          priority: 100
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '22'
            '3389'
          ]
        }
      }
      {
        name: 'allow-cloud-outbound'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'Allow Azure Cloud outbound.'
          priority: 101
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-bastion-host-comm-outbound'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'Allow Bastion data plane outbound.'
          priority: 102
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
        }
      }
      {
        name: 'allow-pki-outbound'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'Allow certificate validation traffic.'
          priority: 103
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

resource VMNSG 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: '${StorageAccountName}-vm-nsg'
  dependsOn: [
    TraceEventStart
  ]
  location: Location
  properties:{
    securityRules: [
      {
        name: 'allow-bastion-subnet-in'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Allow Bastion subnet inbound.'
          sourceAddressPrefix: bastionSubnet
          destinationAddressPrefix: vmSubnet
          destinationPortRanges: [
            '3389'
            '22'
          ]
          sourcePortRange: '*'
          priority: 100
        }
      }
      {
        name: 'allow-slb-in'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Allow SLB inbound.'
          destinationAddressPrefix: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          sourcePortRange: '*'
          priority: 101
        }
      }
      {
        name: 'deny-all-in'
        properties: {
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          description: 'Deny everything else inbound.'
          destinationAddressPrefix: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          sourcePortRange: '*'
          priority: 1000
        }
      }
    ]
  }
}

resource VNET 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: '${StorageAccountName}-vnet'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/22'
      ]
    }
    flowTimeoutInMinutes: 4
    subnets: [
      {
        name: 'storage-pe-subnet'
        properties: {
          addressPrefix: storagePESubnet
          networkSecurityGroup: {
            id: StoragePENSG.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'appgw-subnet'
        properties: {
          addressPrefix: appGWSubnet
          networkSecurityGroup: {
            id: AppGWNSG.id
          }
        }
      }
      {
        name: 'vm-subnet'
        properties: {
          addressPrefix: vmSubnet
          networkSecurityGroup: {
            id: VMNSG.id
          }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnet
          networkSecurityGroup: {
            id: BastionNSG.id
          }
        }
      }
    ]
  }
} 

resource BastionPublicIP 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: '${StorageAccountName}-bastion-pip'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource AppGWPublicIP 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: '${StorageAccountName}-appgw-pip'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource BastionHost 'Microsoft.Network/bastionHosts@2022-05-01' = {
  name: '${StorageAccountName}-bastion'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'ip-config'
        properties: {
          publicIPAddress: {
            id: BastionPublicIP.id
          }
          subnet: {
            id: '${VNET.id}/subnets/AzureBastionSubnet'
          }
        }
      }
    ]
  }
}

resource StorageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: StorageAccountName
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: true
    isHnsEnabled: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
  }
}

resource StaticWebSite 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}-enableStaticWebsite'
  location: Location
  tags: tags
  dependsOn: [
    StorageAccount
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${StorageAccessManagedIdentityId}': {}
    }
  }
  kind: 'AzurePowerShell'
  properties: {
    retentionInterval: 'P1D'
    azPowerShellVersion:'3.0'
    arguments: format('-SubscriptionId "{0}" -ResourceGroupName "{1}" -StorageAccountName "{2}"', subscription().id, resourceGroup().name, StorageAccountName)
    scriptContent: '''
      param (
        [Parameter(Mandatory=$true)][String]$SubscriptionId,
        [Parameter(Mandatory=$true)][String]$ResourceGroupName,
        [Parameter(Mandatory=$true)][String]$StorageAccountName
      )
      
      Start-Sleep -Seconds 5
      Connect-AzAccount -Identity
      Select-AzSubscription -Subscription $SubscriptionId
      $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName
      $ctx = $storageAccount.Context
      Enable-AzStorageStaticWebsite -Context $ctx

    '''
  }
}

resource StoragePE 'Microsoft.Network/privateEndpoints@2022-05-01' = [for grpId in storagePEGroupIDs: {
  name: '${StorageAccountName}-pe-${grpId}'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
    StaticWebSite
  ]
  properties: {
    subnet: {
      id: '${VNET.id}/subnets/storage-pe-subnet'
    }
    privateLinkServiceConnections: [
      {
        name: '${StorageAccountName}-pe'
        properties: {
          privateLinkServiceId: StorageAccount.id
          groupIds: [
            grpId
          ]
        }
      }
    ]
  }
}]

resource PrivateDNSZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for grpId in storagePEGroupIDs: {
  name: 'privatelink.${grpId}.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  dependsOn: [
    StaticWebSite
    TraceEventStart
    VNET
  ]
}]

resource PrivateDNSZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (grpId, i) in storagePEGroupIDs: {
  name: 'privatelink.${grpId}.${environment().suffixes.storage}/vnet-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: VNET.id
    }
  }
  dependsOn: [
    StaticWebSite
    PrivateDNSZones[i]
    TraceEventStart
  ]
}]

resource StoragePEDNSGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = [for (grpId, i) in storagePEGroupIDs: {
  name: '${StoragePE[i].name}/dns-groups'
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    privateDnsZoneConfigs: [
      {
      name: 'config-${grpId}'
      properties: {
        privateDnsZoneId: PrivateDNSZones[i].id
      }
      }
    ]
  }
}]

resource JumpboxNIC 'Microsoft.Network/networkInterfaces@2022-05-01' = {
  name: '${StorageAccountName}-jb-nic'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'ip-config'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${VNET.id}/subnets/vm-subnet'
          }
        }
      }
    ]
  }
}

resource Jumpbox 'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name: '${StorageAccountName}-jb'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_A1'
    }
    osProfile: {
      computerName: 'jumpbox'
      adminPassword: JumpboxPassword
      adminUsername: JumpboxUsername
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-lts'
        version: 'latest'
      }
      osDisk: {
        name: '${StorageAccountName}-osdisk'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: JumpboxNIC.id
        }
      ]
    }
  }
}

resource ContosoPrivateDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'contoso.com'
  location: 'global'
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
}

resource ContosoPrivateDnsARecords 'Microsoft.Network/privateDnsZones/A@2020-06-01' = [for (grpId, i) in storagePEGroupIDs: {
  name: '${ContosoPrivateDns.name}/${grpId}'
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: appGWInternalIP
      }
    ]
  }
}]

resource ContosoPrivateDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${ContosoPrivateDns.name}/vnet-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: VNET.id
    }
  }
}

resource AppGW 'Microsoft.Network/applicationGateways@2022-05-01' = {
  name: '${StorageAccountName}-appgw'
  location: Location
  tags: tags
  dependsOn: [
    StaticWebSite
    ContosoPrivateDns
    ContosoPrivateDnsARecords
    ContosoPrivateDnsLink
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${KeyVaultManagedIdentityId}': {} 
    }
  }
  properties: {
    sku: {
      capacity: 2
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
    gatewayIPConfigurations: [
      {
        name: 'ip-config'
        properties: {
          subnet: {
            id: '${VNET.id}/subnets/appgw-subnet'
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'frontend-port-80'
        properties: {
          port: 80
        }
      }
      {
        name: 'frontend-port-443'
        properties: {
          port: 443
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'frontend-ip'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: appGWInternalIP
          subnet: {
            id: '${VNET.id}/subnets/appgw-subnet'
          }
        }
      }
      {
        name: 'frontend-ip-public'
        properties: {
          publicIPAddress: {
            id: AppGWPublicIP.id
          }
        }
      }
    ]
    sslCertificates: [
      {
        name:'ssl-cert'
        properties: {
          keyVaultSecretId: SSLSecretURL
        }
      }
    ]
    httpListeners: allHttpListeners
    redirectConfigurations: [for (grpId, i) in storagePEGroupIDs: {
      name: 'http-to-https-${grpId}'
      properties: {
        includePath: true
        includeQueryString: true
        redirectType: 'Permanent'
        targetListener: {
          id: resourceId('Microsoft.Network/applicationGateways/httpListeners', '${StorageAccountName}-appgw', 'https-listener-${grpId}')
        }
      }
    }]
    backendAddressPools: [for (grpId, i) in storagePEGroupIDs: {
      name: 'backend-pool-${grpId}'
      properties: {
        backendAddresses: [
          {
            fqdn: replace(replace(replace(reference(StorageAccount.id).primaryEndpoints[grpId], 'https://', ''), 'http://', ''), '/', '')
          }
        ]
      }
    }]
    probes: [for (grpId, i) in storagePEGroupIDs: {
      name: 'storage-probe-${grpId}'
      properties: {
          interval: 30
          pickHostNameFromBackendHttpSettings: true
          port: 443
          protocol: 'Https'
          timeout: 30
          unhealthyThreshold: 3
          path: '/'
          match: {
          statusCodes: [
            '400-499'
          ]
          }
      }
    }]
    backendHttpSettingsCollection: [for (grpId, i) in storagePEGroupIDs: {
      name: 'backend-settings-${grpId}'
      properties: {
        pickHostNameFromBackendAddress: true
        port: 443
        probe: {
          id: resourceId('Microsoft.Network/applicationGateways/probes', '${StorageAccountName}-appgw', 'storage-probe-${grpId}')
        }
        protocol: 'Https'
        cookieBasedAffinity: 'Disabled'
        requestTimeout: 230
      }
    }]
    sslPolicy: {
      disabledSslProtocols: [
         'TLSv1_0'
         'TLSv1_1'
      ]
    }
    requestRoutingRules: allRoutingRules
  }
}

resource TraceEventEnd 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}-trackEventEnd'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
    AppGWNSG
    StoragePENSG
    BastionNSG
    VMNSG
    VNET
    BastionPublicIP
    StorageAccount
    StaticWebSite
    StoragePE
    PrivateDNSZones
    PrivateDNSZoneLink
    StoragePEDNSGroup
    JumpboxNIC
    Jumpbox
    AppGWPublicIP
    AppGW
    ContosoPrivateDns
    ContosoPrivateDnsARecords
    ContosoPrivateDnsLink
  ]
  kind: 'AzurePowerShell'
  properties: {
    retentionInterval: 'P1D'
    azPowerShellVersion:'3.0'
    arguments: format('-correlationId "{0}"', correlationId)
    scriptContent: '''
      param (
        [Guid]$correlationId
      )
      $iKey = (Invoke-RestMethod -UseBasicParsing -Uri https://raw.githubusercontent.com/milope/azuretools/master/api/appinsights/instrumentationKey).InstrumentationKey
      $EventName = "Template deployment completed."
      $CustomProperties = @{Type="Template";Category="Azure Storage";Name="Azure Storage Custom Domain HTTPS";CorrelationId=$correlationId}
      $AuthUserID = [String]::Empty
      if(-not [String]::IsNullOrEmpty($env:USERDOMAIN) -and $env:USERDOMAIN.Length -gt 0) {
        $AuthUserID = "$($env:USERDOMAIN)\$($env:USERNAME)"
      }
      else {
        $AuthUserID = $env:USERNAME
      }
      $body = (@{
          name = "Microsoft.ApplicationInsights.$iKey.Event"
          time = [DateTime]::UtcNow.ToString("o")
          iKey = $iKey
          tags = @{
              "ai.device.id" = $env:COMPUTERNAME
              "ai.device.locale" = $env:USERDOMAIN
              "ai.user.id" = $env:USERNAME
              "ai.user.authUserId" = $AuthUserID
              "ai.cloud.roleInstance" = $env:COMPUTERNAME
          }
          "data" = @{
              baseType = "EventData"
              baseData = @{
                  ver = "2"
                  name = $EventName
                  properties = ($CustomProperties | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
              }
          }
      }) | ConvertTo-Json -Depth 10 -Compress
      $appInsightsEndpoint = "https://dc.services.visualstudio.com/v2/track"    
      $temp = $ProgressPreference
      $ProgressPreference = "SilentlyContinue"
      try {
        Invoke-WebRequest -Method POST -Uri $appInsightsEndpoint -Headers @{"Content-Type"="application/x-json-stream"} -Body $body -TimeoutSec 3 | Out-Null
      }
      catch {}
      finally {
        $ProgressPreference = $temp
      }
    '''
  }
}
