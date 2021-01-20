<#
.SYNOPSIS

Deletes a Cloud Service instance.

.DESCRIPTION

Deletes a single Cloud Service instance.

.PARAMETER CloudServiceName

Specify the name of the Cloud Service for which we will delete an instance of.

.PARAMETER Slot

Specify whether we are deleting from the Production or Staging slot.

.PARAMETER Role

Specify the role name to delete. E.g.: If an instance is named 'WebRole_IN_0' the Name for the Role is 'WebRole'.

.PARAMETER InstanceID

Specify the instance ID to delete. E.g.: If an instance is named 'WebRole_IN_0' the instance ID is 0.

.PARAMETER EnvironmentName

Specify 'AzureCloud' for Public Azure, 'AzureChinaCloud' for Azure China, 'AzureGermanCloud' for Azure Germany and 'AzureUSGovernment' for Azure Government.
The default is AzureCloud for Public Azure.

.INPUTS

This cmdlet does not recieve inputs.

.OUTPUTS

Returns the HTTP Response body of the deletion's result

#>
function Remove-AzCloudServiceInstance {
    [CmdletBinding()]
    param(
        [String][Parameter(Mandatory=$true)]$CloudServiceName,
        [String][Parameter(Mandatory=$true)][ValidateSet("Production", "Staging")]$Slot,
        [String][Parameter(Mandatory=$true)]$Role,
        [Int][Parameter(Mandatory=$true)]$InstanceID,
        [String][Parameter(Mandatory=$false)][ValidateSet("AzureChinaCloud", "AzureCloud","AzureGermanCloud", "AzureUSGovernment")]$EnvironmentName="AzureCloud"
    )
    process {

        function OutputResponse {
            [CmdletBinding()]
            param (
                [System.Net.HttpWebResponse][Parameter(Mandatory=$true)]$Response
            )
            process {
                Write-Host "HTTP/$($response.ProtocolVersion) $([int]$Response.StatusCode) $($Response.StatusDescription)"
                foreach($hdr in $Response.Headers) {
                    Write-Host "$($hdr): $($Response.Headers[$hdr])"
                }

                $stream = $Response.GetResponseStream()

                Write-Host
                $stream.Position = 0
                
                try {

                    $read = 0
                    do {
                        $buffer = New-Object System.Byte[] 1024
                        $read = $stream.Read($buffer,0, $buffer.Length)

                        if($read -gt 0) {
                            Write-Host ([System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)) -NoNewline
                        }
                    }
                    while($read -gt 0 -and $read -lt $Response.ContentLength)

                }
                finally {
                    $stream.Dispose()
                    $response.Dispose()
                }
            }
        }

        $context = Get-AzContext
        if($null -eq $context -or $null -eq $context.Subscription) {
            $errorRecord = New-Object System.Management.Automation.ErrorRecord `
                (New-Object System.Management.Automation.PSInvalidOperationException "Run Connect-AzAccount to login."), `
                "", `
                ([System.Management.Automation.ErrorCategory]::AuthenticationError), `
                $null
            Write-Error $errorRecord
            return
        }

        $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
        $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
        $token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
        $authHeader = "Bearer " + $token.AccessToken

        $instanceName = "$($Role)_IN_$InstanceId"


        $prefix = (Get-AzEnvironment -Name $EnvironmentName).ServiceManagementUrl
        $subscriptionId = $context.Subscription.Id

        $prefix += "$($subscriptionId)/services/hostedservices/$($CloudServiceName)/deploymentslots/$($Slot)/roleinstances/?comp=delete"
        $httpMethod = "POST"
        $xMSVersion = "2013-08-01"
        $body = "<RoleInstances xmlns=`"http://schemas.microsoft.com/windowsazure`" xmlns:i=`"http://www.w3.org/2001/XMLSchema-instance`"><Name>$($instanceName)</Name></RoleInstances>"

        $temp = $ProgressPreference

        try {
            $ProgressPreference = "SilentlyContinue"
            $response = Invoke-WebRequest -Uri $prefix -UserAgent "PowerShell ASM Client" -Headers @{Authorization = $authHeader; "x-ms-version" = $xMSVersion} -Method $httpMethod -Body $body -ContentType "application/xml; charset=utf-8"
            $response.RawContent
        }
        catch {

            $response = ([System.Net.HttpWebResponse]($_.Exception.Response))

            OutputResponse -Response $response
        }
        $ProgressPreference = $temp
    }
}
