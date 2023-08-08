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

var tags = {
  LabCreatedBy: 'Michael Lopez'
  LabCreatedOn: '2023-05-04'
  LabVersion: '1.0'
  LabCategory: 'Storage'
  
}

resource Storage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: StorageAccountName
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

output SubscriptionId string = subscription().id
output ResourceGroupName string = resourceGroup().name
output StorageAccount string = Storage.name
output WebEndpoint string = Storage.properties.primaryEndpoints.web
output AASALink string = '${Storage.properties.primaryEndpoints.web}.well-known/apple-app-site-association'
