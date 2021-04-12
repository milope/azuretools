# Template: API Management using Azure Cache for Redis as External Cache over a Private Link

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fapi-management%2fapim-external-redis-cache-over-private-link%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fapi-management%2fapim-external-redis-cache-over-private-link%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fapi-management%2fapim-external-redis-cache-over-private-link%2fazureDeploy.json)

This template is a sample that demonstrates an API Management using Azure Cache for Redis as an external cache. The connection will be performed over the Private Endpoint and not via a public IP.

# Intent

The intent behind this template is to show that APIM can connect to Azure Cache Redis as an external cache via a Private Endpoint.

# Parameters

The parameters for this template as as follows:

1. 'resourcePrefix': This string will prefix all resource names.
2. 'apimPublisherName': The name of the publisher for both APIM services.
3. 'apimPublisherEMail': The e-mail address of the publisher for both APIM services.
4. 'apimVnetType': The VNET type for APIM. This value can only be 'External' or 'Internal'. As APIM will be connecting to Redis via private endpoint, APIM cannot be of a None VNET type.
5. 'myIP': Specify your external IP (run curl ifconfig.me) to allow through the NSG that is created for APIM.

# Output

This template does not produce an output.

# Remarks

Please note that due to some sort of delay in the Azure Network Resource applying private endpoint-related policies, this template can fail with an error stating that the subnet used for the private endpoint does not have private endpoint policies enabled. If you run into this issue, please try re-deploy this template.

__IMPORTANT NOTE:__ Please note this template is for EDUCATIONAL PURPOSES ONLY and is provided AS IS without any warranty. Please note Microsoft may not support issues caused by using this template nor may support the template itself. Please file an issue against this repo and I will be happy to take a look.

`Tags: milope, templates, redis, apim, private link, external, cache, external cache`
