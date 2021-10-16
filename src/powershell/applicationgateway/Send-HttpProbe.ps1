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

Simulates an HTTP probe. Mostly used to simulate Application Gateway probes.

.DESCRIPTION

Simulates an HTTP probe. Mostly used to simulate Application Gateway probes.
Particularly, this cmdlet is intended to perform 5 tests:

Test 1 (if applicable): Does the Hostname provided resolve to an IP
Test 2: Can we establisha TCP 3-way handshake to the destination IP
Test 3 (if applicable): Can we establish an SSL/TLS handshake with the remote
service using the configured protocol.
Test 4: Can we successfully send a web request to the remote destination.
Test 5: Displays the response code obtained from the remote destination.

.PARAMETER UseSSL

When specified, probe will perform TLS handshake after performing TCP 3-way
handshake.

.PARAMETER NoSNI

When specified, avoids using SNI to send TLS handshake (Application Gateway
probes would omit SNI if an IP is used as the backend pool is an IP instead of
an FQDN).

.PARAMETER UseIPv4Only

When specified and if the remote host resolves to IPv6 addresses, this probe
will still use IPv4 to establish the TCP session.

.PARAMETER Port

Specifies the TCP port to use when establishing a collection.

.PARAMETER SslProtocol

Specifies which SSL protocol to test. Accepted values will be any value in the
System.Security.Authentication.SslProtocols enumeration.

.PARAMETER Hostname

Specifies which hostname to establish an HTTP connection to (this can be an IP)

.PARAMETER HttpHost

If specified, it will attempt to override the HTTP Host used to send a web
request. Otherwise, this value will default to the value specified in the
Hostname parameter.

.PARAMETER Path

If specified, it will send a web request using the specified value for this
parameter. Otherwise, the path will default to '/'.

.INPUTS

This cmdlet does not accept inputs.

.OUTPUTS

This cmdlet will provide the results of the following tests:


Test 1 (if applicable): Does the Hostname provided resolve to an IP
Test 2: Can we establisha TCP 3-way handshake to the destination IP
Test 3 (if applicable): Can we establish an SSL/TLS handshake with the remote
service using the configured protocol.
Test 4: Can we successfully send a web request to the remote destination.
Test 5: Displays the response code obtained from the remote destination.

Sample output below:

Send-HttpProbe -UseSSL -Port 443 -UseIPv4Only -Hostname www.microsoft.com -SslProtocol Tls12

TestType                 TestResult TestOutput
--------                 ---------- ----------
DNS Resolution           Success    Resolved the following IP address(es): 96.7.169.183
TCP Connection           Success    Connnected to 96.7.169.183:443
SSL Handshake            Success    SSL Handshake was successful. Cert info: Thumbprint => 9B2B8AE65169AA477C5783D6480F296EF48CF14D; Subject CN=www.microsoft.com, OU=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=WA, C=US.
Send Web Request         Success    Probe web request sent successfully.
Read Web Response Status Success    Response Status Code: 200, Description: OK. More parsing to come in the future.

Failed test below:

TestType       TestResult TestOutput
--------       ---------- ----------
DNS Resolution Success    Resolved the following IP address(es): 2600:1404:5400:1a9::356e, 2600:1404:5400:1b8::356e, 2600:1404:5400:1a2::356e, 96.7.169.183
TCP Connection Failed     [SocketException] A connection attempt failed because the connected party did not properly respond after a period of time, or established connection

.EXAMPLE

PS> Send-HttpProbe -UseSSL -Port 443 -UseIPv4Only -Hostname www.microsoft.com -SslProtocol Tls12

.EXAMPLE

PS> Send-HttpProbe -UseSSL -Port 443 -Hostname www.microsoft.com -SslProtocol Tls12

.EXAMPLE

PS> Send-HttpProbe -UseSSL -NoSNI -Port 443 -UseIPv4Only -Hostname www.microsoft.com -SslProtocol Tls12 -HttpHost "www.contoso.com"

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

        function Invoke-Cleanup {
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
        $parsedip = [System.Net.IPAddress]::Any
        $hostNameIsIP = [System.Net.IPAddress]::TryParse($Hostname, [ref] $parsedip)

        #Test 1: DNS
        $ips = $null

        if($hostNameIsIP) {
            $ips = New-Object System.Collections.ArrayList
            $ips.Add($parsedip) | Out-Null
        }
        else {
            if($UseIPv4Only.IsPresent -and $UseIPv4Only) {
                $ips = Resolve-DnsName -Name $Hostname -Type A -ErrorAction SilentlyContinue
            }
            else {
                $ips = Resolve-DnsName -Name $Hostname -Type A_AAAA -ErrorAction SilentlyContinue
            }
        }
        
        if($hostNameIsIP) {
            $test1Result = "Skipped"
            $test1Output = "No DNS resolution needed for IP $($Hostname)"
        }
        elseif($null -eq $ips) {
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
        if($hostNameIsIP) {
            $ip = $ips[0]
        }
        else {
            $ip = $ips | Where-Object { $null -ne $_.IPAddress } | Select-Object -First 1 | ForEach-Object { [System.Net.IPAddress]::Parse($_.IPAddress) }
        }
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
                Invoke-Cleanup -Socket $socket -NetworkStream $null -SslStream $null
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
                        [object]$pSender,
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
                Invoke-Cleanup -Socket $socket -NetworkStream $netStream -SslStream $sslStream
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
                Invoke-Cleanup -Socket $socket -NetworkStream $netStream -SslStream $sslStream
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

        
        Invoke-Cleanup -Socket $socket -NetworkStream $netStream -SslStream $sslStream
    }
}