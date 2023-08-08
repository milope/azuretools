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

This function is used to send a request to Azure Resource Manager

.DESCRIPTION

Use This function facilitates the ability to send raw web requests to Azure Resource Manager by using the built-in and current Azure Context from the Az modules.
Please note that requests need to be in the format of /subscriptions/{subid}/{restoftheresourceID}.

.PARAMETER Method

Specifies the HTTP method (GET, POST, PUT, DELETE, or PATCH) to use. Default is GET

.PARAMETER URI

Specifies URI to send to Azure Resource Manager. Please note that requests need to be in the format of /subscriptions/{subid}/{restoftheresourceID}.

.PARAMETER Body

The JSON Body to send for POST, PUT or PATCH requests. Not used for GET or DELETE

.PARAMETER RawResponse

Switch to return all headers and the body in raw format. Otherwise, the output will just be a formatted JSON string for the response.

.INPUTS

None. This cmdlet does not accept inputs, yet.

.OUTPUTS

If RawResponse is passed, the entire response heeader and unformatted body. Otherwise, a formatted response body.

.EXAMPLE

Send-AzRequest -Method GET -URI "/subscriptions/12345678-1234-1234-1234-123456789abc/resourceGroups/resourceGroupName/providers/Microsoft.Compute/virtualMachines/testVM?api-version=2020-06-01"

#>
function Send-AzRequest {
    [CmdletBinding()]
    param (
        [String][Parameter(Mandatory=$false)][ValidateSet("GET", "POST", "PUT", "DELETE", "PATCH")]$Method = "GET",
        [String][Parameter(Mandatory=$true)]$URI,
        [String][Parameter(Mandatory=$false)]$Body,
        [Switch]$RawResponse
    )
    begin {
        function OutputResponse {
            [CmdletBinding()]
            param (
                [System.Net.HttpWebResponse][Parameter(Mandatory=$true)]$Response,
                [Bool]$RawResponse
            )
            process {

                if($RawResponse) {
                    "HTTP/$($response.ProtocolVersion) $([int]$Response.StatusCode) $($Response.StatusDescription)"
                    foreach($hdr in $Response.Headers) {
                        "$($hdr): $($Response.Headers[$hdr])"
                    }
                }

                $stream = $Response.GetResponseStream()
                $stringBuilder = [System.Text.StringBuilder]::new()

                Write-Host
                $stream.Position = 0
                
                try {

                    $read = 0
                    do {
                        $buffer = New-Object System.Byte[] 1024
                        $read = $stream.Read($buffer,0, $buffer.Length)

                        if($read -gt 0) {
                            $stringBuilder.Append(([System.Text.Encoding]::UTF8.GetString($buffer, 0, $read))) | Out-Null
                        }
                    }
                    while($read -gt 0 -and $read -lt $Response.ContentLength)

                }
                finally {
                    $stream.Dispose()
                    $response.Dispose()
                }

                $json = $stringBuilder.ToString()
                if($RawResponse) {
                    [Environment]::NewLine
                    $json
                }
                else {
                    ConvertFrom-Json $json | ConvertTo-Json -Depth 100
                }
            }
        }
    }
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

        $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
        $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
        $token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
        $authHeader = "Bearer " + $token.AccessToken
        $requestHeaders = @{"Authorization"=$authHeader}

        $armURL = $context.Environment.ResourceManagerUrl
        if($armURL.EndsWith("/")) {
            $armURL = $armURL.Substring(0, $armURL.Length - 1)
        }
        $realURL = $armURL + $URI
        
        $temp = $ProgressPreference

        try {
            $ProgressPreference = "SilentlyContinue"
            if($Method -eq "GET") {
                $response = Invoke-WebRequest -Uri $realUrl -UserAgent "PowerShell ARM Client" -Headers $requestHeaders -Method $Method -ContentType "application/json"
            }
            else {
                $response = Invoke-WebRequest -Uri $realUrl -UserAgent "PowerShell ARM Client" -Headers $requestHeaders -Method $Method -Body $Body -ContentType "application/json"
            }

            if($RawResponse) {
                $response.RawContent
            } 
            else {
                ConvertFrom-Json $response.Content | ConvertTo-Json -Depth 100
            }
        }
        catch {

            $response = ([System.Net.HttpWebResponse]($_.Exception.Response))

            (OutputResponse -Response $response -RawResponse $RawResponse)
        }
        $ProgressPreference = $temp
    }
}
