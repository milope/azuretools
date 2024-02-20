

<#
Copyright © 2023 Michael Lopez

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

This cmdlet can be used as a subnet calculator. It can also be used to check
if a given IP is within the subnet range.

.DESCRIPTION

This cmdlet can be used as a subnet calculator. It can also be used to check
if a given IP is within the subnet range.

UPDATES

2023-08-21

.PARAMETER CIDR

Specify the CIDR range. This can be both IPv4 or IPv6.

.PARAMETER TestIP

Specify to check if the value is within the subnet in the CIDR value above.

.INPUTS

CIDRs can be piped from other commands if they return an enumerable of strings.

.OUTPUTS

Returns enumerable of objects with the following properties:

IPRange: An echo back of the CIDR parameter.
SubnetMask: The subnet mask in IP notation.
UsableHosts: The amount of assignable addresses in the subnet range.
FirstAddress: The first usable address in the subnet.
LastAddress: The last usable address in the subnet.
NetworkAddress: The network address in the subnet.
BroadcastAddress: The broadcast address in the subnet.
TestIPInSubnet: Then TestIP is specified, True if the specified IP is in the
range of the given CIDR value, False otherwise.

.EXAMPLE

Invoke-SubnetCalculator -CIDR 10.0.0.0

.EXAMPLE

Invoke-SubnetCalculator -CIDR fd00::/16

.EXAMPLE

Invoke-SubnetCalculator -CIDR fd00::/16 -TestIP "fd00::a"

.EXAMPLE

"10.0.0.0" | Invoke-SubnetCalculator
#>
function Invoke-SubnetCalculator {
    [CmdletBinding()] 
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)][String[]]$CIDR,
        [Parameter(Mandatory=$false)]$TestIP
    )
    begin {
        function iif([Bool]$Condition, $TrueStatement, $FalseStatement) {
            return $(if($condition) { $trueStatement } else { $falseStatement })
        }

        class UInt128 : System.IComparable {
            [UInt64]$Upper
            [UInt64]$Lower

            hidden [Int32]FindMSBIndex() {
                $digit = 0
                for($i = 1; $i -le 64; $i++) {
                    if((($this.Upper -shr (64 - $i)) -band 0x1) -eq 0x1) {
                        return $digit
                    }
                    else {
                        $digit++
                    }
                }
                for($i = 1; $i -le 64; $i++) {
                    if((($this.Lower -shr (64 - $i)) -band 0x1) -eq 0x1) {
                        return $digit
                    }
                    else {
                        $digit++
                    }
                }
                return -1
            }

            static [UInt128] $MaxValue = [UInt128]::new([UInt64]::MaxValue, [UInt64]::MaxValue)
    
            static [UInt128] FromIPv6($IPv6) {

                if($null -eq $IPv6 -or $IPv6.Trim().Length -eq 0) {
                    throw [ArgumentNullException]::new("'IPv6' cannot be null or empty.", "IPv6")
                }

                [Net.IPAddress]$outIP = [Net.IPAddress]::Any
    
                $parseResult = [Net.IPAddress]::TryParse($IPv6,[ref]$outIP);
                if(-not $parseResult -or $outIP.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                    throw [ArgumentException]::new("'IPv6' is not a valid IPv6 string.", "IPv6")
                }
    
                $ipv6Str = $IPv6.ToString();
                $scopeIdx = $ipv6Str.IndexOf('%');
                if($scopeIdx -gt 0) {
                    $ipv6Str = $ipv6Str.Substring(0, $scopeIdx);
                }
                $ipv6Str = $ipv6Str.Replace("::", ":-:");
    
                $currentSegments = $ipv6Str.Split(':', [StringSplitOptions]::RemoveEmptyEntries)
                [UInt64]$dUpper = 0
                [UInt64]$dLower = 0
                
                $continousZeros = 8 - $currentSegments.Length + 1
                $currentShift = 8 * 14;
    
                for($i = 0; $i -lt $currentSegments.Length; $i++) {
                    if($currentSegments[$i] -eq "-") {
                        for($j = 0; $j -lt $continousZeros; $j++) {
                            $currentShift -= 16
                        }
                    }
                    else {
                        [uint64]$segmentAsNumber = [Convert]::ToUInt64($currentSegments[$i], 16)
                        if($currentShift -gt 64) {
                            $dUpper = [UInt64]($dUpper -bor ($segmentAsNumber -shl 64 - (128 - $currentShift)))
                        }
                        else {
                            $dLower = [UInt64]($dLower -bor ($segmentAsNumber -shl $currentShift))
                        }
                        $currentShift -= 16
                    }
                }
    
                return [UInt128]::new($dUpper, $dLower)
            }

            [String] ToIPv6String() {
                [Text.StringBuilder]$output = [Text.StringBuilder]::new()
                [Bool]$compressionAdded = $false

                [UInt16]$value = [UInt16](($this.Upper -shr 48) -band 0x000000000000FFFF)
                if($value -eq 0) {
                    [Void]$output.Append("::")
                    $compressionAdded = $true
                }
                else {
                    [Void]$output.Append("{0:x1}:" -f $value)
                }

                $value = [UInt16](($this.Upper -shr 32) -band 0x000000000000FFFF)
                if($value -eq 0) {
                    if(-not $compressionAdded) {
                        [Void]$output.Append(":")
                        $compressionAdded = $true
                    }
                }
                else {
                    [Void]$output.Append("{0:x1}:" -f $value)
                }

                $value = [UInt16](($this.Upper -shr 16) -band 0x000000000000FFFF)
                if($value -eq 0) {
                    if(-not $compressionAdded) {
                        [Void]$output.Append(":")
                        $compressionAdded = $true
                    }
                }
                else {
                    [Void]$output.Append("{0:x1}:" -f $value)
                }

                $value = [UInt16]($this.Upper -band 0x000000000000FFFF)
                if($value -eq 0) {
                    if(-not $compressionAdded) {
                        [Void]$output.Append(":")
                        $compressionAdded = $true
                    }
                }
                else {
                    [Void]$output.Append("{0:x1}:" -f $value)
                }

                $value = [UInt16](($this.Lower -shr 48) -band 0x000000000000FFFF)
                if($value -eq 0) {
                    if(-not $compressionAdded) {
                        [Void]$output.Append(":")
                        $compressionAdded = $true
                    }
                }
                else {
                    [Void]$output.Append("{0:x1}:" -f $value)
                }

                $value = [UInt16](($this.Lower -shr 32) -band 0x000000000000FFFF)
                if($value -eq 0) {
                    if(-not $compressionAdded) {
                        [Void]$output.Append(":")
                        $compressionAdded = $true
                    }
                }
                else {
                    [Void]$output.Append("{0:x1}:" -f $value)
                }

                $value = [UInt16](($this.Lower -shr 16) -band 0x000000000000FFFF)
                if($value -eq 0) {
                    if(-not $compressionAdded) {
                        [Void]$output.Append(":")
                        $compressionAdded = $true
                    }
                }
                else {
                    [Void]$output.Append("{0:x1}:" -f $value)
                }

                $value = [UInt16]($this.Lower -band 0x000000000000FFFF)
                if($value -eq 0) {
                    if(-not $compressionAdded) {
                        [Void]$output.Append(":")
                        $compressionAdded = $true
                    }
                }
                else {
                    [Void]$output.Append("{0:x1}" -f $value)
                }

                return $output.ToString()
            }

            [String] ToString2() {
                if($this.Upper -eq 0) {
                    return $this.Lower.ToString()
                }
                [UInt128]$that = [UInt128]::New($this.Upper, $this.Lower)
                [UInt128]$divisor = [UInt128]::New(0, 10000000000000000000)
                $divRem = [UInt128]::DivRem($that, $divisor)
                $remainder = $divRem.Item2
                $quotient = $divRem.Item1
                if($quotient.Upper -eq 0) {
                    return "$($quotient.Lower.ToString())$($remainder.Lower.ToString().PadLeft(19, "0"))"
                }
                else {
                    $divRem = [UInt128]::DivRem($quotient, $divisor)
                    $remainder2 = $divRem.Item2
                    $quotient = $divRem.Item1
                    return "$($quotient.Lower.ToString())$($remainder2.Lower.ToString().PadLeft(19, "0"))$($remainder.Lower.ToString().PadLeft(19, "0"))"
                }
            }

            static [UInt128] op_LeftShift([UInt128]$value, [Int32]$shift) {

                if($shift -eq 0) { return [UInt128]::new($value.Upper, $value.Lower) }

                $shift = ($shift -band 0x7F)

                if(($shift -band 0x40) -ne 0)
                {
                    [UInt64]$dUpper = $value.Lower -shl $shift
                    return [UInt128]::new($dUpper, 0)
                }
                elseif($shift -ne 0) {
                    [UInt64]$dLower = $value.Lower -shl $shift
                    [UInt64]$dUpper = ($value.Upper -shl $shift) -bor ($value.Lower -shr (64 - $shift))
                    return [UInt128]::new($dUpper, $dLower)
                }
                return [UInt128]::new($value.Upper, $value.Lower)
            }

            static [UInt128] op_ExclusiveOr([UInt128]$left, [UInt128]$right) {
                return [UInt128]::new(
                    $left.Upper -bxor $right.Upper,
                    $left.Lower -bxor $right.Lower
                );
            }

            static [UInt128] op_BitwiseAnd([UInt128]$left, [UInt128]$right) {
                return [UInt128]::new(
                    $left.Upper -band $right.Upper,
                    $left.Lower -band $right.Lower
                );
            }

            static [UInt128] op_BitwiseOr([UInt128]$left, [UInt128]$right) {
                return [UInt128]::new(
                    $left.Upper -bor $right.Upper,
                    $left.Lower -bor $right.Lower
                );
            }

            static [UInt128] op_Addition([UInt128]$left, [UInt128]$right) {
                # Unfortunately, PowerShell doesn't do unsigned integers very well.
                # Basically if you overflow, then it changes the total's data type
                # to double, let's detect overflow

                [UInt64]$leftToOverflow = [uint64]::MaxValue - $left.Lower # How much is left to overflow
                [UInt64]$carry = 0
                [UInt64]$newLower = 0
                if($right.Lower -gt $leftToOverflow) {
                    $newLower = $right - $leftToOverflow
                    $carry = 1
                }
                else {
                    $newLower = $left.Lower + $right.Lower
                }

                $leftToOverflow = [UInt64]::MaxValue - $left.Upper
                if($right.Upper -gt $leftToOverflow) {
                    [OverflowException]::new("Addition resulted in a number too large for the UInt128 data type.")
                }

                return [UInt128]::new($left.Upper + $right.Upper + $carry, $newLower)
            }

            static [UInt128] op_Subtraction([UInt128]$left, [UInt128]$right) {
                # Same as above. PowerShell recasts the difference as a double if it underflows
                $rightLowerIsHigher = $right.Lower -gt $left.Lower

                if($right.Upper -gt $left.Upper -or ($rightLowerIsHigher -and ($right.Upper + 1 -gt $left.Upper))) {
                    throw [OverflowException]::new("Subtraction resulted in a number too low for the UInt128 data type.")
                }

                [UInt64]$Borrow = 0
                [UInt64]$newLower = 0

                if($rightLowerIsHigher) {
                    $Borrow = 1
                    $newLower = [UInt64]::MaxValue - ($right.Lower - ($left.Lower + 1))
                }
                else {
                    $newLower = $left.Lower - $right.Lower
                }

                return [UInt128]::new($left.Upper - $right.Upper - $Borrow, $newLower)
            }

            static [UInt128] op_Division([UInt128]$left, [UInt128]$right) {
                if($right.Upper -eq 0 -and $right.Lower -eq 0) {
                    throw [System.DivideByZeroException]::new("Cannot divide by zero.")
                }

                if($right -gt $left) {
                    return [UInt128]::(0, 0)
                }

                if($right.Upper -eq $left.Upper -and $right.Lower -eq $left.Lower) {
                    return [UInt128]::new(0, 1)
                }

                if($left.Upper -eq 0 -and $right.Upper -eq 0) {
                    return [UInt128]::new(0, [UInt64][Math]::Floor($left.Upper/$right.Upper))
                }

                [Uint128]$result = 0

                $msb = $right.FindMSBIndex()

                for($i = $msb; $i -ge 0; $i--) {
                    if(($right -shl $i) -le $left) {
                        $left -= ($right -shl $i)
                        $result += ([UInt128]::new(0, 1) -shl $i)
                    }
                }

                return $result
            }

            static [Tuple[[Uint128],[Uint128]]] DivRem([UInt128]$left, [Uint128]$right) {
                if($right.Upper -eq 0 -and $right.Lower -eq 0) {
                    throw [System.DivideByZeroException]::new("Cannot divide by zero.")
                }

                if($right -gt $left) {
                    return [UInt128]::(0, 0)
                }

                if($right.Upper -eq $left.Upper -and $right.Lower -eq $left.Lower) {
                    return [UInt128]::new(0, 1)
                }

                if($right.Upper -eq 0 -and $left.Upper -eq 0) {
                    $div = [UInt64]([Math]::Floor($left.Lower / $right.Lower))
                    $remainder = [UInt128]::new(0, $left.Lower % $right.Lower)
                    return [Tuple]::Create([UInt128]::new(0, $div), $remainder)
                }

                [Uint128]$result = 0

                $msb = $right.FindMSBIndex()

                for($i = $msb; $i -ge 0; $i--) {
                    if(($right -shl $i) -le $left) {
                        $left -= ($right -shl $i)
                        $result += ([UInt128]::new(0, 1) -shl $i)
                    }
                }

                return [Tuple]::Create($result, $left)
            }
            
            static [UInt128] op_Implicit([Int32]$value) {
                if($value -lt 0) {
                    throw [System.OverflowException]::new("Addition operation resulted in an underflow for an unsigned integer 128 data type.")
                }
                return [UInt128]::new(0, $value)
            }

            [Int] CompareTo($that) {
                if(-not ($that -is [UInt128])) {
                    throw [InvalidOperationException]::new("Cannot compare to non-UInt128 classes.")
                }
                
                if($this.Upper -lt $that.Upper) { return -1; }
                elseif($this.Upper -gt $that.Upper) { return 1; }
                elseif($this.Lower -lt $that.Lower) { return -1 }
                elseif($this.Lower -gt $that.Lower) { return 1 }
                return 0
            }

            UInt128([UInt64]$upper, [UInt64]$lower) {
                $this.Upper = $upper
                $this.Lower = $lower
            }
        }

        function ConvertFrom-NumberToIPv4 {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true)][UInt32]$Number
            )
            process {
                [String]$part1 = ($Number -shr 24) -band 0xFF
                [String]$part2 = ($Number -shr 16) -band 0xFF
                [String]$part3 = ($Number -shr 8) -band 0xFF
                [String]$part4 = $Number -band 0xFF
                (@($part1, $part2, $part3, $part4) -join ".")
            }
        }

        function ConvertFrom-IPv4ToNumber {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory=$true)][String]$IPv4
            )
            process {
                [String[]]$split = $IPv4.Split(".")
                [UInt32]::Parse($split[3]) + [UInt32]([UInt32]::Parse($split[2]) -shl 8) `
                    + [UInt32]([UInt32]::Parse($split[1]) -shl 16) + [UInt32]([UInt32]::Parse($split[0]) -shl 24)
            }
        }
    }
    process {
        $CIDR | ForEach-Object {
            $iprange = $_
            $firstSplit = $iprange.Split("/")
            $output = @{}

            if($firstSplit.Count -ne 2) {
                throw [System.ArgumentException]::new("'$iprange' is not a valid range. Ranges are either and IPv4/Number or IPv6/Number.")
            }

            [Net.IPAddress]$outIP = [Net.IPAddress]::Any
            if(-not [Net.IPAddress]::TryParse($firstSplit[0], [ref]$outIP)) {
                throw [System.ArgumentException]::new("'$iprange' is not a valid range. Ranges are either and IPv4/Number or IPv6/Number. Could not parse IP address.")
            }

            $subnetInteger = 0
            if(-not [Byte]::TryParse($firstSplit[1], [ref]$subnetInteger)) {
                throw [System.ArgumentException]::new("'$iprange' is not a valid range. Ranges are either and IPv4/Number or IPv6/Number. CIDR must be an unsigned integer.")
            }

            if($subnetInteger -lt 0) {
                throw [System.ArgumentException]::new("'$iprange' is not a valid range. Ranges are either and IPv4/Number or IPv6/Number. CIDR must be positive.")
            }

            if($outIP.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {

                if($subnetInteger -gt 30) {
                    throw [System.ArgumentException]::new("'$iprange' is not a valid range. The CIDR integer greater than 30 has no usable hosts on IPv4 networks.")
                }

                $subnetMask = $(if($subnetInteger -eq 0) { 0 } else { [UInt32]([UInt32]::MaxValue -shl (32 - $subnetInteger)) })
                $wildcardMask = $(if($subnetInteger -eq 0) { [UInt32]::MaxValue } else { $subnetMask -bxor [UInt32]::MaxValue }) 
                $ipNumber = ConvertFrom-IPv4ToNumber -IPv4 $firstSplit[0]
                $networkAddress = $ipNumber -band $subnetMask
                $broadcastAddress = $ipNumber -bor $wildcardMask

                $output.Add("IPRange", $iprange)
                $output.Add("SubnetMask", (ConvertFrom-NumberToIPv4 -Number $subnetMask))
                $output.Add("UsableHosts", ($wildcardMask - 1))
                $output.Add("NetworkAddress", (ConvertFrom-NumberToIPv4 -Number $networkAddress))
                $output.Add("BroadcastAddress", (ConvertFrom-NumberToIPv4 -Number $broadcastAddress))
                $output.Add("FirstAddress", (ConvertFrom-NumberToIPv4 -Number ($networkAddress + 1)))
                $output.Add("LastAddress", (ConvertFrom-NumberToIPv4 -Number ($broadcastAddress - 1)))

                if($PSBoundParameters.ContainsKey("TestIP") -and $null -ne $TestIP -and $TestIP.Trim().Length -gt 0) {
                    if([Net.IPAddress]::TryParse($TestIP,[ref]$outIP) -and $outIP.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
                        $testIPNumber = ConvertFrom-IPv4ToNumber -IPv4 $TestIP
                        $output.Add("TestIPInSubnet", ($networkAddress -le $testIPNumber -and $testIPNumber -le $broadcastAddress))
                    }
                    else {
                        $output.Add("TestIPInSubnet", $false)
                    }
                }
            }
            elseif($outIP.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {
                $ipString = $outIP.ToString()
                if($ipString.IndexOf("%") -gt 0) {
                    $ipString = $ipString.Substring(0, $ipString.IndexOf("%"))
                }

                $subnetMask = $(if($subnetInteger -eq 0) { [UInt128]::New(0, 0) } else { [UInt128]::MaxValue -shl (128 - $subnetInteger) })
                $wildcardMask = $(if($subnetInteger -eq 0) { [UInt128]::MaxValue } else { $subnetMask -bxor [UInt128]::MaxValue })
                $numberOfHosts = $wildcardMask - [Uint128]::new(0, 1)
                $ipNumber = [UInt128]::FromIPv6($ipString)
                $networkAddress = $ipNumber -band $subnetMask
                $broadcastAddress = $ipNumber -bor $wildcardMask

                $output.Add("IPRange", $iprange)
                $output.Add("SubnetMask", $subnetMask.ToIPv6String())
                $output.Add("UsableHosts", $numberOfHosts.ToString2())
                $output.Add("NetworkAddress", $networkAddress.ToIPv6String())
                $output.Add("BroadcastAddress", $broadcastAddress.ToIPv6String())
                $output.Add("FirstAddress", ($networkAddress + 1).ToIPv6String())
                $output.Add("LastAddress", ($broadcastAddress - 1).ToIPv6String())

                if($PSBoundParameters.ContainsKey("TestIP") -and $null -ne $TestIP -and $TestIP.Trim().Length -gt 0) {
                    if([Net.IPAddress]::TryParse($TestIP,[ref]$outIP) -and $outIP.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {
                        $testIPNumber = [UInt128]::FromIPv6($TestIP)
                        $output.Add("TestIPInSubnet", ($networkAddress -le $testIPNumber -and $testIPNumber -le $broadcastAddress))
                    }
                    else {
                        $output.Add("TestIPInSubnet", $false)
                    }
                }
            }
            else{
                throw [System.ArgumentException]::new("'$iprange' is not a valid range. Ranges are either and IPv4/Number or IPv6/Number.")
            }

            if($output.ContainsKey("TestIPInSubnet")) {
                ($output | ConvertTo-Json | ConvertFrom-Json) | `
                    Select-Object -Property IPRange, SubnetMask, UsableHosts, FirstAddress, LastAddress, NetworkAddress, BroadcastAddress, TestIPInSubnet
            }
            else {
                ($output | ConvertTo-Json | ConvertFrom-Json) | `
                    Select-Object -Property IPRange, SubnetMask, UsableHosts, FirstAddress, LastAddress, NetworkAddress, BroadcastAddress
            }
        }
    }
}