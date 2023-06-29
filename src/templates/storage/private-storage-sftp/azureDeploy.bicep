/*
Copyright © 2023 Michael Lopez
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

@description('Specify the name for the Storage Account we\'re trying to recover items for.')
param StorageAccountName string
@description('Specify a location. Ideally, this should be the same location as the Storage Account to avoid ingress/egress data.')
param Location string = resourceGroup().location
@description('This deployment is a secure deployment. Add your external IP to add to the jumpbox VM.')
param AllowedIP string
@description('Specify an administrator username for the jumpbox.')
param JumpboxUsername string
@description('Specify an administrator password for the jumpbox.')
@secure()
param JumpboxPassword string
@description('Specify an local user username for the SFTP.')
param SftpLocalUsername string

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2023-05-22'
  LabVersion: '1.0'
  LabCategory: 'Storage'
}

var jumpboxPrefix = '10.0.0.0/24'
var storagePEPrefix = '10.0.1.0/24'

resource Storage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  kind: 'StorageV2'
  location: Location
  name: StorageAccountName
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowedCopyScope: 'PrivateLink'
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    dnsEndpointType: 'Standard'
    isHnsEnabled: true
    isLocalUserEnabled: true
    isSftpEnabled: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Deny'
    }
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
  }
}

resource StorageBlobServices 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: Storage
  name: 'default'
  properties: {
    
  }
}

resource SftpContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: StorageBlobServices
  name: 'home'
  properties: {
    publicAccess: 'None'
  }
}

resource SftpLocalUsers 'Microsoft.Storage/storageAccounts/localUsers@2022-09-01' = {
  parent: Storage
  name: SftpLocalUsername
  properties: {
    permissionScopes: [
      {
        permissions: 'rcwdl'
        resourceName: 'home'
        service: 'blob'
      }
    ]
    hasSshKey: false
    hasSshPassword: true
    homeDirectory: 'home'
  }
}

resource JumpboxNSG 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: '${StorageAccountName}-JBNSG'
  location: Location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowedIP-Inbound-All'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
          protocol: '*'
          description: 'Allows the \'Allowed\' IP to connect inbound.'
          destinationAddressPrefix: jumpboxPrefix
          destinationPortRange: '*'
          sourceAddressPrefix: '${AllowedIP}/32'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowedIP-Outbound-All'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          priority: 100
          protocol: '*'
          description: 'Allows the \'Allowed\' IP to connect inbound.'
          destinationAddressPrefix: '${AllowedIP}/32'
          destinationPortRange: '*'
          sourceAddressPrefix: jumpboxPrefix
          sourcePortRange: '*'
        }
      }
    ]
  }
}

resource PENSG 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: '${StorageAccountName}-PENSG'
  location: Location
  tags: tags
  properties: {
    securityRules: [

    ]
  }
}

resource VirtualNetwork 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: '${StorageAccountName}-VNet'
  location: Location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/23'
      ]
    }
    flowTimeoutInMinutes: 4
    subnets: [
      {
        name: 'Jumpbox-Subnet'
        properties: {
          addressPrefix: jumpboxPrefix
          networkSecurityGroup: {
            id: JumpboxNSG.id
          }
        }
      }
      {
        name: 'PE-Subnet'
        properties: {
          addressPrefix: storagePEPrefix
          networkSecurityGroup: {
            id: PENSG.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource PublicIp 'Microsoft.Network/publicIPAddresses@2022-11-01' = {
  name: '${StorageAccountName}-JBIP'
  location: Location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    deleteOption: 'Delete'
    dnsSettings: {
      domainNameLabel: '${StorageAccountName}jb'
    }
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource StorageBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: '${StorageAccountName}-PE-Blob'
  location: Location
  tags: tags
  properties: {
    subnet: {
      id: '${VirtualNetwork.id}/subnets/PE-Subnet'
    }
    privateLinkServiceConnections: [
      {
        name: '${StorageAccountName}-PE-Blob'
        properties: {
          privateLinkServiceId: Storage.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource PrivateDnsZoneBlob 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

resource PrivateDnsZoneBlobVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: PrivateDnsZoneBlob
  name: 'VNETLink'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: VirtualNetwork.id
    }
  }
}

resource PrivateDnsZoneGroupBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = {
  parent: StorageBlobPrivateEndpoint
  dependsOn: [
    VirtualNetwork
  ]
  name: 'ZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'Default'
        properties: {
          privateDnsZoneId: PrivateDnsZoneBlob.id
        }
      }
    ]
  }
}

resource StorageDfsPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: '${StorageAccountName}-PE-DFS'
  location: Location
  tags: tags
  properties: {
    subnet: {
      id: '${VirtualNetwork.id}/subnets/PE-Subnet'
    }
    privateLinkServiceConnections: [
      {
        name: '${StorageAccountName}-PE-DFS'
        properties: {
          privateLinkServiceId: Storage.id
          groupIds: [
            'dfs'
          ]
        }
      }
    ]
  }
}

resource PrivateDnsZoneDfs 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.dfs.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
  dependsOn: [
    VirtualNetwork
  ]
}

resource PrivateDnsZoneDfsVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: PrivateDnsZoneDfs
  name: 'VNETLink'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: VirtualNetwork.id
    }
  }
}

resource PrivateDnsZoneGroupDfs 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = {
  parent: StorageDfsPrivateEndpoint
  name: 'ZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'Default'
        properties: {
          privateDnsZoneId: PrivateDnsZoneDfs.id
        }
      }
    ]
  }
}

resource NIC 'Microsoft.Network/networkInterfaces@2022-11-01' = {
  name: '${StorageAccountName}-NIC'
  location: Location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'Default'
        properties: {
          primary: true
          publicIPAddress: {
            id: PublicIp.id
          }
          subnet: {
            id: '${VirtualNetwork.id}/subnets/Jumpbox-Subnet'
          }
        }
      }
    ]
  }
}

resource Jumpbox 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: '${StorageAccountName}-Jumpbox'
  location: Location
  tags: tags
  dependsOn: [
    PrivateDnsZoneGroupBlob
    PrivateDnsZoneBlobVNetLink
    PrivateDnsZoneGroupDfs
    PrivateDnsZoneDfsVNetLink
  ]
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1ms'
    }
    osProfile: {
      computerName: '${StorageAccountName}jb'
      adminPassword: JumpboxPassword
      adminUsername: JumpboxUsername
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        name: '${StorageAccountName}osdisk'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: NIC.id
        }
      ]
    }
  }
}

var raID = '4dcd3f9f-e151-49a9-81fe-6bcc18b03a48'
resource RoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: raID
  scope: Storage
  properties: {
    principalId: Jumpbox.identity.principalId
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab'
    principalType: 'ServicePrincipal'
    description: 'Just in case, allow the Jumpbox Managed Identity to control Storage Account Blob Data'
  }
}

output JumpboxDNS string = PublicIp.properties.dnsSettings.fqdn
output JumpboxIP string = PublicIp.properties.ipAddress
output StorageAccountBlobDns string = Storage.properties.primaryEndpoints.blob
output StorageAccountDfsDns string = Storage.properties.primaryEndpoints.dfs
