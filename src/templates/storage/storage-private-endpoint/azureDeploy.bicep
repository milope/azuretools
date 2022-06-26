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

@description('Prefix for DNS zones.')
param ResourcePrefix string

@description('Location for resource (leave blank for resource group location).')
param Location string = resourceGroup().location

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2021-11-13'
  LabVersion: '1.0'
  LabCategory: 'Azure Storage'
}

resource VNET 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: '${ResourcePrefix}-vnet'
  tags: tags
  location: Location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/24'
      ]
    }
    subnets: [
      {
        name: 'privateEndpoint'
        properties: {
          addressPrefix: '10.0.0.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource Storage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  kind: 'StorageV2'
  tags: tags
  location: Location
  name: '${ResourcePrefix}storpe'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource PrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-03-01' = {
  name: '${ResourcePrefix}privateEndpoint'
  location: Location
  properties: {
    subnet: {
      id: '${VNET.id}/subnets/privateEndpoint'
    }
    privateLinkServiceConnections: [
      {
        name: 'privateEndpoint'
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

resource PrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  properties: {
    
  }
}

resource PrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${PrivateDnsZone.name}/${VNET.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: VNET.id
    }
  }
}

resource PrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  name: '${PrivateEndpoint.name}/dnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privateDnsZoneConfig'
        properties: {
          privateDnsZoneId: PrivateDnsZone.id
        }
      }
    ]
  }
}
