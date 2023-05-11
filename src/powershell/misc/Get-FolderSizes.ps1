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

Use this to list all directories, their total size and amount of objects inside it.

.DESCRIPTION

Use this to list all directories, their total size and amount of objects inside it.

.PARAMETER Path

Specify the path from where to start looking. Currently, it automatically recurses.

.INPUTS

The paths can be specified as pipeline input.

.OUTPUTS

The output will be a pipeable PSCustomObject with three properties:

Directory => The full path of a directory.
Items => The number of objects in that directory.
TotalSize => The size (in bytes, currently) of this directory.

.EXAMPLE

Get-FolderSizes

.EXAMPLE

Get-FolderSizes -Path C:\

.EXAMPLE

"C:\" | Get-FolderSizes

#>
function Get-FolderSizes {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,ValueFromPipeline=$true,Position=0)][String[]]$Path=@($PWD)
    )
    begin {

    }
    process {
        $Path | ForEach-Object {
            $directories = Get-ChildItem -Path $_ -Directory -ErrorAction SilentlyContinue
            $directories | ForEach-Object {
                $items = Get-ChildItem -Path $_ -File -Recurse -ErrorAction SilentlyContinue
                $totalSize = [Int64]($items | Measure-Object -Property Length -Sum).Sum
                @{Directory=$_.Name;Items=$items.Count;TotalSize=$totalSize} | ConvertTo-Json -Depth 100 | ConvertFrom-Json | Select-Object -Property Directory, Items, TotalSize
            }
            $files = Get-ChildItem -Path $_ -File -ErrorAction SilentlyContinue
            $totalSize = [Int64]($files | Measure-Object -Property Length -Sum).Sum
            @{Directory=". (Files)";Items=$files.Count;TotalSize=$totalSize} | ConvertTo-Json -Depth 100 | ConvertFrom-Json | Select-Object -Property Directory, Items, TotalSize
        }
    }
    end {

    }
}