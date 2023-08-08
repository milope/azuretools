# Template: Azure Storage Static Website with an Apple-App-Site-Association File

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fstorage%2fstorage-static-website-with-an-aasa%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fstorage%2fstorage-static-website-with-an-aasa%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fstorage%2fstorage-static-website-with-an-aasa%2fazureDeploy.json)

## Intent

This template can be used to demonstrate how to create an apple-app-site-association file in an Azure Storage Account with the Static Websites feature enabled. This feature is used to "connect your app and a website to provide both a native app and a browser experience." More information can be found [here](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

## Parameters

- **StorageAccountName**: Required. Specify a name for the Storage Account. Please note names must be unique within an environment as it is the public-facing DNS name. This name will also be used as resource prefix for the other resource names, except the private DNS zones.
- **Location**: The default location for all th resources. If unspecified, it will use the resource group's location.
- **AASAContent**: The content for the apple-app-site-association file. For more information, please visit [here](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

## Output

- **SubscriptionId**: The subscription ID for the Storage Account.
- **ResourceGroupName**: The resource group name for the Storage Account.
- **StorageAccount**: The Storage Account name.
- **WebEndpoint**: The static website endpoint for the Storage Account.
- **AASALink**: The URL for the apple-app-site-association-file.

## Resources Deployed

- **Trace Event Start** and **Trace Event End**: Used to track usage over Application Insights. I would ask that should you use my template to keep it.
- **User-assigned Managed Identity**: A user-assigned Managed Identity is required for two deployment scripts to allow them to connect to Azure and run Az PowerShell commands. One of them enables the static website feature and the other creates the apple-app-site-association file.
- **Role Assignment**: The created Managed Identity is assigned a built-in Storage Account Contributor role at the Storage Account level.
- **Storage Account**: The Storage Account to be created.
- **Two (2) Deployment Scripts**: The first Deployment Script enables the the static website feature using Azure PowerShell. The second Deployment Script creates a blob with blob path `.well-known/apple-app-site-association` in the `$web` container that is created when the static website feature is enabled.

## Remarks

Storage Accounts do support custom domains, which can be added to this template. However, as Azure Storage does not support importing custom certificates to Azure Storage, it is recommended to have a layer-7 type service in front of Azure Storage for custom domain purposes. Microsoft documentation suggests a CDN, but other services like Azure Application Gateway and Azure Frontdoor are options.

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

`Tags: milope, templates, storage, custom domain, custom, domains, aasa, apple-app-site-association`