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

@description('Use this parameter to prefix all resource names')
param ResourcePrefix string

@description('Specify a location, otherwise, it will default to its resource group\'s location')
param Location string = resourceGroup().location

var tags = {
    LabCreatedBy: 'Michael Lopez'
    LabCreatedOn: '2022-02-15'
    LabVersion: '1.0'
    LabCategory: 'Azure Batch'
}

resource PublicIpAddress 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${ResourcePrefix}-vip'
  location: Location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    dnsSettings: {
      domainNameLabel: '${toLower(ResourcePrefix)}-pip'
    }
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 10
  }
}

resource NatGw 'Microsoft.Network/natGateways@2021-05-01' = {
  name: '${ResourcePrefix}-natgw'
  location: Location
  tags: tags
  properties: {
    idleTimeoutInMinutes: 10
    publicIpAddresses: [
      {
        id: PublicIpAddress.id
      }
    ]
  }
}

resource BatchVnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: '${ResourcePrefix}-batch-vnet'
  location: Location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/24'
      ]
    }
    subnets: [
      {
        name: 'batch'
        properties: {
          addressPrefix: '10.0.0.0/24'
          natGateway: {
            id: NatGw.id
          }
        }
      }
    ]
  }
}

resource AutoStorage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  kind: 'StorageV2'
  location: Location
  tags: tags
  name: '${toLower(ResourcePrefix)}autostor'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

resource Batch 'Microsoft.Batch/batchAccounts@2021-06-01' = {
  location: Location
  tags: tags
  name: '${toLower(ResourcePrefix)}batch'
  properties: {
    poolAllocationMode: 'UserSubscription'
    publicNetworkAccess: 'Enabled'
  }
}
