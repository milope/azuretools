function Enable-SystemDotNetTracing {
    [CmdletBinding()]
    param (
        [String][Parameter(Mandatory=$false)]$FilePath
    )
    process {

        if($null -ne $Global:__SystemDotNetTracingOriginalValues) {
            Write-Warning "WARNING: Enable-SystemDotNetTracing has already been executed"
            return
        }

        # Constants
        $blankUrl = "http://localhost"
        $bindingFlags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
        $classType = "System.Net.Logging"
        $listenerName = "System.Net"
        $sourceLevel = [System.Diagnostics.SourceLevels]::All
        $traceOutputOptions = "ProcessId, DateTime"
        $traceModeAttribute = [PSCustomObject]@{Name = "tracemode"; Value = "includehex" }
        $maxdatasizeAttribute = [PSCustomObject]@{Name = "maxdatasize"; Value = "1024" }

        $staticFieldNames = [PSCustomObject]@{
            LoggingInitialized = "s_LoggingInitialized";
            LoggingEnabled = "s_LoggingEnabled";
            WebTraceSource = "s_WebTraceSource";
            HttpListenerTraceSource = "s_HttpListenerTraceSource";
            SocketsTraceSource = "s_SocketsTraceSource";
            CacheTraceSource = "s_CacheTraceSource";
            WebSocketsTraceSource = "s_WebSocketsTraceSource";
            TraceSourceHttpName = "s_TraceSourceHttpName"
        }
        
        # Step 1: Ensure System.Net.Logging is initialized
        $logging = [System.Net.WebRequest]::Create($blankUrl).GetType().Assembly.GetType($classType)
        $initField = $logging.GetField($staticFieldNames.LoggingInitialized, $bindingFlags)
        $initialized = [bool]$initField.GetValue($null)
        if(-not $initialized) {
            $thread = Start-Job {

                # Constants
                $init_blankUrl = "http://localhost"
                $init_classType = "System.Net.Logging"
                $init_LoggingInitialized = "s_LoggingInitialized"

                # Repeat above until initialized
                $init_logging = [System.Net.WebRequest]::Create($init_blankUrl).GetType().Assembly.GetType($init_classType)
                $init_bindingFlags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
                $init_initField = $init_logging.GetField($init_LoggingInitialized, $init_bindingFlags)
                $init_initialized = [bool]$init_initField.GetValue($null)
                while(-not $init_initialized) {
                    Start-Sleep -Milliseconds 100
                    $init_initialized = [bool]$init_initField.GetValue($null)
                }
            }

            Wait-Job $thread | Out-Null
        }

        # Step 2: Setup Fields that configure logging
        $isEnabledField = $logging.GetField($staticFieldNames.LoggingEnabled, $bindingFlags);
        $webTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.WebTraceSource, $bindingFlags).GetValue($null)
        $httpListenerTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.HttpListenerTraceSource, $bindingFlags).GetValue($null)
        $socketsTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.SocketsTraceSource, $bindingFlags).GetValue($null)
        $cacheTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.CacheTraceSource, $bindingFlags).GetValue($null)
        $webSocketsTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.WebSocketsTraceSource, $bindingFlags).GetValue($null)
        $httpTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.TraceSourceHttpName, $bindingFlags).GetValue($null)

        # Step 3: Let's save their original configuration to later use it for disabling

        $Global:__SystemDotNetTracingOriginalValues = [PSCustomObject]@{
            IsEnabled = $isEnabledField.GetValue($null);
            WebTraceSource = New-Object -TypeName System.Diagnostics.TraceSource -ArgumentList "Original";
            WebTraceSourceLevel = $webTraceSource.Switch.Level;
            HttpListenerTraceSource = New-Object -TypeName System.Diagnostics.TraceSource -ArgumentList "Original";
            HttpListenerTraceSourceLevel = $webTraceSource.Switch.Level;
            SocketsTraceSource = New-Object -TypeName System.Diagnostics.TraceSource -ArgumentList "Original";
            SocketsTraceSourceLevel = $webTraceSource.Switch.Level;
            CacheTraceSource = New-Object -TypeName System.Diagnostics.TraceSource -ArgumentList "Original";
            CacheTraceSourceLevel = $webTraceSource.Switch.Level;
            WebSocketsTraceSource = New-Object -TypeName System.Diagnostics.TraceSource -ArgumentList "Original";
            WebSocketsTraceSourceLevel = $webTraceSource.Switch.Level;
            HttpTraceSource = New-Object -TypeName System.Diagnostics.TraceSource -ArgumentList "Original";
            HttpTraceSourceLevel = $webTraceSource.Switch.Level;
            AutoFlush = [System.Diagnostics.Trace]::AutoFlush
        }

        $Global:__SystemDotNetTracingOriginalValues.WebTraceSource.Listeners.AddRange($webTraceSource.Listeners)
        $Global:__SystemDotNetTracingOriginalValues.HttpListenerTraceSource.Listeners.AddRange($httpListenerTraceSource.Listeners)
        $Global:__SystemDotNetTracingOriginalValues.SocketsTraceSource.Listeners.AddRange($socketsTraceSource.Listeners)
        $Global:__SystemDotNetTracingOriginalValues.CacheTraceSource.Listeners.AddRange($cacheTraceSource.Listeners)
        $Global:__SystemDotNetTracingOriginalValues.WebSocketsTraceSource.Listeners.AddRange($webSocketsTraceSource.Listeners)
        $Global:__SystemDotNetTracingOriginalValues.HttpTraceSource.Listeners.AddRange($httpTraceSource.Listeners)

        

        # Step 4: Create the Trace Listener
        $newListener = $null
        if([String]::IsNullOrEmpty($FilePath)) {
            $newListener = New-Object -TypeName System.Diagnostics.ConsoleTraceListener -ArgumentList $true
        }
        else {
            $newListener = New-Object -TypeName System.Diagnostics.TextWriterTraceListener -ArgumentList $FilePath
        }
        $newListener.Name = $listenerName
        $newListener.TraceOutputOptions = $traceOutputOptions
        $newListener.Filter = New-Object System.Diagnostics.EventTypeFilter -ArgumentList $sourceLevel

        # Step 5: Add the Trace Listener to all sources and set the Source Level to all (include hexmode and maxsize for System.Net)

        $webTraceSource.Listeners.Add($newListener) | Out-Null
        $httpListenerTraceSource.Listeners.Add($newListener) | Out-Null
        $socketsTraceSource.Listeners.Add($newListener) | Out-Null
        $cacheTraceSource.Listeners.Add($newListener) | Out-Null
        $webSocketsTraceSource.Listeners.Add($newListener) | Out-Null
        $httpTraceSource.Listeners.Add($newListener) | Out-Null

        $webTraceSource.Switch.Level = $sourceLevel
        $httpListenerTraceSource.Switch.Level = $sourceLevel
        $socketsTraceSource.Switch.Level = $sourceLevel
        $cacheTraceSource.Switch.Level = $sourceLevel
        $webSocketsTraceSource.Switch.Level = $sourceLevel
        $httpTraceSource.Switch.Level = $sourceLevel

        $webTraceSource.Attributes.Add($traceModeAttribute.Name, $traceModeAttribute.Value)
        $webTraceSource.Attributes.Add($maxdatasizeAttribute.Name, $maxdatasizeAttribute.Value)

        # Step 6: Start The Trace
        [System.Diagnostics.Trace]::AutoFlush = $true
        $isEnabledField.SetValue($null, $true)
    }
}

function Disable-SystemDotNetTracing {
    [CmdletBinding()]
    param (
    )
    process {
        if($null -eq $Global:__SystemDotNetTracingOriginalValues) {
            Write-Warning "WARNING: System.Net tracing has not been enabled using Enable-SystemDotNetTracing"
            return
        }

        
        # Constants
        $blankUrl = "http://localhost"
        $bindingFlags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
        $classType = "System.Net.Logging"

        $staticFieldNames = [PSCustomObject]@{
            LoggingInitialized = "s_LoggingInitialized";
            LoggingEnabled = "s_LoggingEnabled";
            WebTraceSource = "s_WebTraceSource";
            HttpListenerTraceSource = "s_HttpListenerTraceSource";
            SocketsTraceSource = "s_SocketsTraceSource";
            CacheTraceSource = "s_CacheTraceSource";
            WebSocketsTraceSource = "s_WebSocketsTraceSource";
            TraceSourceHttpName = "s_TraceSourceHttpName"
        }
        
        # Step 1: Ensure System.Net.Logging is initialized
        $logging = [System.Net.WebRequest]::Create($blankUrl).GetType().Assembly.GetType($classType)
        $initField = $logging.GetField($staticFieldNames.LoggingInitialized, $bindingFlags)
        $initialized = [bool]$initField.GetValue($null)
        if(-not $initialized) {
            $thread = Start-Job {

                # Constants
                $init_blankUrl = "http://localhost"
                $init_classType = "System.Net.Logging"
                $init_LoggingInitialized = "s_LoggingInitialized"

                # Repeat above until initialized
                $init_logging = [System.Net.WebRequest]::Create($init_blankUrl).GetType().Assembly.GetType($init_classType)
                $init_bindingFlags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
                $init_initField = $init_logging.GetField($init_LoggingInitialized, $init_bindingFlags)
                $init_initialized = [bool]$init_initField.GetValue($null)
                while(-not $init_initialized) {
                    Start-Sleep -Milliseconds 100
                    $init_initialized = [bool]$init_initField.GetValue($null)
                }
            }

            Wait-Job $thread | Out-Null
        }

        # Step 2: Setup Fields that configure logging (set Logging back to its original value immediately)
        $isEnabledField = $logging.GetField($staticFieldNames.LoggingEnabled, $bindingFlags);
        $isEnabledField.SetValue($null, $Global:__SystemDotNetTracingOriginalValues.IsEnabled)
        [System.Diagnostics.Trace]::AutoFlush = $Global:__SystemDotNetTracingOriginalValues.AutoFlush

        $webTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.WebTraceSource, $bindingFlags).GetValue($null)
        $httpListenerTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.HttpListenerTraceSource, $bindingFlags).GetValue($null)
        $socketsTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.SocketsTraceSource, $bindingFlags).GetValue($null)
        $cacheTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.CacheTraceSource, $bindingFlags).GetValue($null)
        $webSocketsTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.WebSocketsTraceSource, $bindingFlags).GetValue($null)
        $httpTraceSource = [System.Diagnostics.TraceSource]$logging.GetField($staticFieldNames.TraceSourceHttpName, $bindingFlags).GetValue($null)

        # Step 3: Set original values up

        $webTraceSource.Listeners.Clear()
        $webTraceSource.Listeners.AddRange($Global:__SystemDotNetTracingOriginalValues.WebTraceSource.Listeners)
        $webTraceSource.Switch.Level = $Global:__SystemDotNetTracingOriginalValues.WebTraceSourceLevel
        $webTraceSource.Attributes.Clear()
        $httpListenerTraceSource.Listeners.Clear()
        $httpListenerTraceSource.Listeners.AddRange($Global:__SystemDotNetTracingOriginalValues.HttpListenerTraceSource.Listeners)
        $httpListenerTraceSource.Switch.Level = $Global:__SystemDotNetTracingOriginalValues.HttpListenerTraceSourceLevel
        $socketsTraceSource.Listeners.Clear()
        $socketsTraceSource.Listeners.AddRange($Global:__SystemDotNetTracingOriginalValues.SocketsTraceSource.Listeners)
        $socketsTraceSource.Switch.Level = $Global:__SystemDotNetTracingOriginalValues.SocketsTraceSourceLevel
        $cacheTraceSource.Listeners.Clear()
        $cacheTraceSource.Listeners.AddRange($Global:__SystemDotNetTracingOriginalValues.CacheTraceSource.Listeners)
        $cacheTraceSource.Switch.Level = $Global:__SystemDotNetTracingOriginalValues.CacheTraceSourceLevel
        $webSocketsTraceSource.Listeners.Clear()
        $webSocketsTraceSource.Listeners.AddRange($Global:__SystemDotNetTracingOriginalValues.WebSocketsTraceSource.Listeners)
        $webSocketsTraceSource.Switch.Level = $Global:__SystemDotNetTracingOriginalValues.WebSocketsTraceSourceLevel
        $httpTraceSource.Listeners.Clear()
        $httpTraceSource.Listeners.AddRange($Global:__SystemDotNetTracingOriginalValues.HttpTraceSource.Listeners)
        $httpTraceSource.Switch.Level = $Global:__SystemDotNetTracingOriginalValues.HttpTraceSourceLevel

        $Global:__SystemDotNetTracingOriginalValues = $null
    }
}
