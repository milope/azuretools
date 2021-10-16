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

Deletes a classic Cloud Service instance.

.DESCRIPTION

Deletes a single classic Cloud Service instance.

.PARAMETER CloudServiceName

Specify the name of the classic Cloud Service for which we will delete an instance of.

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
