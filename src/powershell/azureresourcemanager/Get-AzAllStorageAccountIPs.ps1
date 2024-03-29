<#
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
#>
function Get-AzAllStorageAccountIPs {

    $context = Get-AzContext
    
    if($null -eq $context -or $null -eq $context.Account) {
        throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : Run Connect-AzAccount to login."
    }

    # TODO: Iterate if NextLink is present
    $armStorage = Get-AzResource -ResourceId "/subscriptions/$($context.Subscription.Id)/providers/Microsoft.Storage/storageAccounts" -ApiVersion "2019-06-01"
    $asmStorage = Get-AzResource -ResourceId "/subscriptions/$($context.Subscription.Id)/providers/Microsoft.ClassicStorage/storageAccounts" -ApiVersion "2016-11-01"

    $totalEndpoints = New-Object System.Collections.ArrayList
    $armStorage | ForEach-Object { if($null -ne $_.Properties.primaryEndpoints.blob) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.primaryEndpoints.blob).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address; $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="Blob";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.primaryEndpoints.dfs) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.primaryEndpoints.dfs).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="DFS";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.primaryEndpoints.file) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.primaryEndpoints.file).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="File";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.primaryEndpoints.queue) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.primaryEndpoints.queue).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="Queue";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.primaryEndpoints.table) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.primaryEndpoints.table).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="Table";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.primaryEndpoints.web) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.primaryEndpoints.web).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="Web";IPv4=$ip}) | Out-Null } }

    $armStorage | ForEach-Object { if($null -ne $_.Properties.secondaryEndpoints.blob) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.secondaryEndpoints.blob).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address; $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="Blob";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.secondaryEndpoints.dfs) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.secondaryEndpoints.dfs).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="DFS";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.secondaryEndpoints.file) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.secondaryEndpoints.file).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="File";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.secondaryEndpoints.queue) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.secondaryEndpoints.queue).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="Queue";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.secondaryEndpoints.table) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.secondaryEndpoints.table).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="Table";IPv4=$ip}) | Out-Null } }
    $armStorage | ForEach-Object { if($null -ne $_.Properties.secondaryEndpoints.web) { $name = $_.Name; $dns = (New-Object System.Uri $_.Properties.secondaryEndpoints.web).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address;  $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType="Web";IPv4=$ip}) | Out-Null } }

    $asmStorage | ForEach-Object { $name = $_.Name; $_.Properties.endpoints | ForEach-Object { $dns = (New-Object System.Uri $_).DnsSafeHost; $ip=(Resolve-DnsName -Name $dns -Type A).IP4Address; $endpointType = $dns.Split(".")[1]; $endpointType = "Classic $($endpointType[0].ToString().ToUpperInvariant() + $endpointType.Substring(1))"; $totalEndpoints.Add([PSCustomObject]@{Name=$name;DnsName=$dns;EndpointType=$endpointType;IPv4=$ip}) | Out-Null } }
    $totalEndpoints
}
