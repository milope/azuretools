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
<#
.SYNOPSIS

This cmdlet is used to display all the soft-deleted API Management services in the current subscription.

.DESCRIPTION

This cmdlet is used to display all the soft-deleted API Management services in the current subscription.

.PARAMETER ServiceName

Use to specify a deleted APIM service by name.

.INPUTS

None. This cmdlet does not accept inputs, yet.

.OUTPUTS

Returns PSCustomObject data type that has the following properties:

id: The resource ID of the deleted APIM service.
location: The region of the deleted APIM service.
serviceId: The original resource ID for the deleted APIM service.
scheduledPurgeDate: The date in UTC when the APIM will no longer be available for recovery.
deletionDate: The date when the APIM eas deleted

The output of this cmdlet can be piped into the Remove-AzSoftDeletedApiManagement cmdlet

.EXAMPLE

Get-AzSoftDeletedApiManagement

.EXAMPLE

Get-AzSoftDeletedApiManagement -ServiceName mydeletedapimservice

#>
function Get-AzSoftDeletedApiManagement {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]$ServiceName
    )
    process {
        $context = Get-AzContext
        if($null -eq $context -or $null -eq $context.Subscription) {
            $errorRecord = New-Object System.Management.Automation.ErrorRecord `
                (New-Object System.Management.Automation.PSInvalidOperationException "Run Connect-AzureRmAccount to login."), `
                "", `
                ([System.Management.Automation.ErrorCategory]::AuthenticationError), `
                $null
            Write-Error $errorRecord
            return
        }

        $subId = $context.Subscription.Id

        $resources = Get-AzResource -ResourceId "/subscriptions/$subId/providers/Microsoft.ApiManagement/deletedservices" -ApiVersion "2020-06-01-preview"
        $resources `
            | ForEach-Object { `
                $realId = $_.id
                if(-not $realId.StartsWith("/")) { `
                    $realId = "/" + $realId `
                } `
                [PSCustomObject]@{ `
                    id=$realId;name=$_.name; `
                    location=$_.location; `
                    serviceId=$_.properties.serviceId; `
                    scheduledPurgeDate=$_.properties.scheduledPurgeDate; `
                    deletionDate=$_.properties.deletionDate `
                } `
            } `
            | Where-Object { `
                (-not $PSBoundParameters.ContainsKey("ServiceName")) `
                -or [String]::IsNullOrEmpty($ServiceName) `
                -or $_.name.ToLower() -eq $ServiceName.ToLower() `
            }
    }
}
