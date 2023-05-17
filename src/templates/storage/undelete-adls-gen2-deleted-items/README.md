# Template: Undelete ADLS Gen2 Storage Account items

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fstorage%2fundelete-adls-gen2-deleted-items%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fstorage%2fundelete-adls-gen2-deleted-items%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fstorage%2fundelete-adls-gen2-deleted-items%2fazureDeploy.json)

## Intent

Due to different challenges presented when attempting to recover deleted ADLS items (e.g.: can't run PowerShell, can't run CLI, etc.), I'm creating and updating this template to provide an additional resource to perform un-deletion or recovery of soft-deleted ADLS Gen 2 storage account paths.

## Remarks

This script is for ADLS Gen 2 or Hierarchical Namespace-enabled Azure Storage Accounts not for flat-hierarchy Azure Storage Accounts.

## Pre-requisites

- A hierarchical namespace-enabled Azure Storage account.
- The account running this deployment must be have access to perform the following operations in the resource group where the Storage Account belongs to:
  - Create a user-managed Managed Identity.
  - Assign a Storage Data Contributor role to the aforementioned managed identity at the resource group scope.
- If we're attempting to recover items under a directory that is also deleted, it is necessary to recreate the deleted directory for the items to be listed for recovery.

## Parameters

- **StorageAccountName**: Specify the Storage Account we are attempting to undelete paths from.
- **Location**: Choose the same location as the Storage Account as the deployment scripts will be deployed to the chosen location and for performance reasons, it's best if the script resides in the same location as the Storage Account.
- **Path**: Specify the path this deployment will attempt to be recovering. Start with the filesystem following by the directory or directories under which the soft-deleted item was. Please note that it is **required** to recreate a directory for which a soft-deleted item existed. Otherwise, the soft-deleted item may not appear for recovery.
- **WhatIf**: Set to true if we want to perform a test run.

## Output

While this template deployment does not have an output, please review the deployment script resource if we require to track the recovery script's stdout and other outputs.

## Resources Deployed

- **Trace Event Start** and **Trace Event End**: Used to track usage over Application Insights. I would ask that should you use my template to keep it.
- **User-assigned Managed Identity**: This will be used to allow the recovery deployment script run the undelete operation.
- **Role Assignment**: This will assign the Storage Account Data Contributor role to the user-assigned Managed Identity at the resource group scope.
- **Recovery Script**: A deployment script that uses the Azure PowerShell module to call the undelete operation on soft-deleted items found under the provided path.

## License/Disclaimer

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

`Tags: milope, templates, storage, recover, undelete, soft-delete, adls, gen2`
