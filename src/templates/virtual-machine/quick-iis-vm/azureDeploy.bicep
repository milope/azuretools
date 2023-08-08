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

@description('Specify the administrator username.')
param AdminUsername string

@description('Specify the administrator password')
@secure()
param AdminPassword string

@description('Specify your IP or any allowed IP to allow through the network as a Network Security Group will be created.')
param AllowedIP string

@description('Specify a DNS label to access publicly, the template will be adding ipv4 and ipv6 to the label.')
param DNSLabel string = toLower(VMName)

@description('Specify the resource locations or leave unspecified to use the resource group\'s location.')
param Location string = resourceGroup().location

@description('Select the Windows Server edition')
@allowed([
  '2008-R2'
  '2012'
  '2012-R2'
  '2016'
  '2019'
  '2022'
])
param ServerEdition string = '2022'

@description('Use a Server Core OS (if applicable).')
param UseCore bool = false

@description('Use a Gen2 platform (if applicable).')
param UseGen2 bool = false

@description('Specify a Virtual Machine Name (Azure Resource Name).')
param VMName string

var NSGName = '${VMName}-nsg'
var VNetName = '${VMName}-vnet'
var PublicIPv4Name = '${VMName}-publicip-v4'
var PublicIPv6Name = '${VMName}-publicip-v6'
var NICName = '${VMName}-nic'
var OSSku = ServerEdition == '2008-R2' ? '2008-R2-SP1' : (ServerEdition == '2012' ?  (UseGen2 ? '2012-datacenter-gensecond' : '2012-Datacenter') : (ServerEdition == '2012-R2' ?  (UseGen2 ? '2012-r2-datacenter-gensecond' : '2012-R2-Datacenter') : (ServerEdition == '2016' ?  (UseGen2 ? (UseCore ? '2016-datacenter-server-core-g2' : '2016-datacenter-gensecond') : (UseCore ? '2016-Datacenter-Server-Core' : '2016-Datacenter')) : (ServerEdition == '2019' ?  (UseGen2 ? (UseCore ? '2019-datacenter-core-g2' : '2019-datacenter-gensecond') : (UseCore ? '2019-Datacenter-Core' : '2019-Datacenter')) : (ServerEdition == '2019' ?  (UseGen2 ? (UseCore ? '2022-datacenter-core-g2' : '2022-datacenter-g2') : (UseCore ? '2022-datacenter-core' : '2022-datacenter')) : '2022-datacenter')))))

var Tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2022-08-25'
  LabVersion: '1.0'
  LabCategory: 'Virtual Machines (Specialized)'
}

var correlationId = guid(uniqueString(deployment().name))

resource TraceEventStart 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${VMName}-trackEventStart'
  location: Location
  tags: Tags
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
      $CustomProperties = @{Type="Template";Category="Virtual Machines";Name="Quick IIS VM";CorrelationId=$correlationId}
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

resource NSG 'Microsoft.Network/networkSecurityGroups@2022-01-01' = {
  name: NSGName
  tags: Tags
  location: Location
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    securityRules: [
      {
        name: 'AllowedIP'
        properties: {
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          description: 'Allow my IP'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefixes: []
          destinationApplicationSecurityGroups: []
          destinationPortRange: '*'
          destinationPortRanges: []
          priority: 100
          sourceAddressPrefix: AllowedIP
          sourceAddressPrefixes: []
          sourceApplicationSecurityGroups: []
          sourcePortRange: '*'
          sourcePortRanges: []
        }
      }
    ]
  }
}

resource VNet 'Microsoft.Network/virtualNetworks@2022-01-01' = {
  name: VNetName
  location: Location
  tags: Tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/24'
        '2404:f800:8000:122::/64'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefixes: [
            '10.0.0.0/24'
            '2404:f800:8000:122::/64'
          ]
          networkSecurityGroup: {
            id: NSG.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
    ]
  }
}

resource PublicIPv4 'Microsoft.Network/publicIPAddresses@2022-01-01' = {
  name: PublicIPv4Name
  location: Location
  tags: Tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    dnsSettings: {
      domainNameLabel: '${DNSLabel}ipv4'
    }
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource PublicIPv6 'Microsoft.Network/publicIPAddresses@2022-01-01' = {
  name: PublicIPv6Name
  location: Location
  tags: Tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    dnsSettings: {
      domainNameLabel: '${DNSLabel}ipv6'
    }
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv6'
    publicIPAllocationMethod: 'Static'
  }
}

resource NIC 'Microsoft.Network/networkInterfaces@2022-01-01' = {
  name: NICName
  location: Location
  tags: Tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'ipv4-configuration'
        properties: {
          primary: true
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: PublicIPv4.id
          }
          subnet: {
            id: '${VNet.id}/subnets/default'
          }
        }
      }
      {
        name: 'ipv6-configuration'
        properties: {
          primary: false
          privateIPAddressVersion: 'IPv6'
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: PublicIPv6.id
          }
          subnet: {
            id: '${VNet.id}/subnets/default'
          }
        }
      }
    ]
  }
}

resource VM 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: VMName
  location: Location
  tags: Tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS2_v2'
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: NIC.id
          properties: {
            primary: true
          }
        }
      ]
    }
    osProfile: {
      adminPassword: AdminPassword
      adminUsername: AdminUsername
      computerName: toLower(VMName)
      windowsConfiguration: {
        enableAutomaticUpdates: true
      }
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadOnly'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: OSSku
        version: 'latest'
      }
    }
  }
  
}

resource InstallIIS 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  name: '${VM.name}/install-iis'
  location: Location
  tags: Tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    autoUpgradeMinorVersion: true
    type: 'CustomScriptExtension'
    publisher: 'Microsoft.Compute'
    typeHandlerVersion: '1.10'
    settings: {
      timestamp: 1661489263
      fileUris: [
        'https://raw.githubusercontent.com/milope/azuretools/master/src/templates/virtual-machine/quick-iis-vm/IIS_WebDeploy.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File IIS_WebDeploy.ps1'
    }
    protectedSettings: {
    }
  }
}

resource TraceEventEnd 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${VMName}-trackEventEnd'
  location: Location
  tags: Tags
  dependsOn: [
    TraceEventStart
    NSG
    VNet
    PublicIPv4
    PublicIPv6
    NIC
    VM
    InstallIIS
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
      $CustomProperties = @{Type="Template";Category="Virtual Machines";Name="Quick IIS VM";CorrelationId=$correlationId}
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

output IPv4 string = PublicIPv4.properties.dnsSettings.fqdn
output IPv6 string = PublicIPv6.properties.dnsSettings.fqdn
