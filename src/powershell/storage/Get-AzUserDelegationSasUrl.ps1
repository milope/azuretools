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

This cmdlet can be used to generate a user delegation SAS.

.DESCRIPTION

This cmdlet can be used to generate a user delegation SAS. Please note, it has
a dependency on the latest Az module at the time of writing (Az 7.0.0).

.PARAMETER ResourceUri

This represents the Resource Uri for which we are requesting the user
delegation SAS.

.PARAMETER ResponseHeaderCacheControl

This corresponds to the rscc parameter.

.PARAMETER ResponseHeaderContentDisposition

This corresponds to the rscd parameter.

.PARAMETER ResponseHeaderContentEncoding

This corresponds to the rsce parameter.

.PARAMETER ResponseHeaderContentLanguage

This corresponds to the rscl parameter.

.PARAMETER ResponseHeaderContentType

This corresponds to the rsct parameter.

.PARAMETER SignedAuthorizedObjectId

This corresponds to the suoid parameter.

.PARAMETER SignedCorrelationId

This corresponds to the scid parameter.

.PARAMETER SignedEncryptionScope

This corresponds to the ses parameter.

.PARAMETER SignedExpiry

This corresponds to the ske parameter.

.PARAMETER SignedIp

This corresponds to the sip parameter.

.PARAMETER SignedPermissions

This corresponds to the sp parameter.

.PARAMETER SignedProtocol

This corresponds to the spr parameter.

.PARAMETER SignedResource

This corresponds to the sr parameter.

.PARAMETER SignedStart

This corresponds to the st parameter.

.PARAMETER SignedUnauthorizedObjectId

This corresponds to the suoid parameter.

.INPUTS

None. This cmdlet does not support inputs at this time.

.OUTPUTS

This cmdlet will output an object with two properties:

SasToken: Represents the SAS token.
SasUrl: Represents a full SAS URL, based on the provided resource URI.

.EXAMPLE

PS> Get-AzUserDelegationSasUrl `
    -ResourceUri "https://mystgacct.blob.core.windows.net/art/music.mp3" `
    -SignedExpiry ([DateTime]::Now).AddDays(3) -SignedPermissions Read, List `
    -SignedResource Container


SasToken : ?sv=2020-12-06&sr=c&se=2022-01-05T00:08:50Z&sp=rl&skoid=xxxxxxxx-xxx
           x-xxxx-xxxx-xxxxxxxxxxxx&sktid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx&
           skt=2022-01-01T23:53:51Z&ske=2022-01-05T00:08:50Z&sks=b&skv=2020-12-
           06&sig=Kz1****************************************%3D
SasUrl   : https://mystgacct.blob.core.windows.net/art/music.mp3?sv=2020-12-06&
           sr=c&se=2022-01-05T00:08:50Z&sp=rl&skoid=xxxxxxxx-xxxx-xxxx-xxxx-xxx
           xxxxxxxxx&sktid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx&skt=2022-01-01T
           23:53:51Z&ske=2022-01-05T00:08:50Z&sks=b&skv=2020-12-06&sig=Kz1*****
           ***********************************%3D

.NOTES

This script has not gone through thorough testing to ensure all use-cases work.
Please do not hesitate to file an issue if you use this script as an example.

IP and range regex validation based on http://www.ipregex.com/.

.LINK

http://www.ipregex.com/

#>
function Get-AzUserDelegationSasUrl {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][Uri]$ResourceUri,

        # BEGIN: Response Headers
        [Parameter()][String]$ResponseHeaderCacheControl,
        [Parameter()][String]$ResponseHeaderContentDisposition,
        [Parameter()][String]$ResponseHeaderContentEncoding,
        [Parameter()][String]$ResponseHeaderContentLanguage,
        [Parameter()][String]$ResponseHeaderContentType,
        # END: Response Headers

        [Parameter()][Guid]$SignedAuthorizedObjectId,
        [Parameter()][Guid]$SignedCorrelationId,
        [Parameter()][String]$SignedEncryptionScope,
        [Parameter(Mandatory)][DateTime]$SignedExpiry,

        # Credits to: http://www.ipregex.com/
        [Parameter()]
        [ValidatePattern("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(?:\-(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))?$")]
        [String]$SignedIp,

        [Parameter(Mandatory)]
        [ValidateSet("Read", "Add", "Create", "Delete", "DeleteVersion", "PermanentDelete", "List",
            "Tags", "Move", "Execute", "Ownership", "Permissions", "SetImmutabilityPolicy")]
        [String[]]$SignedPermissions,

        [Parameter()]
        [ValidateSet("All", "HttpsOnly")]
        [String]$SignedProtocol,

        [Parameter(Mandatory)]
        [ValidateSet("Blob", "BlobVersion", "BlobSnapshot", "Container", "Directory")]
        [String]$SignedResource,

        [Parameter()]
        [ValidateScript({ $_ -lt $SignedExpiry })]
        [DateTime]$SignedStart,

        [Parameter()][Guid]$SignedUnauthorizedObjectId
    )
    begin {

        $tempPreference = $DebugPreference
        if($PSBoundParameters["Debug"]) {
            $DebugPreference = "Continue"
        }

        # BEGIN: Mapping Readable Values to actual values
        $srHashMap = @{
            Blob = "b"
            BlobVersion = "bv"
            BlobSnapshot = "bs"
            Container = "c"
            Directory = "d"
        }

        $spHashMap = @{
            Read = "r"
            Add = "a"
            Create = "c"
            Write = "w"
            Delete = "d"
            DeleteVersion = "x"
            PermanentDelete = "y"
            List = "l"
            Tags = "t"
            Move = "m"
            Execute = "e"
            Ownership = "o"
            Permissions = "p"
            SetImmutabilityPolicy = "i"
        }

        $sprHashMap = @{
            All = "https,http"
            HttpsOnly = "https"
        }
        # END: Mapping Readable Values to actual values

        function Get-CanonicalizedResource {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory, Position=0)]
                [ValidateScript({
                    # We are doing this so the correct resource URI can be determined
                    $dnshost = $_.DnsSafeHost
                    $regex = "^(?<storageAccount>[a-zA-Z0-9-]+)(?:\.blob|\.dfs)\.core(?:\.windows.net|\.chinacloudapi\.cn|\.cloudapi\.de|\.usgovcloudapi\.net)$"
                    $_.LocalPath -ne "/" -and $dnshost -match $regex #DNS must be a storage DNS and we cannot use the root path
                })]
                [Uri]$Url
            )
            process {
                $regex = "^(?<storageAccount>[a-zA-Z0-9-]+)(?:\.blob|\.dfs)\.core(?:\.windows.net|\.chinacloudapi\.cn|\.cloudapi\.de|\.usgovcloudapi\.net)$"
                $storageAccount = ([Regex]::Match($Url.DnsSafeHost, $regex).Groups["storageAccount"].Value)
                $containerName = $Url.Segments[1]
                if($containerName.EndsWith("/")) { $containerName = $containerName.Substring(0, $containerName.Length - 1) }
                $path = $Url.LocalPath.Substring($containerName.Length + 1)

                Write-Debug "[Get-CanonicalizedResource][process] `$Url = '$Url'"
                Write-Debug "[Get-CanonicalizedResource][process] `$Url.Segments[1] = '$($Url.Segments[1])'"
                Write-Debug "[Get-CanonicalizedResource][process] `$storageAccount = '$storageAccount'"
                Write-Debug "[Get-CanonicalizedResource][process] `$containerName = '$containerName'"

                if($path -eq "/") { $path = [String]::Empty }

                Write-Debug "[Get-CanonicalizedResource][process] `$path = '$path'"

                $sddPath = $(if($path.EndsWith("/")) { $path.Substring(0, $path.Length - 1) } else { $path } )

                $returnValue = [PSCustomObject]@{
                    StorageAccountName = $storageAccount
                    CanonicalizedResource = "/blob/$storageAccount/$($containerName)$($path)"
                    SignedDirectoryDepth = $sddPath.Split("/").Count - 1
                }

                Write-Debug "[Get-CanonicalizedResource][process] `$returnValue.StorageAccountName = '$($returnValue.StorageAccountName)'"
                Write-Debug "[Get-CanonicalizedResource][process] `$returnValue.CanonicalizedResource = '$($returnValue.CanonicalizedResource)'"
                Write-Debug ("[Get-CanonicalizedResource][process] `$returnValue.SignedDirectoryDepth = '$($returnValue.SignedDirectoryDepth)'" + [Environment]::NewLine)

                $returnValue
            }
        }

        function Get-Signature {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory, Position = 0)][String]$Value,
                [Parameter(Mandatory, Position = 1)][String]$Key
            )
            begin {
                $hmacKey = [Convert]::FromBase64String($Key)
                $hmac = [System.Security.Cryptography.HMACSHA256]::new($hmacKey)
            }
            process {
                $signature = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
                [Convert]::ToBase64String($signature)
            }
            end {
                if($null -ne $hmac) {
                    $hmac.Dispose()
                }
            }
        }

        $canonicalizedResourceData = Get-CanonicalizedResource -Url $ResourceUri

        $canonicalizedResource = $canonicalizedResourceData.CanonicalizedResource
        $storageAccountName = $canonicalizedResourceData.StorageAccountName

        [String]$sv = "2020-12-06"
        [String]$sr = $srHashMap[$SignedResource]
        [String]$st = $(if($PSBoundParameters.ContainsKey("SignedStart")) { $SignedStart.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") } else { [String]::Empty })
        [String]$se = $SignedExpiry.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        [String]$sp = (
            @("Read", "Add", "Create", "Delete", "DeleteVersion", "PermanentDelete", "List", `
                "Tags", "Move", "Execute", "Ownership", "Permissions", "SetImmutabilityPolicy") `
                | ForEach-Object {
                    if( $SignedPermissions -contains $_ ) {
                        $spHashMap[$_]
                    }
                }
        ) -join [String]::Empty

        [String]$sip = $SignedIp
        [String]$spr = $(if($PSBoundParameters.ContainsKey("SignedProtocol")) { $sprHashMap[$SignedProtocol] } else { [String]::Empty } )
        [String]$skoid = $null # See Below
        [String]$sktid = $null # See Below
        [String]$skt = $null # See Below
        [String]$ske = $null # See Below
        [String]$sks = $null # See Below
        [String]$skv = $null # See Below
        [String]$saoid = $(if($PSBoundParameters.ContainsKey("SignedAuthorizedObjectId")) { $SignedAuthorizedObjectId.ToString() } else { [String]::Empty } )
        [String]$suoid = $(if($PSBoundParameters.ContainsKey("SignedUnauthorizedObjectId")) { $SignedUnauthorizedObjectId.ToString() } else { [String]::Empty} )
        [String]$scid = $(if($PSBoundParameters.ContainsKey("SignedCorrelationId")) { $SignedCorrelationId.ToString() } else { [String]::Empty } )
        [String]$sdd = $(if($SignedResource -eq "Directory") { $canonicalizedResourceData.SignedDirectoryDepth } else { [String]::Empty })
        [String]$ses = $(if($PSBoundParameters.ContainsKey("SignedEncryptionScope")) { $SignedEncryptionScope } else { [String]::Empty } )
        [String]$rscc = $(if($PSBoundParameters.ContainsKey("ResponseHeaderCacheControl")) { $ResponseHeaderCacheControl } else { [String]::Empty } )
        [String]$rscd = $(if($PSBoundParameters.ContainsKey("ResponseHeaderContentDisposition")) { $ResponseHeaderContentDisposition } else { [String]::Empty } )
        [String]$rsce = $(if($PSBoundParameters.ContainsKey("ResponseHeaderContentEncoding")) { $ResponseHeaderContentEncoding } else { [String]::Empty } )
        [String]$rscl = $(if($PSBoundParameters.ContainsKey("ResponseHeaderContentLanguage")) { $ResponseHeaderContentLanguage } else { [String]::Empty } )
        [String]$rsct = $(if($PSBoundParameters.ContainsKey("ResponseHeaderContentType")) { $ResponseHeaderContentType } else { [String]::Empty } )

        if(-not [String]::IsNullOrEmpty($canonicalizedResource)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Canonicalized Resource: '$canonicalizedResource'" }

        Write-Debug -Message "[Get-AzUserDelegationKey][begin] Generating a bearer token for Azure Storage."
        
        try {
            $token = Get-AzAccessToken -ResourceUrl https://storage.azure.com

            $sst = $(if([String]::IsNullOrEmpty($st)) { [DateTime]::UtcNow.AddMinutes(-15).ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $st })

            $xmlBody = "<?xml version=`"1.0`" encoding=`"utf-8`"?>
<KeyInfo>
    <Start>$sst</Start>
    <Expiry>$se</Expiry>
</KeyInfo>"

            $clientID = [Guid]::NewGuid().ToString()
            $udUri = "https://$($ResourceUri.DnsSafeHost)/?restype=service&comp=userdelegationkey"

            Write-Debug -Message "[Get-AzUserDelegationKey][begin] Obtaining a User Delegation Key for Azure Storage account '$storageAccountName'."
            Write-Debug -Message "[Get-AzUserDelegationKey][begin] Client Request ID = '$clientID'."
            Write-Debug -Message "[Get-AzUserDelegationKey][begin] URI $udUri"
            Write-Debug -Message "[Get-AzUserDelegationKey][begin] XML Request Body $([Environment]::NewLine) $xmlBody"


            $response = Invoke-RestMethod -Method Post -UseBasicParsing `
                -Uri $udUri `
                -Headers @{Authorization="$($token.Type) $($token.Token)";"x-ms-version"="2020-12-06";"x-ms-client-request-id"=$clientID } `
                -Body $xmlBody -ContentType "application/xml; charset=utf-8"

            # BEGIN: UTF BOM Detection
            $hasBOM = $response[0] -eq 239 -and $response[1] -eq 187 -and $response[2] -eq 191
            if($hasBOM) {
                Write-Debug -Message "[Get-AzUserDelegationKey][begin] Eliminating UTF BOM (byte-order mark) from the response."
                $response = $response.Substring(3)
            }

            $skoid = ([xml]$response).UserDelegationKey.SignedOid
            $sktid = ([xml]$response).UserDelegationKey.SignedTid
            $skt = ([xml]$response).UserDelegationKey.SignedStart
            $ske = ([xml]$response).UserDelegationKey.SignedExpiry
            $sks = ([xml]$response).UserDelegationKey.SignedService
            $skv = ([xml]$response).UserDelegationKey.SignedVersion

            if(-not [String]::IsNullOrEmpty($sv)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter sv = '$sv'" }
            if(-not [String]::IsNullOrEmpty($sr)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter sr = '$sr'" }
            if(-not [String]::IsNullOrEmpty($st)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter st = '$st'" }
            if(-not [String]::IsNullOrEmpty($se)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter se = '$se'" }
            if(-not [String]::IsNullOrEmpty($sp)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter sp = '$sp'" }
            if(-not [String]::IsNullOrEmpty($sip)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter sip = '$sip'" }
            if(-not [String]::IsNullOrEmpty($spr)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter spr = '$spr'" }
            if(-not [String]::IsNullOrEmpty($skoid)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter skoid = '$skoid'" }
            if(-not [String]::IsNullOrEmpty($sktid)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter sktid = '$sktid'" }
            if(-not [String]::IsNullOrEmpty($skt)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter skt = '$skt'" }
            if(-not [String]::IsNullOrEmpty($ske)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter ske = '$ske'" }
            if(-not [String]::IsNullOrEmpty($sks)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter sks = '$sks'" }
            if(-not [String]::IsNullOrEmpty($saoid)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter saoid = '$saoid'" }
            if(-not [String]::IsNullOrEmpty($suoid)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter suoid = '$suoid'" }
            if(-not [String]::IsNullOrEmpty($scid)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter scid = '$scid'" }
            if(-not [String]::IsNullOrEmpty($sdd)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter sdd = '$sdd'" }
            if(-not [String]::IsNullOrEmpty($ses)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter ses = '$ses'" }
            if(-not [String]::IsNullOrEmpty($rscc)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter rscc = '$rscc'" }
            if(-not [String]::IsNullOrEmpty($rscd)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter rscd = '$rscd'" }
            if(-not [String]::IsNullOrEmpty($rsce)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter rsce = '$rsce'" }
            if(-not [String]::IsNullOrEmpty($rscl)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter rscl = '$rscl'" }
            if(-not [String]::IsNullOrEmpty($rsct)) { Write-Debug -Message "[Get-AzUserDelegationKey][begin] Parameter rsct = '$rsct'" }

            # Note that the signedSnapshotTime does not appear to be documented 
            $stringToSign = @(
                $sp, $st, $se, $canonicalizedResource, $skoid, $sktid, $skt, $ske, $sks, $skv, $saoid, $suoid,
                $scid, $sip, $spr, $sv, $sr, [String]::Empty <# Snapshot Time#>, $ses, $rscc, $rscd, $rsce, $rscl, $rsct
            ) -join "`n"
    
            $displayStringToSign = $stringToSign.Replace("`n", "\n")
            Write-Debug -Message "[Get-AzUserDelegationKey][begin] String-to-sign = '$displayStringToSign'"

            $hmacKey = ([xml]$response).UserDelegationKey.Value

            [String]$sig = [Net.WebUtility]::UrlEncode((Get-Signature -Value $stringToSign -Key $hmacKey))

            $debugSig = [String]::Concat($sig.Substring(0, 3), [String]::Empty.PadLeft($sig.Length - 6, "*"), $sig.Substring($sig.Length - 3, 3))

            Write-Debug -Message "[Get-AzUserDelegationKey][begin] Computed sig = '$debugSig'"
            Write-Debug -Message "[Get-AzUserDelegationKey][begin] Generating final User Delegation SAS."

            $urlParams = [System.Collections.Generic.List[string]]::new()
            $urlParams.Add("?sv=$sv")
            $urlParams.Add("sr=$sr")
            if(-not [String]::IsNullOrEmpty($st)) { $urlParams.Add("st=$st") }
            $urlParams.Add("se=$se")
            $urlParams.Add("sp=$sp")
            if(-not [String]::IsNullOrEmpty($sip)) { $urlParams.Add("sip=$sip") }
            if(-not [String]::IsNullOrEmpty($spr)) { $urlParams.Add("spr=$spr") }
            $urlParams.Add("skoid=$skoid")
            $urlParams.Add("sktid=$sktid")
            if(-not [String]::IsNullOrEmpty($skt)) { $urlParams.Add("skt=$skt") }
            $urlParams.Add("ske=$ske")
            $urlParams.Add("sks=$sks")
            $urlParams.Add("skv=$skv")
            if(-not [String]::IsNullOrEmpty($saoid)) { $urlParams.Add("saoid=$saoid") }
            if(-not [String]::IsNullOrEmpty($suoid)) { $urlParams.Add("skt=$suoid") }
            if(-not [String]::IsNullOrEmpty($scid)) { $urlParams.Add("skt=$scid") }
            if(-not [String]::IsNullOrEmpty($sdd)) { $urlParams.Add("sdd=$sdd") }
            if(-not [String]::IsNullOrEmpty($ses)) { $urlParams.Add("ses=$ses") }
            $urlParams.Add("sig=$sig")
            if(-not [String]::IsNullOrEmpty($rscc)) { $urlParams.Add("rscc=$rscc") }
            if(-not [String]::IsNullOrEmpty($rscd)) { $urlParams.Add("rscd=$rscd") }
            if(-not [String]::IsNullOrEmpty($rsce)) { $urlParams.Add("ses=$rsce") }
            if(-not [String]::IsNullOrEmpty($rscl)) { $urlParams.Add("ses=$rscl") }
            if(-not [String]::IsNullOrEmpty($rsct)) { $urlParams.Add("ses=$rsct") }

            $sas = ($urlParams.ToArray() -join "&")
            [PSCustomObject]@{
                SasToken = $sas
                SasUrl = $ResourceUri.ToString() + $sas
            }
        }
        catch {
            throw
        }
        
    }
    process {

    }
    end {
        $DebugPreference = $tempPreference
    }
}