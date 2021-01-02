<#
.SYNOPSIS

This cmdlet is used to purge soft-deleted API Management Services.

.DESCRIPTION

This cmdlet is used to purge soft-deleted API Management Services.

.PARAMETER ServiceName

Use to specify a deleted APIM service by name.

.PARAMETER Force

Does not prompt prior to purging deleted APIM service.

.PARAMETER AsJob

Performs the task in the background and returns a PowerShell job.

.INPUTS

This cmdlet can accept the output from the Get-AzSoftDeletedApiManagement cmdlet or an array of
PSCustomObject with an id property there the id must be a valid resource ID for a soft-deleted
APIM service.

.OUTPUTS

None. May throw an exception even when successful. If the AsJob is used, returns a PowerShell job object.

.EXAMPLE

Remove-AzSoftDeletedApiManagement

.EXAMPLE

Remove-AzSoftDeletedApiManagement -ServiceName mydeletedapimservice

.EXAMPLE

Get-AzSoftDeletedApiManagement | Remove-AzSoftDeletedApiManagement

#>
function Remove-AzSoftDeletedApiManagement {
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName="ParamInputObject", ValueFromPipeline=$true, Mandatory=$true)][PSCustomObject[]]$InputObject,
        [Parameter(ParameterSetName="ParamSpecified", Mandatory=$true)][String]$ServiceName,
        [Switch]$Force,
        [Switch]$AsJob
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

        if($PSBoundParameters.ContainsKey("ServiceName") -and -not [String]::IsNullOrEmpty($ServiceName) -and -not [String]::IsNullOrWhiteSpace($ServiceName)) {
            $resources = Get-AzResource -ResourceId "/subscriptions/$subId/providers/Microsoft.ApiManagement/deletedservices" -ApiVersion "2020-06-01-preview"
            $InputObject = ($resources `
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
            })
        }

        if($null -ne $InputObject -and $InputObject.Length -gt 0) {
            $InputObject | ForEach-Object {
                try {
                    if($Force -and $AsJob) {
                        Remove-AzResource -ResourceId $_.id -Force -AsJob
                    }
                    elseif($Force) {
                        Remove-AzResource -ResourceId $_.id -Force
                    }
                    elseif($AsJob) {
                        Remove-AzResource -ResourceId $_.id -AsJob
                    }
                    else {
                        Remove-AzResource -ResourceId $_.id
                    }
                }
                catch {
                    if(-not $_.Exception.Message.StartsWith("CorrelationId")) {
                        throw
                    }
                }
            }
        }
    }
}
