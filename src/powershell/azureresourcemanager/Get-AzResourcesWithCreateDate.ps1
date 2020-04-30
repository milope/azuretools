function Get-AzResourcesWithCreateDate
{
    [CmdletBinding()]
    param (

    )
    process {
        $context = Get-AzContext
    
        if($null -eq $context -or $null -eq $context.Account) {
            throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : Run Connect-AzAccount to login."
        }
    
        $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
        $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
        $token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
        $authHeader = "Bearer " + $token.AccessToken
        $requestHeaders = @{"Authorization"=$authHeader}
        $uri = "$($context.Environment.ResourceManagerUrl)subscriptions/$($context.Subscription.Id)/resources?api-version=2020-01-01&`$expand=createdTime"
    
        do
        {
            $data = Invoke-RestMethod -Method Get -Uri  $uri -Headers $requestHeaders
            $data.value | ForEach-Object { [PSCustomObject]@{ResourceName=$_.name;ResourceType=$_.type;CreatedDate=$_.createdTime} }
            $uri = $data.nextLink
        }
        while(-not [String]::IsNullOrEmpty($uri))
    }
}
