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

function Send-HttpProbe {
    [CmdletBinding()]
    param(
        [Switch][Parameter(Mandatory = $false, ParameterSetName = "SSL")]$UseSSL,
        [Switch][Parameter(Mandatory = $false, ParameterSetName = "SSL")]$NoSNI,
        [Switch][Parameter(Mandatory = $false)]$UseIPv4Only,
        [Int32][Parameter(Mandatory = $false)]$Port,
        [System.Security.Authentication.SslProtocols][Parameter(Mandatory = $false, ParameterSetName = "SSL")]$SslProtocol = [System.Security.Authentication.SslProtocols]::Tls12,
        [String][Parameter(Mandatory = $true)]$Hostname,
        [String][Parameter(Mandatory = $false)]$HttpHost,
        [String][Parameter(Mandatory = $false)]$Path = "/",
        [Switch]$UseExperimentalDnsClient
    )
    begin {
        if (-not $PSBoundParameters.ContainsKey("Port")) {
            if ($UseSSL.IsPresent -and $UseSSL) {
                $Port = 443
            }
            else {
                $Port = 80
            }
        }
        
        $temp = [System.IO.Path]::GetTempPath()
        $sslwarnfile = (Join-Path -Path $temp -ChildPath "ssltestcertwarn.log")
        if (-not $PSBoundParameters.ContainsKey("HttpHost")) {
            $HttpHost = $Hostname
        }

        function Get-InnerMostException {
            [CmdletBinding()]
            param(
                [Exception][Parameter(Mandatory = $true)]$Exception
            )
            process {
                $exp = $exception
                while ($null -ne $exp.InnerException) {
                    $exp = $exp.InnerException
                }
                return $exp
            }
        }

        function Invoke-SocketCleanup {
            [CmdletBinding()]
            param(
                [System.Net.Sockets.Socket][Parameter(Mandatory = $false)]$Socket,
                [System.Net.Sockets.NetworkStream][Parameter(Mandatory = $false)]$NetworkStream,
                [System.Net.Security.SslStream][Parameter(Mandatory = $false)]$SslStream
            )
            process {

                if ($null -ne $SslStream) {
                    $SslStream.Close()
                    $SslStream.Dispose()
                }

                if ($null -ne $NetworkStream) {
                    $NetworkStream.Close()
                    $NetworkStream.Dispose()
                }

                if ($null -ne $Socket) {
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
                [object][Parameter(Mandatory = $true)]$NetworkStream,
                [Byte[]][Parameter(Mandatory = $true)]$Buffer,
                [Int32][Parameter(Mandatory = $true)]$Offset,
                [Int32][Parameter(Mandatory = $true)]$Length
            )
            if ($NetworkStream.GetType().Name -eq "SslStream") {
                return ([System.Net.Security.SslStream]$NetworkStream).Read($Buffer, $Offset, $Length)
            }
            elseif ($NetworkStream.GetType().Name -eq "Socket") {
                return ([System.Net.Sockets.Socket]$NetworkStream).Receive($Buffer, $Offset, $Length, ([System.Net.Sockets.SocketFlags]::None))
            }
        }

        function Send-ToNetworkStream {
            [CmdletBinding()]
            param(
                [object][Parameter(Mandatory = $true)]$NetworkStream,
                [Byte[]][Parameter(Mandatory = $true)]$Buffer
            )
            if ($NetworkStream.GetType().Name -eq "SslStream") {
                return ([System.Net.Security.SslStream]$NetworkStream).Write($Buffer)
            }
            elseif ($NetworkStream.GetType().Name -eq "Socket") {
                return ([System.Net.Sockets.Socket]$NetworkStream).Send($Buffer)
            }
        }

        function Get-IndexOfLineBreak {
            [CmdletBinding()]
            param(
                [Byte[]][Parameter(Mandatory = $true)]$Buffer,
                [Int32][Parameter(Mandatory = $true)]$BytesRead,
                [Switch]$DoubleLineBreak
            )
            process {
                $returnValue = -1
                $min = [Math]::Min($Buffer.Length, $BytesRead) - 1

                for ($i = 0; $i -lt $min; $i++) {
                    if ($Buffer[$i] -eq 13 -and $Buffer[$i + 1] -eq 10) {
                        if($DoubleLineBreak.IsPresent -and $DoubleLineBreak) {
                            if($i -lt ([Math]::Min($Buffer.Length, $BytesRead) - 3)) {
                                if($Buffer[$i + 2] -eq 13 -and $Buffer[$i + 3] -eq 10) {
                                    $returnValue = $i
                                    break
                                }
                            }
                        }
                        else {
                            $returnValue = $i
                            break
                        }
                    }
                }
                return $returnValue
            }
        }

        function Add-ToExistingBuffer {
            [CmdletBinding()]
            param (
                [Byte[]][Parameter()]$OldValue,
                [Byte[]][Parameter()]$NewValue,
                [Int64][Parameter(Mandatory)]$BytesRead
            )
            begin {
                $oldLength = $(if($null -eq $OldValue -or $OldValue.Length -eq 0) { 0 } else { $OldValue.Length })
                $newValueLength = $(if($null -eq $NewValue -or $NewValue.Length -eq 0) { 0 } else { $NewValue.Length })
                $addValue = [Math]::Min($newValueLength, $BytesRead)
                $totalValue = $oldLength + $addValue
                $resultValue = [System.Byte[]]::new($totalValue)

                if($oldLength -gt 0) {
                    [Array]::Copy($OldValue, 0, $resultValue, 0, $OldValue.Length)
                }

                [Array]::Copy($NewValue, 0, $resultValue, $oldLength, $addValue)
                $resultValue
            }
        }

        function Get-HttpResponse {
            [CmdletBinding()]
            param (
                [object][Parameter(Mandatory)]$NetworkStream
            )
            begin {
                $bufferSize = 1024 * 4;
                $buffer = [System.Byte[]]::new($bufferSize)
                $headerBreakIdx = -1
                [System.Byte[]]$fullHeaderBuffer = $null
                # Read until HTTP headers are done
                while($headerBreakIdx -lt 0) {
                    $read = Get-FromNetworkSteam -NetworkStream $NetworkStream -Buffer $buffer -Offset 0 -Length $bufferSize

                    if($read -eq 0) {
                        throw [InvalidOperationException]::new("Socket was disconnected.")
                    }
                    else {
                        $fullHeaderBuffer = Add-ToExistingBuffer -OldValue $fullHeaderBuffer -NewValue $buffer -BytesRead $read
                        $headerBreakIdx = Get-IndexOfLineBreak -Buffer $fullHeaderBuffer -BytesRead $read -DoubleLineBreak
                    }
                }

                $headerString = [Text.Encoding]::UTF8.GetString($fullHeaderBuffer, 0, $headerBreakIdx)
                $headerSplit = $headerString.Split("`r`n", ([StringSplitOptions]::RemoveEmptyEntries -bor [StringSplitOptions]::TrimEntries));
                $resultValue = [System.Collections.Generic.List[String]]::new()
                $resultValue.Add("{")

                (0 .. ($headerSplit.Length - 1)) | ForEach-Object {

                    if($_ -eq 0) {
                        $statusDescriptionSplit = $headerSplit[$_].Split(' ', 3)
                        if($statusDescriptionSplit.Length -eq 3) {
                            $resultValue.Add("`"StatusCode`":`"$($statusDescriptionSplit[1])`"")
                            $resultValue.Add(",`"StatusDescription`":`"$($statusDescriptionSplit[2])`"")
                        }
                        else {
                            throw [InvalidOperationException]::new("Cannot parse HTTP response in the status line.")
                        }
                    } else {
                        if($_ -eq 1) {
                            $resultValue.Add(",`"Headers`":[")
                        }
                        elseif($_ -gt 1) {
                            $resultValue.Add(",")
                        }
                        $headerSplitSplit = $headerSplit[$_].Split(": ", 2, ([StringSplitOptions]::RemoveEmptyEntries -bor [StringSplitOptions]::TrimEntries))

                        if($headerSplitSplit.Length -lt 2) {
                            throw [InvalidOperationException]::new("Cannot parse HTTP header $($headerSplit[$_]).")
                        }
                        # Watch out for repeating header values :)
                        $resultValue.Add("{`"$($headerSplitSplit[0])`":`"$($headerSplitSplit[1])`"}")

                        if($_ -eq $headerSplit.Length - 1) {
                            $resultValue.Add("]")
                        }
                    }
                }

                $resultValue.Add("}")
                $output = ($resultValue -join [String]::Empty) | ConvertFrom-Json
                $output
            }
        }

        function Get-BufferAsString {
            [CmdletBinding()]
            param(
                [Byte[]][Parameter(Mandatory = $true)]$Buffer,
                [Int32][Parameter(Mandatory = $true)]$Length
            )
            begin {
                if ($null -eq $Buffer) {
                    return $null
                }
                if ($Buffer.Length -eq 0) {
                    return [String]::Empty
                }
                return [Text.Encoding]::UTF8.GetString($Buffer, 0, $Length)
            }
            process {
            }
        }

        function Get-DnsServers {
            [CmdletBinding()]
            param (
            )
            begin {
                $progP = $ProgressPreference
                $ProgressPreference = "SilentlyContinue"

                [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() `
                | Where-Object { $_.OperationalStatus -eq "Up" -and $_.Description -notlike "*Loopback*" } `
                | ForEach-Object { $_.GetIPProperties() } `
                | Where-Object { $_.IsDnsEnabled -or $_.IsDynamicDnsEnabled } `
                | ForEach-Object { $_.DnsAddresses } `
                | Select-Object -Unique
            }
            process {
            }
            end {
                $ProgressPreference = $progP
            }
        }

        function Get-DnsQTypeString {
            [CmdletBinding()]
            param (
                [Int16][Parameter(Mandatory)]$QType
            )
            begin {
                switch ($QType) {
                      1 { "A (Host Address)"; break }
                      2 { "NS (Authoritative Name Server)"; break }
                      3 { "MD (Mail Destination)"; break }
                      4 { "MF (Mail Forwarder)"; break }
                      5 { "CNAME (Canonical Name)"; break }
                      6 { "SOA (Start of Zone of Authority)"; break }
                      7 { "MB (Mailbox Domain Name)"; break }
                      8 { "MG (Mail Group Member)"; break }
                      9 { "MR (Mail Group Member)"; break }
                     10 { "NULL (NULL RR)"; break }
                     11 { "WKS (Well-known Service Description)"; break }
                     12 { "PTR (Domain Name Pointer)"; break }
                     13 { "HINFO (Host Information)"; break }
                     14 { "MINFO (Mailbox or Mail List Information)"; break }
                     15 { "MX (Mail Exchange)"; break }
                     16 { "TXT (Text Strings)"; break }
                     28 { "AAAA (IPv6 Host Address)"; break }
                    252 { "AXFR (Full Zone Tranfer Request)"; break }
                    253 { "MAILB (Mailbox-related Record Request)"; break }
                    254 { "MAILA (Mail Agent RRs Request)"; break }
                    255 { "* (All Records Request)"; break }
                    Default {}
                }
            }
            process {

            }
            end {

            }
        }

        function Get-DnsQClassString {
            [CmdletBinding()]
            param (
                [Int16][Parameter(Mandatory)]$QClass
            )
            begin {
                switch ($QClass) {
                      1 { "IN (Internet)"; break }
                      2 { "CS (CSNET Class)"; break }
                      3 { "CH (CHAOS Class)"; break }
                      4 { "HS (Hesiod [Dyer 87])"; break }
                    Default {}
                }
            }
            process {

            }
            end {

            }
        }

        function Read-BufferAsUInt16 {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)][Byte[]]$Buffer,
                [Parameter(Mandatory)]$Offset
            )
            begin {
                if($null -eq $Buffer -or $Buffer.Length -eq 0) {
                    throw [System.ArgumentNullException]::new("Buffer", "Buffer is empty.")
                }
                if($Offset -ge $Buffer.Length - 1) {
                    throw [System.ArgumentOutOfRangeException]::new("Offset", `
                    "Offset cannot exceed Buffer's Length - 1 as two bytes are needed for an Int16")
                }
    
                return (([UInt16]$Buffer[$Offset]) -shl 8) + [UInt16]$Buffer[$Offset + 1]
            }
            process {

            }
            end {

            }
        }

        function Read-BufferAsUInt32 {
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory)][Byte[]]$Buffer,
                [Parameter(Mandatory)]$Offset
            )
            begin {
                if($null -eq $Buffer -or $Buffer.Length -eq 0) {
                    throw [System.ArgumentNullException]::new("Buffer", "Buffer is empty.")
                }
                if($Offset -ge $Buffer.Length - 3) {
                    throw [System.ArgumentOutOfRangeException]::new("Offset", `
                    "Offset cannot exceed Buffer's Length - 3 as four bytes are needed for an Int16")
                }
    
                return (([UInt32]$Buffer[$Offset]) -shl 24) + `
                    (([UInt32]$Buffer[$Offset + 1]) -shl 24) + `
                    (([UInt32]$Buffer[$Offset + 2]) -shl 8) + `
                    [UInt32]$Buffer[$Offset + 3]
            }
            process {

            }
            end {

            }
        }

        function Get-DnsHeader {
            [CmdletBinding()]
            param (
                [Byte[]]$Buffer
            )
            begin {
                if ($Buffer.Length -lt 12) {
                    ("{`"FullHeaderRead`":false}" | ConvertFrom-Json)
                    return
                }
                else {
                    $queryId = "{0:x2}{1:x2}" -f @($Buffer[0], $Buffer[1])

                    $flags1 = $Buffer[2]
                    $flags2 = $Buffer[3]
                    $questions = (([Int16]$Buffer[4]) -shl 8) + [Int16]$Buffer[5]
                    $answers = (([Int16]$Buffer[6]) -shl 8) + [Int16]$Buffer[7]
                    $nameServers = (([Int16]$Buffer[8]) -shl 8) + [Int16]$Buffer[9]
                    $additionalRecords = (([Int16]$Buffer[10]) -shl 8) + [Int16]$Buffer[11]
                    
                    $queryTypeBit = (($flags1 -shr 7) -band 1)
                    $queryType = @(if ($queryTypeBit -eq 0x01) { "DNSResponse" } else { "DNSQuery" })

                    $opCodeI4 = (($flags1) -shr 3) -band 0xF
                    $opCode = ""
                    if ($opCodeI4 -eq 0) {
                        $opCode = "StandardQuery"
                    }
                    elseif ($opCodeI4 -eq 1) {
                        $opCode = "InverseQuery"
                    }
                    elseif ($opCodeI4 -eq 2) {
                        $opCode = "ServerStatus"
                    }

                    $aaBit = (($flags1 -shr 2) -band 1)
                    $aaStr = @(if ($aaBit -eq 0x01) { "true" } else { "false" })

                    $tcBit = (($flags1 -shr 1) -band 1)
                    $tcStr = @(if ($tcBit -eq 0x01) { "true" } else { "false" })

                    $rdBit = ($flags1 -band 1)
                    $rdStr = @(if ($rdBit -eq 0x01) { "true" } else { "false" })

                    $raBit = (($flags2 -shr 7) -band 1)
                    $raStr = @(if ($raBit -eq 0x01) { "true" } else { "false" })

                    # I may be missing Answer Authenticated and Non-authenticated data bits as my RFC states the next 3 bits are reserved but network trace suggests otherwise

                    $rcode = ($flags2 -band 0xF)
                    $rcodestring = ""

                    if ($rcode -eq 0) {
                        $rcodestring = "Succeeded"
                    }
                    elseif ($rcode -eq 1) {
                        $rcodestring = "FormatError"
                    }
                    elseif ($rcode -eq 2) {
                        $rcodestring = "ServerFailure"
                    }
                    elseif ($rcode -eq 3) {
                        $rcodestring = "NameError"
                    }
                    elseif ($rcode -eq 4) {
                        $rcodestring = "NotImplemented"
                    }
                    elseif ($rcode -eq 5) {
                        $rcodestring = "Refused"
                    }
                    elseif ($rcode -eq 6) {
                        $rcodestring = "XYDomain"
                    }
                    elseif ($rcode -eq 7) {
                        $rcodestring = "XYRRSet"
                    }
                    elseif ($rcode -eq 8) {
                        $rcodestring = "NXRRSet"
                    }
                    elseif ($rcode -eq 9) {
                        $rcodestring = "NotAuth"
                    }
                    elseif ($rcode -eq 10) {
                        $rcodestring = "NotZone"
                    }

                    @(
                        "{`"FullHeaderRead`": true"
                        , ", `"QueryID`":`"$($queryId)`""
                        , ", `"QueryType`":`"$($queryType)`""
                        , ", `"OpCode`":`"$($opCode)`""
                        , ", `"IsAuthoritative`":$($aaStr)"
                        , ", `"IsTruncated`":$($tcStr)"
                        , ", `"RecursionDesired`":$($rdStr)"
                        , ", `"RecursionAvailable`":$($raStr)"
                        , ", `"ResponseCode`":$($rcode)"
                        , ", `"ResponseMessage`":`"$($rcodestring)`""
                        , ", `"Questions`":$($questions)"
                        , ", `"Answers`":$($answers)"
                        , ", `"NameServers`":$($nameServers)"
                        , ", `"AdditionalRecords`":$($additionalRecords)"
                        , "}"
                    ) | ConvertFrom-Json
                }
            }
        }

        function Get-DnsString {
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory)][Byte[]]$Buffer,
                [Parameter(Mandatory)][UInt16]$Offset,
                [Parameter()][UInt16]$MaxLength,
                [Switch]$IsRecursion
            )
            begin 
            {
                $bIsRecursion = $IsRecursion.IsPresent -and $IsRecursion
                
                if($null -eq $Buffer -or $Buffer.Length -eq 0) {
                    throw [System.ArgumentNullException]::new("Buffer", "Buffer is empty.")
                }
                if($Offset -ge $Buffer.Length) {
                    throw [System.ArgumentOutOfRangeException]::new("Offset", `
                    "Offset cannot exceed Buffer's Length")
                }
                if($PSBoundParameters.ContainsKey("MaxLength") -and ($Offset + $MaxLength) -gt $Buffer.Length) {
                    throw [System.ArgumentOutOfRangeException]::new("Offset", `
                    "Offset + MaxLength exceed Buffer's Length")
                }

                $bytesRead = 0
                $currentOffset = $Offset
                $currentString = [system.Collections.Generic.List[String]]::new()

                while(
                    !$PSBoundParameters.ContainsKey("MaxLength") `
                    -or ($bytesRead -lt $MaxLength) `
                    -or ($currentOffset -lt $Buffer.Length) `
                )
                {
                    if($currentOffset -lt $Buffer.Length) {
                        $nextLength = $Buffer[$currentOffset]
                        if(($nextLength -band 0xc0) -eq 0xc0) {
                            if($currentOffset -lt $Buffer.Length- 1) {
                                # This is a pointer, (the first two bits are '1'), read the next 14 to determine the address and recurse
                                $nextInt16 = Read-BufferAsUInt16 -Buffer $Buffer -Offset $currentOffset
                                $newOffset = $nextInt16 -band 0x03FF
                                $innerString = (Get-DnsString -Buffer $Buffer -Offset $newOffset -IsRecursion)
                                $currentString.Add($innerString.Value)
                                $currentOffset += 2
                                $bytesRead += 2
                                $returnString = $currentString -join "."
                                if($bIsRecursion) {
                                    $returnJson = "{`"Value`":`"$returnString`",`"NewOffset`":0}"
                                }
                                else {
                                    if(!$bIsRecursion -and $returnString.StartsWith(".")) {
                                        $returnString = $returnString.Substring(1)
                                    }
                                    $returnJson = "{`"Value`":`"$returnString`",`"NewOffset`":$currentOffset}"
                                }
        
                                $returnJson | ConvertFrom-Json
                                return
                            }
                        }
                        elseif($nextLength -eq 0) {
                            # We are finished.
                            $currentOffset++
                            $bytesRead++
                            $returnString = $currentString -join "."
                            $returnJson = "{}"
                            if($bIsRecursion) {
                                $returnJson = "{`"Value`":`"$returnString`",`"NewOffset`":0}"
                            }
                            else {
                                if(!$bIsRecursion -and $returnString.StartsWith(".")) {
                                    $returnString = $returnString.Substring(1)
                                }
                                $returnJson = "{`"Value`":`"$returnString`",`"NewOffset`":$currentOffset}"
                            }

                            $returnJson | ConvertFrom-Json
                            return
                        }
                        else {
                            # Read Next Length as UTF-8
                            $currentString.Add([Text.Encoding]::UTF8.GetString($Buffer, $currentOffset + 1, $nextLength))
                            $currentOffset = $currentOffset + 1 + $nextLength
                            $bytesRead = $bytesRead + 1 + $nextLength
                        }
                    }
                }
            }
            process {

            }
            end {

            }
        }

        function Resolve-DnsNameExt {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory)][String]$Name,
                [Parameter()][System.Net.IPAddress]$Server,
                [Switch]$UseIPv4Only
            )
            begin {
                [System.Net.Sockets.Socket]$socket = $null
                $needsRecursion = (-not $UseIPv4Only.IsPresent) -or (-not $UseIPv4Only)

                if ($PSBoundParameters.ContainsKey("Server")) {
                    $ServerArray = @([System.Net.IPAddress]::Parse($Server))
                }
                else {
                    $servers = Get-DnsServers
                    $ServerArray = $null
                    if ($servers.GetType().FullName -eq "System.String") {
                        $ServerArray = @([System.Net.IPAddress]::Parse($servers))
                    }
                    else {
                        $ServerArray = $servers | ForEach-Object { try { [System.Net.IPAddress]::Parse($_)} catch {} }
                    }

                    if ($null -eq $ServerArray -or $ServerArray.Count -eq 0) {
                        throw [System.InvalidOperationException]::new("No available DNS server to use. Please specify a Server argument.")
                        return
                    }
                }

                [String[]]$Split = $Name.Split(".")
                [System.IO.MemoryStream]$converter = [System.IO.MemoryStream]::new($Name.Length)
                [Byte[]]$NameInBytes = $Null
                try {
                    $Split | ForEach-Object {
                        $converter.WriteByte([Byte]$_.Length)
                        $labelAsBytes = [System.Text.Encoding]::UTF8.GetBytes($_)
                        $labelAsByteCount = [System.Text.Encoding]::UTF8.GetByteCount($_)
                        $converter.Write($labelAsBytes, 0, $labelAsByteCount)
                    }
                    $NameInBytes = $converter.ToArray()
                }
                finally {
                    if ($null -ne $converter) {
                        $converter.Close()
                        $converter.Dispose()
                    }
                }

                [System.Collections.Generic.List[String]]$dnsResult = [System.Collections.Generic.List[String]]::new()

                foreach ($PServer in $ServerArray) {

                    $dnsresult.Clear()
                    $dnsresult.Add("{`"RemoteAddress`":`"$PServer`"")

                    $addressFamily = $PServer.AddressFamily
                    [System.Net.Sockets.SocketType]$socketType = [System.Net.Sockets.SocketType]::Dgram
                    [System.Net.Sockets.ProtocolType]$protocolType = [System.Net.Sockets.ProtocolType]::Udp

                    $wms = [System.IO.MemoryStream]::new()

                    try {
                    
                        $random = [System.Random]::new()
                        [Byte[]]$ID = [Byte[]]::new(2)
                        $random.NextBytes($ID)

                        $wms.Write($ID, 0, 2) # DNS ID
                        # Flags: QR == 0 (Query), OPCODE == 0000 (Standard Query), AA = 0 N/A,
                        # Flags: TC = 0 (Not-truncated, for now), RD == 1 Recurse, RA = 0 N/A, Z = 0000, RCODE = 0000
                        $wms.Write(@(0x01, 0x00), 0, 2)
                        $wms.Write(@(0x00, 0x01), 0, 2) # No. Questions
                        $wms.Write(@(0x00, 0x00), 0, 2) # No. Answer RR
                        $wms.Write(@(0x00, 0x00), 0, 2) # No. Authority RR
                        $wms.Write(@(0x00, 0x00), 0, 2) # No. Additional RR

                        $wms.Write($NameInBytes, 0, $NameInBytes.Length) # Query Name
                        $wms.WriteByte(0x00) # Null Character

                        if ($UseIPv4Only) {
                            $wms.Write(@(0x00, 0x01), 0, 2) # QueryType: A
                        }
                        else {
                            $wms.Write(@(0x00, 0x1c), 0, 2) # QueryType: AAAA
                        }

                        $wms.Write(@(0x00, 0x01), 0, 2) # QueryType: IN

                        $dnsQuery = $wms.ToArray()

                        if ($dnsQuery.Length -gt 512) {
                            # Switch to TCP and hope the DNS Server supports it, otherwise, we're going to have to send the message truncated
                            $socketType = [System.Net.Sockets.SocketType]::Stream
                            $protocolType = [System.Net.Sockets.ProtocolType]::Tcp
                        }

                        $dnsresult.Add(",`"Protocol`":`"$protocolType`"")

                        $socket = [System.Net.Sockets.Socket]::new($addressFamily, $socketType, $protocolType)
                        try {
                            $socket.ReceiveTimeout = 5000
                            $socket.SendTimeout = 5000
                            try {
                                $socket.Connect([System.Net.IPEndPoint]::new($PServer, 53))
                            }
                            catch {
                                $exp = Get-InnerMostException -Exception $_.Exception
                                $dnsresult.Add(",`"LocalAddress`":`"$($socket.LocalEndPoint.Address)`"")
                                $dnsresult.Add(",`"LocalPort`":$($socket.LocalEndPoint.Port)")
                                $dnsresult.Add(",`"RemotePort`":$($socket.RemoteEndPoint.Port)")
                                $dnsresult.Add(",`"Result`":`"Failed`"")
                                $dnsresult.Add(",`"ResponseCode`":0")
                                $dnsresult.Add(",`"ResponseMessage`":null")

                                if ($exp.GetType().FullName -eq "System.Net.Sockets.SocketException") {
                                    $dnsresult.Add(",`"ErrorMessage`":`"Connection Failed. WinSock error code: $([Int32]$exp.SocketErrorCode)`"")
                                }
                                else {
                                    $dnsresult.Add(",`"ErrorMessage`":`"$([Int32]$exp.Message)`"")
                                }
                                $dnsResult.Add("}")
                                ($dnsResult -join [String]::Empty) | ConvertFrom-Json
                                continue
                            }
                            try {
                                $socket.Send($dnsQuery, 0, $dnsQuery.Length, [System.Net.Sockets.SocketFlags]::None) | Out-Null
                            }
                            catch {
                                $exp = Get-InnerMostException -Exception $_.Exception
                                $dnsresult.Add(",`"LocalAddress`":`"$($socket.LocalEndPoint.Address)`"")
                                $dnsresult.Add(",`"LocalPort`":$($socket.LocalEndPoint.Port)")
                                $dnsresult.Add(",`"RemotePort`":$($socket.RemoteEndPoint.Port)")
                                $dnsresult.Add(",`"Result`":`"Failed`"")
                                $dnsresult.Add(",`"ResponseCode`":0")
                                $dnsresult.Add(",`"ResponseMessage`":null")
                                if ($exp.GetType().FullName -eq "System.Net.Sockets.SocketException") {
                                    $dnsresult.Add(",`"ErrorMessage`":`"Could not send DNS query. WinSock error code: $([Int32]$exp.SocketErrorCode)`"")
                                }
                                else {
                                    $dnsresult.Add(",`"ErrorMessage`":`"$([Int32]$exp.Message)`"")
                                }
                                $dnsResult.Add("}")
                                ($dnsResult -join [String]::Empty) | ConvertFrom-Json
                                continue
                            }
                            $receiveBuffer = [byte[]]::new(512)
                            $responseHeader = $null
                            try {
                                $socket.Receive($receiveBuffer, 0, 512, [System.Net.Sockets.SocketFlags]::None) | Out-Null
                                $responseHeader = Get-DnsHeader -Buffer $receiveBuffer
                                while(-not $responseHeader.FullHeaderRead) {
                                    $socket.Receive($receiveBuffer, 0, 512, [System.Net.Sockets.SocketFlags]::None) | Out-Null # Watch it, this isn't an append
                                    $responseHeader = Get-DnsHeader -Buffer $receiveBuffer
                                }
                            }
                            catch {
                                $exp = Get-InnerMostException -Exception $_.Exception
                                $dnsresult.Add(",`"LocalAddress`":`"$($socket.LocalEndPoint.Address)`"")
                                $dnsresult.Add(",`"LocalPort`":$($socket.LocalEndPoint.Port)")
                                $dnsresult.Add(",`"RemotePort`":$($socket.RemoteEndPoint.Port)")
                                $dnsresult.Add(",`"Result`":`"Failed`"")
                                $dnsresult.Add(",`"ResponseCode`":0")
                                $dnsresult.Add(",`"ResponseMessage`":null")
                                if ($exp.GetType().FullName -eq "System.Net.Sockets.SocketException") {
                                    $dnsresult.Add(",`"ErrorMessage`":`"Did not get a query response. WinSock error code: $([Int32]$exp.SocketErrorCode)`"")
                                }
                                else {
                                    $dnsresult.Add(",`"ErrorMessage`":`"$([Int32]$exp.Message)`"")
                                }
                                $dnsResult.Add("}")
                                ($dnsResult -join [String]::Empty) | ConvertFrom-Json
                                continue
                            }

                            try {
                                $dnsresult.Add(",`"LocalAddress`":`"$($socket.LocalEndPoint.Address)`"")
                                $dnsresult.Add(",`"LocalPort`":$($socket.LocalEndPoint.Port)")
                                $dnsresult.Add(",`"RemotePort`":$($socket.RemoteEndPoint.Port)")

                                if ($responseHeader.ResponseCode -gt 0) {
                                    $dnsresult.Add(",`"Result`":`"Failed`"")
                                }
                                else {
                                    $dnsresult.Add(",`"Result`":`"Succeeded`"")
                                }
                                $dnsresult.Add(",`"ResponseCode`":$($responseHeader.ResponseCode)")
                                $dnsresult.Add(",`"ResponseMessage`":`"$($responseHeader.ResponseMessage)`"")
                                $dnsresult.Add(",`"QueryID`":`"$($responseHeader.QueryID)`"")
                                $dnsresult.Add(",`"QueryType`":`"$($responseHeader.QueryType)`"")
                                $dnsresult.Add(",`"OpCode`":`"$($responseHeader.OpCode)`"")
                                $dnsresult.Add(",`"IsAuthoritative`":$($responseHeader.IsAuthoritative | ConvertTo-Json)")
                                $dnsresult.Add(",`"IsTruncated`":$($responseHeader.IsTruncated | ConvertTo-Json)")
                                $dnsresult.Add(",`"RecursionDesired`":$($responseHeader.RecursionDesired | ConvertTo-Json)")
                                $dnsresult.Add(",`"RecursionAvailable`":$($responseHeader.RecursionAvailable | ConvertTo-Json)")
                                $dnsresult.Add(",`"Questions`":[")
                                $currIdx = 12

                                for($i = 0; $i -lt $responseHeader.Questions; $i++) {
                                    if($i -gt 0) {
                                        $dnsresult.Add(",")    
                                    }
                                    $dnsresult.Add("{")

                                    $dnsString = Get-DnsString -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx = $dnsString.NewOffset
                                    $queryName = $dnsString.Value

                                    $queryType = Read-BufferAsUInt16 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 2

                                    $queryClass = Read-BufferAsUInt16 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 2

                                    $dnsresult.Add("`"QueryName`":`"$queryName`"")
                                    $dnsresult.Add(",`"QueryType`":`"$((Get-DnsQTypeString -QType $queryType))`"")
                                    $dnsresult.Add(",`"QueryClass`":`"$((Get-DnsQClassString -QClass $queryClass))`"")
                                    $dnsresult.Add("}")
                                }
                                
                                $dnsresult.Add("],`"Answers`":[")
                                
                                for($i = 0; $i -lt $responseHeader.Answers; $i++) {
                                    if($i -gt 0) {
                                        $dnsresult.Add(",")    
                                    }
                                    $dnsresult.Add("{")

                                    $dnsString = Get-DnsString -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx = $dnsString.NewOffset
                                    $answerName = $dnsString.Value

                                    $answerType = Read-BufferAsUInt16 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 2

                                    $answerClass = Read-BufferAsUInt16 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 2

                                    $answerTtl = Read-BufferAsUInt32 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 4

                                    $dataLength = Read-BufferAsUInt16 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 2
                                    
                                    $dnsresult.Add("`"Name`":`"$answerName`"")
                                    $dnsresult.Add(",`"Type`":`"$((Get-DnsQTypeString -QType $answerType))`"")
                                    $dnsresult.Add(",`"Class`":`"$((Get-DnsQClassString -QClass $answerClass))`"")
                                    $dnsresult.Add(",`"TTL`":$answerTtl")

                                    if($answerType -eq 1) { # A Record
                                        if(($currIdx + $dataLength) -lt $receiveBuffer.Length) {
                                            $octet1 = [Byte]$receiveBuffer[$currIdx]
                                            $octet2 = [Byte]$receiveBuffer[$currIdx+1]
                                            $octet3 = [Byte]$receiveBuffer[$currIdx+2]
                                            $octet4 = [Byte]$receiveBuffer[$currIdx+3]
                                            $dnsresult.Add(",`"IPAddress`":`"$octet1.$octet2.$octet3.$octet4`"")
                                        }
                                    }
                                    elseif($answerType -eq 5) { # CNAME Record
                                        $dnsString = Get-DnsString -Buffer $receiveBuffer -Offset $currIdx -MaxLength $dataLength
                                        $answerCname = $dnsString.Value
                                        $dnsresult.Add(",`"Host`":`"$answerCname`"")
                                    }
                                    elseif($answerType -eq 28) { # AAAA Record
                                        if(($currIdx + $dataLength) -lt $receiveBuffer.Length) {
                                            $ipv6str = "{0:x2}{1:x2}" -f @($receiveBuffer[$currIdx], $receiveBuffer[$currIdx+1])
                                            $ipv6str += ":{0:x2}{1:x2}" -f @($receiveBuffer[$currIdx+2], $receiveBuffer[$currIdx+3])
                                            $ipv6str += ":{0:x2}{1:x2}" -f @($receiveBuffer[$currIdx+4], $receiveBuffer[$currIdx+5])
                                            $ipv6str += ":{0:x2}{1:x2}" -f @($receiveBuffer[$currIdx+6], $receiveBuffer[$currIdx+7])
                                            $ipv6str += ":{0:x2}{1:x2}" -f @($receiveBuffer[$currIdx+8], $receiveBuffer[$currIdx+9])
                                            $ipv6str += ":{0:x2}{1:x2}" -f @($receiveBuffer[$currIdx+10], $receiveBuffer[$currIdx+11])
                                            $ipv6str += ":{0:x2}{1:x2}" -f @($receiveBuffer[$currIdx+12], $receiveBuffer[$currIdx+13])
                                            $ipv6str += ":{0:x2}{1:x2}" -f @($receiveBuffer[$currIdx+14], $receiveBuffer[$currIdx+15])
                                            $dnsresult.Add(",`"IPAddress`":`"$([System.Net.IPAddress]::Parse($ipv6str))`"")
                                        }                                           
                                    }
                                    else {
                                    }
                                    $currIdx+=$dataLength
                                    $dnsresult.Add("}")
                                }

                                
                                $dnsresult.Add("],`"AuthoritativeNameServers`":[")

                                for($i = 0; $i -lt $responseHeader.NameServers; $i++) {
                                    if($i -gt 0) {
                                        $dnsresult.Add(",")    
                                    }
                                    $dnsresult.Add("{")

                                    $dnsString = Get-DnsString -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx = $dnsString.NewOffset
                                    $authNSName = $dnsString.Value

                                    $authNSType = Read-BufferAsUInt16 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 2

                                    $authNSClass = Read-BufferAsUInt16 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 2

                                    $authNSTtl = Read-BufferAsUInt32 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 4

                                    $dataLength = Read-BufferAsUInt16 -Buffer $receiveBuffer -Offset $currIdx
                                    $currIdx += 2
                                    
                                    $dnsresult.Add("`"Name`":`"$authNSName`"")
                                    $dnsresult.Add(",`"Type`":`"$((Get-DnsQTypeString -QType $authNSType))`"")
                                    $dnsresult.Add(",`"Class`":`"$((Get-DnsQClassString -QClass $authNSClass))`"")
                                    $dnsresult.Add(",`"TTL`":$authNSTtl")

                                    if($authNSType -eq 6) {

                                        $dnsString = Get-DnsString -Buffer $receiveBuffer -Offset $currIdx
                                        $currIdx = $dnsString.NewOffset
                                        $soaMName = $dnsString.Value
                                        
                                        $dnsString = Get-DnsString -Buffer $receiveBuffer -Offset $currIdx
                                        $currIdx = $dnsString.NewOffset
                                        $soaRName = $dnsString.Value
                                        
                                        $soaSerial = Read-BufferAsUInt32 -Buffer $receiveBuffer -Offset $currIdx
                                        $currIdx += 4

                                        $soaRefresh = Read-BufferAsUInt32 -Buffer $receiveBuffer -Offset $currIdx
                                        $currIdx += 4

                                        $soaRetry = Read-BufferAsUInt32 -Buffer $receiveBuffer -Offset $currIdx
                                        $currIdx += 4

                                        $soaExpire = Read-BufferAsUInt32 -Buffer $receiveBuffer -Offset $currIdx
                                        $currIdx += 4

                                        $soaMinimum = Read-BufferAsUInt32 -Buffer $receiveBuffer -Offset $currIdx
                                        $currIdx += 4

                                        $dnsresult.Add(",`"PrimaryNameServer`":`"$soaMName`"")
                                        $dnsresult.Add(",`"ResponsibleAuthorityMailbox`":`"$soaRName`"")
                                        $dnsresult.Add(",`"SerialNumber`":$soaSerial")
                                        $dnsresult.Add(",`"RefreshInterval`":$soaRefresh")
                                        $dnsresult.Add(",`"RetryInterval`":$soaRetry")
                                        $dnsresult.Add(",`"ExpireLimit`":$soaExpire")
                                        $dnsresult.Add(",`"MinimumTTL`":$soaMinimum")
                                    }
                                    $currIdx += $dataLength
                                    $dnsresult.Add("}")
                                }
                                $dnsresult.Add("]")
                                break
                                #Ignore additional records
                            }
                            catch {
                            }
                            finally {
                                $dnsResult.Add("}")
                                $json = ($dnsResult -join [String]::Empty)
                                $json | ConvertFrom-Json
                            }
                        }
                        finally {
                            if ($null -ne $socket) {
                                if ($socket.Connected) {
                                    try { $socket.Close() } catch { }
                                }
            
                                $socket.Dispose()
                            }
                        }
                    }
                    finally {
                        if ($null -ne $mws) {
                            $wms.Close()
                            $wms.Dispose()
                        }
                    }
                }

                if ($needsRecursion) {
                    if($PSBoundParameters.ContainsKey("Server")) {
                        Resolve-DnsNameExt -Server $Server -Name $Name -UseIPv4Only
                    }
                    else {
                        Resolve-DnsNameExt -Name $Name -UseIPv4Only
                    }
                }
            }
            end {
                if ($null -ne $socket) {
                    if ($socket.Connected) {
                        try { $socket.Close() } catch { }
                    }

                    $socket.Dispose()
                }
            }
        }
    }
    process {

        #$test1Name = "DNS Resolution"
        #$test1Result = "Not Started"
        #$test1Output = ""

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
        #$test5Result = "Not Started"
        #$test5Output = "Either DNS resolution, TCP connection, SSL handshake or Web Request tests failed."

        $stop = $false
        $parsedip = [System.Net.IPAddress]::Any
        $hostNameIsIP = [System.Net.IPAddress]::TryParse($Hostname, [ref] $parsedip)

        $final = [Collections.ArrayList]::new()

        #Test 1: DNS
        $ips = $null

        if ($hostNameIsIP) {
            $ips = New-Object System.Collections.ArrayList
            $ips.Add($parsedip) | Out-Null

            $outObject = "{`"TestType`":`"DNS Resolution`",`"TestResult`":`"Skipped`",`"TestOutput`":`"No DNS resolution is needed for IP $($ips[0]).`"}" | ConvertFrom-Json
            $final.Add($outObject) | Out-Null

            if($ips -eq $null -or $ips.Count -eq 0) {
                $stop = $true
            }
        }
        else {
            if($UseExperimentalDnsClient.IsPresent -and $UseExperimentalDnsClient) {
                $output = Resolve-DnsNameExt -Name $Hostname -UseIPv4Only:$UseIPv4Only

                $ips = $output.Answers | Select-Object IPAddress
                $test1String = [Collections.Generic.List[String]]::new()
                $test1String.Add("{`"TestType`":`"DNS Resolution`"")
                if($null -eq $ips -or $ips.Count -eq 0) {
                    $test1String.Add(",`"TestResult`":`"Failed`"")
                    $stop = $true
                } 
                else {
                    $test1String.Add(",`"TestResult`":`"Succeeded`"")
                }
                $test1String.Add(",`"TestOutput`":[")
                $i = 1

                $output | ForEach-Object {
                    if($i -gt 1) {$test1String.Add(",")}
                    $i++
                    $test1String.Add("{`"DNSServer`":`"$($_.RemoteAddress)`"")
                    $test1String.Add(",`"Protocol`":`"$($_.Protocol)`"")
                    $test1String.Add(",`"LocalAddress`":`"$($_.LocalAddress)`"")
                    $test1String.Add(",`"LocalPort`":$($_.LocalPort)")
                    $test1String.Add(",`"ResponseCode`":`"$($_.ResponseCode)`"")
                    $test1String.Add(",`"ResponseMessage`":`"$($_.ResponseMessage)`"")
                    $test1String.Add(",`"QueryID`":`"$($_.QueryID)`"")
                    $test1String.Add(",`"IsAuthoritative`":$($_.IsAuthoritative | ConvertTo-Json)")
                    
                    $ipAnswers = $_.IPAddress;
                    #if($ipAnswers.Count -gt 0) { $test1String.Add(",`"Answers`":[$(($ipAnswers | ForEach-Object { [String]::Concat('"', $_,'"') } ) -join ",")]") }
                    if($ipAnswers.Count -gt 0) { $test1String.Add(",`"Answers`":$(($ipAnswers -join ","))`"") }

                    if($_.AuthoritativeNameServers.Count -gt 0) {
                        #$test1String.Add(",`"NameServers`":[$(($_.AuthoritativeNameServers.PrimaryNameServer | ForEach-Object { [String]::Concat('"', $_,'"') } ) -join ",")]")
                        $test1String.Add(",`"NameServers`":`"$(($_.AuthoritativeNameServers.PrimaryNameServer  -join ","))`"")
                    }
                    $test1String.Add("}")
                }
                $test1String.Add("]}")

                $final.Add(($test1String -join "" | ConvertFrom-Json)) | Out-Null
            }
            else {
                if ($UseIPv4Only.IsPresent -and $UseIPv4Only) {
                    $ips = Resolve-DnsName -Name $Hostname -Type A -ErrorAction SilentlyContinue
                }
                else {
                    $ips = Resolve-DnsName -Name $Hostname -Type A_AAAA -ErrorAction SilentlyContinue
                }

                if ($null -eq $ips) {
                    $outObject = "{`"TestType`":`"DNS Resolution`",`"TestResult`":`"Failed`",`"TestOutput`":`"Could not resolve DNS Name $($Hostname)`"}" | ConvertFrom-Json
                }
                else {
                    $outObject = "{`"TestType`":`"DNS Resolution`",`"TestResult`":`"Succeeded`",`"TestOutput`":`"Resolved $Hostname to the following IPs $([String]::Join(", ", ($ips | Where-Object { $null -ne $_.IPAddress } | ForEach-Object { $_.IPAddress })))`"}" | ConvertFrom-Json
                }
                $final.Add($outObject) | Out-Null
            }
        }

        if ($stop) {
            $final | Format-List
            return
        }

        #Test 2: Connectivity
        if ($hostNameIsIP) {
            $ip = $ips[0]
        }
        else {
            $ip = $ips | Where-Object { $null -ne $_.IPAddress } | Select-Object -First 1 | ForEach-Object { [System.Net.IPAddress]::Parse($_.IPAddress) }
        }
        $socket = New-Object System.Net.Sockets.Socket $ip.AddressFamily, ([System.Net.Sockets.SocketType]::Stream), ([System.Net.Sockets.ProtocolType]::Tcp)
        $ipendpoint = New-Object System.Net.IPEndPoint($ip, $Port)
        try {
            $socket.Connect($ipendpoint) | Out-Null
            $test2Result = "Succeeded"
            if ($ip.AddressFamily -eq ([System.Net.Sockets.AddressFamily]::InterNetworkV6)) {
                $test2Output = "Connected from [$($socket.LocalEndPoint.Address)]:$($socket.LocalEndPoint.Port) to [$($ip)]:$($Port)"
            }
            else {
                $test2Output = "Connected from $($socket.LocalEndPoint.Address):$($socket.LocalEndPoint.Port) to $($ip):$($Port)"
            }
        }
        catch {
            $stop = $true
            $exp = Get-InnerMostException -Exception $_.Exception
            $test2Result = "Failed"
            if ($exp.GetType().Name -eq "SocketException") {
                $test2Output = "[$($exp.GetType().Name)] $($exp.Message) (WinSock error $($exp.SocketErrorCode))."
            }
            else {
                $test2Output = "[$($exp.GetType().Name)] $($exp.Message)."
            }
        }

        $final.Add(([PSCustomObject]@(
            [PSCustomObject]@{
                TestType   = $test2Name
                TestResult = $test2Result
                TestOutput = $test2Output
            }
        ))) | Out-Null

        if ($stop) {
            if ($null -ne $socket) {
                Invoke-SocketCleanup -Socket $socket -NetworkStream $null -SslStream $null
            }
            $final | Format-List
            return
        }

        #Test 3: SSL Handshake

        if ($UseSSL.IsPresent -and $UseSSL) {
            $sslHost = $Hostname
            if ($NoSNI.IsPresent -and $NoSNI) {
                $sslHost = $ip.ToString()
            }
        
            $netStream = New-Object System.Net.Sockets.NetworkStream $socket
            $remoteCallback = $null
            $certificates = New-Object System.Security.Cryptography.X509Certificates.X509CertificateCollection

            if ($NoSNI.IsPresent -and $NoSNI) {
                $remoteCallback = {
                    param(
                        [object]$theSender,
                        [System.Security.Cryptography.X509Certificates.X509Certificate]$certificate,
                        [System.Security.Cryptography.X509Certificates.X509Chain]$chain,
                        [System.Net.Security.SslPolicyErrors]$sslPolicyErrors
                    )
                    if ($sslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::None -or $sslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) {
                        if ($sslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) {
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
                if (Test-Path -Path $sslwarnfile ) {
                    Remove-Item -Path $sslwarnfile | Out-Null
                    $test3Result = "Warning"
                    $test3Output = "Using -NoSNI will always result in a failed certificate validation. Will correct this script in the future. Cert info: Thumbprint => $($cert.Thumbprint); Subject $($cert.SubjectName)."
                }
                else {
                    $test3Result = "Succeeded"
                    $test3Output = "SSL Handshake was successful. Cert info: Thumbprint => $($cert.Thumbprint); Subject $($cert.Subject)."
                }
            }
            catch {
                $stop = $true
                $exp = Get-InnerMostException -Exception $_.Exception
                $test3Result = "Failed"
                if ($exp.GetType().Name -eq "SocketException") {
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

        $final.Add(([PSCustomObject]@(
            [PSCustomObject]@{
                TestType   = $test3Name
                TestResult = $test3Result
                TestOutput = $test3Output
            }
        ))) | Out-Null

        if ($stop) {
            if ($null -ne $socket) {
                Invoke-SocketCleanup -Socket $socket -NetworkStream $netStream -SslStream $sslStream
            }
            $final | Format-List
            return
        }

        #Test 4: Web Request
        $stream = $null
        if ($UseSSL.IsPresent -and $UseSSL) {
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
            $test4Result = "Succeeded"
            $test4Output = "Probe web request sent successfully."
        }
        catch {
            $stop = $true
            $exp = Get-InnerMostException -Exception $_.Exception
            $test4Result = "Failed"
            if ($exp.GetType().Name -eq "SocketException") {
                $test4Output = "[$($exp.GetType().Name)] $($exp.Message) (WinSock error $($exp.SocketErrorCode))."
            }
            else {
                $test4Output = "[$($exp.GetType().Name)] $($exp.Message)."
            }
        }

        $final.Add([PSCustomObject]@{
                TestType   = $test4Name
                TestResult = $test4Result
                TestOutput = $test4Output
            }
        ) | Out-Null

        if ($stop) {
            if ($null -ne $socket) {
                Invoke-SocketCleanup -Socket $socket -NetworkStream $netStream -SslStream $sslStream
            }
            $final | Format-List
            return
        }

        try {
            $response = Get-HttpResponse -NetworkStream $stream

            $final.Add(
                [PSCustomObject]@{
                    TestType   = $test5Name
                    TestResult = "Succeeded"
                    TestOutput = $response
                }
            ) | Out-Null
        }
        catch {            
            $final.Add([PSCustomObject]@{
                    TestType   = $test5Name
                    TestResult = "Failed"
                    TestOutput = $_.Exception.Message
                }
            ) | Out-Null
        }



        # Get status line
        <#
        while ($true) {
            try {
                $read = Get-FromNetworkSteam -Buffer $buffer -NetworkStream $stream -Offset 0 -Length $bufferSize
            }
            catch {
                $exp = Get-InnerMostException -Exception $_.Exception
                $test5Result = "Failed"
                if ($exp.GetType().Name -eq "SocketException") {
                    $test5Output = "[$($exp.GetType().Name)] $($exp.Message) (WinSock error $($exp.SocketErrorCode))."
                }
                else {
                    $test5Output = "[$($exp.GetType().Name)] $($exp.Message)."
                }
            }
            if ($read -eq 0) {
                $test5Result = "Failed"
                $test5Output = "Remote Server disconnected."
                break
            }

            $idx = Get-IndexOfLineBreak -Buffer $buffer -BytesRead $read
            if ($idx -gt -1) {
                $statusLine = Get-BufferAsString -Buffer $buffer -Length $idx
                break
            }
        }

        if ($null -ne $statusLine) {
            $statusLineSplit = $statusLine.Split(' ', 3)
            $statusCode = $statusLineSplit[1]
            $statusDescription = $statusLineSplit[2]

            $test5Result = "Succeeded"
            $test5Output = "Response Status Code: $($statusCode), Description: $($statusDescription). More parsing to come in the future."
        }
        elseif ($test5Output -ne "Failed") {
            $test5Result = "Failed"
            $test5Output = "For an unknown reason, couldn't parse the status line from the response."
        }

        $final.Add(([PSCustomObject]@(
            [PSCustomObject]@{
                TestType   = $test5Name
                TestResult = $test5Result
                TestOutput = $test5Output
            }
        ))) | Out-Null #>

        $final | Format-List
        
        Invoke-SocketCleanup -Socket $socket -NetworkStream $netStream -SslStream $sslStream
    }
}
