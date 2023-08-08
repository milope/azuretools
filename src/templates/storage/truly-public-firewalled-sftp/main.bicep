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

@description('Use this parameter to override the default resource locations. If unspecified, the resource group\'s location will be used.')
param Location string = resourceGroup().location

@description('Allowed IP Address esto allow through the Firewall. Specify in CIDR notation.')
param AllowedIPs array

@description('Use this parameter to specify and address space for the virtual network where the Azure Firewall will run.')
param VnetAddressSpace string = '10.0.0.0/24'

@description('Use this parameter to specify a DNS label for the Azure Firewall public IP.')
param FirewallDnsLabel string

@description('Use this parameter to specify and create a container name for the Sftp User, if needed.')
param SftpUserContainerName string

@description('Use this parameter to specify and create an Sftp user, if needed. The password or key will need to be generated via the Portal.')
param SftpUser string


var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2023-06-26'
  LabVersion: '1.0'
  LabCategory: 'Storage'
}

var correlationId = guid(uniqueString(deployment().name))
resource TraceEventStart 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${ResourcePrefix}trackEventStart'
  location: Location
  tags: tags
  kind: 'AzurePowerShell'
  properties: {
    retentionInterval: 'PT1H'
    azPowerShellVersion:'9.7'
    arguments: format('-correlationId "{0}"', correlationId)
    scriptContent: '''
      param (
        [Guid]$correlationId
      )
      $iKey = (Invoke-RestMethod -UseBasicParsing -Uri https://raw.githubusercontent.com/milope/azuretools/master/api/appinsights/instrumentationKey).InstrumentationKey
      $EventName = "Template deployment started."
      $CustomProperties = @{Type="Template";Category="Azure Storage";Name="Truly Public Azure Storage SFTP Service";CorrelationId=$correlationId}
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
    cleanupPreference: 'Always'
  }
}

resource VNet 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: '${ResourcePrefix}VNet'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    addressSpace: {
      addressPrefixes: [
        VnetAddressSpace
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: VnetAddressSpace
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
    ]
  }
}

resource AzFirewallPolicy 'Microsoft.Network/firewallPolicies@2022-11-01' = {
  name: '${ResourcePrefix}FwPolicies'
  tags: tags
  location: Location
  dependsOn: [
    TraceEventStart
  ]
  properties: {
    sku: {
      tier: 'Standard'
    }
  }
}

resource Storage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  kind: 'StorageV2'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Standard_LRS'
  }
  name: '${ResourcePrefix}sftp'
  properties: {
    accessTier: 'Hot'
    isHnsEnabled: true
    isLocalUserEnabled: true
    isSftpEnabled: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: '${VNet.id}/subnets/AzureFirewallSubnet'
        }
      ]
    }
  }
}

resource StorageAccountBlobServices 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = if(length(trim(SftpUserContainerName)) > 0 && length(trim(SftpUser)) > 0) {
  name: 'default'
  parent: Storage
}

resource StorageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = if(length(trim(SftpUserContainerName)) > 0) {
  parent: StorageAccountBlobServices
  name: SftpUserContainerName
}

resource LocalUser 'Microsoft.Storage/storageAccounts/localUsers@2022-09-01' = if(length(trim(SftpUserContainerName)) > 0) {
  parent: Storage
  name: SftpUser
  properties: {
    homeDirectory: StorageContainer.name
  }
}

resource PublicIP 'Microsoft.Network/publicIPAddresses@2022-11-01' = {
  name: '${ResourcePrefix}FwPublicIP'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: FirewallDnsLabel
    }
  }
}

resource AzFirewallDNATRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-11-01' = {
  parent: AzFirewallPolicy
  name: 'storageDNATRules'
  properties: {
    priority: 1001
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        action: {
          type: 'DNAT'
        }
        name: 'storageDNATRules'
        priority: 1000
        rules: [
          {
            ruleType: 'NatRule'
            description: 'Use this to NAT to Azure Storage.'
            sourceAddresses: AllowedIPs
            destinationAddresses: [
              PublicIP.properties.ipAddress
            ]
            destinationPorts: [
              '22'
            ]
            ipProtocols: [
              'TCP'
            ]
            translatedFqdn: '${Storage.name}.blob.${environment().suffixes.storage}'
            translatedPort: '22'
          }
        ]
      }
    ]
  }
}

resource AzFirewall 'Microsoft.Network/azureFirewalls@2022-11-01' = {
  name: '${ResourcePrefix}Fw'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
    AzFirewallDNATRules
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
        name: 'ipConfig'
        properties: {
          publicIPAddress: {
            id: PublicIP.id
          }
          subnet: {
            id: '${VNet.id}/subnets/AzureFirewallSubnet'
          }
        }
      }
    ]
  }
}

resource TraceEventEnd 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${ResourcePrefix}-trackEventEnd'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
    VNet
    AzFirewallPolicy
    Storage
    StorageAccountBlobServices
    StorageContainer
    LocalUser
    PublicIP
    AzFirewallDNATRules
    AzFirewall
  ]
  kind: 'AzurePowerShell'
  properties: {
    retentionInterval: 'PT1H'
    azPowerShellVersion:'9.7'
    arguments: format('-correlationId "{0}"', correlationId)
    scriptContent: '''
      param (
        [Guid]$correlationId
      )
      $iKey = (Invoke-RestMethod -UseBasicParsing -Uri https://raw.githubusercontent.com/milope/azuretools/master/api/appinsights/instrumentationKey).InstrumentationKey
      $EventName = "Template deployment completed."
      $CustomProperties = @{Type="Template";Category="Azure Storage";Name="Truly Public Azure Storage SFTP Service";CorrelationId=$correlationId}
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
    cleanupPreference: 'Always'
  }
}
