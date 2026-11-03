BeforeAll {
    . "$PSScriptRoot\OSDCloudPreOOBE.ps1" -Preview
    Initialize-OOBEMenuNative
}

Describe 'PreOOBE ordered scheduler' {
    BeforeEach {
        Mock Write-OOBEMenuLog {}
        Mock Set-Content {}
        $engine = New-OSDCloudPreOOBEState
        $script:types = [Collections.Generic.List[string]]::new()
        Mock Start-OOBEMenuUpdateWorker {
            $script:types.Add($Type)
            $State.Outcome = 'Succeeded'
            $State.DurationMs = 12L
            $pipeline = [pscustomobject]@{ Streams = [pscustomobject]@{ Error = @() } }
            $pipeline | Add-Member ScriptMethod EndInvoke { param($handle) }
            $pipeline | Add-Member ScriptMethod Dispose {}
            $runspace = [pscustomobject]@{}
            $runspace | Add-Member ScriptMethod Dispose {}
            [pscustomobject]@{ Pipeline = $pipeline; Runspace = $runspace; Handle = [pscustomobject]@{ IsCompleted = $true } }
        }
    }

    It 'runs drivers then software then drivers and waits the full 15-second countdown' {
        1..4 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        ($script:types -join ',') | Should -Be 'DriverPack,Software,Driver'
        @($engine.Tasks | Where-Object Outcome -ne Succeeded).Count | Should -Be 0
        $engine.Remaining | Should -Be 15
        $engine.Done | Should -BeFalse
        $engine.Countdown = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(14.99) }
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Remaining | Should -Be 1
        $engine.Done | Should -BeFalse
        $engine.Countdown = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(15) }
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Done | Should -BeTrue
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        Should -Invoke Set-Content -Times 1 -Exactly
    }

    It 'never starts a skipped pending update and still completes' {
        $engine.Tasks[1].Outcome = 'Skipped'
        1..3 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        ($script:types -join ',') | Should -Be 'DriverPack,Driver'
        $engine.Tasks[1].Outcome | Should -Be 'Skipped'
        $engine.Countdown | Should -Not -BeNullOrEmpty
    }

    It 'continues independent tasks after worker startup failures' {
        Mock Start-OOBEMenuUpdateWorker { throw 'Simulated startup error' } -ParameterFilter { $Type -eq 'Software' }
        1..4 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        $engine.Tasks[1].Outcome | Should -Be 'Failed'
        $engine.Tasks[2].Outcome | Should -Be 'Succeeded'
        ($engine.Output -join "`n") | Should -BeLike '*Simulated startup error*'
    }

    It 'does not force cancel OEM installation when closing and skips remaining tasks' {
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Worker.Handle.IsCompleted = $false
        $engine.CloseRequested = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Shared.CancelRequested | Should -BeFalse
        $engine.Done | Should -BeFalse
        $engine.Worker.Handle.IsCompleted = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Done | Should -BeTrue
        $engine.Tasks[1].Outcome | Should -Be Skipped
        $script:types.Count | Should -Be 1
    }

    It 'cancels an active update cooperatively on close and waits for its completion' {
        $engine.Tasks[0].Outcome = 'NotApplicable'
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Worker.Handle.IsCompleted = $false
        $engine.CloseRequested = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Shared.CancelRequested | Should -BeTrue
        $engine.Done | Should -BeFalse
        $engine.Shared.Outcome = 'Cancelled'
        $engine.Worker.Handle.IsCompleted = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Tasks[1].Outcome | Should -Be Cancelled
        $engine.Done | Should -BeTrue
    }

    It 'preserves reboot state and drains the final worker message' {
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Shared.RebootRequired = $true
        $engine.Shared.Messages.Enqueue('Final worker message')
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.RebootRequired | Should -BeTrue
        $engine.Shared.RebootRequired | Should -BeTrue
        $engine.Output | Should -Contain 'Final worker message'
    }
}

Describe 'PreOOBE connectivity and task eligibility' {
    BeforeEach {
        Mock Write-OOBEMenuLog {}
        Mock Invoke-OOBEMenuWindowsUpdate { $State.Succeeded = $true }
        Mock Invoke-OSDCloudPreOOBEDriverPack { $State.Outcome = 'NotApplicable' }
        Mock Test-OSDCloudPreOOBEConnectivity { [pscustomobject]@{ Connected = $true; Reason = 'Connected'; DurationMs = 10 } }
        $state = [hashtable]::Synchronized(@{
            Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new(); CancelRequested = $false
            RebootRequired = $false; Succeeded = $false; Outcome = 'Pending'
        })
    }

    It 'skips updates without starting WUA when connectivity fails: <Reason>' -TestCases @(
        @{ Reason = 'No cable' }, @{ Reason = 'DNS failure' }, @{ Reason = 'Timeout' },
        @{ Reason = 'Proxy authentication' }, @{ Reason = 'TLS failure' }, @{ Reason = 'Captive portal' }
    ) {
        param($Reason)
        Mock Test-OSDCloudPreOOBEConnectivity { [pscustomobject]@{ Connected = $false; Reason = $Reason; DurationMs = 10000 } }
        Invoke-OSDCloudPreOOBETask -Type Software -State $state
        $state.Outcome | Should -Be Skipped
        ($state.Messages.ToArray() -join "`n") | Should -BeLike "*$Reason*"
        Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 0 -Exactly
    }

    It 'rechecks connectivity for each update and recognizes restored connectivity' {
        Mock Test-OSDCloudPreOOBEConnectivity { [pscustomobject]@{ Connected = $false; Reason = 'offline' } }
        Invoke-OSDCloudPreOOBETask -Type Software -State $state
        $state.Outcome | Should -Be Skipped
        Mock Test-OSDCloudPreOOBEConnectivity { [pscustomobject]@{ Connected = $true; Reason = 'restored' } }
        Invoke-OSDCloudPreOOBETask -Type Driver -State $state
        $state.Outcome | Should -Be Succeeded
        Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 2 -Exactly
        Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 1 -ParameterFilter { $Type -eq 'Driver' }
    }

    It 'does not gate local OEM drivers on internet access' {
        Invoke-OSDCloudPreOOBETask -Type DriverPack -State $state
        $state.Outcome | Should -Be NotApplicable
        Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 0 -Exactly
        Should -Invoke Invoke-OSDCloudPreOOBEDriverPack -Times 1 -Exactly
    }

    It 'preview never probes or invokes native installation' {
        foreach ($type in 'DriverPack','Software','Driver') {
            Invoke-OSDCloudPreOOBETask -Type $type -State $state -PreviewOnly
        }
        Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 0 -Exactly
        Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 0 -Exactly
        Should -Invoke Invoke-OSDCloudPreOOBEDriverPack -Times 0 -Exactly
    }

    It 'never starts WUA when cancelled during a connectivity check' {
        Mock Test-OSDCloudPreOOBEConnectivity { $State.CancelRequested = $true; [pscustomobject]@{ Connected = $true } }
        Invoke-OSDCloudPreOOBETask -Type Software -State $state
        $state.Outcome | Should -Be Cancelled
        Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 0 -Exactly
    }

    It 'does not start even a connectivity probe if already cancelled' {
        $state.CancelRequested = $true
        Invoke-OSDCloudPreOOBETask -Type Driver -State $state
        $state.Outcome | Should -Be Cancelled
        Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 0 -Exactly
    }
}

Describe 'PreOOBE rendered automation' -Tag Interactive {
    BeforeEach {
        $Preview = $true
        Mock Write-OOBEMenuLog {}
        Mock Set-Content {}
        Mock Write-Error {}
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
        $result = @{ Error = $null }
        $uiProbeTimer = [Windows.Threading.DispatcherTimer]::new()
        $uiProbeTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    }
    AfterEach { $uiProbeTimer.Stop() }

    It 'keeps title-bar shell, script and calendar actions inert in preview' {
        $result.Ticks = 0
        $uiProbeTimer.Add_Tick({
            $result.Ticks++
            $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object {
                $_.RootVisual -is [Windows.Window] -and $_.RootVisual.Title -like 'OSDCloudPreOOBE*'
            } | Select-Object -ExpandProperty RootVisual)[0]
            try {
                if ($result.Ticks -eq 1) {
                    $testWindow.FindName('ShellMenuButton').ContextMenu.Items[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
                    $testWindow.FindName('ScriptsMenuButton').ContextMenu.Items[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
                    $testWindow.FindName('CalendarButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                    $clockWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object {
                        $_.RootVisual -is [Windows.Window] -and $_.RootVisual.Title -eq 'Date, Time and TimeZone'
                    } | Select-Object -ExpandProperty RootVisual)[0]
                    $clockWindow.FindName('DatePicker').SelectedDate = [datetime]'2030-06-15'
                    $clockWindow.FindName('TimeTextBox').Text = '14:30:00'
                    $clockWindow.FindName('TimeZoneComboBox').SelectedValue = 'UTC'
                    $clockWindow.FindName('ApplyClockButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                    $result.ClockText = $clockWindow.FindName('ClockStatusText').Text
                    $clockWindow.Close()
                    return
                }
                if ($result.Ticks -lt 5) { return }
                $uiProbeTimer.Stop()
                $result.Output = $testWindow.FindName('OutputTextBox').Text
                $testWindow.Close()
            }
            catch {
                $result.Error = "$($_.Exception.Message) at $($_.InvocationInfo.PositionMessage); output: $($engine.Output -join '|')"
                $uiProbeTimer.Stop()
                if ($testWindow) { $testWindow.Close() }
            }
        })
        $uiProbeTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $result.Error | Should -BeNullOrEmpty
        $result.Output | Should -BeLike '*Preview: would open *cmd.exe /d /k*'
        $result.Output | Should -BeLike '*Preview: would open *notepad.exe*"*\OOBE.cmd"*'
        $result.ClockText | Should -Be 'Preview: would set 2030-06-15 14:30:00 (UTC).'
    }

    It 'has title-bar scripts, shells and calendar; output fills height and closure returns zero' {
        $uiProbeTimer.Add_Tick({
            $uiProbeTimer.Stop()
            $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                Select-Object -ExpandProperty RootVisual)[0]
            try {
                $result.Title = $testWindow.Title
                $result.Topmost = $testWindow.Topmost
                $result.Scripts = @($testWindow.FindName('ScriptsMenuButton').ContextMenu.Items | ForEach-Object Header)
                $result.Shells = @($testWindow.FindName('ShellMenuButton').ContextMenu.Items | ForEach-Object Header)
                $result.Calendar = [Windows.Automation.AutomationProperties]::GetName($testWindow.FindName('CalendarButton'))
                $testWindow.FindName('ScriptsMenuButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $result.Open = $testWindow.FindName('ScriptsMenuButton').ContextMenu.IsOpen
                $testWindow.FindName('ScriptsMenuButton').ContextMenu.IsOpen = $false
                $testWindow.Height = 480
                $testWindow.UpdateLayout()
                $result.Initial = $testWindow.FindName('OutputTextBox').ActualHeight
                $testWindow.Height = 800
                $testWindow.UpdateLayout()
                $result.Tall = $testWindow.FindName('OutputTextBox').ActualHeight
                $testWindow.Width = 480; $testWindow.Height = 360
                $testWindow.UpdateLayout()
                $result.Small = $testWindow.FindName('OutputTextBox').ActualHeight
                $testWindow.FindName('MaximizeButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $result.Maximized = $testWindow.WindowState
                $testWindow.FindName('MaximizeButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $result.Restored = $testWindow.WindowState
                $testWindow.Close()
            }
            catch { $result.Error = $_; $testWindow.Close() }
        })
        $uiProbeTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $result.Error | Should -BeNullOrEmpty
        $result.Title | Should -Be 'OSDCloudPreOOBE (Preview)'
        $result.Topmost | Should -BeTrue
        ($result.Scripts -join ',') | Should -Be 'OOBE.cmd,SetupComplete.cmd'
        ($result.Shells -join ',') | Should -Be 'CMD Prompt,Windows PowerShell'
        $result.Calendar | Should -Be 'Date, Time and TimeZone'
        $result.Open | Should -BeTrue
        ($result.Tall - $result.Initial) | Should -Be 320
        $result.Small | Should -BeGreaterThan 0
        $result.Maximized | Should -Be ([Windows.WindowState]::Maximized)
        $result.Restored | Should -Be ([Windows.WindowState]::Normal)
    }
}
