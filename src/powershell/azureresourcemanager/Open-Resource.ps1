<#
Copyright © 2022 Michael Lopez
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

Use this function to view or edit Microsoft Azure resources.

.DESCRIPTION

Use this function to view or edit Microsoft Azure resources.

.PARAMETER ResourceId

Pass a resource ID for the resource being edited.

.PARAMETER EditMode

When specifying Edit Mode, saving the file after changing it will prompt the
user to confirm if they would want to commit the changes. If 'yes' is passed,
the script will send a PUT request with the new changes. Otherwise, the script
will exit.

.INPUTS

Resource ID can be piped into this script.

.OUTPUTS

This script would return the outout from a PUT request in edit mode.

.EXAMPLE

Open-Resource -ResourceId "/subscriptions/12345678-1234-1234-1234-123456789abc/resourceGroups/resourceGroupName/providers/Microsoft.Compute/virtualMachines/testVM"

.EXAMPLE

Open-Resource -ResourceId "/subscriptions/12345678-1234-1234-1234-123456789abc/resourceGroups/resourceGroupName/providers/Microsoft.Compute/virtualMachines/testVM" -EditMode

.NOTES

This script has not been thoroughly tested, please exercise caution when using
this script and report errors.

#>
function Open-Resource {
    [CmdletBinding()]
    param (
        [String][Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]$ResourceId,
        [Switch]$EditMode
    )
    begin {
        function Send-TrackEvent (
            [Parameter(Mandatory=$true, HelpMessage="Specify the App Insights Instrumentation Key",Position=0)][ValidateScript({ $_ -ne [Guid]::Empty})][Guid] $iKey,
            [Parameter(Mandatory=$true, HelpMessage="Specify the Event to send to App Insights",Position=1)][String]$EventName,
            [Parameter(Mandatory=$false, HelpMessage="Specify custom properties", Position=2)][Hashtable]$CustomProperties
        )
        {    
            $sendEvent = {
                param (
                    [Guid]$piKey,
                    [String]$pEventName,
                    [Hashtable]$pCustomProperties
                )

                $appInsightsEndpoint = "https://dc.services.visualstudio.com/v2/track"
                $body = @{
                    name = "Microsoft.ApplicationInsights.$piKey.Event"
                    time = [DateTime]::UtcNow.ToString("o")
                    iKey = $piKey
                    #tags = @{
                    #    "ai.device.id" = $env:COMPUTERNAME
                    #    "ai.device.locale" = $env:USERDOMAIN
                    #    "ai.user.id" = $env:USERNAME
                    #    "ai.user.authUserId" = "$($env:USERDOMAIN)\$($env:USERNAME)"
                    #    "ai.cloud.roleInstance" = $env:COMPUTERNAME
                    #}
                    "data" = @{
                        baseType = "EventData"
                        baseData = @{
                            ver = "2"
                            name = $pEventName
                            properties = ($pCustomProperties | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
                        }
                    }
                } | ConvertTo-Json -Depth 10 -Compress
    
                $temp = $ProgressPreference
                $ProgressPreference = "SilentlyContinue"
                Invoke-WebRequest -Method POST -Uri $appInsightsEndpoint -Headers @{"Content-Type"="application/x-json-stream"} -Body $body -TimeoutSec 3 | Out-Null
                $ProgressPreference = $temp
            }
    
            Start-Job -ScriptBlock $sendEvent -ArgumentList @($iKey, $EventName, $CustomProperties) | Out-Null
        }

        $correlationId = [Guid]::NewGuid()
        $iKey = (Invoke-RestMethod -UseBasicParsing -Uri https://raw.githubusercontent.com/milope/azuretools/master/api/appinsights/instrumentationKey -ErrorAction SilentlyContinue).InstrumentationKey
        if($null -ne $iKey) {
            Send-TrackEvent -iKey $iKey -EventName "PowerShell Started" -CustomProperties @{Type="PowerShell";Category="Debugging";Name="Open-Resource";ResourceId=$ResourceId;EditMode=($EditMode.IsPresent -and $EditMode);CorrelationId=$correlationId}
        }

        #TODO: Add Validation
        #TODO: Support Subscription api-version
        #TODO: Support non-happy paths 
    
        $namespaceName = $null
        $resourceType = $null
        $url = $null
    
        $context = Get-AzContext
        if($null -eq $context -or $null -eq $context.Account) {
            throw New-Object System.Management.Automation.PSInvalidOperationException "$($MyInvocation.MyCommand) : Run Connect-AzAccount to login."
        }
     
        if($ResourceId.Contains("providers/")) {
            $url = [System.Uri]::new("https://tempuri.org$ResourceId")
    
            for($i = $url.Segments.Length - 1; $i -gt 0; $i--) {
                if($url.Segments[$i].ToLowerInvariant() -eq "providers/") {
                    $namespaceName = $url.Segments[$i+1]
                    $resourceType = $url.Segments[$i+2]
                    for($j = $i+4; $j -lt $url.Segments.Length; $j+=2) {
                        $resourceType += $url.Segments[$j]
                    }
                    break
                }
            }
    
            $namespaceName = $namespaceName.Substring(0, $namespaceName.Length - 1)
            $resourceType = $resourceType.Substring(0, $resourceType.Length - 1)
        }
    
        $apiVersion = $null
    
        if($null -ne 0 -and $namespaceName.Trim().Length -gt 0) {
            $rp = Get-AzResourceProvider -ListAvailable | Where-Object { $_.ProviderNamespace.ToLowerInvariant() -eq $namespaceName.ToLowerInvariant() }
            $rt = $rp.ResourceTypes | Where-Object { $_.ResourceTypeName.ToLowerInvariant() -eq $resourceType.ToLowerInvariant() }
            $apiVersion = $rt.ApiVersions[0]
        }
    
        $response = $null
    
        if($null -ne 0 -and $apiVersion.Trim().Length -gt 0) {
            $url = "$($context.Environment.ResourceManagerUrl)$($resourceId.Substring(1))?api-version=$apiVersion"
            $response = Invoke-AzRest -Method GET -Uri $url
        }
    
        if($response.StatusCode -eq 200) {

            $responseObj = $response.Content | ConvertFrom-Json
            $fileName = "$($responseObj.Name)-$(([DateTime]::UtcNow).ToFileTimeUtc()).json"

            $outFile = Join-Path -Path $env:TEMP -ChildPath $fileName
            $responseObj | ConvertTo-Json -Depth 100 | Out-File $outFile
            $fileHash = (Get-FileHash $outFile -Algorithm SHA256).Hash
            Start-Process -FilePath $outFile
            if($EditMode) {
                Write-Warning "Suspending script until a file change is detected. Use Ctrl+C to stop."
                Write-Warning "Use your editor to make changes to the resource JSON. Once saved, our probing will detect the file change and commit the changes as a PUT after confirmation is granted."
                while($true) {
                    if(-not (Test-Path $outFile)) {
                        Write-Warning "Script exiting as the JSON file was deleted."
                        break
                    }

                    $newHash = (Get-FileHash $outFile -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                    if($null -ne $newHash -and $newHash -ne $fileHash) {
                        Write-Host -ForegroundColor Yellow
                        $response = Read-Host -Prompt "Detected resource change. Confirm committing changes? Y(es)|N(no). (NOTE: Choosing anything other than 'yes' will end script)"
                        if($null -ne $response -and ($response.ToLowerInvariant() -eq "y" -or $response.ToLowerInvariant() -eq "yes")) {
                            $json = Get-Content -Raw -Path $outFile | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 100
                            Invoke-AzRest -Method PUT -Uri $url -Payload $json
                        }
                        break
                    }

                    Start-Sleep -Seconds 1
                }
            }
            
            Start-Sleep -Seconds 2
            Remove-Item $outFile -Force
        }
    }
    end {
        if($null -ne $iKey) {
            Send-TrackEvent -iKey $iKey -EventName "PowerShell Completed" -CustomProperties @{Type="PowerShell";Category="Debugging";Name="Open-Resource";ResourceId=$ResourceId;EditMode=($EditMode.IsPresent -and $EditMode);CorrelationId=$correlationId}
        }
    }
}