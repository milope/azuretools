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

@description('Use this parameter to prefix all resources created')
param ResourcePrefix string

@description('Specify a location for the resources.')
param Location string = resourceGroup().location

@description('Pass your IP Address to allow through NSG')
param MyIP string

@description('Use this value to represent the Redis spoke VNET and Subnet spoke address space.')
param RedisVNetAddressRange string = '10.0.1.0/24'

@description('Azure Firewall and Bastion Hub VNET address space.')
param HubVNetAddressRange string = '10.0.0.0/24'

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2022-01-15'
  LabVersion: '1.0'
  LabCategory: 'Cache for Redis'
}

var initSuffix = 'core'
var latterSuffix = '.windows.net'

var monitorEndpointSuffix = '${initSuffix}${latterSuffix}'

resource FlowLogStorage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: 'flowlogs${uniqueString(resourceGroup().id)}'
  location: Location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {

  }
}

resource LaWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: '${ResourcePrefix}-oms'
  location: Location
  tags: tags
  properties: {
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource RedisNsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: '${ResourcePrefix}-redis-nsg'
  location: Location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'inbound-allowme'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Allow me through anything'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
          priority: 100
          sourceAddressPrefix: '${MyIP}/32'
          sourcePortRange: '*'
        }
      }
      {
        name: 'outbound-allowme'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'Allow me through anything'
          destinationAddressPrefix: '${MyIP}/32'
          destinationPortRange: '*'
          priority: 101
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
      {
        name: 'inbound-redis-clients'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          description: 'Client communication to Redis, Azure Load Balancing'
          destinationAddressPrefixes: [
            RedisVNetAddressRange
          ]
          destinationPortRanges: [
            '6379-6380'
            '10221-10231'
            '13000-13999'
            '15000-15999'
          ]
          priority: 102
          sourceAddressPrefixes: [
            RedisVNetAddressRange
            HubVNetAddressRange
          ]
          sourcePortRange: '*'
        }
      }
      {
        name: 'inbound-redis-internal-comm'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          description: 'Internal communications for Redis'
          destinationAddressPrefixes: [
            RedisVNetAddressRange
          ]
          destinationPortRanges: [
            '8443'
            '10221-10231'
            '20226'
          ]
          priority: 103
          sourceAddressPrefix:  RedisVNetAddressRange
          sourcePortRange: '*'
        }
      }
      {
        name: 'inbound-azure-slb'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Azure Load Balancing'
          destinationAddressPrefix: RedisVNetAddressRange
          destinationPortRanges: [
            '6379-6380'
            '8500'
            '13000-13999'
            '15000-15999'
            '16001'
          ]
          priority: 104
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
        }
      }
      {
        name: 'outbound-redis-internal-comm'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: 'Tcp'
          description: 'Internal communications for Redis'
          destinationAddressPrefixes: [
            RedisVNetAddressRange
          ]
          destinationPortRanges: [
            '6379-6380'
            '8443'
            '10221-10231'
            '13000-13999'
            '15000-15999'
            '20226'
          ]
          priority: 105
          sourceAddressPrefixes: [
            RedisVNetAddressRange
          ]
          sourcePortRange: '*'
        }
      }
      {
        name: 'outbound-redis-dns'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'Redis dependencies on DNS'
          destinationAddressPrefixes: [
            '168.63.129.16'
            '169.254.169.254'
          ]
          destinationPortRanges: [
            '53'
          ]
          priority: 106
          sourceAddressPrefixes: [
            RedisVNetAddressRange
          ]
          sourcePortRange: '*'
        }
      }
      {
        name: 'outbound-redis-web-dependencies'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'This should allow connections to Storage, PKI, Azure Key Vault and Azure Monitor'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
          priority: 107
          sourceAddressPrefix: RedisVNetAddressRange
          sourcePortRange: '*'
        }
      }
    ]
  }
}

resource AzureFirewallPublicIp 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: '${ResourcePrefix}-az-firewall-pip'
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  location: Location
  properties: {
    dnsSettings: {
      domainNameLabel: '${toLower(ResourcePrefix)}fw'
    }
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource NetworkWatcher 'Microsoft.Network/networkWatchers@2021-03-01' = {
  name: '${ResourcePrefix}-nw'
  tags: tags
  location: Location
  properties: {
    
  }
}

resource FlowLogsRedis 'Microsoft.Network/networkWatchers/flowLogs@2021-03-01' = {
  name: '${NetworkWatcher.name}/flowlogs-redis'
  tags: tags
  location: Location
  properties: {
    targetResourceId: RedisNsg.id
    storageId: FlowLogStorage.id
    enabled: true
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        workspaceResourceId: LaWorkspace.id
        workspaceRegion: LaWorkspace.location
        workspaceId: LaWorkspace.properties.customerId
        trafficAnalyticsInterval: 10
      }
    }
  }
}

resource RedisVnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: '${ResourcePrefix}-redis-vnet'
  tags: tags
  location: Location
  properties: {
    addressSpace: {
      addressPrefixes: [
        RedisVNetAddressRange
      ]
    }
    subnets: [
      {
        name: 'redis-subnet'
        properties: {
          addressPrefix: RedisVNetAddressRange
          networkSecurityGroup: {
            id: RedisNsg.id
          }
        }
      }
    ]
  }
}

resource HubVnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: '${ResourcePrefix}-hub-vnet'
  location: Location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        HubVNetAddressRange
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: HubVNetAddressRange
        }
      }
    ]
  }
}

resource RedisVnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-03-01' = {
  name: '${RedisVnet.name}/redis-to-hub'
  properties: {
    allowForwardedTraffic: true
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: HubVnet.id
    }
  }
}

resource HubVnetPeering  'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-03-01' = {
  name: '${HubVnet.name}/hub-to-redis'
  properties: {
    allowForwardedTraffic: true
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: RedisVnet.id
    }
  }
}

resource AzFirewallPolicy 'Microsoft.Network/firewallPolicies@2021-03-01' = {
  name: '${ResourcePrefix}-fw-policy'
  tags: tags
  location: Location
  properties: {
    sku: {
      tier: 'Standard'
    }
  }
}

resource ForcedAppCollectionRule 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2021-03-01' = {
  name: '${AzFirewallPolicy.name}/forced-app-rule'
  properties: {
    priority: 1002
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'forced-app-rule'
        priority: 1003
        rules: [
          {
            ruleType: 'ApplicationRule'
            description: 'This rule is to force application rule evaluation logic'
            name: 'ForcedAppRule'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
              {
                port: 80
                protocolType: 'Http'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'www.microsoft.com'
            ]
          }
        ]
      }
    ]
  }

}

resource RedisRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2021-03-01' = {
  name: '${AzFirewallPolicy.name}/redis-collection-groups'
  dependsOn: [
    ForcedAppCollectionRule
  ]
  properties: {
    priority: 1000
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'redis-deployment-rules'
        priority: 1001
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-storage'
            description: 'Allow storage to allow for successful deployment'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            terminateTLS: false
            targetFqdns: [
              '*.storage.azure.net'
              '*.blob.${environment().suffixes.storage}'
              '*.queue.${environment().suffixes.storage}' 
              '*.table.${environment().suffixes.storage}'
              '*.file.${environment().suffixes.storage}'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-pki'
            description: 'Azure Microsoft PKI for successful deployment'
            protocols: [
              {
                port: 80
                protocolType: 'Http'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            terminateTLS: false
            targetFqdns: [
              'crl.microsoft.com'
              'ocsp.digicert.com'
              'crl4.digicert.com'
              'ocsp.msocsp.com'
              'mscrl.microsoft.com'
              'crl3.digicert.com'
              'cacerts.digicert.com'
              'oneocsp.microsoft.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-key-vault'
            description: 'Allow storage to allow for successful deployment'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            terminateTLS: false
            targetFqdns: [
              '*${environment().suffixes.keyvaultDns}'
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'redis-dependency-rules-application'
        priority: 1002
        rules: [
          {
            ruleType: 'ApplicationRule'
            description: 'Allowing connections for Azure Monitor purposes'
            name: 'allow-azure-monitor'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'gcs.prod.monitoring.${monitorEndpointSuffix}'
              '*.prod.warm.ingest.monitor.${monitorEndpointSuffix}'
              'global.prod.microsoftmetrics.com'
              'azurewatsonanalysis-prod.${monitorEndpointSuffix}'
              'azredis.prod.microsoftmetrics.com'
              'azredis-black.prod.microsoftmetrics.com'
              'azredis-red.prod.microsoftmetrics.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Allowing connections to Event Hubs'
            name: 'allow-azure-event-hubs'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              '*.servicebus.windows.net'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for windows diagnostic data'
            name: 'allow-windows-diagnostic-data'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'v10.events.data.microsoft.com'
              'v10c.events.data.microsoft.com'
              'v10.vortex-win.data.microsoft.com'
              'watson.telemetry.microsoft.com'
              'watson.telemetry.microsoft.com'
              'watson.microsoft.com'
              'umwatson.events.data.microsoft.com'
              'umwatson.telemetry.data.microsoft.com'
              '*-umwatson.telemetry.data.microsoft.com'
              'umwatsonc.telemetry.microsoft.com'
              'umwatsonc.events.data.microsoft.com'
              '*-umwatsonc.events.data.microsoft.com'
              'ceuswatcab01.blob.${monitorEndpointSuffix}'
              'ceuswatcab02.blob.${monitorEndpointSuffix}'
              'eaus2watcab01.blob.${monitorEndpointSuffix}'
              'eaus2watcab02.blob.${monitorEndpointSuffix}'
              'weus2watcab01.blob.${monitorEndpointSuffix}'
              'weus2watcab02.blob.${monitorEndpointSuffix}'
              'oca.telemetry.microsoft.com'
              'oca.microsoft.com'
              'kmwatsonc.telemetry.microsoft.com'
              '*-kmwatsonc.telemetry.microsoft.com'
              'settings-win.data.microsoft.com'
              '*.live.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for windows update'
            name: 'allow-windows-update'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
              {
                port: 80
                protocolType: 'Http'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'ctldl.windowsupdate.com'
              '*.update.microsoft.com'
              '*.windowsupdate.com'
              'emdl.ws.microsoft.com'
              'delivery.mp.microsoft.com'
              '*.delivery.mp.microsoft.com'
              '*.do.dsp.mp.microsoft.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for connectivity testing'
            name: 'allow-connectivity-test'
            protocols: [
              {
                port: 80
                protocolType: 'Http'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'www.msftconnecttest.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for Windows Device Metadata'
            name: 'allow-windows-device-metadata'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'dmd.metaservices.microsoft.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for Windows Defender'
            name: 'allow-windows-defender-https'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'wdcp.microsoft.com'
              'wdcpalt.microsoft.com'
              '*smartscreen.microsoft.com'
              'definitionupdates.microsoft.com'
              'smartscreen-sn3p.smartscreen.microsoft.com'
              'unitedstates.smartscreen-prod.microsoft.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for Windows Defender'
            name: 'allow-windows-defender-http'
            protocols: [
              {
                port: 80
                protocolType: 'Http'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'dmd.metaservices.microsoft.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for Windows Activation'
            name: 'allow-windows-activation-https'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'go.microsoft.com'
              'validation-v2.sls.microsoft.com'
              'activation.sls.microsoft.com'
              'validation.sls.microsoft.com'
              'activation-v2.sls.microsoft.com'
              'displaycatalog.mp.microsoft.com'
              '*.displaycatalog.mp.microsoft.com'
              'licensing.mp.microsoft.com'
              '*.licensing.mp.microsoft.com'
              'purchase.mp.microsoft.com'
              '*.purchase.mp.microsoft.com'
              'displaycatalog.md.mp.microsoft.com'
              '*.displaycatalog.md.mp.microsoft.com'
              'licensing.md.mp.microsoft.com'
              '*.licensing.md.mp.microsoft.com'
              'purchase.md.mp.microsoft.com'
              '*.purchase.md.mp.microsoft.com'
              '*.live.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for Microsoft Store'
            name: 'allow-microsoft-store'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'clientconfig.passport.net'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for Windows Activation'
            name: 'allow-windows-activation-http'
            protocols: [
              {
                port: 80
                protocolType: 'Http'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'go.microsoft.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            description: 'Used for unknown dependencies'
            name: 'allow-unknown-dependencies-https'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              RedisVNetAddressRange
            ]
            targetFqdns: [
              'shavamanifestcdnprod1.azureedge.net'
              'shavamanifestazurecdnprod1.azureedge.net'
              'azureprofilerfrontdoor.cloudapp.net'
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'redis-dependency-rules-network'
        priority: 1000
        rules: [
          {
            ruleType: 'NetworkRule'
            description: 'Adding Azure Monitor Network Rules'
            destinationAddresses: [
              'AzureCloud'
            ]
            destinationPorts: [
              '12000'
            ]
            ipProtocols: [
              'TCP'
            ]
            name: 'allow-azure-monitor-network'
            sourceAddresses: [
              RedisVNetAddressRange
            ]
          }
          {
            ruleType: 'NetworkRule'
            description: 'Adding KMS'
            destinationAddresses: [
              'AzureCloud'
            ]
            destinationPorts: [
              '1688'
            ]
            ipProtocols: [
              'TCP'
            ]
            name: 'allow-kms'
            sourceAddresses: [
              RedisVNetAddressRange
            ]
          }
          {
            ruleType: 'NetworkRule'
            description: 'Adding NTP'
            destinationAddresses: [
              'AzureCloud'
            ]
            destinationPorts: [
              '123'
            ]
            ipProtocols: [
              'UDP'
            ]
            name: 'allow-ntp'
            sourceAddresses: [
              RedisVNetAddressRange
            ]
          }
        ]
      }
    ]
  }
}

resource AzFirewall 'Microsoft.Network/azureFirewalls@2021-03-01' = {
  name: '${ResourcePrefix}-fw'
  location: Location
  tags: tags
  dependsOn: [
    ForcedAppCollectionRule
    RedisRuleCollectionGroup
  ]
  properties: {
    firewallPolicy: {
      id: AzFirewallPolicy.id
    }
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'fw-public-ip'
        properties: {
          publicIPAddress: {
            id: AzureFirewallPublicIp.id
          }
          subnet: {
            id: '${HubVnet.id}/subnets/AzureFirewallSubnet'
          }
        }
      }
    ]
  }
}

resource AzFirewallDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: AzFirewall
  properties: {
    workspaceId: LaWorkspace.id
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    logs: [
      {
        category: 'AzureFirewallApplicationRule'
        enabled: true
        retentionPolicy: {
            enabled: false
            days: 0
        }
      }
      {
          category: 'AzureFirewallNetworkRule'
          enabled: true
          retentionPolicy: {
              enabled: false
              days: 0
          }
      }
      {
          category: 'AzureFirewallDnsProxy'
          enabled: true
          retentionPolicy: {
              enabled: false
              days: 0
          }
      }
    ]
  }
}

resource Udr 'Microsoft.Network/routeTables@2021-03-01' = {
  name: '${ResourcePrefix}-rt'
  location: Location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'forced-tunnel'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          hasBgpOverride: false
          nextHopIpAddress: AzFirewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

resource UdrToSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-03-01' = {
  name: '${RedisVnet.name}/redis-subnet'
  properties: {
    addressPrefix: RedisVNetAddressRange
    networkSecurityGroup: {
      id: RedisNsg.id
    }
    routeTable: {
      id: Udr.id
    }
  }
}

// Ensuring Azure Cache for Redis is deployed as last as possible
resource Redis 'Microsoft.Cache/redis@2020-12-01' = {
  location: Location
  tags: tags
  name: '${toLower(ResourcePrefix)}redis'
  dependsOn: [
    AzFirewall
    AzFirewallDiagnostics
    ForcedAppCollectionRule
    RedisRuleCollectionGroup
    Udr
    UdrToSubnet
  ]
  properties: {
    sku: {
      capacity: 1
      family: 'P'
      name: 'Premium'
    }
    enableNonSslPort: true
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    redisVersion: '4'
    subnetId: '${RedisVnet.id}/subnets/redis-subnet'
  }
}

resource RedisDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: Redis
  properties: {
    workspaceId: LaWorkspace.id
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
    logs: [
      {
        enabled: true
        category: 'ConnectedClientList'
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
  }
}

output DataExplorerClusterUrl string = 'https://ade.loganalytics.io${LaWorkspace.id}'
output CacheForRedisHostName string = Redis.properties.hostName
output CacheForRedisIp string = Redis.properties.staticIP
output AzFirewallPublicIp string = AzureFirewallPublicIp.properties.ipAddress
output AzFirewallPrivateIp string = AzFirewall.properties.ipConfigurations[0].properties.privateIPAddress
