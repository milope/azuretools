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

param(
    [Parameter(Mandatory=$false)]$filter,
    [Parameter(Mandatory=$false)][ValidateSet("AzureCloud", "AzureUSGovernment", "AzureChinaCloud", "AzureGermanyCloud")]$Environment="AzureCloud"
)

$context = Get-AzContext
if($null -eq $context -or $null -eq $context.Account) {
    Connect-AzContext -Environment $Environment
}

$subscriptionId = $context.Subscription.Id
$extra =  $(if($null -ne $filter -and -not [String]::IsNullOrEmpty($filter.Trim())) { "&`$filter=$($filter.Trim())" } else { [String]::Empty })
$apiVersion = "2019-10-01"
$url = "/subscriptions/$($subscriptionId)/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults?api-version=$($apiVersion)$($extra)"
$method = "POST"

do {
    $data = Invoke-AzRestMethod -Path $url -Method $method
    $data = ($data.Content | ConvertFrom-Json)

    $data.value | Select-Object -Property resourceId, policyDefinitionName, isCompliant

    $url = $data.'@odata.nextLink'
} while($null -ne $url -and $url.Trim().Length -gt 0)