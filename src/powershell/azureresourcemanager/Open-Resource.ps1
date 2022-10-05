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

param (
    [String][Parameter(Mandatory=$true)]$ResourceId
)
begin {

    #TODO: Add Validation
    #TODO: Support Subscription api-version
    #TODO: Support non-happy paths 

    $namespaceName = $null
    $resourceType = $null

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
        $outFile = Join-Path -Path $env:TEMP -ChildPath (([DateTime]::UtcNow).ToFileTimeUtc().ToString() + ".json")
        $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 100 | Out-File $outFile
        Start-Process -FilePath $outFile
        Start-Sleep -Seconds 2
        Remove-Item $outFile -Force
    }
}