# Template: Deploy a quick VM with IIS, Application Request Routing and Web Deploy

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fvirtual-machine%2fquick-iis-vm%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fvirtual-machine%2fquick-iis-vm%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fvirtual-machine%2fquick-iis-vm%2fazureDeploy.json)

This template creates a Windows Server of the user's choosing along with adding Internet Information Services (IIS), Application Request Routing (ARR) and configuring Web Deploy on the Server.

## Intent

I decided to create this template as back in the day I supported both IIS and Azure Plaform as a Service technologies. I had a PowerShell script that would setup an IIS Web Server for my labs. Decided to update it and convert it to a template for the benefit of all. If Links are broken, please let me know.

## Parameters

1. **Admin Username**: Specify a username for the Administrator.
2. **Admin Password**: Specify a password for the Administrator.
3. **AllowedIP**: The deployment includes a Network Security Rule, to be able to connect, specify this IP and the IP will be added as allowed through the NSG rules.
4. **DNSLabel**: Specify a public DNS label. If not specified, the DNS label will be automatically set to the `VMName` parameter in lowercase. The DNS label will be appended *ipv4* and *ipv6* to allow for IPv4 and IPv6 connections.
5. **Location**: Specify an Azure region for the deployment. If not specified, the template will use the resource group's location.
6. **ServerEdition**: Specify the Windows Server Edition, currently allowed (2008-R2, 2012, 2012-R2, 2016, 2019 and 2022).
7. **UseCore**: When applicable, use the Server Core version of the Windows Server.
8. **UseGen2**: Use a [Generation 2 virtual machine](URL "https://docs.microsoft.com/en-us/azure/virtual-machines/generation-2").
9. **VMName**: Specifies the resource name for the virtual machine. The value specified will be converted to lower case and used for the computer name as well.

## Output

This template will return the fully qualified domain name for both the public IPv4 and IPv6 addresses.

## Resources Deployed

1. **Trace Event Start** and **Trace Event End**: Used to track usage over Application Insights. I would ask that should you use my template to keep it.
2. **Network Security Group (NSG)**: Mostly a default Network Security Group that allows the specified `AllowedIP` parameter through both TCP and ICMP hopefully.
3. **Virtual Network**: An Azure Virtual Network with a default subnet. This will be used by the deployed virtual machine.
4. **Public IP Addresses**: Two (2) Azure Public IP Addresses. One will be for IPv4 connections and the other will be for IPv6 connections.
5. **Network Interface Card**: A dual-stack network interface card for the virtual machine.
6. **Virtual Machine**: This will be the virtual machine where IIS, ARR and Web Deploy will be installed in.
7. **Custom Script Extension**: The custom script extension will download the PowerShell script in this repository into the Virtual Machine and execute it to install IIS, ARR and Web Deploy.

## Remarks

Links come and go, if the script or its download links fail, please let me know. Check the C:\approot folder to debug how the script runs in the Virtual machine.

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

`Tags: milope, templates, iis, windows, dual-stack, web deploy, arr, application request routing, rewrite, reverse proxy`
