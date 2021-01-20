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


        $tcpClient = New-Object System.Net.Sockets.TcpClient
        try {
            $tcpClient.Connect($host2, $port)

            $ssl = New-Object System.Net.Security.SslStream $tcpClient.GetStream(), $false, {
                Write-Warning "NOTE: The server certificate is invalid. This script is ignoring the error."
                $true
            }, $null

            try {
                $certificates = New-Object System.Security.Cryptography.X509Certificates.X509CertificateCollection
                $enabledProtocols = [System.Security.Authentication.SslProtocols]::Tls11

                $ssl.AuthenticateAsClient($host, $certificates, $enabledProtocols, $false)
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
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