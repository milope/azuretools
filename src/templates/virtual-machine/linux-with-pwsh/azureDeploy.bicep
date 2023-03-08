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

@description('Use this parameter to prefix all resources created.')
param ResourcePrefix string

@description('Specify a location for the resources.')
param Location string = resourceGroup().location

@description('Pass your IP Address to allow through NSG')
param MyIP string

@description('Virtual Network Address Range')
param VNetAddressRange string = '10.0.0.0/23'

@description('Specify a jumpbox VM endpoint subnet address range')
param VMDnsLabel string = '${ResourcePrefix}vm'

@description('Specify an Administrator username.')
param AdminUsername string

@description('Specify an Administrator password.')
@secure()
param AdminPassword string


resource NSG 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: '${ResourcePrefix}-nsg'
  location: Location
  properties: {
    securityRules: [
      {
        name: 'AllowMe-In-RDP-SSH'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          description: 'Allow my IP inbound through the NSGs for RDP and SSH.'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '22'
            '3389'
          ]
          priority: 100
          sourceAddressPrefix: '${MyIP}/32'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowMe-In-ICMP'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Icmp'
          description: 'Allow my IP ICMP inbound through the NSGs.'
          destinationAddressPrefix: 'VirtualNetwork'
          priority: 101
          sourceAddressPrefix: '${MyIP}/32'
          sourcePortRange: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'AllowMe-Out-ICMP'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: 'Icmp'
          description: 'Allow my IP ICMP outbound through the NSGs.'
          destinationAddressPrefix: '${MyIP}/32'
          priority: 100
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource PublicIp 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
  name: '${ResourcePrefix}-publicip'
  location: Location
  sku: {
    name: 'Standard'
  }
  properties: {
    dnsSettings: {
      domainNameLabel: VMDnsLabel
    }
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource VNet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: '${ResourcePrefix}-vnet'
  location: Location
  properties: {
    addressSpace: {
      addressPrefixes: [
        VNetAddressRange
      ]
    }
    subnets: [
      {
        name: 'vm-subnet'
        properties: {
          addressPrefix: VNetAddressRange
          networkSecurityGroup: {
            id: NSG.id
          }
        }
      }
    ]
  }
}

resource NIC 'Microsoft.Network/networkInterfaces@2022-07-01' = {
  name: '${ResourcePrefix}-nic'
  location: Location
  properties: {
    ipConfigurations: [
      {
        name: 'ip-config'
        properties: {
          primary: true
          subnet: {
            id: '${VNet.id}/subnets/vm-subnet'
          }
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          publicIPAddress: {
            id: PublicIp.id
            properties: {
              deleteOption: 'Delete'
            }
          }
        }
      }
    ]
  }
}

resource VM 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: '${ResourcePrefix}-vm'
  location: Location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: NIC.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    osProfile: {
      computerName: '${toLower(ResourcePrefix)}vm'
      adminUsername: AdminUsername
      adminPassword: AdminPassword
      linuxConfiguration: {
        patchSettings: {
          patchMode: 'ImageDefault'
        }
      }
    }
  }
}

resource InstallPowerShell 'Microsoft.Compute/virtualMachines/extensions@2022-11-01' = {
  parent: VM
  name: 'install-powershell'
  location: Location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: 'sh install_powershell_ubuntu.sh'
      fileUris: [
        'https://raw.githubusercontent.com/milope/azuretools/master/src/shell/install_powershell_ubuntu.sh'
      ]
    }
  }
}

output VMDNS string = PublicIp.properties.dnsSettings.fqdn
output VMIP string = PublicIp.properties.ipAddress
