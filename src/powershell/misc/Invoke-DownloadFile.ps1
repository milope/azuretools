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