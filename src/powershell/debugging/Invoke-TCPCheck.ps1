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

Performs a quick TCP 3-way handshake and 4-way handshake to test TCP connections.

.DESCRIPTION

Performs a quick TCP 3-way handshake and 4-way handshake to test TCP connections.

.PARAMETER Hostname

Specify the hostname to test. IPs are supported.

.PARAMETER Port

Specify the port to connect

.PARAMETER ForceIPv4

Force connection tests to use a resolved IPv4 in case a DNS resolves to an IPv6

.PARAMETER Port

Specifies the TCP port to use when establishing a collection.

.INPUTS

This cmdlet does not accept inputs.

.OUTPUTS

This cmdlet just writes results to the host including WinSock error codes if there's a connection issue

.EXAMPLE

PS> Invoke-TCPCheck -Hostname www.microsoft.com -Port 443

.EXAMPLE

PS> Invoke-TCPCheck -Hostname www.microsoft.com -Port 443 -ForceIPv4

.EXAMPLE

PS> Invoke-TCPCheck -Hostname 192.168.1.1 -Port 443

#>
Function Invoke-TCPCheck {
    [CmdletBinding()]
    param (
        [string][Parameter(Mandatory=$true)]$Hostname,
        [Int][Parameter(Mandatory=$true)]$Port,
        [Switch]$ForceIPv4
    )
    begin {
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
    }
    process
    {
        $ips = [System.Net.Dns]::GetHostAddresses($Hostname) #Resolve DNS
        $afv6 = [System.Net.Sockets.AddressFamily]::InterNetworkV6
        $afv4 = [System.Net.Sockets.AddressFamily]::InterNetwork

        $ip = $ips | Where-Object { $_.AddressFamily -eq $afv6 } | Select-Object -First 1

        if($null -eq $ip -or $ForceIPv4) {
            $ip = $ips | Where-Object { $_.AddressFamily -eq $afv4 } | Select-Object -First 1
        }

        if($null -eq $ip) {
            throw New-Object System.InvalidOperationException "Failed to resolve $($Hostname) to an IP"
        }

        $socketType = [System.Net.Sockets.SocketType]::Stream
        $protocolType = [System.Net.Sockets.ProtocolType]::Tcp
        $socket = New-Object System.Net.Sockets.Socket $ip.AddressFamily, $socketType, $protocolType

        Write-Host "Successfully resolved $($Hostname) to IP $($ip). Will try to connect to this IP using destination port $($Port)" -ForegroundColor Green

        try
        {
            $ipendpoint = New-Object System.Net.IPEndPoint($ip, $Port)
            $socket.Connect($ipendpoint) # SYN, SYN-ACK, ACK
            
            Write-Host "Successfully connected to $($Hostname) using IP $($ip), port $($Port)." -ForegroundColor Green
        }
        catch {
            $exp = Get-InnerMostException -Exception $_.Exception
            if($exp.GetType().Name -eq "SocketException") {
                throw New-Object System.InvalidOperationException "Failed to connect to IP $($ip) port $($Port). [$($exp.GetType().Name)] $($exp.Message) (WinSock error $([Int32]$exp.SocketErrorCode) $($exp.SocketErrorCode))."
            }
            else {
                throw New-Object System.InvalidOperationException "Failed to connect to IP $($ip) port $($Port)."
            }
        }
        finally
        {
            if($null -ne $socket) {
                try {
                    $socket.Close() # FIN-ACK-FIN-ACK
                }
                catch {
                }
                $socket.Dispose()
            }
        }
    }
}