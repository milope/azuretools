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

@description('This will be a prefix for all virtual machine scale sets')
@minLength(1)
@maxLength(3)
param ResourcePrefix string

@description('This will be the username for all virtual machine scale sets')
@maxLength(15)
param Username string

@description('This will be the username for all virtual machine scale sets')
@maxLength(30)
@secure()
param Password string

@description('Specify the number of virtual machine scale sets')
@minValue(1)
@maxValue(798)
param Amount int

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2022-01-28'
  LabVersion: '1.0'
  LabCategory: 'Virtual Machine Scale Sets'
}


resource Storage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: 'mlosdisk${uniqueString(resourceGroup().id)}'
  kind: 'Storage'
  tags: tags
  location: resourceGroup().location
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: false
  }
}

resource VirtualNetwork 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: '${ResourcePrefix}-vnet'
  location: resourceGroup().location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/8'
      ]
    }
    subnets: [
      {
        name: 'Default'
        properties: {
          addressPrefix: '10.0.0.0/8'
        }
      }
    ]
  }
}

resource VMSS 'Microsoft.Compute/virtualMachineScaleSets@2021-07-01' = [for i in range(0, Amount): {
  name: '${ResourcePrefix}vmss${padLeft(string(i + 1), 4, '0')}'
  location: resourceGroup().location
  tags: tags
  sku: {
    tier: 'Basic'
    capacity: 0
    name: 'Basic_A0'
  }
  properties: {
    overprovision: false
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          caching: 'ReadWrite'
          vhdContainers: [
            '${Storage.properties.primaryEndpoints.blob}/vhds'
          ]
          name: 'osdisk'
          createOption: 'FromImage'
        }
        imageReference: {
          sku: '2019-Datacenter'
          publisher: 'MicrosoftWindowsServer'
          version: 'latest'
          offer: 'WindowsServer'
        }
      }
      osProfile: {
        computerNamePrefix: 'mlvmss'
        adminUsername: Username
        adminPassword: Password
        windowsConfiguration: {
          enableAutomaticUpdates: false
          provisionVMAgent: false
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'vmss'
            properties: {
              ipConfigurations: [
                {
                  name: 'ip-config'
                  properties: {
                    primary: true
                    privateIPAddressVersion: 'IPv4'
                    subnet: {
                      id: '${VirtualNetwork.id}/subnets/Default'
                    }
                  }
                }
              ]
              enableAcceleratedNetworking: false
              primary: true
            }
          }
        ]
      }
    }
    upgradePolicy: {
      mode: 'Automatic'
    }
  }
}]

