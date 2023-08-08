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

Use this to list all directories, their total size and amount of objects inside it.

.DESCRIPTION

Use this to list all directories, their total size and amount of objects inside it.

.PARAMETER Path

Specify the path from where to start looking. Currently, it automatically recurses.

.INPUTS

None. This cmdlet does not accept inputs, yet.

.OUTPUTS

The output will be a pipeable PSCustomObject with three properties:

Directory => The full path of a directory.
Objects => The number of objects in that directory.
Size => The size (in bytes, currently) of this directory.

.EXAMPLE

Get-DirectorySizeSummary

.EXAMPLE

Get-DirectorySizeSummary -Path C:\

#>

function Get-DirectorySizeSummary {
    [CmdletBinding()]
    param (
        [String][Parameter(Mandatory=$false, Position=0)]$Path
    )
    begin
    {
        if(-not $PSBoundParameters.ContainsKey("Path")) {
            $Path = $pwd
        }
    }
    process
    {
        function Get-_Subdirectories_ {
            [CmdletBinding()]
            param(
                [String][Parameter(Mandatory=$true, Position=0)]$pPath
            )
            process {
                if([String]::IsNullOrEmpty($pPath)) {
                    return
                }

                Write-Debug "Entering Get-Subdirectories -pPath = $($pPath))"

                Get-ChildItem -Path $pPath -Force -ErrorAction SilentlyContinue `
                | Where-Object {($_.Attributes -band [System.IO.FileAttributes]::Directory) -eq [System.IO.FileAttributes]::Directory } `
                | ForEach-Object { $_.FullName }

                Write-Debug "Exiting Get-Subdirectories -pPath = $($pPath))"
            }
        }

        function Get-_Statistics_ {
            [CmdletBinding()]
            param (
                [String][Parameter(Mandatory=$false)]$pPath
            )
            
            if([String]::IsNullOrEmpty($pPath)) {
                return
            }

            Write-Debug "Entering Get-Statistics -pPath $($pPath)"

            [Long]$count = 0
            [Long]$size = 0

            Get-ChildItem -Path $pPath -Recurse -Force -ErrorAction SilentlyContinue `
            | Select-Object -Property FullName, Length -ErrorAction SilentlyContinue `
            | ForEach-Object { $count++; $size += $_.Length }

            Write-Output ([PSCustomObject]@{
                Directory = $pPath;
                Objects = $count;
                Size = $size
            })

            Get-_Subdirectories_ -pPath $pPath | ForEach-Object { Get-_Statistics_ -pPath $_ }

            Write-Debug "Exiting Get-Statistics -pPath $($pPath)"
        }

        Get-_Statistics_ -pPath $Path
    }
}