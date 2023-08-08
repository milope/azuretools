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

Computes the string to sign for an Azure Storage request.

.DESCRIPTION

Given the parameters, this cmdlet will compute (best-effort) the string to
sign string for Azure Storage requests. This can then be used as the
string-to-sign parameter when computing the SharedKey authorization header.

.PARAMETER Method

Specify the GET, HEAD, PUT, PATCH or DELETE methods.


.PARAMETER Uri

Specify the URI and Query String that will be used for Azure Storage. 

.PARAMETER Headers

Specify the headers that will be sent in the Azure Storage request.

NOTE: If the Content-Length is specified in the Headers, it will override the
Content-Length automatically computed from the Body parameter.

.PARAMETER Body

When applicable, specify the body for the Azure Storage request.

NOTE: Specifying a Body will automatically compute the string-to-sign based on
the length of the body. As both Invoke-WebRequest doesn't require to specify
the Content-Length as the Headers, the string-to-sign behaves the same way.

.PARAMETER StorageAccountName

When using a custom domainf or the URL, if a Storage Account cannot be derived
by resolving the DNS, use this parameter to specify which Storage Account
we are computing the string-to-sign for. This parameter overrides any Storage
Account derived as well.

.PARAMETER Raw

Displays the result in raw form. The carriage returns will not be displayed as
'\n'. Rather, they will be kept as true carriage returns.

.INPUTS

This cmdlet does not recieve inputs.

.OUTPUTS

If Raw is specified returns the string-to-sign as is (doesn't replace carriage
returns with '\n'). Otherwise, returns the string to sign in a printable mode.
#>
function Get-AzureStorageStringToSign {
    [CmdletBinding()]
    param (
        [String][Parameter(Mandatory=$true)][ValidateSet("GET","HEAD","PUT","DELETE","PATCH")]$Method,
        [String][Parameter(Mandatory=$true)]$Uri,
        [Hashtable][Parameter(Mandatory=$false)]$Headers,
        [String][Parameter(Mandatory=$false)]$Body,
        [String][Parameter(Mandatory=$false)]$StorageAccountName,
        [Switch]$Raw
    )
    begin {
        function Get-HeaderValue {
            [CmdletBinding()]
            param (
                [HashTable][Parameter(Mandatory=$false, Position=0)]$Headers,
                [String][Parameter(Mandatory=$true, Position=1)]$Name
            )
            process {
                if($null -eq $Headers -or $null -eq $Headers.Keys -or $Headers.Keys.Count -eq 0 -or -not $Headers.ContainsKey($Name)) {
                    [String]::Empty
                    return
                }

                $Headers[$Name]
            }
        }

        function Get-StorageAccountName {
            [CmdletBinding()]
            param (
                [String][Parameter(Mandatory=$true)]$Uri,
                [String][Parameter(Mandatory=$false)]$StorageAccountName
            )
            process {
                if($PSBoundParameters.ContainsKey("StorageAccountName") -and -not [String]::IsNullOrEmpty($StorageAccountName)) {
                    $StorageAccountName
                    return
                }

                $pUri = [Uri]::new($Uri, [System.UriKind]::Absolute)
                $dnsSafeHost = $pUri.DnsSafeHost
                if($dnsSafeHost -like "*.core.windows.net") {
                    $dnsSafeHost.Split(".") | Select-Object -First 1
                    return
                }

                $dnsSafeHost = Resolve-DnsName -Name dnsSafeHost `
                    | Where-Object { $_.QueryType -eq "CNAME" -and $_.NameHost-like "*core.windows.net" } `
                    | Select-Object -First 1 -Property NameHost `
                    | ForEach-Object { $_.NameHost }
                if(-not [String]::IsNullOrEmpty($dnsSafeHost.Trim())) {
                    $dnsSafeHost.Split(".") | Select-Object -First 1
                    return
                }

                
                if($null -eq $context -or $null -eq $context.Subscription) {
                    $errorRecord = New-Object System.Management.Automation.ErrorRecord `
                        (New-Object System.Management.Automation.PSInvalidOperationException "Could not derive storage account name from either Uri '$($Uri)' nor Storage Account Name $($StorageAccountName)"), `
                        "", `
                        ([System.Management.Automation.ErrorCategory]::InvalidArgument), `
                        $null
                    Write-Error $errorRecord
                }
            }
        }

        function Remove-LinearWhitespaces {
            [CmdletBinding()]
            param (
                [String][Parameter(Mandatory=$true)]$Value
            )
            process {
                $inSingleQuote = $false
                $inDoubleQuote = $false
                $sb = New-Object System.Text.StringBuilder
                for($i = 0; $i -lt $Value.Length; $i++) {
                    $char = $Value[$i]

                    if($char -eq "`"" -and $inDoubleQuote) {
                        $inDoubleQuote = $false
                        $sb.Append("`"") | Out-Null
                    }
                    elseif($char -eq "'" -and $inSingleQuote) {
                        $inSingleQuote = $false
                        $sb.Append("'") | Out-Null
                    }
                    elseif($inSingleQuote -or $inDoubleQuote) {
                        $sb.Append($char) | Out-Null
                    }
                    elseif($char -eq "`"" -and -not $inDoubleQuote -and -not $inSingleQuote) {
                        $inDoubleQuote = $true
                        $sb.Append("`"") | Out-Null
                    }
                    elseif($char -eq "'" -and -not $inSingleQuote -and -not $inDoubleQuote) {
                        $inSingleQuote = $true
                        $sb.Append("'") | Out-Null
                    }
                    elseif(($char -eq " " -or $char -eq "`t" -or $char -eq "`r" -or $char -eq "`n") -and -not $inSingleQuote ` -and -not $inDoubleQuote) {
                        $sb.Append(" ") | Out-Null
                        while($i -lt $Value.Length -1) {
                            $nextChar = $Value[$i + 1]
                            if($nextChar -eq " " -or $nextChar -eq "`t" -or $nextChar -eq "`r" -or $nextChar -eq "`n") {
                                $i++
                                continue
                            }
                            break
                        }
                    }
                    else {
                        $sb.Append($char) | Out-Null
                    }
                }
                $sb.ToString()
            }
        }

        function Get-CanonicalizedHeaders {
            [CmdletBinding()]
            param (
                [Hashtable][Parameter(Mandatory=$false)]$headers
            )
            process {
                $cHeaders = $headers.Keys `
                    | Where-Object { $_ -like "x-ms-*" } `
                    | ForEach-Object { 
                        [PSCustomObject]@{
                            Header=$_.ToLowerInvariant();
                            Value=(Remove-LinearWhitespaces $Headers[$_].Trim())
                        }
                    } `
                    | Sort-Object -Property Header `
                    | ForEach-Object {
                        [string]::Concat($_.Header, ":", $_.Value)
                    }
                $cHeaders -join "`n"
            }
        }

        function Get-CanonicalizedResource {
            [CmdletBinding()]
            param (
                [String][Parameter(Mandatory=$true)]$Uri,
                [String][Parameter(Mandatory=$false)]$StorageAccountName
            )
            process {
                $stAcctName = Get-StorageAccountName $Uri $StorageAccountName -ErrorAction Stop
                $pUri = [Uri]::new($Uri, [System.UriKind]::Absolute)
                if($null -eq $pUri.Query -or $pUri.Query.Length -eq 0 -or $pUri.Query -eq "?") {
                    [String]::Concat("/", $stAcctName, $pUri.AbsolutePath)
                    return
                }
                $queryParsed = ($pUri.Query.Substring(1).Split("&") `
                    | ForEach-Object {
                        $split = $_.Split("=")
                        [PSCustomObject]@{Key=$split[0].ToLowerInvariant();Value=$split[1].Trim()}
                    } `
                    | Sort-Object -Property Key, Value `
                    | Group-Object -Property Key `
                    | ForEach-Object {
                        [String]::Concat($_.Name, ":", ($_.Group.Value -join ","))
                    })
                [String]::Concat("/", $stAcctName, $pUri.AbsolutePath, "`n", $queryParsed -join "`n")
            }
        }
    }
    process {

        $verb = $Method
        $contentEncoding = Get-HeaderValue $Headers "Content-Encoding"
        $contentLanguage = Get-HeaderValue $Headers "Content-Language"
        $contentLength = [String]::Empty
        # Special case for Content-Length, if specified as a header, it will be used,
        # Otherwise, measure the body and use that as a the value
        if($Method -eq "POST" -or $Method -eq "PUT") {
            $contentLength = Get-HeaderValue $Headers "Content-Length"
            if($null -eq $contentLength -or [String]::IsNullOrEmpty($contentLength.Trim())) {
                if($null -ne $Body -and $Body.Length -gt 0) {
                    $contentLength = $Body.Length.ToString()
                }
            }
        }

        $contentMD5 = Get-HeaderValue $Headers "Content-MD5"
        $contentType = Get-HeaderValue $Headers "Content-Type"
        $date = Get-HeaderValue $Headers "Date"
        $ifModifiedSince = Get-HeaderValue $Headers "If-Modified-Since"
        $ifMatch = Get-HeaderValue $Headers "If-Match"
        $ifNonMatch = Get-HeaderValue $Headers "If-Non-Match"
        $ifUnmodifiedMatch = Get-HeaderValue $Headers "If-Unmodified-Match"
        $range = Get-HeaderValue $Headers "Range"
        $canonicalizedHeaders = Get-CanonicalizedHeaders $Headers
        $canonicalizedResource = Get-CanonicalizedResource $Uri $StorageAccountName

        $stringToSign = [String]::Concat(
            $verb, "`n",
            $contentEncoding, "`n",
            $contentLanguage, "`n",
            $contentLength, "`n",
            $contentMD5, "`n",
            $contentType, "`n",
            $date, "`n",
            $ifModifiedSince, "`n",
            $ifMatch, "`n",
            $ifNonMatch, "`n",
            $ifUnmodifiedMatch, "`n",
            $range, "`n",
            $canonicalizedHeaders, "`n",
            $canonicalizedResource
        )

        if($Raw) {
            $stringToSign
            return
        }

        $stringToSign -replace "`n", "\n"
    }
}