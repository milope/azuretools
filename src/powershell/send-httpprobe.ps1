<#
THE CONTENTS PROVIDED ON THIS SCRIPT IS PROVIDED AS IS WITH NO WARRANTY.
I WILL NOT BE HELD LIABLE FOR ANY DAMAGES RESULTING FROM THE USAGE OF THIS SCRIPT
OR ANY DERIVATIVE FROM IT

This script is used to test HTTP/HTTPS endpoints
#>

function Send-HttpProbe {
    [CmdletBinding()]
    param(
        [Switch][Parameter(Mandatory=$false, ParameterSetName="SSL")]$UseSSL,
        [Switch][Parameter(Mandatory=$false, ParameterSetName="SSL")]$NoSNI,
        [Switch][Parameter(Mandatory=$false)]$UseIPv4Only,
        [Int32][Parameter(Mandatory=$false)]$Port,
        [System.Security.Authentication.SslProtocols][Parameter(Mandatory=$false, ParameterSetName="SSL")]$SslProtocol = [System.Security.Authentication.SslProtocols]::Tls12,
        [String][Parameter(Mandatory=$true)]$Hostname,
        [String][Parameter(Mandatory=$false)]$HttpHost,
        [String][Parameter(Mandatory=$false)]$Path="/"
    )
    begin {
        if(-not $PSBoundParameters.ContainsKey("Port")) {
            if($UseSSL.IsPresent -and $UseSSL) {
                $Port = 443
            }
            else {
                $Port = 80
            }
        }

        $sslwarnfile = (Join-Path -Path $env:TEMP -ChildPath "ssltestcertwarn.log")
        if(-not $PSBoundParameters.ContainsKey("HttpHost"))
        {
            $HttpHost = $Hostname
        }

        function Get-InnerMostException {
            [CmdletBinding()]
            param(
                [Exception][Parameter(Mandatory=$true)]$Exception
            )
            process {
                $exp = $exception
                while($null -ne $exp.InnerException) {
                    $exp = $exp.InnerException
                }
                return $exp
            }
        }

        function Do-Cleanup {
            [CmdletBinding()]
            param(
                [System.Net.Sockets.Socket][Parameter(Mandatory=$false)]$Socket,
                [System.Net.Sockets.NetworkStream][Parameter(Mandatory=$false)]$NetworkStream,
                [System.Net.Security.SslStream][Parameter(Mandatory=$false)]$SslStream
            )
            process {

                if($null -ne $SslStream) {
                    $SslStream.Close()
                    $SslStream.Dispose()
                }

                if($null -ne $NetworkStream) {
                    $NetworkStream.Close()
                    $NetworkStream.Dispose()
                }

                if($null -ne $Socket) {
                    try {
                        $socket.Shutdown(([System.Net.Sockets.SocketShutdown]::Both))
                    }
                    catch {
                    }
                    $socket.Close()
                    $socket.Dispose()
                }
            }
        }

        function Get-FromNetworkSteam {
            [CmdletBinding()]
            param(
                [object][Parameter(Mandatory=$true)]$NetworkStream,
                [Byte[]][Parameter(Mandatory=$true)]$Buffer,
                [Int32][Parameter(Mandatory=$true)]$Offset,
                [Int32][Parameter(Mandatory=$true)]$Length
            )
            if($NetworkStream.GetType().Name -eq "SslStream") {
                return ([System.Net.Security.SslStream]$NetworkStream).Read($Buffer, $Offset, $Length)
            }
            elseif($NetworkStream.GetType().Name -eq "Socket") {
                return ([System.Net.Sockets.Socket]$NetworkStream).Receive($Buffer, $Offset, $Length, ([System.Net.Sockets.SocketFlags]::None))
            }
        }

        function Send-ToNetworkStream {
            [CmdletBinding()]
            param(
                [object][Parameter(Mandatory=$true)]$NetworkStream,
                [Byte[]][Parameter(Mandatory=$true)]$Buffer
            )
            if($NetworkStream.GetType().Name -eq "SslStream") {
                return ([System.Net.Security.SslStream]$NetworkStream).Write($Buffer)
            }
            elseif($NetworkStream.GetType().Name -eq "Socket") {
                return ([System.Net.Sockets.Socket]$NetworkStream).Send($Buffer)
            }
        }

        function Get-IndexOfLineBreak {
            [CmdletBinding()]
            param(
                [Byte[]][Parameter(Mandatory=$true)]$Buffer,
                [Int32][Parameter(Mandatory=$true)]$BytesRead
            )
            process {
                $returnValue = -1
                $min = [Math]::Min($Buffer.Length - 2, $BytesRead)
                for($i = 0; $i -lt $min; $i++) {
                    if($Buffer[$i] -eq 13 -and $Buffer[$i + 1] -eq 10) {
                        $returnValue = $i
                        break
                    }
                }
                return $returnValue
            }
        }

        function Get-BufferAsString {
            [CmdletBinding()]
            param(
                [Byte[]][Parameter(Mandatory=$true)]$Buffer,
                [Int32][Parameter(Mandatory=$true)]$Length
            )
            process {
                if($null -eq $Buffer) {
                    return $null
                }
                if($Buffer.Length -eq 0) {
                    return [String]::Empty
                }
                return [Text.Encoding]::UTF8.GetString($Buffer, 0, $Length)
            }
        }
    }
    process {

        $test1Name = "DNS Resolution"
        $test1Result = "Not Started"
        $test1Output = ""

        $test2Name = "TCP Connection"
        $test2Result = "Not Started"
        $test2Output = "DNS Resolution test failed"

        $test3Name = "SSL Handshake"
        $test3Result = "Not Started"
        $test3Output = "Either DNS resolution or TCP connection tests failed"

        $test4Name = "Send Web Request"
        $test4Result = "Not Started"
        $test4Output = "Either DNS resolution, TCP connection or SSL handshake tests failed."

        $test5Name = "Read Web Response Status"
        $test5Result = "Not Started"
        $test5Output = "Either DNS resolution, TCP connection, SSL handshake or Web Request tests failed."


        $stop = $false

        #Test 1: DNS
        $ips = $null
        if($UseIPv4Only.IsPresent -and $UseIPv4Only) {
            $ips = Resolve-DnsName -Name $Hostname -Type A -ErrorAction SilentlyContinue
        }
        else {
            $ips = Resolve-DnsName -Name $Hostname -Type A_AAAA -ErrorAction SilentlyContinue
        }
        
        if($null -eq $ips) {
            $stop = $true
            $test1Result = "Failed"
            $test1Output = "Could not resolve DNS Name $($Hostname)"
        }
        else {
            $test1Result = "Success"
            $test1Output = "Resolved the following IP address(es): $([String]::Join(", ", ($ips | Where-Object { $null -ne $_.IPAddress } | ForEach-Object { $_.IPAddress })))"
        }
                
        [PSCustomObject]@(
            [PSCustomObject]@{
                TestType=$test1Name
                TestResult=$test1Result
                TestOutput=$test1Output
            }
        )

        if($stop) {
            return
        }


        #Test 2: Connectivity
        $ip = $ips | Where-Object { $null -ne $_.IPAddress } | Select-Object -First 1 | % { [System.Net.IPAddress]::Parse($_.IPAddress) }
        $socket = New-Object System.Net.Sockets.Socket $ip.AddressFamily, ([System.Net.Sockets.SocketType]::Stream), ([System.Net.Sockets.ProtocolType]::Tcp)
        $ipendpoint = New-Object System.Net.IPEndPoint($ip, $Port)
        try {
            $socket.Connect($ipendpoint) | Out-Null
            $test2Result = "Success"
            if($ip.AddressFamily -eq ([System.Net.Sockets.AddressFamily]::InterNetworkV6)) {
                $test2Output = "Connnected to [$($ip)]:$($Port)"
            }
            else {
                $test2Output = "Connnected to $($ip):$($Port)"
            }
        }
        catch {
            $stop = $true
            $exp = Get-InnerMostException -Exception $_.Exception
            $test2Result = "Failed"
            if($exp.GetType().Name -eq "SocketException") {
                $test2Output = "[$($exp.GetType().Name)] $($exp.Message) (WinSock error $($exp.SocketErrorCode))."
            }
            else {
                $test2Output = "[$($exp.GetType().Name)] $($exp.Message)."
            }
        }

        [PSCustomObject]@(
            [PSCustomObject]@{
                TestType=$test2Name
                TestResult=$test2Result
                TestOutput=$test2Output
            }
        )

        if($stop) {
            if($null -ne $socket) {
                Do-Cleanup -Socket $socket -NetworkStream $null -SslStream $null
            }
            return
        }

        #Test 3: SSL Handshake

        if($UseSSL.IsPresent -and $UseSSL) {
            $sslHost = $Hostname
            if($NoSNI.IsPresent -and $NoSNI) {
                $sslHost = $ip.ToString()
            }

        
            $netStream = New-Object System.Net.Sockets.NetworkStream $socket
            $remoteCallback = $null
            $certificates = New-Object System.Security.Cryptography.X509Certificates.X509CertificateCollection

            if($NoSNI.IsPresent -and $NoSNI) {
                $remoteCallback ={
                    param(
                        [object]$sender,
                        [System.Security.Cryptography.X509Certificates.X509Certificate]$certificate,
                        [System.Security.Cryptography.X509Certificates.X509Chain]$chain,
                        [System.Net.Security.SslPolicyErrors]$sslPolicyErrors
                    )
                    if($sslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::None -or $sslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) {
                        if($sslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) {
                            "WARNING" | Out-File -FilePath $sslwarnfile
                        }
                        return $true
                    }
                    return $false
                }
            }

            $sslStream = New-Object System.Net.Security.SslStream -ArgumentList @($netStream, $false, $remoteCallback, $null)
        
            try {
                $sslStream.AuthenticateAsClient($sslHost, $certificates, $SslProtocol, $false) | Out-Null
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $sslStream.RemoteCertificate
                if(Test-Path -Path $sslwarnfile ) {
                    Remove-Item -Path $sslwarnfile | Out-Null
                    $test3Result = "Warning"
                    $test3Output = "Using -NoSNI will always result in a failed certificate validation. Will correct this script in the future. Cert info: Thumbprint => $($cert.Thumbprint); Subject $($cert.SubjectName)."
                }
                else {
                    $test3Result = "Success"
                    $test3Output = "SSL Handshake was successful. Cert info: Thumbprint => $($cert.Thumbprint); Subject $($cert.Subject)."
                }
            }
            catch {
                $stop = $true
                $exp = Get-InnerMostException -Exception $_.Exception
                $test3Result = "Failed"
                if($exp.GetType().Name -eq "SocketException") {
                    $test3Output = "[$($exp.GetType().Name)] $($exp.Message) (WinSock error $($exp.SocketErrorCode))."
                }
                else {
                    $test3Output = "[$($exp.GetType().Name)] $($exp.Message)."
                }
            }
        }
        else {
            $test3Result = "Skipped"
            $test3Output = "-UseSSL not specified"
        }

        [PSCustomObject]@(
            [PSCustomObject]@{
                TestType=$test3Name
                TestResult=$test3Result
                TestOutput=$test3Output
            }
        )

        if($stop) {
            if($null -ne $socket) {
                Do-Cleanup -Socket $socket -NetworkStream $netStream -SslStream $sslStream
            }
            return
        }

        #Test 4: Web Request
        $stream = $null
        if($UseSSL.IsPresent -and $UseSSL) {
            $sslStream.WriteTimeout = 5000
            $sslStream.ReadTimeout = 5000
            $stream = $sslStream

        }
        else {
            $socket.ReceiveTimeout = 5000
            $socket.SendTimeout = 5000
            $stream = $socket
        }


        
        $webRequest = "GET $($Path) HTTP/1.1`r`nHost: $($HttpHost)`r`nUser-Agent: milope+send+http+probe+test`r`n`r`n"
        try {

            Send-ToNetworkStream -NetworkStream $stream -Buffer ([Text.Encoding]::UTF8.GetBytes($webRequest)) | Out-Null
            $test4Result = "Success"
            $test4Output = "Probe web request sent successfully."
        }
        catch {
            $stop = $true
            $exp = Get-InnerMostException -Exception $_.Exception
            $test4Result = "Failed"
            if($exp.GetType().Name -eq "SocketException") {
                $test4Output = "[$($exp.GetType().Name)] $($exp.Message) (WinSock error $($exp.SocketErrorCode))."
            }
            else {
                $test4Output = "[$($exp.GetType().Name)] $($exp.Message)."
            }
        }

        [PSCustomObject]@(
            [PSCustomObject]@{
                TestType=$test4Name
                TestResult=$test4Result
                TestOutput=$test4Output
            }
        )

        if($stop) {
            if($null -ne $socket) {
                Do-Cleanup -Socket $socket -NetworkStream $netStream -SslStream $sslStream
            }
            return
        }

        #TODO: Test 5
        
        $bufferSize = 4 * 1024
        $buffer = New-Object System.Byte[] $bufferSize
        $read = 0
        $statusLine = $null

        # Get status line
        while($true) {
            try {
                $read = Get-FromNetworkSteam -Buffer $buffer -NetworkStream $stream -Offset 0 -Length $bufferSize
            }
            catch {
                $exp = Get-InnerMostException -Exception $_.Exception
                $test5Result = "Failed"
                if($exp.GetType().Name -eq "SocketException") {
                    $test5Output = "[$($exp.GetType().Name)] $($exp.Message) (WinSock error $($exp.SocketErrorCode))."
                }
                else {
                    $test5Output = "[$($exp.GetType().Name)] $($exp.Message)."
                }
            }
            if($read -eq 0) {
                $test5Result = "Failed"
                $test5Output = "Remote Server disconnected."
                break
            }

            $idx = Get-IndexOfLineBreak -Buffer $buffer -BytesRead $read
            if($idx -gt -1) {
                $statusLine = Get-BufferAsString -Buffer $buffer -Length $idx
                break
            }
        }

        if($null -ne $statusLine) {
            $statusLineSplit = $statusLine.Split(' ', 3)
            $statusCode = $statusLineSplit[1]
            $statusDescription = $statusLineSplit[2]

            $test5Result = "Success"
            $test5Output = "Response Status Code: $($statusCode), Description: $($statusDescription). More parsing to come in the future."
        }
        elseif($test5Output -ne "Failed") {
            $test5Result = "Failed"
            $test5Output = "For an unknown reason, couldn't parse the status line from the response."
        }

        [PSCustomObject]@(
            [PSCustomObject]@{
                TestType=$test5Name
                TestResult=$test5Result
                TestOutput=$test5Output
            }
        )

        
        Do-Cleanup -Socket $socket -NetworkStream $netStream -SslStream $sslStream
    }
}
