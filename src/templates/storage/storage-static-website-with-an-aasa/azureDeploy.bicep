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

@description('Specify the name for the Storage Account (must be globally unique).')
param StorageAccountName string

@description('Specify a location for the Storage Account. If unspecified, will use the resource group\'s location')
param Location string = resourceGroup().location

@description('Specify the Apple Site Association file content.')
param AASAContent string

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2023-05-04'
  LabVersion: '1.0'
  LabCategory: 'Storage'
  
}

var correlationId = guid(uniqueString(deployment().name))
resource TraceEventStart 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}-trackEventStart'
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
      $CustomProperties = @{Type="Template";Category="Azure Storage";Name="Azure Storage with AASA";CorrelationId=$correlationId}
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

resource UserAMI 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${StorageAccountName}-uami'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
}

resource Storage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: StorageAccountName
  dependsOn: [
    TraceEventStart
  ]
  location: Location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

resource RoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: '360d5770-27d3-4b96-bef9-7b040628b734'
  scope: Storage
  properties: {
    principalId: UserAMI.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab'
    description: 'Adding the managed identity access to be able to run listKeys and create the AASA. This can be removed later.'
  }
}

resource StaticWebSite 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}enableStaticWebsite'
  location: Location
  kind: 'AzurePowerShell'
  tags: tags
  dependsOn: [
    Storage
    RoleAssignment
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${UserAMI.id}': {}
    }
  }
  properties: {
    retentionInterval: 'P1D'
    azPowerShellVersion:'3.0'
    arguments: format('-SubscriptionId "{0}" -ResourceGroupName "{1}" -StorageAccountName "{2}"', subscription().subscriptionId, resourceGroup().name, StorageAccountName)
    scriptContent: '''
      param (
        [Parameter(Mandatory=$true)][String]$SubscriptionId,
        [Parameter(Mandatory=$true)][String]$ResourceGroupName,
        [Parameter(Mandatory=$true)][String]$StorageAccountName
      )
      
      Start-Sleep -Seconds 60
      $DebugPreference = "Continue"
      Connect-AzAccount -Identity
      $context = Get-AzContext
      if($null -eq $context -or $null -eq $context.Account) {
        throw [System.Exception]::new("I failed to login to Azure using the Managed Identity.")
      }
      Select-AzSubscription -Subscription $SubscriptionId
      $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName -ErrorAction SilentlyContinue
      if($null -eq $storageAccount) {
        throw [System.Exception]::new("I failed to get the storage account $StorageAccountName.")
      }
      $ctx = $storageAccount.Context
      Enable-AzStorageStaticWebsite -Context $ctx

    '''
  }
}

resource AASA 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}addAASA'
  location: Location
  kind: 'AzurePowerShell'
  tags: tags
  dependsOn: [
    StaticWebSite
    RoleAssignment
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${UserAMI.id}': {}
    }
  }
  properties: {
    retentionInterval: 'P1D'
    azPowerShellVersion:'3.0'
    arguments: format('-SubscriptionId "{0}" -ResourceGroupName "{1}" -StorageAccountName "{2}" -AASAContent "{3}"', subscription().subscriptionId, resourceGroup().name, StorageAccountName, base64(AASAContent))
    scriptContent: '''
    param (
      [Parameter(Mandatory=$true)][String]$SubscriptionId,
      [Parameter(Mandatory=$true)][String]$ResourceGroupName,
      [Parameter(Mandatory=$true)][String]$StorageAccountName,
      [Parameter(Mandatory=$true)][String]$AASAContent
    )
    
    Start-Sleep -Seconds 60
    $DebugPreference = "Continue"
    $actualAASAContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AASAContent))
    Connect-AzAccount -Identity
    $context = Get-AzContext
    if($null -eq $context -or $null -eq $context.Account) {
      throw [System.Exception]::new("I failed to login to Azure using the Managed Identity.")
    }
    Select-AzSubscription -Subscription $SubscriptionId
    $storageAccount = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    while($null -eq $storageAccount) {
        Start-Sleep -Seconds 3
        $storageAccount = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    }
    
    $storageContext = $storageAccount.Context
    $webContainer = Get-AzStorageContainer -Name "`$web" -Context $storageContext -ErrorAction SilentlyContinue
    while($null -eq $webContainer) {
        Start-Sleep -Seconds 3
        $webContainer = Get-AzStorageContainer -Name "`$web" -Context $storageContext -ErrorAction SilentlyContinue
    }
    
    $contentFile = ".\temp.json"
    Write-Debug "Writing '$actualAASAContent' to $contentFile"
    $actualAASAContent | Out-File $contentFile
    if(Test-Path -Path $contentFile) {
        try {
            Write-Debug "Writing the AASA blob."
            Set-AzStorageBlobContent -Context $storageContext -Container $webContainer.Name -File $contentFile -Blob ".well-known/apple-app-site-association" -Properties @{"ContentType"="application/json"} -Force | Out-Null
            Write-Debug "Done!!"
        }
        finally {
            Remove-Item $contentFile -Force
        }
    }
    '''
  }
}

resource TraceEventEnd 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}-trackEventEnd'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
    Storage
    StaticWebSite
    AASA
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
      $CustomProperties = @{Type="Template";Category="Azure Storage";Name="Azure Storage with AASA";CorrelationId=$correlationId}
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

output SubscriptionId string = subscription().id
output ResourceGroupName string = resourceGroup().name
output StorageAccount string = Storage.name
output WebEndpoint string = Storage.properties.primaryEndpoints.web
output AASALink string = '${Storage.properties.primaryEndpoints.web}.well-known/apple-app-site-association'
