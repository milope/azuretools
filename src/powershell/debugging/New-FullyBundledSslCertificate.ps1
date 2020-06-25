function New-FullyBundledSslCertificate {
    [CmdletBinding()]
    param(
        [String][Parameter(Mandatory=$true)]$RootSubject,
        [String][Parameter(Mandatory=$false)]$RootFriendlyName="Root",
        [String][Parameter(Mandatory=$true)]$CASubject,
        [String][Parameter(Mandatory=$false)]$CAFriendlyName="Intermediate",
        [String][Parameter(Mandatory=$true)]$LeafSubject,
        [String][Parameter(Mandatory=$false)]$LeafFriendlyName="Leaf",
        [String][Parameter(Mandatory=$false)]$ClientCertSubject,
        [String][Parameter(Mandatory=$false)]$ClientCertFriendlyName="ClientCert",
        [String[]][Parameter(Mandatory=$true)]$DNSNames,
        [SecureString][Parameter(Mandatory=$true)]$Password,
        [String][Parameter(Mandatory=$true)]$OutputPath,
        [Switch]$RetainCAPFX
    )
    process {

        # From: https://superuser.com/questions/749243/detect-if-powershell-is-running-as-administrator
        if(-not [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")) {
            throw [InvalidOperationException]::new("This script can only be run as an Administrator.")
        }

        if(-not (Test-Path $OutputPath)) {
            throw [Exception]::new("The path $($OutputPath) does not exist.")
        }

        $signerStart = [DateTime](Get-Date).ToString("yyyy-MM-dd")
        $signerEnd = $signerStart.AddYears(10)
        $sslCertStart = $signerStart
        $sslCertEnd = $sslCertStart.AddYears(2)
        $cspProvider = "Microsoft Enhanced RSA and AES Cryptographic Provider"

        $rootExtension = "2.5.29.19={critical}{text}ca=1&pathLength=3"
        $caExtension = "2.5.29.37={text},1.3.6.1.5.5.7.3.2,1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.9", "2.5.29.19={critical}{text}ca=1&pathLength=0"
        $sslExtension = "2.5.29.37={text},1.3.6.1.5.5.7.3.1"
        $clientExtension = "2.5.29.37={text},1.3.6.1.5.5.7.3.2"

        $rootPath = Join-Path -Path $OutputPath -ChildPath "root.cer"
        $caPath = Join-Path -Path $OutputPath -ChildPath "ca.cer"
        $leafPath = Join-Path -Path $OutputPath -ChildPath "certificate-bundled.pfx"
        $clientPath = $null
        if(-not [String]::IsNullOrEmpty($ClientCertSubject)) {
            $clientPath = Join-Path -Path $OutputPath -ChildPath "client-cert.pfx"
        }

        $root = (New-SelfSignedCertificate -KeyUsageProperty Sign -KeyUsage CertSign, CRLSign -KeyLength 2048 `
            -KeyExportPolicy Exportable -KeyProtection None -KeyAlgorithm RSA -Subject $RootSubject `
            -HashAlgorithm SHA256 -CertStoreLocation Cert:\LocalMachine\My -NotBefore $signerStart -NotAfter $signerEnd `
            -FriendlyName $RootFriendlyName -Provider $cspProvider -TextExtension $rootExtension)

        $ca = (New-SelfSignedCertificate -KeyUsage DigitalSignature,CertSign,CRLSign -KeyLength 2048 -KeyExportPolicy Exportable `
            -KeyProtection None -KeyAlgorithm RSA -Subject $CASubject -HashAlgorithm SHA256 `
            -CertStoreLocation Cert:\LocalMachine\My -NotBefore $signerStart -NotAfter $signerEnd -FriendlyName $CAFriendlyName `
            -Signer $root -TextExtension $caExtension -Provider $cspProvider)

        $serverCert = (New-SelfSignedCertificate -KeyUsage DigitalSignature, KeyEncipherment, DataEncipherment -KeyLength 2048 `
            -KeyExportPolicy Exportable -KeyProtection None -KeyAlgorithm RSA -Subject $LeafSubject -HashAlgorithm SHA256 `
            -CertStoreLocation cert:\LocalMachine\My -NotBefore $sslCertStart -NotAfter $sslCertEnd -FriendlyName $LeafFriendlyName `
            -Signer $ca -TextExtension $sslExtension -DnsName $DNSNames)

        $clientCert = $null

        if(-not [String]::IsNullOrEmpty($ClientCertSubject)) {
            $clientCert = (New-SelfSignedCertificate -KeyUsage DigitalSignature, KeyEncipherment, DataEncipherment -KeyLength 2048 `
            -KeyExportPolicy Exportable -KeyProtection None -KeyAlgorithm RSA -Subject $ClientCertSubject -HashAlgorithm SHA256 `
            -CertStoreLocation Cert:\CurrentUser\My -NotBefore $sslCertStart -NotAfter $sslCertEnd -FriendlyName $ClientCertFriendlyName `
            -Signer $ca -TextExtension $clientExtension -DnsName $DNSNames)
        }
        
        Export-PfxCertificate -Password $Password -ChainOption BuildChain -Cert $serverCert -FilePath $leafPath |  Out-Null
        if(-not [String]::IsNullOrEmpty($ClientCertSubject)) {
            Export-PfxCertificate -Password $Password -ChainOption EndEntityCertOnly -Cert $clientCert -FilePath $clientPath |  Out-Null
        }

        Export-Certificate -Type CERT -FilePath $caPath -Cert $ca |  Out-Null
        Export-Certificate -Type CERT -FilePath $rootPath -Cert $root |  Out-Null

        # This is a hacky way to put the certs where they go

        $rootPfxPath = Join-Path -Path $OutputPath -ChildPath "root.pfx"
        $caPfxPath = Join-Path -Path $OutputPath -ChildPath "ca.pfx"

        Export-PfxCertificate -Password $Password -FilePath $rootPfxPath -Cert $root | Out-Null
        Export-PfxCertificate -Password $Password -FilePath $caPfxPath -Cert $ca | Out-Null
        Import-PfxCertificate -Exportable -Password $password -CertStoreLocation Cert:\LocalMachine\Root -FilePath $rootPfxPath | Out-Null
        Import-PfxCertificate -Exportable -Password $password -CertStoreLocation Cert:\LocalMachine\CA -FilePath $caPfxPath | Out-Null

        if(-not $RetainCAPFX) {
            Remove-Item $rootPfxPath | Out-Null
            Remove-Item $caPfxPath | Out-Null
        }

        if([String]::IsNullOrEmpty($ClientCertSubject)) {
            [PSCustomObject]@{
                RootCertificate = "Cert:\LocalMachine\Root\$($root.Thumbprint)";
                CACertificate = "Cert:\LocalMachine\CA\$($ca.Thumbprint)";
                LeafCertificate = "Cert:\LocalMachine\My\$($serverCert.Thumbprint)";
                RootPath = $rootPath;
                CAPath = $caPath;
                LeafPath = $leafPath
            }
        }
        else {
            [PSCustomObject]@{
                RootCertificate = "Cert:\LocalMachine\Root\$($root.Thumbprint)";
                CACertificate = "Cert:\LocalMachine\CA\$($ca.Thumbprint)";
                LeafCertificate = "Cert:\LocalMachine\My\$($serverCert.Thumbprint)";
                ClientCertificate = "Cert:\CurrentUser\My\$($clientCert.Thumbprint)";
                RootPath = $rootPath;
                CAPath = $caPath;
                LeafPath = $leafPath;
                ClientCertificatePath = $clientPath
            }
        }

        if(Test-Path "Cert:\LocalMachine\My\$($root.Thumbprint)") {
            Remove-Item "Cert:\LocalMachine\My\$($root.Thumbprint)" -Force
        }

        if(Test-Path "Cert:\LocalMachine\My\$($ca.Thumbprint)") {
            Remove-Item "Cert:\LocalMachine\My\$($ca.Thumbprint)" -Force
        }
    }
}
