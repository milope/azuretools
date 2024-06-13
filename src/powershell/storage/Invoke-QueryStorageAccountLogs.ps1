<#
.SYNOPSIS

Use this cmdlet for Storage Accounts that export their diagnostic logs to Azure Storage.

.DESCRIPTION

Use this cmdlet for Storage Accounts that export their diagnostic logs to Azure Storage.
This cmdlet will help query these logs.

.PARAMETER SubscriptionId

Pass the subscription ID.

.PARAMETER ResourceGroupName

Resource Group Name for the Storage Account

.PARAMETER StorageAccountName

The storage account name. NOTE: This is the storage account name with the diagnostic settings, not the destination storage account.

.PARAMETER StartTime

The Start Time

.PARAMETER EndTime

The end time

.INPUTS

This cmdlet does not accept pipeline input.

.OUTPUTS

Outputs the log contents.

.EXAMPLE

Import-QueryStorageAccount -ResourceGroupName "rg-name" -StorageAccountName "storageaccount" -StartTime "2024-06-13T00:00:00Z" -EndTime "2024-06-14T00:00:00Z"

#>
function Invoke-QueryStorageAccountLogs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][String]$SubscriptionId,
        [Parameter(Mandatory=$true)][String]$ResourceGroupName,
        [Parameter(Mandatory=$true)][String]$StorageAccountName,
        [Parameter(Mandatory=$true)][DateTime]$StartTime,
        [Parameter(Mandatory=$true)][DateTime]$EndTime
    )
    begin {
        $tempDebugPreference = $DebugPreference
        $isDebugging = $PSBoundParameters.Keys -contains "Debug"
        if($isDebugging) {
            $DebugPreference = "Continue"
        }

        function Write-LogDebug {
            [CmdletBinding()]
            param (
                [String[]]$Message
            )
            begin {

            }
            process {
                $Message | ForEach-Object {
                    Write-Debug "[$([DateTime]::UtcNow.ToString("o"))] $Message"
                }
            }
            end {

            }
        }

        
        $parameters = (Get-Command -Name ($PSCmdlet.MyInvocation.InvocationName)).Parameters
        $maxLength = 0
        $parameters.Keys | ForEach-Object { if($_.Length -gt $maxLength) { $maxLength = $_.Length} }

        if($isDebugging) {
            Write-LogDebug
            Write-LogDebug "+------------------------------------------------------------------------------+"
            Write-LogDebug "| Method: Invoke-QueryStorageAccountLogs                                       |"
            Write-LogDebug "+------------------------------------------------------------------------------+"
            Write-LogDebug "| Parameters:                                                                  |"
            Write-LogDebug "+------------------------------------------------------------------------------+"

            $parameters.Keys | ForEach-Object { 
                $parameterName = $_
                $parameterValue = $(
                    if($PSBoundParameters.Keys -contains $_) {
                        $var = (Get-Variable -Name $parameterName -ErrorAction SilentlyContinue)
                        if($var.Value -is [DateTime]) {
                            $var.Value.ToString("o")
                        }
                        else {
                            $var.Value
                        }
                    }
                    else {
                        "(Not Specified)"
                    }
                )

                $stringValue = "| $($parameterName.PadRight($maxLength)) : $parameterValue"
                if($stringValue.Length -gt 79) {
                    $stringValue = "$($stringValue.Substring(0, 74)) ... "
                }
                else {
                    $stringValue += [String]::Empty.PadRight(79 - $stringValue.Length)
                }
                $stringValue += "|"

                Write-LogDebug $stringValue
            }

            Write-LogDebug "+------------------------------------------------------------------------------+"
            Write-LogDebug
        }

        if($PSBoundParameters.Keys -contains "SubscriptionId") {
            [Void](Select-AzSubscription -Subscription $SubscriptionId)
        }
        
        $storageAccount = (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue)
        if($null -eq $storageAccount) {
            Write-Error "Storage Account '$StorageAccountName' in resource group '$ResourceGroupName' was not found."
            return
        }

        if($isDebugging) {
            Write-LogDebug
            Write-LogDebug "Found Storage Account with Resource Id '$($storageAccount.Id)'"
        }
    }
    process {
        if($null -eq $storageAccount) { return }
        $resourceId = $storageAccount.Id
        $storageSubscriptionId = (Get-AzResource -ResourceId $resourceId).SubscriptionId

        $diagnosticSettings = $(
            @("blob", "table", "queue", "file") | ForEach-Object {
                $service = $_

                Get-AzDiagnosticSetting -ResourceId "$resourceId/$($_)Services/default" `
                    | Where-Object { $null -ne $_.StorageAccountId -and $_.StorageAccountId.Trim().Length -gt 0} `
                    | Select-Object -Property StorageAccountId,@{label="StorageAccount";expression={(Get-AzResource -ResourceId $_.StorageAccountId -ErrorAction SilentlyContinue)}} `
                    | Where-Object { $null -ne $storageAccount} `
                    | Select-Object -First 1 -Property `
                        @{label="SubscriptionId";expression={$_.Storageaccount.SubscriptionId}}, `
                        @{label="StorageAccountName";expression={$_.Storageaccount.Name}}, `
                        @{label="ResourceGroupName";expression={$_.Storageaccount.ResourceGroupName}}, `
                        @{label="Service";expression={$service}} `
                    | Select-Object -Property SubscriptionId, StorageAccountName, ResourceGroupName, Service, `
                        @{label="BlobPathPrefix";expression={
                            "resourceId=/subscriptions/" + $storageSubscriptionId + "/resourceGroups/" + $storageAccount.ResourceGroupName + `
                            "/providers/Microsoft.Storage/storageAccounts/" + $storageAccount.StorageAccountName + "/" + $_.Service + "Services/default"
                        }}
            }
        )

        if($null -eq $diagnosticSettings -or $diagnosticSettings.Count -eq 0) {
            Write-Error "No diagnostic settings were found pointing to a Storage Account for the Storage Account '$StorageAccountName'. Nothing to query."
            return
        }

        if($isDebugging) {
            Write-LogDebug
            $diagnosticSettings | ForEach-Object {
                Write-LogDebug ( `
                    "Found diagnostic setting pointing to a Storage Account name '$($_.StorageAccountName)' in Subscription ID '$($_.SubscriptionId)'" + `
                    ", Resource Group '$($_.ResourceGroupName)', for the $($_.Service) service."
                )
            }
        }

        $blobPathPrefixes = @()
        $containerNames = @("insights-logs-storageread","insights-logs-storagewrite","insights-logs-storagedelete")
        $utcStartTime = $startTime.ToUniversalTime()
        $utcEndTime = $endTime.ToUniversalTime()
        $currentTime = [DateTime]::new($utcStartTime.Year, $utcStartTime.Month, $utcStartTime.Day, $utcStartTime.Hour, 0, 0, 0)
        while($currentTime -lt $utcEndTime) {
            $blobPathPrefixes += $currentTime.ToString("/\y=yyyy/\m=MM/\d=dd/\h=HH/\m=00/P\T1\H.j\son")
            $currentTime = $currentTime.AddHours(1)
        }

        $diagnosticSettings | ForEach-Object {
            $diagStorageAccount = Get-AzStorageAccount -ResourceGroupName $_.ResourceGroupName -Name $_.StorageAccountName -ErrorAction SilentlyContinue
            if($null -eq $diagStorageAccount) { continue }
            $diagSettingBlobPathPrefix = $_.BlobPathPrefix
            $diagStorageContext = New-AzStorageContext -StorageAccountName $_.StorageAccountName -UseConnectedAccount
            $containerNames | ForEach-Object {
                $containerName = $_
                $container = Get-AzStorageContainer -Context $diagStorageContext -Name $containerName -ErrorAction SilentlyContinue
                if($null -eq $container) { continue }
                $blobPathPrefixes | ForEach-Object {

                    $blobPath = $diagSettingBlobPathPrefix + $_
                    $blob = (Get-AzStorageBlob -Context $diagStorageContext -Container $containerName -Blob $blobPath -ErrorAction SilentlyContinue)

                    if($null -ne $blob) {
                        Write-LogDebug "Retrieving contents for the blob '$blobPath'."

                        $tempPath = (Join-Path $env:TEMP "PT1H.json")
                        $tempProgressPreference = $ProgressPreference
                        $ProgressPreference = "SilentlyContinue"
                        try {
                            [Void]($blob | Get-AzStorageBlobContent -Destination $tempPath -Force)
                            (Get-Content $tempPath).Split([Environment]::NewLine) | ForEach-Object {
                                ConvertFrom-Json $_
                            } | Where-Object { $utcStartTime -le $_.time -and $_.time -le $utcEndTime}
                            Remove-Item $tempPath -Force
                        }
                        finally {
                            $ProgressPreference = $tempProgressPreference
                        }
                    }
                }
            }
        }
    }
    end {
        $DebugPreference = $tempDebugPreference
    }
}