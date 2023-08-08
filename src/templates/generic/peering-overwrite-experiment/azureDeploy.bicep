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

param ResourcePrefix string
param Location string = resourceGroup().location
param MyIP string
@secure()
param AdminPassword string
param AdminUsername string
param OverwritePeering bool

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2022-05-21'
  LabVersion: '1.0'
  LabCategory: 'Networking'
}

var correlationId = guid(uniqueString(deployment().name))

resource TraceEventStart 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${ResourcePrefix}-trackEventStart'
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
      $CustomProperties = @{Type="Template";Category="Azure Networking";Name="Peering Overwrite Experiment";CorrelationId=$correlationId}

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

resource FlowLogStorage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: 'flowlogs${uniqueString(resourceGroup().id)}'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
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

resource FlowLogsBastion 'Microsoft.Network/networkWatchers/flowLogs@2021-03-01' = {
  name: '${NetworkWatcher.name}/flowlogs-bastion'
  tags: tags
  location: Location
  properties: {
    targetResourceId: BastionNsg.id
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

resource FlowLogsDefaultNsg 'Microsoft.Network/networkWatchers/flowLogs@2021-03-01' = {
  name: '${NetworkWatcher.name}/flowlogs-default'
  tags: tags
  location: Location
  properties: {
    targetResourceId: DefaultNsg.id
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

resource NetworkWatcher 'Microsoft.Network/networkWatchers@2021-03-01' = {
  name: '${ResourcePrefix}-nw'
  tags: tags
  location: Location
  properties: {
    
  }
}

resource BastionPublicIp 'Microsoft.Network/publicIPAddresses@2021-08-01' = {
  name: '${ResourcePrefix}-bastion'
  location: Location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    dnsSettings: {
      domainNameLabel: '${ResourcePrefix}bastion'
    }
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource BastionNsg 'Microsoft.Network/networkSecurityGroups@2021-08-01' = {
  name: '${ResourcePrefix}-bastion-nsg'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    securityRules: [
      {
        name: 'allow-me'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          description: 'Allow myself in only.'
          destinationAddressPrefix: '10.0.0.0/25'
          priority: 100
          destinationPortRange: '*'
          sourceAddressPrefix: '${MyIP}/32'
          sourcePortRange: '*'
        }
      }
      {
        name: 'allow-GatewayManager'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          description: 'Allow GatewayManager in.'
          destinationAddressPrefix: '*'
          priority: 101
          destinationPortRange: '443'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
        }
      }
      {
        name: 'allow-443-to-azure-cloud'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'Allow 443 to Azure Cloud outbound.'
          destinationAddressPrefix: 'AzureCloud'
          priority: 101
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'allow-rdp-to-vnet'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'Allow RDP to VNET outbound.'
          destinationAddressPrefix: 'VirtualNetwork'
          priority: 102
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
      {
        name: 'allow-ssh-to-vnet'
        properties: {
          access: 'Allow'
          direction: 'Outbound'
          protocol: '*'
          description: 'Allow SSH to VNET outbound.'
          destinationAddressPrefix: 'VirtualNetwork'
          priority: 103
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }
    ]
  }
}

resource DefaultNsg 'Microsoft.Network/networkSecurityGroups@2021-08-01' = {
  name: '${ResourcePrefix}-default-nsg'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    securityRules: [
      {
        name: 'allow-all-internal-in'
        properties: {
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          description: 'Allow all all internal inbound.'
          destinationAddressPrefixes: [
            '10.0.0.0/24'
            '10.0.1.0/24'
          ]
          destinationPortRange: '*'
          sourceAddressPrefixes: [
            '10.0.0.0/24'
            '10.0.1.0/24'
          ]
          sourcePortRange: '*'
          priority: 100
        }
      }
      {
        name: 'allow-all-internal-out'
        properties: {
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          description: 'Allow all all internal outbound.'
          destinationAddressPrefixes: [
            '10.0.0.0/24'
            '10.0.1.0/24'
          ]
          destinationPortRange: '*'
          sourceAddressPrefixes: [
            '10.0.0.0/24'
            '10.0.1.0/24'
          ]
          sourcePortRange: '*'
          priority: 101
        }
      }
    ]
  }
}

resource ClientVNet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: '${ResourcePrefix}-client-vnet'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    addressSpace: {
       addressPrefixes: [
         '10.0.0.0/24'
       ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.0.0/25'
          networkSecurityGroup: {
            id: BastionNsg.id
          }
        }
      }
      {
        name: 'client-vms'
        properties: {
          addressPrefix: '10.0.0.128/25'
        }
      }
    ]
  }
}

resource ServerVNet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: '${ResourcePrefix}-server-vnet'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.1.0/24'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

resource S2CVNetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-08-01' = {
  name: '${ServerVNet.name}/c2s-peering'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: true
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: ClientVNet.id
    }
  }
}

resource C2SVNetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-08-01' = {
  name: '${ClientVNet.name}/c2s-peering'
  properties: {
    allowForwardedTraffic: true
    allowGatewayTransit: true
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: ServerVNet.id
    }
  }
}

resource ClientIlb 'Microsoft.Network/loadBalancers@2021-08-01' = {
  name: '${ResourcePrefix}-client-ilb'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Standard'
  }
  properties: {
    backendAddressPools: [
      {
        name: 'windows-vms'
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'frontend-config'
        properties: {
          subnet: {
            id: '${ClientVNet.id}/subnets/client-vms'
          }
        }
      }
    ]
    probes: [
      {
        name: 'ha-ports'
        properties: {
          port: 3389
          protocol: 'Tcp'
          intervalInSeconds: 30
          numberOfProbes: 3
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'all-ports'
        properties: {
          frontendPort: 0
          protocol: 'All'
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${ResourcePrefix}-client-ilb', 'windows-vms')
          }
          backendPort: 0
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${ResourcePrefix}-client-ilb', 'frontend-config')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${ResourcePrefix}-client-ilb', 'ha-ports')
          }
        }
      }
    ]
  }
}

resource ServerIlb 'Microsoft.Network/loadBalancers@2021-08-01' = {
  name: '${ResourcePrefix}-server-ilb'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Basic'
  }
  properties: {
    backendAddressPools: [
      {
        name: 'backend-IIS-servers'
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'frontend-config'
        properties: {
          subnet: {
            id: '${ServerVNet.id}/subnets/default'
          }
        }
      }
    ]
    probes: [
      {
        name: 'http-probe'
        properties: {
          port: 80
          protocol: 'Tcp'
          intervalInSeconds: 30
          numberOfProbes: 3
        }
      }
      {
        name: 'https-probe'
        properties: {
          port: 443
          protocol: 'Tcp'
          intervalInSeconds: 30
          numberOfProbes: 3
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'http-load-balancing-rule'
        properties: {
          frontendPort: 80
          protocol: 'Tcp'
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${ResourcePrefix}-server-ilb', 'backend-IIS-servers')
          }
          backendPort: 80
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${ResourcePrefix}-server-ilb', 'frontend-config')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${ResourcePrefix}-server-ilb', 'http-probe')
          }
        }
      }
      {
        name: 'https-load-balancing-rule'
        properties: {
          frontendPort: 443
          protocol: 'Tcp'
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${ResourcePrefix}-server-ilb', 'backend-IIS-servers')
          }
          backendPort: 443
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${ResourcePrefix}-server-ilb', 'frontend-config')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${ResourcePrefix}-server-ilb', 'https-probe')
          }
        }
      }
    ]
  }
}

resource ServerNic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: '${ResourcePrefix}-server-nic'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          loadBalancerBackendAddressPools: [
            {
              id: '${ServerIlb.id}/backendAddressPools/backend-IIS-servers'
            }
          ]
          primary: true
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: '${ServerVNet.id}/subnets/default'
          }
        }
      }
    ]
  }
}

resource IISServer 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: '${ResourcePrefix}-iis-server'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      imageReference: {
         publisher: 'MicrosoftWindowsServer'
         offer: 'WindowsServer'
         sku: '2019-Datacenter-Core'
         version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: ServerNic.id
        }
      ]
    }
    osProfile: {
      computerName: '${ResourcePrefix}iis'
      adminPassword: AdminPassword
      adminUsername: AdminUsername
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
  }
}

resource IIS 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  name: '${IISServer.name}/install-iis'
  location: Location
  tags: tags
  properties: {
     autoUpgradeMinorVersion: true
     enableAutomaticUpgrade: false
     publisher: 'Microsoft.Compute'
     type: 'CustomScriptExtension'
     typeHandlerVersion: '1.10'
     settings: {}
     protectedSettings: {
       commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File IIS_WebDeploy.ps1'
       fileUris: [
         'http://miketools.azurewebsites.net/IIS_WebDeploy.ps1'
       ]
     }
  }
}

resource NetworkWatcherIIS 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  name: '${IISServer.name}/network-watcher'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    publisher: 'Microsoft.Azure.NetworkWatcher'
    type: 'NetworkWatcherAgentWindows'
    typeHandlerVersion: '1.4'
    autoUpgradeMinorVersion: true
  }
}

resource ClientNic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: '${ResourcePrefix}-client-nic'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          loadBalancerBackendAddressPools: [
            {
              id: '${ClientIlb.id}/backendAddressPools/windows-vms'
            }
          ]
          primary: true
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: '${ClientVNet.id}/subnets/client-vms'
          }
        }
      }
    ]
  }
}

resource ClientVM 'Microsoft.Compute/virtualMachines@2021-11-01' = {
  name: '${ResourcePrefix}-windows-vm'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
      imageReference: {
         publisher: 'MicrosoftWindowsDesktop'
         offer: 'windows-11'
         sku: 'win11-21h2-pro'
         version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: ClientNic.id
        }
      ]
    }
    osProfile: {
      computerName: '${ResourcePrefix}win11'
      adminPassword: AdminPassword
      adminUsername: AdminUsername
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
  }
}

resource NetworkWatcherClient 'Microsoft.Compute/virtualMachines/extensions@2021-11-01' = {
  name: '${ClientVM.name}/network-watcher'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    publisher: 'Microsoft.Azure.NetworkWatcher'
    type: 'NetworkWatcherAgentWindows'
    typeHandlerVersion: '1.4'
    autoUpgradeMinorVersion: true
  }
}

resource BastionHost 'Microsoft.Network/bastionHosts@2021-08-01' = {
  name: '${ResourcePrefix}-bastion'
  location: Location
  tags: tags
  sku: {
    name: 'Basic'
  }
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    ipConfigurations:[
      {
        name: 'default'
        properties: {
          publicIPAddress: {
            id: BastionPublicIp.id
          }
          subnet: {
            id: '${ClientVNet.id}/subnets/AzureBastionSubnet'
          }
        }
      }
    ]
  }
}

resource OverwriteUdr 'Microsoft.Network/routeTables@2021-08-01' = if(OverwritePeering) {
  name: '${ResourcePrefix}-overwrite-peer'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'ovewrite-peering'
        properties: {
          nextHopType: 'VirtualAppliance'
          addressPrefix: '10.0.0.0/24'
          nextHopIpAddress: ClientIlb.properties.frontendIPConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

resource OverwriteUdrAssignment 'Microsoft.Network/virtualNetworks/subnets@2021-08-01' = if(OverwritePeering) {
  name: '${ServerVNet.name}/default'
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    addressPrefix: '10.0.1.0/24'
    routeTable: {
      id: OverwriteUdr.id
    }
  }
}

resource TraceEventEnd 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${ResourcePrefix}-trackEventEnd'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
    FlowLogStorage
    FlowLogsBastion
    NetworkWatcher
    LaWorkspace
    BastionPublicIp
    BastionNsg
    ClientVNet
    ServerVNet
    ServerIlb
    ServerNic
    IISServer
    ClientNic
    ClientVM
    BastionHost
    IIS
    NetworkWatcherIIS
    NetworkWatcherClient
    C2SVNetPeering
    OverwriteUdr
    OverwriteUdrAssignment
    DefaultNsg
    FlowLogsDefaultNsg
    S2CVNetPeering
    ClientIlb
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
      $CustomProperties = @{Type="Template";Category="Azure Networking";Name="Peering Overwrite Experiment";CorrelationId=$correlationId}

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

output DataExplorerClusterUrl string = 'https://ade.loganalytics.io${LaWorkspace.id}'
output BastionPublicIp string = BastionPublicIp.properties.ipAddress
output IisIlbPrivateIp string = ServerIlb.properties.frontendIPConfigurations[0].properties.privateIPAddress
output ClientIlbPrivateIp string = ClientIlb.properties.frontendIPConfigurations[0].properties.privateIPAddress
output WindoiwsPrivateIp string = ClientNic.properties.ipConfigurations[0].properties.privateIPAddress
output IsOverwritten bool = OverwritePeering
