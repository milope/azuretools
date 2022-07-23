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
function Get-PerfMonDateRange {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][String]$Path
    )
    begin {
        if(-not (Test-Path -Path $Path)) {
            return
        }

        $data = Import-Counter -Path $Path -ErrorAction SilentlyContinue
        $lastTimestamps = $data | ForEach-Object { $_.CounterSamples | Where-Object { $_.Timestamp100NSec -gt 0 } | Sort-Object -Descending -Property Timestamp100NSec | Select-Object -First 1 -Property Timestamp100NSec }
        $lastTimestamp = $lastTimestamps | Sort-Object -Property Timestamp100NSec -Descending | Select-Object -First 1
        $firstTimestamp = $lastTimestamps | Sort-Object -Property Timestamp100NSec | Select-Object -First 1

        [PSCustomObject]@{Path=[IO.Path]::GetFileName($Path);StartTime = [System.DateTime]::FromFileTime($firstTimestamp.Timestamp100NSec).ToUniversalTime(); EndTime=[DateTime]::FromFileTime($lastTimestamp.Timestamp100NSec).ToUniversalTime()}
    }
}