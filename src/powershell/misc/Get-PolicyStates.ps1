param(
    [Parameter(Mandatory=$false)]$filter,
    [Parameter(Mandatory=$false)][ValidateSet("AzureCloud", "AzureUSGovernment", "AzureChinaCloud", "AzureGermanyCloud")]$Environment="AzureCloud"
)

$context = Get-AzContext
if($null -eq $context -or $null -eq $context.Account) {
    Connect-AzContext
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