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

Downloads a file to a specified or current folder.

.DESCRIPTION

Downloads a file to a specified or current folder.

Please note this cmdlet requires that the bitstransfer module is present.

.PARAMETER URL

The URL for the file to download.

.PARAMETER Path

The location from where to store the file

.PARAMETER AsJob

If specified, executes the download as a job in the background.

.INPUTS

Receives an array of URL strings and attempts to download the files if the are
URLs

.OUTPUTS

Outputs Jobs if AsJob is passed, otherwise, it returns the result of Get-Item
for the downloaded file.

#>
function Invoke-DownloadFile {
    [Alias("download")]
    [CmdletBinding()]
    param (
        [String[]][Parameter(Mandatory=$true, ParameterSetName="io", ValueFromPipeline=$true)]$InputObject,
        [String][Parameter(Mandatory=$true, ParameterSetName="iline")]$Url,
        [String]
        [Parameter(Mandatory=$false, ParameterSetName="io")]
        [Parameter(Mandatory=$false, ParameterSetName="iline")]
        $Path=$PWD,
        [Switch]$AsJob
    )
    process {

        if($PSBoundParameters.ContainsKey("Url")) {
            $InputObject = @($Url)
        }
        
        $scriptCommand = {
            param($pUrl, $pPath, $pAsJob)
            Import-Module bitstransfer
            $destinationFile = "$pPath\$(Split-Path -Leaf (New-Object System.Uri -ArgumentList $pUrl).AbsolutePath)";
            Start-BitsTransfer $pUrl $destinationFile
            if(-not $AsJob) {
                Get-Item -Path $destinationFile
            }
        }

        foreach($iUrl in $InputObject) {
            if($AsJob) {
                Start-Job -ScriptBlock $scriptCommand -ArgumentList $iUrl, $Path
            }
            else {
                Invoke-Command -ScriptBlock $scriptCommand -ArgumentList $iUrl, $Path
            }
        }
    }
}