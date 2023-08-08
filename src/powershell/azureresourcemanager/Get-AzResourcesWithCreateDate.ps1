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
