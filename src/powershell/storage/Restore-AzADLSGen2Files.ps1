<#
Copyright © 2023 Michael Lopez

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

Use to undelete all ADLS Gen-2 paths that have been soft-deleted.

.DESCRIPTION

Use to undelete all ADLS Gen-2 paths that have been soft-deleted.

.PARAMETER SubscriptionId

Specify a subscription ID for the affected Storage Account.
The current Azure PowerShell context subscription is used if
unspecified.

.PARAMETER ResourceGroupName

Specify the Resource Group name for the affected Storage Account.

.PARAMETER StorageAccountName

Specify the affected Storage Account (must have ADLS Gen 2 enabled).

.PARAMETER Path

Specify the paths to restore. NOTE: The first segment must include
the impacted filesystem as such:

/filesystem1/directoryA/

.PARAMETER WhatIf

Specify this flag if intended to just list the impacted items.

.INPUTS

The paths can be specified as a pipeline input.

.OUTPUTS

The output will a AzureDataLakeGen2Item object enumeration, based on
recovered items

.EXAMPLE

Get-FolderSizes

.EXAMPLE

Get-FolderSizes -Path C:\

.EXAMPLE

Restore-AzADLSGen2Files -ResourceGroupName resourceGroup `
    -StorageAccountName account -Path filesystem1/directory1

.EXAMPLE

Restore-AzADLSGen2Files -SubscriptionId xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx `
    -ResourceGroupName resourceGroup `
    -StorageAccountName account -Path filesystem1/directory1

.EXAMPLE

@("filesystem1/directory1", "filesystem1/directory2") | `
    Restore-AzADLSGen2Files -ResourceGroupName resourceGroup `
    -StorageAccountName account

.EXAMPLE

Restore-AzADLSGen2Files -ResourceGroupName resourceGroup `
    -StorageAccountName account -Path filesystem1/directory1 -WhatIf

#>

function Restore-AzADLSGen2Files {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][String]$SubscriptionId,
        [Parameter(Mandatory=$true)][String]$ResourceGroupName,
        [Parameter(Mandatory=$true)][String]$StorageAccountName,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)][String[]]$Path,
        [Switch]$WhatIf
    )
    begin {

        $tempDebugPreference = $DebugPreference
        if($PSBoundParameters.ContainsKey("Debug")) {
            $DebugPreference = "Continue"
        }

        function Write-ErrorRecord {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$false)][System.Type]$Type = [System.Management.Automation.PSInvalidOperationException],
                [Parameter(Mandatory=$false)][System.Management.Automation.ErrorCategory]$Category = ([System.Management.Automation.ErrorCategory]::InvalidOperation),
                [Parameter(Mandatory=$true)][String]$Message,
                [Switch]$StopScript
            )
            begin {
                $errorRecord = ([System.Management.Automation.ErrorRecord]::new(
                    (New-Object -Type $Type.FullName -ArgumentList $Message),
                    [String]::Empty,
                    $Category,
                    $null
                ))
                if($StopScript) {
                    Write-ErrorRecord $errorRecord -ErrorAction Stop 
                }
                else {
                    Write-ErrorRecord $errorRecord
                }
            }

            process {

            }
            end {

            }
        }

        Write-Debug "Getting Azure PowerShell Context."
        $azContext = Get-AzContext
        if($null -eq $azContext -and $null -eq $azContext.Account) {
            Write-Debug "Az Context was not found, will try to login to Azure PowerShell."
            Connect-AzAccount -ErrorAction SilentlyContinue
        }

        if($null -eq $azContext -and $null -eq $azContext.Account) {
            Write-Debug "Could not get an Azure PowerShell Context"
            Write-ErrorRecord -Message "Unable to get an Az Context with an account." -StopScript
        }

        if($null -ne $SubscriptionId -and $SubscriptionId.Trim().Length -gt 0) {
            Select-AzSubscription -Subscription $SubscriptionId
        }

        $storageAccount = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        if($null -eq $storageAccount) {
            Write-ErrorRecord -Message "Unable to get an Az Context with an account." -StopScript
        }

        if(-not $storageAccount.EnableHierarchicalNamespace) {
            Write-ErrorRecord -Message "The storage account '$StorageAccountName' is not an ADLS Gen 2-enabled Azure Storage Account." -StopScript
        }
    }
    process {
        $Path | ForEach-Object {

            $thisPath = $_

            Write-Debug "Working on path '$thisPath'."
            if($thisPath.StartsWith("/")) {
                $thisPath = $thisPath.Substring(1)
            }

            $uri = [System.Uri]::new("$($storageAccount.primaryEndpoints.Dfs)$($Path)")
            if($uri.Segments.Length -eq 1) {
                Write-Warning "Skipping '$thisPath' as it doesn't have a filesystem in the path."
            }
            $fileSystem = $(if($uri.Segments[1].EndsWith("/")) { $uri.Segments[1].Substring(0, $uri.Segments[1].Length - 1) } else { $uri.Segments[1] })
            $filePath = $null

            $getParameters = @{
                Context = $storageAccount.Context
                FileSystem = $fileSystem
            }

            if($uri.Segments.Length -gt 2) {
                $filePath = (@(2 .. ($uri.Segments.Length - 1)) | ForEach-Object { $uri.Segments[$_] }) -join [String]::Empty
                if($filePath.EndsWith("/")) {
                    $filePath = $filePath.Substring(0, $filePath.Length - 1)
                }
                $getParameters = @{
                    Context = $storageAccount.Context
                    FileSystem = $fileSystem
                    Path = $filePath
                }
            }

            if($WhatIf) {
                Get-AzDataLakeGen2DeletedItem @getParameters
            }
            else {
                Get-AzDataLakeGen2DeletedItem @getParameters | Restore-AzDataLakeGen2DeletedItem
            }
        }
    }
    end {
        $DebugPreference = $tempDebugPreference
    }
}