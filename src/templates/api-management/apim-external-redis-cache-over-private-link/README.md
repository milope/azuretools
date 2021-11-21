# Template: API Management using Azure Cache for Redis as External Cache over a Private Link

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fapi-management%2fapim-external-redis-cache-over-private-link%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fapi-management%2fapim-external-redis-cache-over-private-link%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fapi-management%2fapim-external-redis-cache-over-private-link%2fazureDeploy.json)

This template is a sample that demonstrates an API Management using Azure Cache for Redis as an external cache. The connection will be performed over the Private Endpoint and not via a public IP.

## Intent

---

The intent behind this template is to show that APIM can connect to Azure Cache Redis as an external cache via a Private Endpoint.

## Parameters

---

The parameters for this template as as follows:

1. 'resourcePrefix': This string will prefix all resource names.
2. 'apimPublisherName': The name of the publisher for both APIM services.
3. 'apimPublisherEMail': The e-mail address of the publisher for both APIM services.
4. 'apimVnetType': The VNET type for APIM. This value can only be 'External' or 'Internal'. As APIM will be connecting to Redis via private endpoint, APIM cannot be of a None VNET type.
5. 'myIP': Specify your external IP (run curl ifconfig.me) to allow through the NSG that is created for APIM.

## Output

---

This template does not produce an output.

## Remarks

---

Please note that due to some sort of delay in the Azure Network Resource applying private endpoint-related policies, this template can fail with an error stating that the subnet used for the private endpoint does not have private endpoint policies enabled. If you run into this issue, please try re-deploy this template.

## License/Disclaimer

---

Copyright © 2021 Michael Lopez

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

`Tags: milope, templates, redis, apim, private link, external, cache, external cache`
