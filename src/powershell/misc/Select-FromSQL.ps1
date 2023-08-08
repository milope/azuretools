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
<#
.SYNOPSIS

This is a simple cmdlet to run SQL queries.

.DESCRIPTION

This is a simple cmdlet to run SQL queries.

.PARAMETER Server

Specify the SQL server to connect to.

.PARAMETER Database

Specify the database to run the query against.

.PARAMETER Username

If using SQL Server Authentication, specify the username. Do not specify if
the intent is to use Windows Authentication.

.PARAMETER Password

If using SQL Server Authentication, specify the password. Do not specify if
the intent is to use Windows Authentication.

.PARAMETER Query

Specify the query to execute.

.PARAMETER AsDataColumns

Specify this switch to return the DataTable Columns instead of the query
result.

.INPUTS

None. This cmdlet does not support inputs at this time.

.OUTPUTS

If AsDataColumns is specified, it will enumerate the data table Columns
property as an output.

If AsDataColumns is not specified, it will enumerate the data table Rows
property as an output. This will be the results of the query.

.EXAMPLE

PS> Select-FromSQL -Server myserver -Database mydb `
    -Query "SELECT * FROM [dbo].[People]"

This will use Windows Authentication to connect to SQL.

.EXAMPLE

PS> $password = Read-Host -Message "Enter your password" -AsSecureString
PS> Select-FromSQL -Server myserver -Database mydb `
    -Username myuser -Password $password
    -Query "SELECT * FROM [dbo].[People]"

This will use SQL Server authentication

.EXAMPLE

PS> Select-FromSQL -Server myserver -Database mydb `
    -Query "SELECT * FROM [dbo].[People]" -AsDataColumns

This will dump the column metadata from the resulting query.

#>
function Select-FromSQL {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName="WindowsAuth", Position=0)]
        [Parameter(Mandatory, ParameterSetName="UserAuth", Position=0)]
        [String]$Server,
        
        [Parameter(ParameterSetName="WindowsAuth", Position=1)]
        [Parameter(ParameterSetName="UserAuth", Position=1)]
        [String]$Database="master",

        [Parameter(Mandatory, ParameterSetName="UserAuth", Position=2)]
        [String]$Username,
        
        [Parameter(Mandatory, ParameterSetName="UserAuth", Position=3)]
        [SecureString]$Password,
        
        [Parameter(Mandatory, ParameterSetName="WindowsAuth", Position=2)]
        [Parameter(Mandatory, ParameterSetName="UserAuth", Position=4)]
        [String]$Query,
        
        [Parameter(ParameterSetName="WindowsAuth")]
        [Parameter(ParameterSetName="UserAuth")]
        [Switch]$AsDataColumns
    )
    begin {
        [String]$connectionString
        [System.Data.SqlClient.SqlConnection]$sqlConn
        [System.Data.SqlClient.SqlCommand]$sqlCmd
        [System.Data.SqlClient.SqlDataReader]$reader
        [System.Data.DataTable]$dt = [System.Data.DataTable]::new()

        function ConvertTo-PlainText (
            [SecureString][Parameter(Mandatory=$true, Position = 0)]$Value
        ) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
            try {
                [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }

        if($PSCmdlet.ParameterSetName -eq "WindowsAuth") {
            $connectionString = "Server='$Server';Initial Catalog='$Database';Trusted_Connection=True;Encrypt=True;TrustServerCertificate=True;Connection Timeout=60"
        }
        elseif($PSCmdlet.ParameterSetName -eq "UserAuth") {
            $connectionString = "Server='$Server';Initial Catalog='$Database';User ID='$Username';Password='$((ConvertTo-PlainText -Value $Password))';Encrypt=True;TrustServerCertificate=True;Connection Timeout=60"
        }

        $sqlConn = [System.Data.SqlClient.SqlConnection]::new($connectionString)
        $connectionString = $null
        try {
            $sqlConn.Open()
            $sqlCmd = [System.Data.SqlClient.SqlCommand]::new($Query, $sqlConn)
    
            $reader = $sqlCmd.ExecuteReader()
            $dt.Load($reader)
        }
        catch {
            Write-Error $_.Exception.Message
        }
    }
    process {
        if($AsDataColumns) {
            $dt.Columns | ForEach-Object { $_ }
        }
        else {
            $dt.Rows | ForEach-Object { $_ }
        }
    }
    end {

        if($null -ne $dt) {
            $dt.Dispose()
        }

        if($null -ne $reader) {
            $reader.Close()
            $reader.Dispose()
        }

        if($null -ne $sqlCmd) {
            $sqlCmd.Dispose()
        }

        if($null -ne $sqlConn) {
            $sqlConn.Close()
            $sqlConn.Dispose()
        }
    }
}