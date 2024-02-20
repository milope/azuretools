<#
Copyright © 2024 Michael Lopez

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

List blobs in a container with the purpose of executing an action for each blob.

.DESCRIPTION

The whole purpose of this command is to handle the do/while loop usually
recommended by Microsoft when iterating blobs. It also takes into account
increasing minimum thread pool sizes and clearing the trace listener
setup by Azure PowerShell cmdlets for Storage that tend to require
a lot of memory to work.

.PARAMETER Container

Specifies the name of the container.

.PARAMETER ClientTimeoutPerRequest

Specifies the client-side time-out interval, in seconds, for one service
request. If the previous call fails in the specified interval, this cmdlet
retries the request. If this cmdlet does not receive a successful response
before the interval elapses, this cmdlet returns an error.

.PARAMETER ConcurrentTaskCount

Specifies the maximum concurrent network calls. You can use this parameter to
limit the concurrency to throttle local CPU and bandwidth usage by specifying
the maximum number of concurrent network calls. The specified value is an
absolute count and is not multiplied by the core count. This parameter can help
reduce network connection problems in low bandwidth environments, such as 100
kilobits per second. The default value is 10.

.PARAMETER Context

Specifies the Azure storage account from which you want to get a list of blobs.
You can use the New-AzStorageContext cmdlet to create a storage context.

.PARAMETER DefaultProfile

The credentials, account, tenant, and subscription used for communication with
Azure.

.PARAMETER IncludeDeleted

Include Deleted Blob, by default get blob won't include deleted blob.

.PARAMETER IncludeTag

Include blob tags, by default get blob won't include blob tags.

.PARAMETER IncludeVersion

Blob versions will be listed only if this parameter is present, by default get
blob won't include blob versions.

.PARAMETER MaxCount

The MaxCount determines how many max blobs per iteration this cmdlet will use.
Lower the number to preserve memory but make more calls to Azure Storage.

.PARAMETER Prefix

Specifies a prefix for the blob names that you want to get. This parameter does
not support using regular expressions or wildcard characters to search. This
means that if the container has only blobs named "My", "MyBlob1", and "MyBlob2"
and you specify "-Prefix My*", the cmdlet returns no blobs. However, if you
specify "-Prefix My", the cmdlet returns "My", "MyBlob1", and "MyBlob2".

.PARAMETER ServerTimeoutPerRequest

Specifies the service side time-out interval, in seconds, for a request. If the
specified interval elapses before the service processes the request, the
storage service returns an error.

.PARAMETER FilterScript

Specify a filter script block before applying the Process script block. For
example, if we need to work with all blobs that have abc in their name, we can
specity -FilterScript { $_.Name -like "*abc*" }

.PARAMETER Process

This script block represents the action to take for each blob. For example, to
undelete a blob we can use -Process { $_.BlobClient.Undelete() }

.EXAMPLE

To undelete all blobs, we can perform the following:

ForEach-AzStorageBlob -Container "ContainerName" -IncludeDeleted -Process { $_.BlobClient.Undelete() }

.EXAMPLE

To undelete all blobs that start with prefix a that have 999 in the name:

ForEach-AzStorageBlob -Container "ContainerName" -Prefix "a" -FilterScript { $_.Name -like "*999*" } -IncludeDeleted -Process { $_.BlobClient.Undelete() }

#>
function ForEach-AzStorageBlob {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][String]$Container,
        [Parameter(Mandatory=$false)][Nullable[Int32]]$ClientTimeoutPerRequest,
        [Parameter(Mandatory=$false)][Nullable[Int32]]$ConcurrentTaskCount,
        [Parameter(Mandatory=$false)][Microsoft.Azure.Commands.Common.Authentication.Abstractions.IStorageContext]$Context,
        [Parameter(Mandatory=$false)][Microsoft.Azure.Commands.Common.Authentication.Abstractions.Core.IAzureContextContainer]$DefaultProfile,
        [Switch]$IncludeDeleted,
        [Switch]$IncludeTag,
        [Switch]$IncludeVersion,
        [Parameter(Mandatory=$true)][Int32]$MaxCount,
        [Parameter(Mandatory=$false)][String]$Prefix,
        [Parameter(Mandatory=$false)][Nullable[Int32]]$ServerTimeoutPerRequest,
        [Parameter(Mandatory=$false)][ScriptBlock]$FilterScript,
        [Parameter(Mandatory=$true)][ScriptBlock]$Process
    )
    begin {
        
        [Microsoft.Azure.Storage.Blob.BlobContinuationToken]$ContinuationToken = $null
        $tempProgressPreference = $ProgressPreference
        [Int32]$maxWorkerThreads = 0
        [Int32]$maxCompletionPorts = 0
        [Threading.ThreadPool]::GetMinThreads([ref]$maxWorkerThreads,[ref]$maxCompletionPorts)
        [Threading.ThreadPool]::SetMinThreads(300, 300) | Out-Null

        [Hashtable]$GetAzStorageBlobParameters = @{
            Container = $Container
            MaxCount = $MaxCount
        }

        if($PSBoundParameters.ContainsKey("ClientTimeoutPerRequest") -and $ClientTimeoutPerRequest.HasValue) {
            $GetAzStorageBlobParameters.Add("ClientTimeoutPerRequest", $ClientTimeoutPerRequest)
        }

        if($PSBoundParameters.ContainsKey("ConcurrentTaskCount") -and $ConcurrentTaskCount.HasValue) {
            $GetAzStorageBlobParameters.Add("ConcurrentTaskCount", $ConcurrentTaskCount)
        }

        if($PSBoundParameters.ContainsKey("Context") -and $null -ne $Context) {
            $GetAzStorageBlobParameters.Add("Context", $Context)
        }

        if($PSBoundParameters.ContainsKey("DefaultProfile") -and $null -ne $DefaultProfile) {
            $GetAzStorageBlobParameters.Add("DefaultProfile", $DefaultProfile)
        }

        if($PSBoundParameters.ContainsKey("IncludeDeleted") -and $IncludeDeleted) {
            $GetAzStorageBlobParameters.Add("IncludeDeleted", $IncludeDeleted)
        }

        if($PSBoundParameters.ContainsKey("IncludeTag") -and $IncludeTag) {
            $GetAzStorageBlobParameters.Add("IncludeTag", $IncludeTag)
        }

        if($PSBoundParameters.ContainsKey("IncludeVersion") -and $IncludeVersion) {
            $GetAzStorageBlobParameters.Add("IncludeVersion", $IncludeVersion)
        }

        if($PSBoundParameters.ContainsKey("Prefix") -and $null -ne $Prefix) {
            $GetAzStorageBlobParameters.Add("Prefix", $Prefix)
        }

        if($PSBoundParameters.ContainsKey("ServerTimeoutPerRequest") -and $ServerTimeoutPerRequest.HasValue) {
            $GetAzStorageBlobParameters.Add("ServerTimeoutPerRequest", $ServerTimeoutPerRequest)
        }

        $BlobCount = 0
        $GCTracker = 0
        $stopWatch = [Diagnostics.Stopwatch]::new()
        $stopWatch.Start()
    }
    process {
        do {
            # The reason this is being cleared is because of the large amount of 
            # memory Get-AzStorageBlob tends to consume due to event listeners
            [Diagnostics.Trace]::Listeners.Clear()
            $ProgressPreference = "SilentlyContinue"
            $Blobs = Get-AzStorageBlob @GetAzStorageBlobParameters -ContinuationToken $ContinuationToken
            $ProgressPreference = $tempProgressPreference
            if($null -eq $Blobs) { break }
            $isSingle = $Blobs.GetType().Name -eq "AzureStorageBlob"

            #Set-StrictMode will cause Get-AzureStorageBlob returns result in different data types when there is only one blob
            $ContinuationToken = $(if($isSingle) { $null } else { $Blobs[-1].ContinuationToken } )

            if($null -ne $FilterScript) {
                $Blobs | Where-Object -FilterScript $FilterScript | ForEach-Object -Process $Process
            }
            else {
                $Blobs | ForEach-Object -Process $Process
            }
            $increment = $(if($isSingle) { 1 } else { $Blobs.Count })
            $BlobCount += $increment
            $GCTracker += $increment

            $ProgressParameters = @{
                Activity = "ForEach-AzStorageBlob -"
                Status = "Number of blobs iterated: $BlobCount. Elapsed time: $($stopWatch.Elapsed.ToString())."
                CurrentOperation = "Processing Blobs"
            }
            Write-Progress @ProgressParameters

            $Blobs = $null
            
            
            if($GCTracker -ge 25000) {
                # The reason this is being induced is because of the large amount of 
                # memory Get-AzStorageBlob tends to consume due to event listeners
                [GC]::Collect()
                $GCTracker = 0
            }

        } while($null -ne $ContinuationToken)
    }
    end {

        $ProgressParameters = @{
            Activity = "ForEach-AzStorageBlob -"
            Status = "Number of blobs iterated: $BlobCount. Elapsed time: $($stopWatch.Elapsed.ToString())."
            CurrentOperation = "Processing Blobs"
        }
        Write-Progress @ProgressParameters -Completed

        $stopWatch.Stop()

        [Threading.ThreadPool]::SetMinThreads($maxWorkerThreads,$maxCompletionPorts) | Out-Null
        $ProgressPreference = $tempProgressPreference
        $ContinuationToken = $null
    }
}