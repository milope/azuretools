# Using Azure Firewall to Discover Cache for Redis Dependencies

The following is the final template after this research was completed.

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.json)

## Summary

---

One of the most frequently wondered things I always wonder and get asked about is "what IPs or hostnames do we need to open for [insert Azure Service here]?". This article provides an approach to finding and documenting this dependency information out if the Azure service in question can join an Azure Virtual Network. The general idea is to deploy the Azure resource behind an Azure Firewall and to ensure the Azure Firewall has at least one (1) application rule in its firewall policy or rules. By adding the single application rule, it will check for SNI and hostnames for most connections. We can proceed to dump the firewall logs in Log Analytics and begin the analysis to investigate which outbound dependencies an Azure service may have. I prefer to divide the research into 2 categories: The minimal required dependencies to successfully deploy the service and the rest of the required dependencies.

I will test this method today against Azure Cache for Redis. The first iteration of the template deployment will place Azure Cache for Redis in a Virtual Network with the most restrictive NSGs possible with its subnet pointing traffic to an Azure Firewall via a default Azure Route Table route. The Azure Firewall will have its logs being sent to Log Analytics and will only include an application rule for 'www.microsoft.com:80'. The deployment is expected to fail as Cache For Redis will not be able to reach out to its dependencies, however this will allow us to identify which dependencies are needed to successfully deploy Azure Cache for Redis by using the Azure Firewall logs that are being sent to Log Analytics.

## Parameters

---

- **ResourcePrefix**: Used as a prefix for resource naming.
- **MyIP**: Used to open your public IP through Network Security Groups.
- **RedisVNetAddressRange**: Used to specify the address range for the Cache for Redis Virtual Network.
- **HubVNetAddressRange**:  Used to specify the address range for the hub Virtual Network.

## Resources Deployed

---

Let's start with the first template. We will have the following resource:

- One (1) Azure Storage Account to store Network Security Group Flow Logs.
- One (1) Azure Log Analytics Workspace to store desired logs, such as Azure Firewall firewall logs.
- One (1) Azure Network Security Groups for the Cache for Redis subnet.
- One (1) Azure Public IP Addresses for the Azure Firewall.
- One (1) Azure Network Watcher resource to enable two (2) Network Security Group Flow Logs.
- Two (2) Azure Virtual Networks: One for Cache for Redis and the other being a hub Virtual Network for Azure Firewall.
- Two (2) Azure Virtual Network Peerings to connect the Redis and the hub Virtual Network.
- One (1) Azure Firewall Policy to create a default application rule and a collection of rule groups that will eventually be the Cache for Redis rules.
- One (1) Azure Firewall to control traffic and send the firewall logs to Azure Log Analytics.
- One (1) Azure Route Table to force tunnel connections from the Cache for Redis subnet to the Azure Firewall.
- One (1) Azure Cache for Redis in Premium SKU to be able to join the VNET.
- Two (2) Azure Monitor Diagnostic Settings: One for Azure Firewall and one for Azure Cache for Redis

## Initial Locked Down Template

---

Here is the initial fully locked down template before the correct rules are added to Azure Firewall (azureDeploy.initial.json or azureDeploy.initial.bicep):

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.initial.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.initial.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.initial.json)

The expectation here is that the Cache for Redis will fail as it will not be able to start the service. In the meantime, Azure Firewall will be logging all its deny firewall logs in Log Analytics. Unfortunately, we will definitely not get an exhaustive list right away. We will have to continue to log deny entries and allow them until Cache for Redis successfully deploys. Here is the first attempt:

Log Analtytics Azure Firewall Rules query to search for deny entries:

```kql
let latestNewDeploymentStartTime = datetime(2022-01-25 16:15);
let redisSubnetStart = '10.0.1';
let allowed = (
    AzureDiagnostics
    | where TimeGenerated > latestNewDeploymentStartTime
    | where Category in ("AzureFirewallApplicationRule", "AzureFirewallNetworkRule")
    | where msg_s !contains "Deny"
    | extend
        Protocol = extract("^([a-zA-Z]+) (?: )?request", 1, msg_s),
        Source = extract("request from (.*:\\d{1,5}) to", 1, msg_s),
        Destination = extract("request from (.*:\\d{1,5}) to (.*:\\d{1,5})", 2, msg_s),
        Action = extract("Action:\\s(Allow|Deny)\\.", 1, msg_s)
    | project TimeGenerated, msg_s, Protocol, Source, Destination, Action
    | where Source startswith redisSubnetStart
    | summarize FirstTimeAllowed=min(TimeGenerated), LastTimeAllowed=max(TimeGenerated), TotalAllows=count() by Destination
    | project Destination, FirstTimeAllowed, TotalAllows, LastTimeAllowed
);
let denies = (AzureDiagnostics
| where TimeGenerated > latestNewDeploymentStartTime
| where Category in ("AzureFirewallApplicationRule", "AzureFirewallNetworkRule")
| where msg_s contains "Deny"
| extend
    Protocol = extract("^([a-zA-Z]+) (?: )?request", 1, msg_s),
    Source = extract("request from (.*:\\d{1,5}) to", 1, msg_s),
    Destination = extract("request from (.*:\\d{1,5}) to (.*:\\d{1,5})", 2, msg_s),
    Action = extract("Action:\\s(Allow|Deny)\\.", 1, msg_s)
| project TimeGenerated, msg_s, Protocol, Source, Destination, Action
| where Source startswith redisSubnetStart
| extend Source = substring(Source, 0, indexof(Source, ':'))
| summarize FirstGenerated=min(TimeGenerated), LastTimeDenied=max(TimeGenerated), TotalDenies=count() by Protocol, Destination
| join kind=leftouter (
    allowed
) on Destination
| project-away Destination1
| order by FirstGenerated desc);
union allowed, denies
| extend NotUsedSince= datetime_diff('minute', now(), iif(isnull(LastTimeDenied), LastTimeAllowed, LastTimeDenied))
```

Now that we are observing the list of deny entries, I will begin updating the template to add network or application rules to the Azure Firewall Policy until I allow all enough endpoints for the Cache for Redis service to finish deploying. Ultimately, the observation was that the following endpoints were needed before Azure Cache for Redis deployed successfully. Please note this list may not be exahustive and is subject to change as time goes by.

- Azure Storage:
  - *.blob.core.windows.net
  - *.table.core.windows.net
  - *.queue.core.windows.net
- Azure PKI:
  - ocsp.digicert.com
  - crl4.digicert.com
  - ocsp.msocsp.com
  - mscrl.microsoft.com
  - crl3.digicert.com
  - cacerts.digicert.com
  - oneocsp.microsoft.com
  - crl.microsoft.com
- Azure Key Vault:
  - *.vault.azure.net

I highly recommend the rules with a wildcard stay as such as the Storage and Key Vault endpoints can have unique name per service. Below is the template that allowed Cache for Redis to deploy successfully (azureDeploy.deployment.json or azureDeployment.deployment.bicep):

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.deployment.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.deployment.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.deployment.json)

Following a successful deployment, we continue to monitor any other outbound connection from the Cache for Redis. The following dependencies were observed. Please note this list is not exhaustive. Also, checkpoints with a question mark '?' indicate that I was not entirely sure what it was for following some research on public documentation available.

| Endpoint | Usage |
|----------|-------|
| 104.43.210.62:12000 | Azure Monitor |
| 23.102.135.246:1688 | Windows KMS |
| 40.119.6.228:123 | Windows NTP? |
| 40.122.160.17:12000 | Azure Monitor |
| au.download.windowsupdate.com:80 | Windows Update |
| azredis.prod.microsoftmetrics.com:443 | Azure Monitor |
| azredis-black.prod.microsoftmetrics.com:443 | Azure Monitor |
| azredis-red.prod.microsoftmetrics.com:443 | Azure Monitor |
| azureprofilerfrontdoor.cloudapp.net:443 | Azure Monitoring |
| azurewatsonanalysis-prod.core.windows.net:443 | Azure Monitoring |
| clientconfig.passport.net:443 | Microsoft Store for Business and Education |
| cp601.prod.do.dsp.mp.microsoft.com:443 | Windows Update |
| ctldl.windowsupdate.com:80 | Root Certificate Update |
| dmd.metaservices.microsoft.com:80 | Device Metadata |
| download.windowsupdate.com:80 | Windows Update |
| emdl.ws.microsoft.com:80 | Windows Update |
| fe2.update.microsoft.com:443 | Windows Update |
| fe3.delivery.mp.microsoft.com:443 | Windows Update |
| gcs.prod.monitoring.core.windows.net:443 | Azure Monitor |
| geo-prod.do.dsp.mp.microsoft.com:443 | Windows Update |
| global.prod.microsoftmetrics.com:443 | Azure Monitor |
| go.microsoft.com:443 | Windows Activation |
| go.microsoft.com:80 | Windows Activation |
| *.servicebus.windows.net:443 | Azure Event Hubs |
| kv601.prod.do.dsp.mp.microsoft.com:443 | Windows Update |
| login.live.com:443 | Windows Device Authentication |
| md-ssd-bnz51ttstspj.z14.blob.storage.azure.net:443 | Azure Dependency? |
| md-ssd-shqv3ggz0v3w.z9.blob.storage.azure.net:443 | Azure Dependency? |
| qos.prod.warm.ingest.monitor.core.windows.net:443 | Azure Monitor |
| settings-win.data.microsoft.com:443 | Setting Updates |
| shavamanifestazurecdnprod1.azureedge.net:443 | Azure Monitoring
| sls.update.microsoft.com:443 | Windows Device Auto-update |
| southcentralus-shared.prod.warm.ingest.monitor.core.windows.net:443 | Azure Monitor |
| v10.events.data.microsoft.com:443 | Diagnostic Data |
| validation-v2.sls.microsoft.com:443 | Activation |
| wdcp.microsoft.com:443 | Antivirus |
| www.msftconnecttest.com:80 | NCSI |

In the end, the following ended up being my final template. However, based on documentation used to discover some of these endpoints, it is likely this template still does not cover all possible dependencies (azureDeploy.json or azureDeploy.bicep).

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3a%2f%2fraw.githubusercontent.com%2fmilope%2fazuretools%2fmaster%2fsrc%2ftemplates%2fcache-for-redis%2fcache-for-redis-behind-az-firewall%2fazureDeploy.json)

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

`Tags: milope, templates, redis, firewall, az firewall, azfirewall, azurefirewall, dependency, detection`
