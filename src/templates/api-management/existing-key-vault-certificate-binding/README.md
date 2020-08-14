#Template: Create Azure Key Vault-bound API Management Service given an existing Azure Key Vault and Certificate

This particular template is a sample where the following takes place.

1.  A blank API Management service is created with a System managed identity.
2.  An access policy is added to provided Azure Key Vault to grant the newly-created API Management managed identity GET operations to its Secrets.
3.  Once the operation is completed, the newly-created API Management service is updated to have add a custom domain for the Proxy endpoint and binds a provided Key Vault certificate (via secret name) to the Proxy endpoint.

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fapi-management%2fexisting-key-vault-certificate-binding%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fapi-management%2fexisting-key-vault-certificate-binding%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fapi-management%2fexisting-key-vault-certificate-binding%2fazureDeploy.json)
