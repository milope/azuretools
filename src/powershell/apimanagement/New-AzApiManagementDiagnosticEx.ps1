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

Use this cmdlet to fully control all diagnostic settings for an API Management.

.DESCRIPTION

This cmdlet is similar to the New-AzApiManagementDiagnostic with the exception
that it spans all properties, including data masking.

.PARAMETER ResourceGroupName

The name of the resource group the API Management service is located.

.PARAMETER ServiceName

The name of the API Management service.

.PARAMETER DiagnosticId

The name of the diagnostic ID setting.

.PARAMETER ApiId

[Optional] Specify the API ID to update the diagnostic settings for a specific
API. Otherwise, do not specify to update the diagnostic settings for all APIs.

.PARAMETER LoggerId

Resource Id of a target logger.

.PARAMETER AlwaysLog

Specifies for what type of messages sampling settings should not apply.

.PARAMETER BackendRequestDataMaskingHeaderSettings

Specifies the data masking mode and header name for the backend request.
Accepted values for the mode are:

- Hide: Hide the presence of an entity.
- Mask: Mask the value of an entity.

Example: To hide the Authorization header, specify the parameter as follows:

@{Mode="Hide";Name="Authorization"}

This parameter accepts multiple values as such:

@{Mode="Mask";Name="Authorization"},@{Mode="Hide";Name="SecretHeader"}

.PARAMETER BackendRequestDataMaskingQueryParamsSettings

Specifies the data masking mode and query string name for the backend request.
Accepted values for the mode are:

- Hide: Hide the presence of an entity.
- Mask: Mask the value of an entity.

Example: To hide the id query string, specify the parameter as follows:

@{Mode="Hide";Name="id"}

This parameter accepts multiple values as such:

@{Mode="Mask";Name="token"},@{Mode="Hide";Name="secret-id"}

.PARAMETER BackendRequestHttpHeadersToLog

Array of HTTP Headers to log for the backend request.

.PARAMETER BackendRequestBodyBytes

Number of backend request body bytes to log.

.PARAMETER BackendResponseDataMaskingHeaderSettings

Specifies the data masking mode and header name for the backend response.
Accepted values for the mode are:

- Hide: Hide the presence of an entity.
- Mask: Mask the value of an entity.

Example: To hide the Authorization header, specify the parameter as follows:

@{Mode="Hide";Name="Authorization"}

This parameter accepts multiple values as such:

@{Mode="Mask";Name="Authorization"},@{Mode="Hide";Name="SecretHeader"}

.PARAMETER BackendResponseDataMaskingQueryParamsSettings

Specifies the data masking mode and query string name for the backend response.
Accepted values for the mode are:

- Hide: Hide the presence of an entity.
- Mask: Mask the value of an entity.

Example: To hide the id query string, specify the parameter as follows:

@{Mode="Hide";Name="id"}

This parameter accepts multiple values as such:

@{Mode="Mask";Name="token"},@{Mode="Hide";Name="secret-id"}

.PARAMETER BackendResponseHttpHeadersToLog

Array of HTTP Headers to log for the backend response.

.PARAMETER BackendResponseBodyBytes

Number of backend response body bytes to log.

.PARAMETER FrontendRequestDataMaskingHeaderSettings

Specifies the data masking mode and header name for the frontend request.
Accepted values for the mode are:

- Hide: Hide the presence of an entity.
- Mask: Mask the value of an entity.

Example: To hide the Authorization header, specify the parameter as follows:

@{Mode="Hide";Name="Authorization"}

This parameter accepts multiple values as such:

@{Mode="Mask";Name="Authorization"},@{Mode="Hide";Name="SecretHeader"}

.PARAMETER FrontendRequestDataMaskingQueryParamsSettings

Specifies the data masking mode and query string name for the frontend request.
Accepted values for the mode are:

- Hide: Hide the presence of an entity.
- Mask: Mask the value of an entity.

Example: To hide the id query string, specify the parameter as follows:

@{Mode="Hide";Name="id"}

This parameter accepts multiple values as such:

@{Mode="Mask";Name="token"},@{Mode="Hide";Name="secret-id"}

.PARAMETER FrontendRequestHttpHeadersToLog

Array of HTTP Headers to log for the frontend request.

.PARAMETER FrontendRequestBodyBytes

Number of frontend request body bytes to log.

.PARAMETER FrontendResponseDataMaskingHeaderSettings

Specifies the data masking mode and header name for the frontend response.
Accepted values for the mode are:

- Hide: Hide the presence of an entity.
- Mask: Mask the value of an entity.

Example: To hide the Authorization header, specify the parameter as follows:

@{Mode="Hide";Name="Authorization"}

This parameter accepts multiple values as such:

@{Mode="Mask";Name="Authorization"},@{Mode="Hide";Name="SecretHeader"}

.PARAMETER FrontendResponseDataMaskingQueryParamsSettings

Specifies the data masking mode and query string name for the frontend
response.
Accepted values for the mode are:

- Hide: Hide the presence of an entity.
- Mask: Mask the value of an entity.

Example: To hide the id query string, specify the parameter as follows:

@{Mode="Hide";Name="id"}

This parameter accepts multiple values as such:

@{Mode="Mask";Name="token"},@{Mode="Hide";Name="secret-id"}

.PARAMETER FrontendResponseHttpHeadersToLog

Array of HTTP Headers to log for the frontend response.

.PARAMETER FrontendResponseBodyBytes

Number of frontend response body bytes to log.

.PARAMETER HttpCorrelationProtocol

Sets correlation protocol to use for Application Insights diagnostics.

Accepted values are:

- Legacy: Inject Request-Id and Request-Context headers with request
          correlation data.
- None: Do not read and inject correlation headers.
- W3C: Inject Trace Context headers.

.PARAMETER LogClientIp

Log the ClientIP. Default is false.

.PARAMETER OperationNameFormat

The format of the Operation Name for Application Insights telemetries. Default
is Name.

Accepted Values are:

- Name: API_NAME;rev=API_REVISION - OPERATION_NAME
- Url: HTTP_VERB URL

.PARAMETER SamplingPercentage

Rate of sampling for fixed-rate sampling.

.PARAMETER SamplingType

Sampling type for Diagnostic. Currently, only 'fixed' is accepted (Fixed-rate
sampling).

.PARAMETER Verbosity

The verbosity level applied to traces emitted by trace policies.

Accepted Values are:

- error: Only traces with 'severity' set to 'error' will be sent to the logger
         attached to this diagnostic instance.
- information: Traces with 'severity' set to 'information' and 'error' will be
               sent to the logger attached to this diagnostic instance.
- verbose: All the traces emitted by trace policies will be sent to the logger
           attached to this diagnostic instance.
- debug: Sets diagnostics to debug mode. Experimental.

.PARAMETER DoNotTrack

Disable sending custom event to Application Insights

.INPUTS

None. This cmdlet does not support inputs

.OUTPUTS

Unless a failure takes place, this cmdlet will return an object matchin the
DiagnosticContract data type.

See: https://docs.microsoft.com/en-us/rest/api/apimanagement/current-ga/api-diagnostic/update#diagnosticcontract

.EXAMPLE

Import-Module .\new-AzApiManagementDiagnosticEx.ps1
New-AzApiManagementDiagnosticEx -ResourceGroupName resourceGroupName `
    -ServiceName apimName -DiagnosticId default -ApiId echo-api `
    -LoggerId "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/resourceGroupName/providers/Microsoft.ApiManagement/service/apinName/loggers/applicationInsights"
    -AlwaysLog $true `
    -BackendRequestDataMaskingHeaderSettings @{mode="mask";name="Authorization"},@{mode="hide";name="x-ms-secret-code"} `
    -BackendResponseDataMaskingHeaderSettings @{mode="mask";name="Authorization"},@{mode="hide";name="x-ms-secret-code"} `
    -FrontendRequestDataMaskingHeaderSettings @{mode="mask";name="Authorization"},@{mode="hide";name="x-ms-secret-code"} `
    -FrontendResponseDataMaskingHeaderSettings @{mode="mask";name="Authorization"},@{mode="hide";name="x-ms-secret-code"} `
    -BackendRequestDataMaskingQueryParamsSettings @{mode="Mask";name="id"} `
    -BackendResponseDataMaskingQueryParamsSettings @{mode="Mask";name="id"} `
    -FrontendRequestDataMaskingQueryParamsSettings @{mode="Mask";name="id"} `
    -FrontendResponseDataMaskingQueryParamsSettings @{mode="Mask";name="id"} `
    -BackendRequestHttpHeadersToLog Authorization,Date,x-ms-secret-code `
    -BackendResponseHttpHeadersToLog Authorization,Date,x-ms-secret-code `
    -FrontendRequestHttpHeadersToLog Authorization,Date,x-ms-secret-code `
    -FrontendResponseHttpHeadersToLog Authorization,Date,x-ms-secret-code `
    -BackendRequestBodyBytes 1024 -BackendResponseBodyBytes 1024 `
    -FrontendRequestBodyBytes 1024 -FrontendResponseBodyBytes 1024 `
    -HttpCorrelationProtocol W3C -LogClientIp $true `
    -OperationNameFormat Url -SamplingPercentage .50 -SamplingType fixed

#>

$Source = @"
public enum ATPSDataMaskingMode {
    Hide,
    Mask
}


public class ATPSDataMaskingEntity {

    private ATPSDataMaskingMode _mode;
    private string _name;

    public ATPSDataMaskingMode Mode {
        get { return _mode; }
        set { _mode = value; }
    }

    public string Name {
        get { return _name; }
        set { _name = value; }
    }

    public ATPSDataMaskingEntity() { }

    public ATPSDataMaskingEntity(string name) {
        _name = name;
        _mode = ATPSDataMaskingMode.Hide;
    }

    public ATPSDataMaskingEntity(string name, ATPSDataMaskingMode mode) {
        _name = name;
        _mode = mode;
    }

    public ATPSDataMaskingEntity(string name, string mode) {
        _name = name;
        _mode = (ATPSDataMaskingMode)System.Enum.Parse(typeof(ATPSDataMaskingMode), mode, true);
    }
}
"@

Add-Type -TypeDefinition $Source

function New-AzApiManagementDiagnosticEx {
    [CmdletBinding()]
    param (
        # Url
        [Parameter(Mandatory)][String]$ResourceGroupName,
        [Parameter(Mandatory)][String]$ServiceName,
        [Parameter(Mandatory)][String]$DiagnosticId,
        [Parameter(Mandatory=$false)][String]$ApiId,
        # Body (Required)
        [Parameter(Mandatory)][String]$LoggerId,
        # Body (Optional)
        [Parameter(Mandatory=$false)][Bool]$AlwaysLog,
        [Parameter(Mandatory=$false)][ATPSDataMaskingEntity[]]$BackendRequestDataMaskingHeaderSettings,
        [Parameter(Mandatory=$false)][ATPSDataMaskingEntity[]]$BackendRequestDataMaskingQueryParamsSettings,
        [Parameter(Mandatory=$false)][String[]]$BackendRequestHttpHeadersToLog,
        [Parameter(Mandatory=$false)][Int32]$BackendRequestBodyBytes,
        [Parameter(Mandatory=$false)][ATPSDataMaskingEntity[]]$BackendResponseDataMaskingHeaderSettings,
        [Parameter(Mandatory=$false)][ATPSDataMaskingEntity[]]$BackendResponseDataMaskingQueryParamsSettings,
        [Parameter(Mandatory=$false)][String[]]$BackendResponseHttpHeadersToLog,
        [Parameter(Mandatory=$false)][Int32]$BackendResponseBodyBytes,
        [Parameter(Mandatory=$false)][ATPSDataMaskingEntity[]]$FrontendRequestDataMaskingHeaderSettings,
        [Parameter(Mandatory=$false)][ATPSDataMaskingEntity[]]$FrontendRequestDataMaskingQueryParamsSettings,
        [Parameter(Mandatory=$false)][String[]]$FrontendRequestHttpHeadersToLog,
        [Parameter(Mandatory=$false)][Int32]$FrontendRequestBodyBytes,
        [Parameter(Mandatory=$false)][ATPSDataMaskingEntity[]]$FrontendResponseDataMaskingHeaderSettings,
        [Parameter(Mandatory=$false)][ATPSDataMaskingEntity[]]$FrontendResponseDataMaskingQueryParamsSettings,
        [Parameter(Mandatory=$false)][String[]]$FrontendResponseHttpHeadersToLog,
        [Parameter(Mandatory=$false)][Int32]$FrontendResponseBodyBytes,
        [Parameter(Mandatory=$false)][ValidateSet("Legacy","None","W3C")][String]$HttpCorrelationProtocol,
        [Parameter(Mandatory=$false)][Bool]$LogClientIp,
        [Parameter(Mandatory=$false)][ValidateSet("Name","Url")][String]$OperationNameFormat,
        [Parameter(Mandatory=$false)][Double]$SamplingPercentage,
        [Parameter(Mandatory=$false)][ValidateSet("fixed")][String]$SamplingType,
        [Parameter(Mandatory=$false)][ValidateSet("error","information","verbose","debug")][String]$Verbosity,
        [Switch]$DoNotTrack
    )
    begin {

        function Send-TrackEvent (
            [Parameter(Mandatory=$true,HelpMessage="Specify the App Insights Instrumentation Key",Position=0)][ValidateScript({ $_ -ne [Guid]::Empty})][Guid] $iKey,
            [Parameter(Mandatory=$true,HelpMessage="Specify the Event to send to App Insights",Position=1)][String]$EventName,
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
                $body = (@{
                    name = "Microsoft.ApplicationInsights.$iKey.Event"
                    time = [DateTime]::UtcNow.ToString("o")
                    iKey = $piKey
                    tags = @{
                        "ai.device.id" = $env:COMPUTERNAME
                        "ai.device.locale" = $env:USERDOMAIN
                        "ai.user.id" = $env:USERNAME
                        "ai.user.authUserId" = "$($env:USERDOMAIN)\$($env:USERNAME)"
                        "ai.cloud.roleInstance" = $env:COMPUTERNAME
                    }
                    "data" = @{
                        baseType = "EventData"
                        baseData = @{
                            ver = "2"
                            name = $pEventName
                            properties = ($pCustomProperties | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
                        }
                    }
                }) | ConvertTo-Json -Depth 10 -Compress
    
                $temp = $ProgressPreference
                $ProgressPreference = "SilentlyContinue"
                Invoke-WebRequest -Method POST -Uri $appInsightsEndpoint -Headers @{"Content-Type"="application/x-json-stream"} -Body $body -TimeoutSec 3 | Out-Null
                $ProgressPreference = $temp
            }
    
            Start-Job -ScriptBlock $sendEvent -ArgumentList @($iKey, $EventName, $CustomProperties) | Out-Null
        }

        $correlationId = [Guid]::NewGuid().ToString()

        if(-not $DoNotTrack) {
            $iKey = (Invoke-RestMethod -UseBasicParsing -Uri https://raw.githubusercontent.com/milope/azuretools/master/api/appinsights/instrumentationKey).InstrumentationKey
            Send-TrackEvent -iKey $iKey -EventName "New-AzApiManagementDiagnosticEx" `
                -CustomProperties @{CorrelationId=$correlationId}
            $iKey = $null
        }

        $tempDPref = $DebugPreference

        if($PSBoundParameters["Debug"]) {
            $DebugPreference = "Continue"
        }
        Write-Debug ((Get-Date).ToString("T") + " - SetAzApiManagementDiagnosticEx start processing.")
        
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

        $subscriptionId = $context.Subscription.Id

        $httpMethod = "PUT"
        $uri = "$($context.Environment.ResourceManagerUrl)subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ApiManagement/service/$ServiceName"
        if(-not [String]::IsNullOrEmpty($ApiId)) {
            $uri += "/apis/$ApiId"
        }
        $uri += "/diagnostics/$($DiagnosticId)?api-version=2021-08-01"
        $bodyHash = @{properties=@{loggerId=$LoggerId}}

        if($PSBoundParameters.ContainsKey("AlwaysLog")) {
            $bodyHash["properties"]["alwaysLog"] = $AlwaysLog.ToString().ToLowerInvariant()
        }

        $addBackendRequestDataMaskingSettings = $PSBoundParameters.ContainsKey("BackendRequestDataMaskingHeaderSettings") `
            -or $PSBoundParameters.ContainsKey("BackendRequestDataMaskingQueryParamsSettings")

        $addBackendResponseDataMaskingSettings = $PSBoundParameters.ContainsKey("BackendResponseDataMaskingHeaderSettings") `
            -or $PSBoundParameters.ContainsKey("BackendResponseDataMaskingQueryParamsSettings")

        $addFrontendRequestDataMaskingSettings = $PSBoundParameters.ContainsKey("FrontendRequestDataMaskingHeaderSettings") `
            -or $PSBoundParameters.ContainsKey("FrontendRequestDataMaskingQueryParamsSettings")
    
        $addFrontendResponseDataMaskingSettings = $PSBoundParameters.ContainsKey("FrontendResponseDataMaskingHeaderSettings") `
            -or $PSBoundParameters.ContainsKey("FrontendResponseDataMaskingQueryParamsSettings")

        $addBackendRequestSettings = $PSBoundParameters.ContainsKey("BackendRequestHttpHeadersToLog") `
            -or $PSBoundParameters.ContainsKey("BackendRequestBodyBytes") -or $addBackendRequestDataMaskingSettings
            
        $addBackendResponseSettings = $PSBoundParameters.ContainsKey("BackendResponseHttpHeadersToLog") `
            -or $PSBoundParameters.ContainsKey("BackendResponseBodyBytes") -or $addBackendResponseDataMaskingSettings

        $addFrontendRequestSettings = $PSBoundParameters.ContainsKey("FrontendRequestHttpHeadersToLog") `
            -or $PSBoundParameters.ContainsKey("FrontendRequestBodyBytes") -or $addFrontendRequestDataMaskingSettings
                
        $addFrontendResponseSettings = $PSBoundParameters.ContainsKey("FrontendResponseHttpHeadersToLog") `
            -or $PSBoundParameters.ContainsKey("FrontendResponseBodyBytes") -or $addFrontendResponseDataMaskingSettings

        if($addBackendRequestSettings -or $addBackendResponseSettings) {
            $bodyHash["properties"]["backend"] = @{}
            if($addBackendRequestSettings) {
                $bodyHash["properties"]["backend"]["request"] = @{}
                if($PSBoundParameters.ContainsKey("BackendRequestBodyBytes")) {
                    $bodyHash["properties"]["backend"]["request"]["body"] = @{"bytes"=$BackendRequestBodyBytes}
                }
                if($PSBoundParameters.ContainsKey("BackendRequestHttpHeadersToLog")) {
                    $bodyHash["properties"]["backend"]["request"]["headers"] = $BackendRequestHttpHeadersToLog
                }
                if($addBackendRequestDataMaskingSettings) {
                    $bodyHash["properties"]["backend"]["request"]["dataMasking"] = @{}
                    if($PSBoundParameters.ContainsKey("BackendRequestDataMaskingHeaderSettings")) {
                        $bodyHash["properties"]["backend"]["request"]["dataMasking"]["headers"] = New-Object System.Collections.ArrayList
                        $BackendRequestDataMaskingHeaderSettings | ForEach-Object {
                            [Void]$bodyHash["properties"]["backend"]["request"]["dataMasking"]["headers"].Add(@{mode=$_.Mode.ToString();value=$_.Name})
                        }
                    }
                    if($PSBoundParameters.ContainsKey("BackendRequestDataMaskingQueryParamsSettings")) {
                        $bodyHash["properties"]["backend"]["request"]["dataMasking"]["queryParams"] = New-Object System.Collections.ArrayList
                        $BackendRequestDataMaskingQueryParamsSettings | ForEach-Object {
                            [Void]$bodyHash["properties"]["backend"]["request"]["dataMasking"]["queryParams"].Add(@{mode=$_.Mode.ToString();value=$_.Name})
                        }
                    }
                }
            }
            if($addBackendResponseSettings) {
                $bodyHash["properties"]["backend"]["response"] = @{}
                if($PSBoundParameters.ContainsKey("BackendResponseBodyBytes")) {
                    $bodyHash["properties"]["backend"]["response"]["body"] = @{"bytes"=$BackendResponseBodyBytes}
                }
                if($PSBoundParameters.ContainsKey("BackendResponseHttpHeadersToLog")) {
                    $bodyHash["properties"]["backend"]["response"]["headers"] = $BackendResponseHttpHeadersToLog
                }
                if($addBackendResponseDataMaskingSettings) {
                    $bodyHash["properties"]["backend"]["response"]["dataMasking"] = @{}
                    if($PSBoundParameters.ContainsKey("BackendResponseDataMaskingHeaderSettings")) {
                        $bodyHash["properties"]["backend"]["response"]["dataMasking"]["headers"] = New-Object System.Collections.ArrayList
                        $BackendResponseDataMaskingHeaderSettings | ForEach-Object {
                            [Void]$bodyHash["properties"]["backend"]["response"]["dataMasking"]["headers"].Add(@{mode=$_.Mode.ToString();value=$_.Name})
                        }
                    }
                    if($PSBoundParameters.ContainsKey("BackendResponseDataMaskingQueryParamsSettings")) {
                        $bodyHash["properties"]["backend"]["response"]["dataMasking"]["queryParams"] = New-Object System.Collections.ArrayList
                        $BackendResponseDataMaskingQueryParamsSettings | ForEach-Object {
                            [Void]$bodyHash["properties"]["backend"]["response"]["dataMasking"]["queryParams"].Add(@{mode=$_.Mode.ToString();value=$_.Name})
                        }
                    }
                }
            }
        }

        if($addFrontendRequestSettings -or $addFrontendResponseSettings) {
            $bodyHash["properties"]["frontend"] = @{}
            if($addFrontendRequestSettings) {
                $bodyHash["properties"]["frontend"]["request"] = @{}
                if($PSBoundParameters.ContainsKey("FrontendRequestBodyBytes")) {
                    $bodyHash["properties"]["frontend"]["request"]["body"] = @{"bytes"=$FrontendRequestBodyBytes}
                }
                if($PSBoundParameters.ContainsKey("FrontendRequestHttpHeadersToLog")) {
                    $bodyHash["properties"]["frontend"]["request"]["headers"] = $FrontendRequestHttpHeadersToLog
                }
                if($addFrontendRequestDataMaskingSettings) {
                    $bodyHash["properties"]["frontend"]["request"]["dataMasking"] = @{}
                    if($PSBoundParameters.ContainsKey("FrontendRequestDataMaskingHeaderSettings")) {
                        $bodyHash["properties"]["frontend"]["request"]["dataMasking"]["headers"] = New-Object System.Collections.ArrayList
                        $FrontendRequestDataMaskingHeaderSettings | ForEach-Object {
                            [Void]$bodyHash["properties"]["frontend"]["request"]["dataMasking"]["headers"].Add(@{mode=$_.Mode.ToString();value=$_.Name})
                        }
                    }
                    if($PSBoundParameters.ContainsKey("FrontendRequestDataMaskingQueryParamsSettings")) {
                        $bodyHash["properties"]["frontend"]["request"]["dataMasking"]["queryParams"] = New-Object System.Collections.ArrayList
                        $FrontendRequestDataMaskingQueryParamsSettings | ForEach-Object {
                            [Void]$bodyHash["properties"]["frontend"]["request"]["dataMasking"]["queryParams"].Add(@{mode=$_.Mode.ToString();value=$_.Name})
                        }
                    }
                }
            }
            if($addFrontendResponseSettings) {
                $bodyHash["properties"]["frontend"]["response"] = @{}
                if($PSBoundParameters.ContainsKey("FrontendResponseBodyBytes")) {
                    $bodyHash["properties"]["frontend"]["response"]["body"] = @{"bytes"=$FrontendResponseBodyBytes}
                }
                if($PSBoundParameters.ContainsKey("FrontendResponseHttpHeadersToLog")) {
                    $bodyHash["properties"]["frontend"]["response"]["headers"] = $FrontendResponseHttpHeadersToLog
                }
                if($addFrontendResponseDataMaskingSettings) {
                    $bodyHash["properties"]["frontend"]["response"]["dataMasking"] = @{}
                    if($PSBoundParameters.ContainsKey("FrontendResponseDataMaskingHeaderSettings")) {
                        $bodyHash["properties"]["frontend"]["response"]["dataMasking"]["headers"] = New-Object System.Collections.ArrayList
                        $FrontendResponseDataMaskingHeaderSettings | ForEach-Object {
                            [Void]$bodyHash["properties"]["frontend"]["response"]["dataMasking"]["headers"].Add(@{mode=$_.Mode.ToString();value=$_.Name})
                        }
                    }
                    if($PSBoundParameters.ContainsKey("FrontendResponseDataMaskingQueryParamsSettings")) {
                        $bodyHash["properties"]["frontend"]["response"]["dataMasking"]["queryParams"] = New-Object System.Collections.ArrayList
                        $FrontendResponseDataMaskingQueryParamsSettings | ForEach-Object {
                            [Void]$bodyHash["properties"]["frontend"]["response"]["dataMasking"]["queryParams"].Add(@{mode=$_.Mode.ToString();value=$_.Name})
                        }
                    }
                }
            }
        }

        if($PSBoundParameters.ContainsKey("HttpCorrelationProtocol")) {
            $bodyHash["properties"]["httpCorrelationProtocol"] = $HttpCorrelationProtocol
        }

        if($PSBoundParameters.ContainsKey("logClientIp")) {
            $bodyHash["properties"]["logClientIp"] = $LogClientIp.ToString().ToLowerInvariant()
        }

        if($PSBoundParameters.ContainsKey("OperationNameFormat")) {
            $bodyHash["properties"]["operationNameFormat"] = $OperationNameFormat
        }

        if($PSBoundParameters.ContainsKey("SamplingPercentage") -or $PSBoundParameters.ContainsKey("SamplingType")) {
            $bodyHash["properties"]["sampling"] = @{}

            if($PSBoundParameters.ContainsKey("SamplingPercentage")) {
                $bodyHash["properties"]["sampling"]["percentage"] = $SamplingPercentage
            }
            if($PSBoundParameters.ContainsKey("SamplingType")) {
                $bodyHash["properties"]["sampling"]["samplingType"] = $SamplingType
            }
        }

        if($PSBoundParameters.ContainsKey("Verbosity")) {
            $bodyHash["properties"]["verbosity"] = $Verbosity
        }

        $payload = ($bodyHash | ConvertTo-Json -Depth 100 -Compress)

        $aToken = Get-AzAccessToken -ResourceUrl $context.Environment.ResourceManagerUrl

        $token = ConvertTo-SecureString $aToken.Token -AsPlainText -Force

        if($PSBoundParameters["Debug"]) {
            $debugPayload = [Newtonsoft.Json.JsonConvert]::DeserializeObject($payload)
            $formatting = [Newtonsoft.Json.Formatting]::Indented

            Write-Debug "METHOD: $httpMethod"
            Write-Debug "URI: $uri"
            Write-Debug "Payload"
            Write-Debug ("================================================================================" `
                + [Environment]::NewLine + [Newtonsoft.Json.JsonConvert]::SerializeObject($debugPayload, $formatting))
            Write-Debug "================================================================================"
        }

        Invoke-RestMethod -Uri $uri -Method $httpMethod -Body $payload -Authentication $aToken.Type -Token $token `
            -Headers @{"x-ms-client-request-id"=$correlationId} `
            -UserAgent "Milope Azure Tools (PowerShell $($PSVersionTable.PSEdition)/$($PSVersionTable.PSVersion) $($PSVersionTable.OS))"
    }
    process {

    }
    end {
        $DebugPreference = $tempDPref
    }
}