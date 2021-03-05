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