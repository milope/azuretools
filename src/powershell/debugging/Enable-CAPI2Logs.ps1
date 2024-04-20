function Enable-CAPI2Logs {
    [CmdletBinding()]
    param ()
    process {
        $log = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new('Microsoft-Windows-CAPI2/Operational')
        if($null -ne $log) {
            $log.IsEnabled = $true
            $log.SaveChanges()
        }
    }
}

function Disable-CAPI2Logs {
    [CmdletBinding()]
    param ()
    process {
        $log = [System.Diagnostics.Eventing.Reader.EventLogConfiguration]::new('Microsoft-Windows-CAPI2/Operational')
        if($null -ne $log) {
            $log.IsEnabled = $false
            $log.SaveChanges()
        }
    }
}