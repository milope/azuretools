# Template: Create an Azure Service Fabric Cluster With Visual Studio 2019 Remote Debugging Enabled

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fservice-fabric%2fvs2019-remote-debugging-enabled-cluster%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fservice-fabric%2fvs2019-remote-debugging-enabled-cluster%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fservice-fabric%2fvs2019-remote-debugging-enabled-cluster%2fazureDeploy.json)

__IMPORTANT NOTE:__ Please note this template is for EDUCATIONAL PURPOSES ONLY and is provided AS IS without any warranty. Please note Microsoft may not support issues caused by using this template nor may support the template itself. Please file an issue against this repo and I will be happy to take a look.

## Create a Server and Client Remote Debugging Certificates

Using the [createRemoteDebuggingCert.ps1](https://raw.githubusercontent.com/milope/azuretools/master/src/templates/service-fabric/vs2019-remote-debugging-enabled-cluster/createRemoteDebuggingCert.ps1) cmdlet, we can create or use an existing Azure Resource Group and Azure Key Vault and include two certificates, one for the client to authentication and another for the server to host. This cmdlet is meant to be idempotent.

The output of this command will look as follows:


```
ResourceGroupName                          : {resourceGroupName}
TenantID                                   : {tenantId}
Location                                   : {location}
KeyVaultID                                 : /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.KeyVault/vaults/{vaultName}
KeyVaultURL                                : https://{vaultName}.vault.azure.net/
RemoteDebuggingServerCertificateThumbprint : {certificateThumbprint}
RemoteDebuggingServerCertificateSecretID   : https://{vaultName}.vault.azure.net:443/secrets/{certificateName}/{version}
RemoteDebuggingClientCertificateThumbprint : {certificateThumbprint}
RemoteDebuggingClientCertificateSecretID   : https://{vaultName}.vault.azure.net:443/secrets/{certificateName}/{version}
```

Please take note of these values as the will be used in the template.

## Base Template

These instructions and the resulting template are based on the Microsoft official [5-VM-Windows-1-NodeTypes-Secure](https://github.com/Azure-Samples/service-fabric-cluster-templates/tree/master/5-VM-Windows-1-NodeTypes-Secure) template deployment.

## Template Parameters File

From the official [5-VM-Windows-1-NodeTypes-Secure](https://github.com/Azure-Samples/service-fabric-cluster-templates/tree/master/5-VM-Windows-1-NodeTypes-Secure) template:

1. **Add 4 new parameters** to the [azureDeploy.parameters.json](https://raw.githubusercontent.com/Azure-Samples/service-fabric-cluster-templates/master/5-VM-Windows-1-NodeTypes-Secure/AzureDeploy.Parameters.json) file as so:

```
"remoteDebugKeyVault": {
	"value": "GEN-REMOTE-KEY-VAULT-ID"
},
"remoteDebugCertificateThumbprint": {
	"value": "GEN-REMOTE-DEBUG-SERVER-CERTIFICATE-THUMBPRINT"
},
"remoteDebugCertificateUrl": {
	"value": "GEN-REMOTE-DEBUG-SERVER-CERTIFICATE-SECRET-URL"
},
"remoteDebugClientCertificateThumbprint": {
	"value": "GEN-REMOTE-DEBUG-CLIENT-CERTIFICATE-THUMBPRINT"
}

```

2. Replace **remoteDebugKeyVault** with the **KeyVaultID** value from the cmdlet results above.
1. Replace **remoteDebugCertificateThumbprint** with the **RemoteDebuggingServerCertificateThumbprint** value from the cmdlet results above.
1. Replace **remoteDebugCertificateUrl** with the **RemoteDebuggingServerCertificateSecretID** value from the cmdlet results above.
1. Replace **remoteDebugClientCertificateThumbprint** with the **RemoteDebuggingClientCertificateThumbprint** value from the cmdlet results above.


## Template File

From the official [5-VM-Windows-1-NodeTypes-Secure](https://github.com/Azure-Samples/service-fabric-cluster-templates/tree/master/5-VM-Windows-1-NodeTypes-Secure) template file, make the following changes:

1. In the **parameters** section. add the **remoteDebugKeyVault**, **remoteDebugCertificateThumbprint**, **remoteDebugCertificateUrl** and **remoteDebugClientCertificateThumbprint** parameters as so:

```
"remoteDebugKeyVault": {
    "type": "string",
    "defaultValue": "GEN-REMOTE-KEY-VAULT-ID",
    "metadata": {
        "description": "Remote debug key vault resource ID"
    }
},
"remoteDebugCertificateThumbprint": {
    "type": "string",
    "defaultValue": "GEN-REMOTE-DEBUG-SERVER-CERTIFICATE-THUMBPRINT",
    "metadata": {
        "description": "Remote debug certificate thumbprint"
    }
},
"remoteDebugCertificateUrl": {
    "type": "string",
    "defaultValue": "GEN-REMOTE-DEBUG-SERVER-CERTIFICATE-SECRET-URL",
    "metadata": {
        "description": "Certificate Secret URL for Remote Debug Server Certificate"
    }
},
"remoteDebugClientCertificateThumbprint": {
    "type": "string",
    "defaultValue": "GEN-REMOTE-DEBUG-CLIENT-CERTIFICATE-THUMBPRINT",
    "metadata": {
        "description": "Remote debug client certificate thumbprint"
    }
}
```

2. In the **variables** section, add the **lbNatPoolID1**, **lbNatPoolID2**, **lbNatPoolID3**, **lbNatPoolID4** variables as so:

```
"lbNatPoolID1": "[concat(variables('lbID0'),'/inboundNatPools/RemoteDebugConnectorNatPool')]",
"lbNatPoolID2": "[concat(variables('lbID0'),'/inboundNatPools/RemoteDebugForwarderNatPool')]",
"lbNatPoolID3": "[concat(variables('lbID0'),'/inboundNatPools/RemoteDebugForwarderx86NatPool')]",
"lbNatPoolID4": "[concat(variables('lbID0'),'/inboundNatPools/RemoteDebugFileUploadNatPool')]"
```

3. In the **Microsoft.Network/loadBalancers** resource, add 4 new NAT pools for each of the required Visual Studio Remote Debugging in the **properties > inboundNatPools** section as so:

```
{
    "name": "RemoteDebugConnectorNatPool",
    "properties": {
        "backendPort": "30398",
        "frontendIPConfiguration": {
            "id": "[variables('lbIPConfig0')]"
        },
        "frontendPortRangeEnd": "30407",
        "frontendPortRangeStart": "30398",
        "protocol": "tcp"
    }
},
{
    "name": "RemoteDebugForwarderNatPool",
    "properties": {
        "backendPort": "31398",
        "frontendIPConfiguration": {
            "id": "[variables('lbIPConfig0')]"
        },
        "frontendPortRangeEnd": "31407",
        "frontendPortRangeStart": "31398",
        "protocol": "tcp"
    }
},
{
    "name": "RemoteDebugForwarderx86NatPool",
    "properties": {
        "backendPort": "31399",
        "frontendIPConfiguration": {
            "id": "[variables('lbIPConfig0')]"
        },
        "frontendPortRangeEnd": "31417",
        "frontendPortRangeStart": "31408",
        "protocol": "tcp"
    }
},
{
    "name": "RemoteDebugFileUploadNatPool",
    "properties": {
        "backendPort": "32398",
        "frontendIPConfiguration": {
            "id": "[variables('lbIPConfig0')]"
        },
        "frontendPortRangeEnd": "32407",
        "frontendPortRangeStart": "32398",
        "protocol": "tcp"
    }
}
```

4. In the **Microsoft.Compute/virtualMachineScaleSets resource**, we will perform 3 changes:
  - In the **properties > virutalMachineProfile > extensionProfile > extensions**, we will add the Visual Studio Remote Debugger extension as follows:

```
{
    "name": "[concat('RemoteDebugging_',variables('vmNodeType0Name'))]",
    "properties": {
        "publisher": "Microsoft.VisualStudio.Azure.RemoteDebug",
        "type": "VSRemoteDebugger",
        "typeHandlerVersion": "1.1",
        "autoUpgradeMinorVersion": true,
        "settings": {
            "clientThumbprint": "[parameters('remoteDebugClientCertificateThumbprint')]",
            "serverThumbprint": "[parameters('remoteDebugCertificateThumbprint')]",
            "connectorPort": 30398,
            "fileUploadPort": 32398,
            "forwarderPort": 31398,
            "forwarderPortx86": 31399
        },
        "protectedSettings": null
    }
}
```
 - In the **properties > virtualMachineProfile > networkProfile > networkInterfaceConfigurations > properties > ipConfigurations > properties > loadBalancerInboundNatPools** section, add the 4 NatPools created on Step 3 as shown below:

```
{
    "id": "[variables('lbNatPoolID1')]"
},
{
    "id": "[variables('lbNatPoolID2')]"
},
{
    "id": "[variables('lbNatPoolID3')]"
},
{
    "id": "[variables('lbNatPoolID4')]"
}
```
 - In the **properties > virtualMachineProfile > osProfile > secrets** add the remote debug server certificate as follows:
    - If the Key Vault containing the Remote Debugging certificate is **different** from the Key Vault containing the Service Fabric cluster certificate:

```
{
    "sourceVault": {
        "id": "[parameters('remoteDebugKeyVault')]"
    },
    "vaultCertificates": [
        {
            "certificateStore": "My",
            "certificateUrl": "[parameters('remoteDebugCertificateUrl')]"
        }
    ]
}
```

  - If the Key Vault containing the remote debug certificate is **the same** as the Key Vault containing the Service Fabric cluster certificate, then in the same entry for the Service Fabric cluster certificate secret, add an extra vaultCertificate array element as shown below:

```
"secrets": [
    {
        "sourceVault": {
            "id": "[parameters('sourceVaultValue')]"
        },
        "vaultCertificates": [
            {
                "certificateStore": "[parameters('certificateStoreValue')]",
                "certificateUrl": "[parameters('certificateUrlValue')]"
            },
            {
                "certificateStore": "My",
                "certificateUrl": "[parameters('remoteDebugCertificateUrl')]"
            }
        ]
    }
]
```

## Security Groups and Firewall Remarks

Please ensure to open up **inbound ports 30398 to 30407, 31398 to 31417, 32398 to 32407** or as defined in the 4 aforementioned new NAT pools in any Network Security Group or inbound firewall so that developers and other users can successfully attach the debuggers to the Service Fabric cluster.

## Developers Using Visual Studio 2019

Developers that will be using Visual Studio 2019's Cloud Explorer to attach the remote debugging client will need to download the Remote Debugging **client certificate** as a **pfx** with a private key and install the in the **Current User > Personal** certificate store. We can use the `Import-PfxCertificate` from Windows PowerShell to perform the import as well.

## Resulting Template

I've included the resulting template in this directory for reference.

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fservice-fabric%2fvs2019-remote-debugging-enabled-cluster%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fservice-fabric%2fvs2019-remote-debugging-enabled-cluster%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fservice-fabric%2fvs2019-remote-debugging-enabled-cluster%2fazureDeploy.json)

__IMPORTANT NOTE:__ Please note this template is for EDUCATIONAL PURPOSES ONLY and is provided AS IS without any warranty. Please note Microsoft may not support issues caused by using this template nor may support the template itself. Please file an issue against this repo and I will be happy to take a look.

`Tags: milope, templates, service fabric, visual studio, visual studio 2019`
