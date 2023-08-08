function Get-Average{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)][Int[]]$Numbers
    )
    begin {
        $total = 0
    }
    process {
        $Numbers | ForEach-Object { $total += $_ }
    }
    end {
        $total / $Numbers.Count
    }
}