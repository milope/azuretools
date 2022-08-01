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

@description('Remote desktop/SSH username.')
param AdminUsername string

@description('Remote desktop/SSH user password. Must be a strong password.')
@secure()
param AdminPassword string

@description('Resource Id of the key vault, is should be in the format of /subscriptions/<Sub ID>/resourceGroups/<Resource group name>/providers/Microsoft.KeyVault/vaults/<vault name>.')
param CertificateKeyVaultResourceId string

@description('Refers to the location URL in your key vault where the certificate was uploaded, it is should be in the format of https://<name of the vault>.<vault suffix>:443/secrets/<exact location>.')
param CertificateSecretUrl string

@description('The cluster and client certificate thumbprint.')
param CertificateThumbprint string

@description('Protection level.Three values are allowed - EncryptAndSign, Sign, None. It is best to keep the default of EncryptAndSign, unless you have a need not to.')
@allowed([
  'None'
  'Sign'
  'EncryptAndSign'
])
param ClusterProtectionLevel string = 'EncryptAndSign'

@description('Instance count for the Linux cluster primary node type.')
param LinuxInstanceCount int

@description('Specify the Linux node type durability.')
@allowed([
  'Bronze'
  'Silver'
  'Gold'
])
param LinuxDurability string = 'Silver'

@description('Specify a location, otherwise, it will default to its resource group\'s location')
param Location string = resourceGroup().location

@description('Specify your IP as this cluster will be protected by NSG.')
param MyIP string

@description('Use this parameter to prefix all resource names.')
param ResourcePrefix string

@description('Instance count for the Windows cluster primary node type.')
param WindowsInstanceCount int

@description('Specify the Windows node type durability.')
@allowed([
  'Bronze'
  'Silver'
  'Gold'
])
param WindowsDurability string = 'Silver'

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2022-07-29'
  LabVersion: '1.0'
  LabCategory: 'Service Fabric'
}

var windowsClusterName = '${ResourcePrefix}-sfwin'
var linuxClusterName = '${ResourcePrefix}-sflin'

var windowsReliability = WindowsInstanceCount < 5 ? 'Bronze' : (WindowsInstanceCount < 7 ? 'Silver' : 'Gold')
var linuxReliabilty = WindowsInstanceCount < 5 ? 'Bronze' : (WindowsInstanceCount < 7 ? 'Silver' : 'Gold')

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
      $CustomProperties = @{Type="Template";Category="Service Fabric";Name="Windows and Linux Double Cluster";CorrelationId=$correlationId}
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

resource SupportLogStorageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  location: Location
  name: toLower('sflogs${uniqueString(resourceGroup().id)}2')
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  dependsOn: [
    TraceEventStart
  ]
  tags: tags
}

resource ApplicationDiagnosticsStorageAccount 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  location: Location
  name: toLower('wad${uniqueString(resourceGroup().id)}3')
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  dependsOn: [
    TraceEventStart
  ]
  tags: tags
}

resource NSG 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: '${ResourcePrefix}-nsg'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    securityRules: [
      {
        name: 'AllowMe'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          description: 'Allow me for SFX, SF Client, SSH, RDP and SMB'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '19000'
            '19080'
            '3389'
            '22'
            '445'
            '139'
          ]
          priority: 100
          sourceAddressPrefix: '${MyIP}/32'
          sourcePortRange: '*'
        }
      }
      {
        name: 'AllowMe-ICMP'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Icmp'
          sourcePortRange: '*'
          description: 'Allow me for ICM, because I can'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
          priority: 101
          sourceAddressPrefix: '${MyIP}/32'
        }
      }
    ]
  }
}

resource VNet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: '${ResourcePrefix}-vnet'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/23'
      ]
    }
    subnets: [
      {
        name: 'linux-subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
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
      {
        name: 'windows-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
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

resource PublicIpWindows 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: '${ResourcePrefix}-pip-win'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: toLower('${ResourcePrefix}sfwin')
    }
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource PublicIpLinux 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: '${ResourcePrefix}-pip-lin'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: toLower('${ResourcePrefix}sflin')
    }
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}

resource LoadBalancer 'Microsoft.Network/loadBalancers@2021-03-01' = {
  name: '${ResourcePrefix}-slb'
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
        name: 'windows-address-pool'
      }
      {
        name: 'linux-address-pool'
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'windows-frontend-ip-config'
        properties: {
          publicIPAddress: {
            id: PublicIpWindows.id
          }
        }
      }
      {
        name: 'linux-frontend-ip-config'
        properties: {
          publicIPAddress: {
            id: PublicIpLinux.id
          }
        }
      }
    ]
    probes: [
      {
        name: 'fabric-client-probe'
        properties: {
          port: 19000
          protocol: 'Tcp'
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
      {
        name: 'sfx-probe'
        properties: {
          port: 19080
          protocol: 'Tcp'
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    inboundNatPools: [
    ]
    loadBalancingRules: [
      {
        name: 'windows-fabric-client-rule'
        properties: {
          frontendPort: 19000
          protocol:  'Tcp'
          backendAddressPool: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/backendAddressPools/windows-address-pool'
          }
          backendPort: 19000
          enableFloatingIP: false
          enableTcpReset: true
          frontendIPConfiguration: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/frontendIPConfigurations/windows-frontend-ip-config'
          }
          idleTimeoutInMinutes: 4
          probe: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/probes/fabric-client-probe'
          }
        }
      }
      {
        name: 'linux-fabric-client-rule'
        properties: {
          frontendPort: 19000
          protocol:  'Tcp'
          backendAddressPool: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/backendAddressPools/linux-address-pool'
          }
          backendPort: 19000
          enableFloatingIP: false
          enableTcpReset: true
          frontendIPConfiguration: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/frontendIPConfigurations/linux-frontend-ip-config'
          }
          idleTimeoutInMinutes: 4
          probe: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/probes/fabric-client-probe'
          }
        }
      }
      {
        name: 'windows-sfx-rule'
        properties: {
          frontendPort: 19080
          protocol:  'Tcp'
          backendAddressPool: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/backendAddressPools/windows-address-pool'
          }
          backendPort: 19080
          enableFloatingIP: false
          enableTcpReset: true
          frontendIPConfiguration: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/frontendIPConfigurations/windows-frontend-ip-config'
          }
          idleTimeoutInMinutes: 4
          probe: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/probes/sfx-probe'
          }
        }
      }
      {
        name: 'linux-sfx-rule'
        properties: {
          frontendPort: 19080
          protocol:  'Tcp'
          backendAddressPool: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/backendAddressPools/linux-address-pool'
          }
          backendPort: 19080
          enableFloatingIP: false
          enableTcpReset: true
          frontendIPConfiguration: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/frontendIPConfigurations/linux-frontend-ip-config'
          }
          idleTimeoutInMinutes: 4
          probe: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/probes/sfx-probe'
          }
        }
      }
    ]
    inboundNatRules: [
      {
        name: 'windows-rdp-nat-rule'
        properties: {
          backendAddressPool: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/backendAddressPools/windows-address-pool'
          }
          backendPort: 3389
          enableFloatingIP: false
          enableTcpReset: true
          frontendIPConfiguration: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/frontendIPConfigurations/windows-frontend-ip-config'
          }
          frontendPortRangeStart: 3389
          frontendPortRangeEnd: 3389 + WindowsInstanceCount + 1
          idleTimeoutInMinutes: 4
          protocol: 'Tcp'
        }
      }
      {
        name: 'linux-rdp-nat-rule'
        properties: {
          backendAddressPool: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/backendAddressPools/linux-address-pool'
          }
          backendPort: 22
          enableFloatingIP: false
          enableTcpReset: true
          frontendIPConfiguration: {
            id: '${resourceId('Microsoft.Network/loadBalancers', '${ResourcePrefix}-slb')}/frontendIPConfigurations/linux-frontend-ip-config'
          }
          frontendPortRangeStart: 22
          frontendPortRangeEnd: 22 + WindowsInstanceCount + 1
          idleTimeoutInMinutes: 4
          protocol: 'Tcp'
        }
      }
    ]
  }
}

resource WindowsVmss 'Microsoft.Compute/virtualMachineScaleSets@2021-07-01' = {
  name: '${ResourcePrefix}-win-vmss'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    capacity: WindowsInstanceCount
    tier: 'Standard'
    name: 'Standard_D2_V2'
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      extensionProfile: {
        extensions: [
          {
            name: 'sfnodeext_system'
            properties: {
              autoUpgradeMinorVersion: true
              type: 'ServiceFabricNode'
              publisher: 'Microsoft.Azure.ServiceFabric'
              settings: {
                clusterEndpoint: reference(windowsClusterName).clusterEndpoint
                nodeTypeRef: 'system'
                dataPath: 'D:\\SvcFab'
                durabilityLevel: WindowsDurability
                enableParallelJobs: true
                nicPrefixOverride: '10.0.1.0/24'
                certificate: {
                  thumbprint: CertificateThumbprint
                  x509StoreName: 'My'
                }
              }
              protectedSettings: {
                StorageAccountKey1: listKeys(SupportLogStorageAccount.id, SupportLogStorageAccount.apiVersion).keys[0].value
                StorageAccountKey2: listKeys(SupportLogStorageAccount.id, SupportLogStorageAccount.apiVersion).keys[1].value
              }
              typeHandlerVersion: '1.1'
            }
          }
          {
            name: 'vmdiagnostics_system'
            properties: {
              autoUpgradeMinorVersion: true
              type: 'IaaSDiagnostics'
              publisher: 'Microsoft.Azure.Diagnostics'
              protectedSettings: {
                storageAccountName: ApplicationDiagnosticsStorageAccount.name
                storageAccountKey: listKeys(ApplicationDiagnosticsStorageAccount.id, ApplicationDiagnosticsStorageAccount.apiVersion).keys[0].value
                storageAccountEndPoint: 'https://${environment().suffixes.storage}'
              }
              settings: {
                XmlCfg: ''
                WadCfg: {
                  DiagnosticMonitorConfiguration: {
                    overallQuotaInMB: '50000'
                    EtwProviders: {
                      EtwEventSourceProviderConfiguration: [
                        {
                          provider: 'Microsoft-ServiceFabric-Actors'
                          scheduledTransferKeywordFilter: '1'
                          scheduledTransferPeriod: 'PT5M'
                          DefaultEvents: {
                            eventDestination: 'ServiceFabricReliableActorEventTable'
                          }
                        }
                        {
                          provider: 'Microsoft-ServiceFabric-Services'
                          scheduledTransferPeriod: 'PT5M'
                          DefaultEvents: {
                            eventDestination: 'ServiceFabricReliableServiceEventTable'
                          }
                        }
                        {
                          provider: 'Microsoft-Windows-HttpService'
                          scheduledTransferPeriod: 'PT5M'
                          DefaultEvents: {
                            eventDestination: 'HttpServiceEventTable'
                          }
                        }
                      ]
                      EtwManifestProviderConfiguration: [
                        {
                          provider: 'cbd93bc2-71e5-4566-b3a7-595d8eeca6e8'
                          scheduledTransferLogLevelFilter: 'Information'
                          scheduledTransferKeywordFilter: '4611686018427387904'
                          scheduledTransferPeriod: 'PT5M'
                          DefaultEvents: {
                            eventDestination: 'ServiceFabricSystemEventTable'
                          }
                        }
                      ]
                    }
                  }
                }
                StorageAccount: ApplicationDiagnosticsStorageAccount.name
              }
              typeHandlerVersion: '1.1'
            }
          }
        ]
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'primary'
            properties: {
              ipConfigurations: [
                {
                  name: 'ipconfig'
                  properties: {
                    loadBalancerBackendAddressPools: [
                      {
                        id: '${LoadBalancer.id}/backendAddressPools/windows-address-pool'
                      }
                    ]
                    subnet: {
                      id: '${VNet.id}/subnets/windows-subnet'
                    }
                  }
                }
              ]
              primary: true
            }
          }
        ]
      }
      osProfile: {
        adminPassword: AdminPassword
        adminUsername: AdminUsername
        computerNamePrefix: 'system'
        secrets: [
          {
            sourceVault: {
              id: CertificateKeyVaultResourceId
            }
            vaultCertificates: [
              {
                certificateStore: 'My'
                certificateUrl: CertificateSecretUrl
              }
            ]
          }
        ]
      }
      storageProfile: {
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2016-Datacenter-with-Containers'
          version: 'latest'
        }
        osDisk: {
          caching: 'ReadOnly'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
          }
        }
      }
    }
  }
}

resource LinuxVmss 'Microsoft.Compute/virtualMachineScaleSets@2021-07-01' = {
  name: '${ResourcePrefix}-lin-vmss'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      extensionProfile: {
        extensions: [
          {
            name: 'servicefabric_system'
            properties: {
                type: 'ServiceFabricLinuxNode'
                autoUpgradeMinorVersion: true
                protectedSettings: {
                    StorageAccountKey1: listKeys(SupportLogStorageAccount.id, SupportLogStorageAccount.apiVersion).keys[0].value
                    StorageAccountKey2: listKeys(SupportLogStorageAccount.id, SupportLogStorageAccount.apiVersion).keys[1].value
                }
                publisher: 'Microsoft.Azure.ServiceFabric'
                settings: {
                    clusterEndpoint: reference(linuxClusterName).clusterEndpoint
                    nodeTypeRef: 'system'
                    durabilityLevel: LinuxDurability
                    certificate: {
                        thumbprint: CertificateThumbprint
                        x509StoreName: 'My'
                    }
                }
                typeHandlerVersion: '1.1'
            }
          }
          {
            name: 'vmdiagnostics_system'
            properties: {
              type: 'LinuxDiagnostic'
              autoUpgradeMinorVersion: true
              protectedSettings: {
                  storageAccountName: ApplicationDiagnosticsStorageAccount.name
                  storageAccountKey: listKeys(SupportLogStorageAccount.id, ApplicationDiagnosticsStorageAccount.apiVersion).keys[0].value
                  storageAccountEndPoint: 'https://${environment().suffixes.storage}'
              }
              publisher: 'Microsoft.OSTCExtensions'
              settings: {
                  xmlCfg: base64('<WadCfg><DiagnosticMonitorConfiguration><PerformanceCounters scheduledTransferPeriod="PT1M"><PerformanceCounterConfiguration counterSpecifier="\\Memory\\AvailableMemory" sampleRate="PT15S" unit="Bytes"><annotation displayName="Memory available" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\Memory\\PercentAvailableMemory" sampleRate="PT15S" unit="Percent"><annotation displayName="Mem. percent available" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\Memory\\UsedMemory" sampleRate="PT15S" unit="Bytes"><annotation displayName="Memory used" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\Memory\\PercentUsedMemory" sampleRate="PT15S" unit="Percent"><annotation displayName="Memory percentage" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\Memory\\PercentUsedByCache" sampleRate="PT15S" unit="Percent"><annotation displayName="Mem. used by cache" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\Processor\\PercentIdleTime" sampleRate="PT15S" unit="Percent"><annotation displayName="CPU idle time" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\Processor\\PercentUserTime" sampleRate="PT15S" unit="Percent"><annotation displayName="CPU user time" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\Processor\\PercentProcessorTime" sampleRate="PT15S" unit="Percent"><annotation displayName="CPU percentage guest OS" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\Processor\\PercentIOWaitTime" sampleRate="PT15S" unit="Percent"><annotation displayName="CPU IO wait time" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\BytesPerSecond" sampleRate="PT15S" unit="BytesPerSecond"><annotation displayName="Disk total bytes" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\ReadBytesPerSecond" sampleRate="PT15S" unit="BytesPerSecond"><annotation displayName="Disk read guest OS" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\WriteBytesPerSecond" sampleRate="PT15S" unit="BytesPerSecond"><annotation displayName="Disk write guest OS" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\TransfersPerSecond" sampleRate="PT15S" unit="CountPerSecond"><annotation displayName="Disk transfers" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\ReadsPerSecond" sampleRate="PT15S" unit="CountPerSecond"><annotation displayName="Disk reads" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\WritesPerSecond" sampleRate="PT15S" unit="CountPerSecond"><annotation displayName="Disk writes" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\AverageReadTime" sampleRate="PT15S" unit="Seconds"><annotation displayName="Disk read time" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\AverageWriteTime" sampleRate="PT15S" unit="Seconds"><annotation displayName="Disk write time" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\AverageTransferTime" sampleRate="PT15S" unit="Seconds"><annotation displayName="Disk transfer time" locale="en-us"/></PerformanceCounterConfiguration><PerformanceCounterConfiguration counterSpecifier="\\PhysicalDisk\\AverageDiskQueueLength" sampleRate="PT15S" unit="Count"><annotation displayName="Disk queue length" locale="en-us"/></PerformanceCounterConfiguration></PerformanceCounters><Metrics resourceId="${resourceId('Microsoft.Compute/virtualMachineScaleSets', '${ResourcePrefix}-lin-vmss')}"><MetricAggregation scheduledTransferPeriod="PT1H"/><MetricAggregation scheduledTransferPeriod="PT1M"/></Metrics></DiagnosticMonitorConfiguration></WadCfg>')
                  StorageAccount: ApplicationDiagnosticsStorageAccount.name
              }
              typeHandlerVersion: '2.3'
            }
          }
        ]
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'primary'
            properties: {
              ipConfigurations: [
                {
                  name: 'ipconfig'
                  properties: {
                    loadBalancerBackendAddressPools: [
                      {
                        id: '${LoadBalancer.id}/backendAddressPools/linux-address-pool'
                      }
                    ]
                    subnet: {
                      id: '${VNet.id}/subnets/linux-subnet'
                    }
                  }
                }
              ]
              primary: true
            }
          }
        ]
      }
      osProfile: {
        adminPassword: AdminPassword
        adminUsername: AdminUsername
        computerNamePrefix: 'system'    
        secrets: [
          {
            sourceVault: {
              id: CertificateKeyVaultResourceId
            }
            vaultCertificates: [
              {
                certificateUrl: CertificateSecretUrl
              }
            ]
          }
        ]
      }
      storageProfile: {
        imageReference: {
            publisher: 'Canonical'
            offer: 'UbuntuServer'
            sku: '16.04-LTS'
            version: 'latest'
        }
        osDisk: {
          caching: 'ReadOnly'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'StandardSSD_LRS'
          }
        }
      }
    }
  }
  sku: {
      name: 'Standard_D2_v2'
      capacity: LinuxInstanceCount
      tier: 'Standard'
  }
}

resource WindowsSf 'Microsoft.ServiceFabric/clusters@2021-06-01' = {
  name: windowsClusterName
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    addOnFeatures: [
      'DnsService'
      'RepairManager'
    ]
    certificate: {
      thumbprint: CertificateThumbprint
      x509StoreName: 'My'
    }
    diagnosticsStorageAccountConfig: {
      storageAccountName: SupportLogStorageAccount.name
      protectedAccountKeyName: 'StorageAccountKey1'
      tableEndpoint: SupportLogStorageAccount.properties.primaryEndpoints.table
      blobEndpoint: SupportLogStorageAccount.properties.primaryEndpoints.blob
      queueEndpoint: SupportLogStorageAccount.properties.primaryEndpoints.queue
    }
    fabricSettings: [
      {
        name: 'Security'
        parameters: [
          {
            name: 'ClusterProtectionLevel'
            value: ClusterProtectionLevel
          }
        ]
      }
    ]
    managementEndpoint: 'https://${PublicIpWindows.properties.dnsSettings.fqdn}:19080'
    nodeTypes: [
      {
        name: 'system'
        applicationPorts: {
          startPort: 20000
          endPort: 30000
        }
        clientConnectionEndpointPort: 19000
        durabilityLevel: WindowsDurability
        httpGatewayEndpointPort: 19080
        isPrimary: true
        reverseProxyEndpointPort: 19081
        vmInstanceCount: WindowsInstanceCount
        ephemeralPorts: {
          endPort: 65534
          startPort: 49152
        }
      }
    ]
    reliabilityLevel: windowsReliability
    reverseProxyCertificate: {
      thumbprint: CertificateThumbprint
      x509StoreName: 'My'
    }
    upgradeMode: 'Automatic'
    vmImage: 'Windows'
  }
}

resource LinuxSf 'Microsoft.ServiceFabric/clusters@2021-06-01' = {
  name: linuxClusterName
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    addOnFeatures: [
      'DnsService'
      'RepairManager'
    ]
    certificate: {
      thumbprint: CertificateThumbprint
      x509StoreName: 'My'
    }
    diagnosticsStorageAccountConfig: {
      storageAccountName: SupportLogStorageAccount.name
      protectedAccountKeyName: 'StorageAccountKey1'
      tableEndpoint: SupportLogStorageAccount.properties.primaryEndpoints.table
      blobEndpoint: SupportLogStorageAccount.properties.primaryEndpoints.blob
      queueEndpoint: SupportLogStorageAccount.properties.primaryEndpoints.queue
    }
    fabricSettings: [
      {
        name: 'Security'
        parameters: [
          {
            name: 'ClusterProtectionLevel'
            value: ClusterProtectionLevel
          }  
          {
            name: 'EnforceLinuxMinTlsVersion'
            value: 'true'
          }
          {
            name: 'TLS1_2_CipherList'
            value: 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES-128-GCM-SHA256:ECDHE-ECDSA-AES256-CBC-SHA384:ECDHE-ECDSA-AES128-CBC-SHA256:ECDHE-RSA-AES256-CBC-SHA384:ECDHE-RSA-AES128-CBC-SHA256'
          }
        ]
      }
    ]
    managementEndpoint: 'https://${PublicIpLinux.properties.dnsSettings.fqdn}:19080'
    nodeTypes: [
      {
        name: 'system'
        applicationPorts: {
          startPort: 20000
          endPort: 30000
        }
        clientConnectionEndpointPort: 19000
        durabilityLevel: LinuxDurability
        httpGatewayEndpointPort: 19080
        isPrimary: true
        reverseProxyEndpointPort: 19081
        vmInstanceCount: LinuxInstanceCount
        ephemeralPorts: {
          endPort: 65534
          startPort: 49152
        }
      }
    ]
    reliabilityLevel: linuxReliabilty
    upgradeMode: 'Automatic'
    vmImage: 'Linux'
  }
}

resource TraceEventEnd 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${ResourcePrefix}-trackEventEnd'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
    LinuxSf
    WindowsSf
    LinuxVmss
    WindowsVmss
    LoadBalancer
    PublicIpLinux
    PublicIpWindows
    VNet
    NSG
    ApplicationDiagnosticsStorageAccount
    SupportLogStorageAccount
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
