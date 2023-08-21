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

This cmdlet can be used to download the public certificate from a given endpoint to a specified file path.

.DESCRIPTION

This cmdlet can be used to download the public certificate from a given endpoint to a specified file path.

UPDATES

2021-01-19: Original compilation correction of small bug in origina script above

.PARAMETER URL

Specify the URL endpoint for which to download the certificate.

.PARAMETER FilePath

Specify where to download the file.

.INPUTS

None. This cmdlet does not support inputs, yet.

.OUTPUTS

This cmdlet will return the result from calling Get-Item on the recently downloaded certificate

.EXAMPLE

.\get-GetificateFromUrl.ps1 -URL https://www.microsoft.com -FilePath C:\Temp\microsoft.com.cer

#>
function Get-CertificateForUrl
{
    [CmdletBinding()]
    param (
        [String][Parameter(Mandatory=$true)]$URL,
        [String][Parameter(Mandatory=$true)]$FilePath
    )
    process {

        $uri = New-Object System.Uri $URL
        if($uri.Scheme -ne "https") {
            throw "$URL is not an HTTPS URL"
        }
        $host2 = $uri.DnsSafeHost
        $port = $uri.Port


        $tcpClient = [System.Net.Sockets.TcpClient]::new()
        try {
            $tcpClient.Connect($host2, $port)

            $ssl = [System.Net.Security.SslStream]::new($tcpClient.GetStream(), $false, {
                [CmdletBinding()]
                param
                (
                    [Object]$sndr,
                    [Security.Cryptography.X509Certificates.X509Certificate]$certificate,
                    [Security.Cryptography.X509Certificates.X509Chain]$chain,
                    [Net.Security.SslPolicyErrors]$sslPolicyError
                )
                
                if($sslPolicyError -eq [Net.Security.SslPolicyErrors]::None) {
                    $true
                    return
                }
                Write-Warning "NOTE: The certificate is invalid according to validation procedure. This script is ignoring the error:"
                if(($sslPolicyError -band [Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) -eq [Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) {
                    Write-Warning "-- Remote certificate name mismatch."
                }
                if(($sslPolicyError -band [Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors) -eq [Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors) {
                    Write-Warning "-- Remote certificate is not trusted. Chain errors below"
                    $chain.ChainStatus | ForEach-Object {
                        switch($_) {
                            [System.Security.Cryptography.X509Certificates]::CtlNotSignatureValid { "-- Specifies that the certificate trust list (CTL) contains an invalid signature."}
                            [System.Security.Cryptography.X509Certificates]::CtlNotTimeValid { "-- Specifies that the certificate trust list (CTL) is not valid because of an invalid time value, such as one that indicates that the CTL has expired."}
                            [System.Security.Cryptography.X509Certificates]::CtlNotValidForUsage { "-- Specifies that the certificate trust list (CTL) is not valid for this use."}
                            [System.Security.Cryptography.X509Certificates]::Cyclic { "-- Specifies that the X509 chain could not be built."}
                            [System.Security.Cryptography.X509Certificates]::ExplicitDistrust { "-- Specifies that the certificate is explicitly distrusted."}
                            [System.Security.Cryptography.X509Certificates]::HasExcludedNameConstraint { "-- Specifies that the X509 chain is invalid because a certificate has excluded a name constraint."}
                            [System.Security.Cryptography.X509Certificates]::HasNotDefinedNameConstraint { "-- Specifies that the certificate has an undefined name constraint"}
                            [System.Security.Cryptography.X509Certificates]::HasNotPermittedNameConstraint { "-- Specifies that the certificate has an impermissible name constraint."}
                            [System.Security.Cryptography.X509Certificates]::HasNotSupportedCriticalExtension { "-- Specifies that the certificate does not support a critical extension."}
                            [System.Security.Cryptography.X509Certificates]::HasNotSupportedNameConstraint { "-- Specifies that the certificate does not have a supported name constraint or has a name constraint that is unsupported."}
                            [System.Security.Cryptography.X509Certificates]::HasWeakSignature { "-- Specifies that the certificate has not been strong signed. Typically, this indicates that the MD2 or MD5 hashing algorithms were used to create a hash of the certificate."}
                            [System.Security.Cryptography.X509Certificates]::InvalidBasicConstraints { "-- Specifies that the X509 chain is invalid due to invalid basic constraints."}
                            [System.Security.Cryptography.X509Certificates]::InvalidExtension { "-- Specifies that the X509 chain is invalid due to an invalid extension."}
                            [System.Security.Cryptography.X509Certificates]::InvalidNameConstraints { "-- Specifies that the X509 chain is invalid due to invalid name constraints."}
                            [System.Security.Cryptography.X509Certificates]::InvalidPolicyConstraints { "-- Specifies that the X509 chain is invalid due to invalid policy constraints."}
                            [System.Security.Cryptography.X509Certificates]::NoError { "-- Specifies that the X509 chain has no errors."}
                            [System.Security.Cryptography.X509Certificates]::NoIssuanceChainPolicy { "-- Specifies that there is no certificate policy extension in the certificate. This error would occur if a group policy has specified that all certificates must have a certificate policy."}
                            [System.Security.Cryptography.X509Certificates]::NotSignatureValid { "-- Specifies that the X509 chain is invalid due to an invalid certificate signature."}
                            [System.Security.Cryptography.X509Certificates]::NotTimeNested { "-- Deprecated. Specifies that the CA (certificate authority) certificate and the issued certificate have validity periods that are not nested. For example, the CA cert can be valid from January 1 to December 1 and the issued certificate from January 2 to December 2, which would mean the validity periods are not nested."}
                            [System.Security.Cryptography.X509Certificates]::NotTimeValid { "-- Specifies that the X509 chain is not valid due to an invalid time value, such as a value that indicates an expired certificate."}
                            [System.Security.Cryptography.X509Certificates]::NotValidForUsage { "-- Specifies that the key usage is not valid."}
                            [System.Security.Cryptography.X509Certificates]::OfflineRevocation { "-- Specifies that the online certificate revocation list (CRL) the X509 chain relies on is currently offline."}
                            [System.Security.Cryptography.X509Certificates]::PartialChain { "-- Specifies that the X509 chain could not be built up to the root certificate."}
                            [System.Security.Cryptography.X509Certificates]::RevocationStatusUnknown { "-- Specifies that it is not possible to determine whether the certificate has been revoked. This can be due to the certificate revocation list (CRL) being offline or unavailable."}
                            [System.Security.Cryptography.X509Certificates]::Revoked { "-- Specifies that the X509 chain is invalid due to a revoked certificate."}
                            [System.Security.Cryptography.X509Certificates]::UntrustedRoot { "-- Specifies that the X509 chain is invalid due to an untrusted root certificate."}
                        }
                    }
                }
                if(($sslPolicyError -band [Net.Security.SslPolicyErrors]::RemoteCertificateNotAvailable) -eq [Net.Security.SslPolicyErrors]::RemoteCertificateNotAvailable) {
                    Write-Warning "-- Remote certificate was not presented."
                }
                $true
            })

            try {
                $certificates = [System.Security.Cryptography.X509Certificates.X509CertificateCollection]::new()
                $enabledProtocols = [System.Security.Authentication.SslProtocols]::Tls12
                $ssl.AuthenticateAsClient($host2, $certificates, $enabledProtocols, $false)
                $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)
                $contentType = [System.Security.Cryptography.X509Certificates.X509ContentType]::Cert
                $certBytes = $cert.Export($contentType)
                [IO.File]::WriteAllBytes($FilePath, $certBytes)

                Get-Item -Path $FilePath
            }
            finally {
                $ssl.Close()
                $ssl.Dispose()
            }

        }
        finally {
            if($null -eq $tcpClient) {
                $tcpClient.Close()
                $tcpClient.Dispose()
            }
        }
    }
}