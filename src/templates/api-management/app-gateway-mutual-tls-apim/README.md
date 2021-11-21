# Mutual TLS Certificate Forwarding from Application Gateway to API Management

## Introduction

---

In a normal SSL TLS setup, a server would present a server certificate and a client would be tasked with validating the presented certificate. With mutual TLS, both the server and client would require to present a certificate that the receiving side would need to validate.

The main challenge with mutual TLS presents itself on a topology where we would have a de-militarized zone (DMZ) hosting an external layer-7 reverse proxy that would then forward web requests to a private backend web server where this web server would require a client certificate for authentication.

With public key infrastructure, a client certificate and public key are forwarded to a web server, the web server would encrypt traffic utilizing the public key and send a response to a client. The client would use its private key to decrypt the traffic.

Now, since a reverse proxy is considered a layer-7 device, it may have features where it would need to decrypt the return traffic from its backend, such as injecting response headers or validating response entities for insecure content. These features would require the reverse proxy to also have a private key to decrypt the traffic that returns from the backend.

In a scenario where the backend web server requires a client certificate for authentication, while a reverse proxy receives a public key and certificate from a client, it does not receive the client certificate private key, leaving it unable to utilize the client certificate for a second hop mutual TLS. Result: TLS is achieving its job of protecting traffic from a middleware device spoofing traffic.

## So, What Do We Do?

---

The idea at this point is to have the reasonable expectation that, unless we manually upload a client certificate and private key to the reverse proxy, we will need to use another mechanism to forward the certificate and the receiving server will have to trust that the reverse proxy performed a successful and valid mutual TLS authentication with an authorized client certificate.

This example is an attempt to achieve this configuration by having Application Gateway v2 SKU perform the mutual TLS handshake and forward the certificate and its properties via HTTP headers to the backend. Azure API Management will serve as the backend and will receive the certificate headers via policy and echo them as HTML. Additionally, Application Gateway will forward the certificate in base-64 encoding, however, this example will not make use of the certificate itself.

## Template Parameters

---

This is my first Bicep template being published and it will contain the following parameters:

- **ApiManagementSubnetAddressRange:** This parameter is optional and can be used to specify an address range for the API Management Virtual Network Subnet. If not specified, it's default will be 10.0.1.0/24 (or 10.0.1.4 to 10.0.1.254).
- **ApiManagementDnsLabel:** We're deploying an internal Virtual Network-joined API Management Service using the stv2 model. This type of deployment requires us to specify a static standard public IP for management API calls along with a DNS label. This parameter corresponds to the DNS label for API Management's Management API Public IP.
- **ApplicationGatewayDnsLabel:** Public DNS label for Application Gateway's public IP.
- **ApplicationGatewaySslCertificate:** Application Gateway's SSL certificate. You will need to export a PFX certificate and encode it in base-64 value and pass it to this variable.
- **ApplicationGatewaySslCertificatePassword:** Specify a password for the SSL certificate PFX file specified in the previous parameter.
- **ApplicationGatewaySubnetAddressRange:** This parameter is optional and can be used to specify an address range for the Application Gateway Virtual Network Subnet. If not specified, it's default will be 10.0.0.0/24 (or 10.0.0.4 to 10.0.0.254).
- **ApplicationGatewayTrustedClientCerts:** Specify a list of Application Gateway trusted certificates. These will also be in base-64 encoded. Specifying this value can be complicated, I recommend following the steps on the following documentation to understand how to pass this value. [Export a trusted client CA certificate chain to use with client authentication | Microsoft Docs](https://docs.microsoft.com/azure/application-gateway/mutual-authentication-certificate-management])
- **MyIP:** Specify your public IP address to be allowed through the Application Gateway Network Security Groups (NSG). You can send a request to ifconfig.me to see your IP.
- **PublisherEmail:** Specify the publisher E-mail for the API Management service.
- **PublisherName:** Specify the publisher name for the API Management service.
- **ResourcePrefix:** My pattern for resource naming is just to pass a resource prefix and append a simple name per parent resource. This parameter specifies the resource prefix. If you were to specify 'hello' then the API Management service would be named 'helloapim'.
- **VnetAddressRange:**: Specify the Virtual Network address range for this deployment. Please ensure that the address space covers both the API Management and Application Gateway subnet's address ranges.

## Template Resources

---

- **Network Security Groups (x2):** There will be 2 separate network security groups. One will be for Application Gateway's subnet, which will allow for the "MyIP" IP address to be allowed and for the Health Probes as well. The other network security group will be used to lock APIM so that it only receives traffic from Application Gateway and the API Management Control Plane.
- **Virtual Network:** The virtual network will have 2 subnets, one to host Application Gateway computes and another to host API Management computes.
- **Public IP Addresses (x2):** There will be two static Standard public IP addresses, one for Application Gateway and the other for API Management's management APIs.
- **Private DNS Zone:** The private DNS zone will be for azure-api.net, azure-api.us, azure-api.cn, or azure-api.de DNS zones. It will allow Application Gateway to be able to reach the internal API Management using the fully qualified domain name. The Private DNS zone will be linked to the virtual network from this template.
- **API Management:** The API management will contain an API with a single GET operation. The GET operation will have a policy that will check for the certificate headers forwarded from Application Gateway and echo the certificate properties. If the certificate headers are not present, it should then attempt to perform a mutual TLS itself and echo the certificate headers (**NOTE: this fallback is currently not tested**) and echo the certificate properties, otherwise it will return a 401.
- **Application Gateway:** The Application Gateway will be used to perform the true mutual TLS and will be configured with header rewrites to forward the certificate and its properties to API Management as headers.

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

`Tags: milope, templates, application gateway, appgw, apim, mutual, tls, client certificate, client, certificate`
