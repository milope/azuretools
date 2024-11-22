param Location string = resourceGroup().location
param CacheName string
param FirewallDnsLabel string
param SpokeIPRange string = '10.0.0.0/24'
param HubIPRange string = '10.0.1.0/24'

var tags = {
  Lab: 'DependencyDump'
}

resource PublicIpAddress 'Microsoft.Network/publicIPAddresses@2024-03-01' = {
  name: '${CacheName}-fw-ip'
  location: Location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  tags: tags
  properties: {
    deleteOption: 'Delete'
    dnsSettings: {
      domainNameLabel:FirewallDnsLabel
    }
    idleTimeoutInMinutes: 10
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource LaWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: '${CacheName}-logs'
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

resource NetworkSecurityGroups 'Microsoft.Network/networkSecurityGroups@2024-03-01' = {
  name: '${CacheName}-nsg'
  location: Location
  tags: tags
  properties: {
    securityRules: [

    ]
  }
}

resource RedisVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-03-01' = {
  name: '${CacheName}-spoke-vnet'
  location: Location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        SpokeIPRange
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: SpokeIPRange
          networkSecurityGroup: {
            id: NetworkSecurityGroups.id
          } 
        }
      }
    ]
  }
}

resource FirewallVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-03-01' = {
  name: '${CacheName}-hub-vnet'
  location: Location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        HubIPRange
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: HubIPRange
        }
      }
    ]
  }
}

resource FirewallToRedisPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-03-01' = {
  name: 'hub-to-spoke-peering'
  parent: FirewallVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    remoteVirtualNetwork: {
      id: RedisVirtualNetwork.id
    }
  }
}

resource RedisToFirewallPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-03-01' = {
  name: 'spoke-to-hub-peering'
  parent: RedisVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    remoteVirtualNetwork: {
      id: FirewallVirtualNetwork.id
    }
  }
}

resource FirewallPolicy 'Microsoft.Network/firewallPolicies@2024-03-01' = {
  name: '${CacheName}-fwpolicy'
  tags: tags
  location: Location
  properties: {
    sku: {
      tier:'Standard'
    }
  }
}

resource ForcedAppCollectionRule 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2021-03-01' = {
  name: 'forced-app-rule'
  parent: FirewallPolicy
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
              SpokeIPRange
            ]
            targetFqdns: [
              'www.github.com'
            ]
          }
        ]
      }
    ]
  }
}

resource RedisRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2021-03-01' = {
  name: 'redis-collection-groups'
  parent: FirewallPolicy
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
        name: 'redis-deployment-network-rules'
        priority: 1001
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'allow-deployment-dependencies-tcp'
            description: 'Allow Cache for Redis dependencies for successful deployment'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              SpokeIPRange
            ]
            destinationAddresses: [
              'AzureCloud'
            ]
            destinationPorts: [
              '1688'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'allow-deployment-dependencies-udp'
            description: 'Allow Cache for Redis dependencies for successful deployment'
            ipProtocols: [
              'UDP'
            ]
            sourceAddresses: [
              SpokeIPRange
            ]
            destinationAddresses: [
              'AzureCloud'
            ]
            destinationPorts: [
              '123'
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'redis-deployment-application-rules'
        priority: 1002
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'allow-deployment-dependencies-https'
            description: 'Allow Cache for Redis dependencies for successful deployment'
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            sourceAddresses: [
              SpokeIPRange
            ]
            terminateTLS: false
            targetFqdns: [
              'www.microsoft.com'
              'go.microsoft.com'
              '*.blob.${environment().suffixes.storage}'
              'settings-win.data.microsoft.com'
              '*.update.microsoft.com'
              '*.events.data.microsoft.com'
              '*${environment().suffixes.keyvaultDns}'
              '*.queue.${environment().suffixes.storage}'
              'gcs.prod.monitoring.${environment().suffixes.storage}'
              '*.prod.warm.ingest.monitor.${environment().suffixes.storage}'
              'definitionupdates.microsoft.com'
              '*.delivery.mp.microsoft.com'
              'validation-v2.sls.microsoft.com'
              'wdcp.microsoft.com'
              'wdcpalt.microsoft.com'
            ]
          }
          {
            ruleType: 'ApplicationRule'
            name: 'allow-deployment-dependencies-http'
            description: 'Allow Cache for Redis dependencies for successful deployment'
            protocols: [
              {
                port: 80
                protocolType: 'Http'
              }
            ]
            sourceAddresses: [
              SpokeIPRange
            ]
            terminateTLS: false
            targetFqdns: [
              'www.msftconnecttest.com'
              'ctldl.windowsupdate.com'
              'crl.microsoft.com'
            ]
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'redis-runtime-network-rules'
        priority: 1003
        rules: [
          // Populate this as we make more discoveries
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        name: 'redis-runtime-application-rules'
        priority: 1004
        rules: [
          // Populate this as we make more discoveries
        ]
      }
    ]
  }
}

resource AzFirewall 'Microsoft.Network/azureFirewalls@2024-03-01' = {
  name: '${CacheName}-fw'
  location: Location
  tags: tags
  dependsOn: [
    ForcedAppCollectionRule
    RedisRuleCollectionGroup
  ]
  properties: {
    firewallPolicy: {
      id: FirewallPolicy.id
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
            id: PublicIpAddress.id
          }
          subnet: {
            id: '${FirewallVirtualNetwork.id}/subnets/AzureFirewallSubnet'
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
    logAnalyticsDestinationType: 'Dedicated'
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
        categoryGroup: 'AllLogs'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
  }
}

resource RouteTable 'Microsoft.Network/routeTables@2024-03-01'= {
  name: '${CacheName}-rt'
  location: resourceGroup().location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'forced-tunnel'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: AzFirewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

resource UdrToSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-03-01' = {
  name: 'default'
  parent: RedisVirtualNetwork
  properties: {
    addressPrefix: SpokeIPRange
    networkSecurityGroup: {
      id: NetworkSecurityGroups.id
    }
    routeTable: {
      id: RouteTable.id
    }
  }
}

resource Redis 'Microsoft.Cache/redis@2024-11-01' = {
  location: Location
  tags: tags
  name: toLower(CacheName)
  dependsOn: [
    AzFirewall
    AzFirewallDiagnostics
    ForcedAppCollectionRule
    RedisRuleCollectionGroup
    RouteTable
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
    redisVersion: '6'
    subnetId: UdrToSubnet.id
  }
}

output DataExplorerCluster string = LaWorkspace.id
