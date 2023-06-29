
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
@description('This deployment is a secure deployment. Add your external IP to add to the jumpbox VM.')
param AllowedIP string
@description('Specify an local user username for the SFTP.')
param SftpLocalUsername string

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2023-05-22'
  LabVersion: '1.0'
  LabCategory: 'Storage'
}

resource StorageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  kind: 'StorageV2'
  location: Location
  tags: tags
  name: StorageAccountName
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    isHnsEnabled: true
    isSftpEnabled: true
    isLocalUserEnabled: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: [
        {
          value: AllowedIP
        }
      ]
    }
  }
}


resource StorageBlobServices 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: StorageAccount
  name: 'default'
  properties: {
    
  }
}

resource SftpContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: StorageBlobServices
  name: 'home'
  properties: {
    publicAccess: 'None'
  }
}

resource SftpLocalUsers 'Microsoft.Storage/storageAccounts/localUsers@2022-09-01' = {
  parent: StorageAccount
  name: SftpLocalUsername
  properties: {
    permissionScopes: [
      {
        permissions: 'rcwdl'
        resourceName: 'home'
        service: 'blob'
      }
    ]
    hasSshKey: true
    hasSshPassword: true
    homeDirectory: 'home'
  }
}
