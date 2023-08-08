# Template: Linux and Windows Service Fabric Clusters simultaneously

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fservice-fabric%2fdouble-cluster-linux-and-windows-w-nsg%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fservice-fabric%2fdouble-cluster-linux-and-windows-w-nsg%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fservice-fabric%2fdouble-cluster-linux-and-windows-w-nsg%2fazureDeploy.json)

This template creates both a Windows and a Linux Azure Service Fabric cluster simultaneously.

## Intent

None in particular. I needed both a Windows and a Linux cluster to test a situation. They are both deployed to the same VNET, different subnets, behind the same standard Azure Load Balancer. Decided to make this template public. It is based on the Windows and Linux templates in the official [Azure Samples GitHub](https://github.com/Azure-Samples).

## Parameters

The parameters for this template are as follows:

1. **AdminUsername**: Admin username for both the RDP and SSH session.
2. **AdminPassword**: Admin password for both the RDP and SSH session.
3. **CertificateKeyVaultResourceId**: Key Vault Resource ID that will contain the Cluster certificate.
4. **CertificateSecretUrl**: Certificate **secret** URL for the cluste certificate. **Not the certificate URL!!**.
5. **CertificateThumbprint**: Cluster certificate thumbprint.
6. **ClusterProtectionLevel**: Specify the cluster protection level. Values can be None, Sign or EncryptAndSign. Default value: EncryptAndSign.
7. **LinuxInstanceCount**: Specify the number of VMSS instances for the Linux cluster. Please note that the number of instances will determine the cluster reliability.
8. **LinuxDurability**: Specify the durability level for the Linux cluster. Values can be Bronze, Silver or Gold. Default value: Silver.
9. **Location**: Specify the resource locations. Default value: The resource group location.
10. **MyIP**: Specify your public version 4 IP to allow through the network security group (NSG).
11. **ResourcePrefix**: Resource prefix for all resources. This is my personal style for resource naming.
12. **WindowsInstanceCount**: Specify the number of VMSS instances for the Windows cluster. Please note that the number of instances will determine the cluster reliability.
13. **WindowsDurability**: Specify the durability level for the Windows cluster. Values can be Bronze, Silver or Gold. Default value: Silver.

## Output

This template does not provide any output beyond that of a default resource group deployment output.

## Resources Deployed

1. **Trace Event Start** and **Trace Event End**: Used to track usage over Application Insights. I would ask that should you use my template to keep it.
2. **Support Log** and **Application Diagnostics Storage Accounts**: Used to stored the Serivce Fabric and IaaS Diagnostics files respectively. **NOTE**: As an experiment, I have chosen to store the HTTP.sys ETW provider as well.
3. **Network Security Group (NSG)**: Mostly a default Network Security Group that allows the specified *MyIP* parameter through both TCP and ICMP hopefully.
4. **Virtual Network**: An Azure Virtual Network with two (2) subnets, once for each Service Fabric VMSS.
5. **Public IP Addresses**: Two (2) Azure Public IP Addresses. They will both be assigned to the same standard *Azure Load Balancer* with Load Balancing Rules and NAT rules to ensure each public IP directs to only one of the clusters.
6. **Load Balancer**: One (1) Azure Standard Load Balancer. It will have two (2) public IP addresses. It will use the load balancing rules and NAT rules to ensure only one public IP address maps to the Linux cluster and the other to the Windows cluster.
7. **Virtual Machine Scale Sets**: Two (2) Virtual Machine Scale Sets that will be used to be the Linux and Windows Service Fabric clusters respectively.
8. **Service Fabric Clusters**: Two (2) Azure Service Fabric clusters that will be the Windows and Linux Service Fabric clusters respectively.

## Remarks

This template demonstrates that one can have a single Standard Load Balancer to front-end multiple Service Fabric Clusters. Ideally, the same concept can apply to multi-node clusters.

## License/Disclaimer

Copyright © 2022 Michael Lopez

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

`Tags: milope, templates, service-fabric, linux, windows, single load balancer, standard, load balancer`
