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
@description('Specify the path to attempt recovery for in the {filesystem}/{directory}/{file} format')
param Path string
@description('Set to true if we want to try a dry run.')
param WhatIf bool = false

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2023-05-12'
  LabVersion: '1.0'
  LabCategory: 'Storage'
}

var correlationId = guid(uniqueString(deployment().name))
var gustring = uniqueString(resourceGroup().id, StorageAccountName)
var whatIfFlag = WhatIf ? ' -WhatIf' : ''

resource TraceEventStart 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}${gustring}ts'
  location: Location
  tags: tags
  kind: 'AzurePowerShell'
  properties: {
    retentionInterval: 'PT1M'
    azPowerShellVersion:'9.7'
    arguments: format('-correlationId "{0}"', correlationId)
    scriptContent: '''
      param (
        [Guid]$correlationId
      )
      $iKey = (Invoke-RestMethod -UseBasicParsing -Uri https://raw.githubusercontent.com/milope/azuretools/master/api/appinsights/instrumentationKey).InstrumentationKey
      $EventName = "Template deployment started."
      $CustomProperties = @{Type="Template";Category="Azure Storage";Name="Recover ADLS Gen 2 Items";CorrelationId=$correlationId}
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
  name: '${StorageAccountName}${gustring}uami'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
  ]
}

var raID = '76d2e0d5-3f6a-4d14-b6f8-5e5ac01c4644'
resource RoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: raID
  properties: {
    principalId: UserAMI.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab'
    description: 'Adding the managed identity access to be able to run listKeys and create the AASA. This can be removed later.'
  }
}

resource Recovery 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}${gustring}rec'
  location: Location
  tags: tags
  kind: 'AzurePowerShell'
  dependsOn: [
    TraceEventStart
    RoleAssignment
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${UserAMI.id}': {}
    }
  }
  properties: {
    retentionInterval: 'PT1M'
    azPowerShellVersion:'9.7'
    arguments: format('-SubscriptionId "{0}" -ResourceGroupName "{1}" -StorageAccountName "{2}" -Path "{3}"{4}', subscription().subscriptionId, resourceGroup().name, StorageAccountName, Path, whatIfFlag)
    scriptContent: '''
    param (
        [Parameter(Mandatory=$false)][String]$SubscriptionId,
        [Parameter(Mandatory=$true)][String]$ResourceGroupName,
        [Parameter(Mandatory=$true)][String]$StorageAccountName,
        [Parameter(Mandatory=$true)][String]$Path,
        [Switch]$WhatIf
    )
    
    function Write-ErrorRecord {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)][System.Type]$Type = [System.Management.Automation.PSInvalidOperationException],
            [Parameter(Mandatory=$false)][System.Management.Automation.ErrorCategory]$Category = ([System.Management.Automation.ErrorCategory]::InvalidOperation),
            [Parameter(Mandatory=$true)][String]$Message,
            [Switch]$StopScript
        )
        begin {
            $errorRecord = ([System.Management.Automation.ErrorRecord]::new(
                (New-Object -Type $Type.FullName -ArgumentList $Message),
                [String]::Empty,
                $Category,
                $null
            ))
            if($StopScript) {
                Write-ErrorRecord $errorRecord -ErrorAction Stop 
            }
            else {
                Write-ErrorRecord $errorRecord
            }
        }
    
        process {
    
        }
        end {
    
        }
    }
    
    $tempDebugPreference = $DebugPreference
    if($PSBoundParameters.ContainsKey("Debug")) {
        $DebugPreference = "Continue"
    }
    
    try
    {
        Write-Debug "Getting Azure PowerShell Context."
        $azContext = Get-AzContext
        if($null -eq $azContext -and $null -eq $azContext.Account) {
            Write-Debug "Az Context was not found, will try to login to Azure PowerShell."
            Connect-AzAccount -ErrorAction SilentlyContinue
        }
    
        if($null -eq $azContext -and $null -eq $azContext.Account) {
            Write-Debug "Could not get an Azure PowerShell Context"
            Write-ErrorRecord -Message "Unable to get an Az Context with an account." -StopScript
        }
    
        if($null -ne $SubscriptionId -and $SubscriptionId.Trim().Length -gt 0) {
            Select-AzSubscription -Subscription $SubscriptionId
        }
    
        $storageAccount = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if($null -eq $storageAccount) {
            Write-ErrorRecord -Message "Unable to get an Az Context with an account." -StopScript
        }
    
        if(-not $storageAccount.EnableHierarchicalNamespace) {
            Write-ErrorRecord -Message "The storage account '$StorageAccountName' is not an ADLS Gen 2-enabled Azure Storage Account." -StopScript
        }
    
    
        Write-Debug "Working on path '$Path'."
        if($Path.StartsWith("/")) {
            $Path = $Path.Substring(1)
        }
    
        $uri = [System.Uri]::new("$($storageAccount.primaryEndpoints.Dfs)$($Path)")
        if($uri.Segments.Length -eq 1) {
            Write-Warning "Skipping '$Path' as it doesn't have a filesystem in the path."
        }
        $fileSystem = $(if($uri.Segments[1].EndsWith("/")) { $uri.Segments[1].Substring(0, $uri.Segments[1].Length - 1) } else { $uri.Segments[1] })
        $filePath = $null
    
        $getParameters = @{
            Context = $storageAccount.Context
            FileSystem = $fileSystem
        }
    
        if($uri.Segments.Length -gt 2) {
            $filePath = (@(2 .. ($uri.Segments.Length - 1)) | ForEach-Object { $uri.Segments[$_] }) -join [String]::Empty
            if($filePath.EndsWith("/")) {
                $filePath = $filePath.Substring(0, $filePath.Length - 1)
            }
            $getParameters = @{
                Context = $storageAccount.Context
                FileSystem = $fileSystem
                Path = $filePath
            }
        }
    
        if($WhatIf) {
            Get-AzDataLakeGen2DeletedItem @getParameters
        }
        else {
            Get-AzDataLakeGen2DeletedItem @getParameters | Restore-AzDataLakeGen2DeletedItem
        }
    }
    finally {
        $DebugPreference = $tempDebugPreference
    }
    '''
  }
}

resource TraceEventEnd 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${StorageAccountName}${gustring}te'
  location: Location
  tags: tags
  dependsOn: [
    TraceEventStart
    Recovery
  ]
  kind: 'AzurePowerShell'
  properties: {
    retentionInterval: 'PT1M'
    azPowerShellVersion:'9.7'
    arguments: format('-correlationId "{0}"', correlationId)
    scriptContent: '''
      param (
        [Guid]$correlationId
      )
      $iKey = (Invoke-RestMethod -UseBasicParsing -Uri https://raw.githubusercontent.com/milope/azuretools/master/api/appinsights/instrumentationKey).InstrumentationKey
      $EventName = "Template deployment completed."
      $CustomProperties = @{Type="Template";Category="Azure Storage";Name="Recover ADLS Gen 2 Items";CorrelationId=$correlationId}
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
