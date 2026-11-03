BeforeAll {
    . "$PSScriptRoot\OSDCloudPreOOBE.ps1" -Preview
    Initialize-OOBEMenuNative
}

Describe 'PreOOBE ordered scheduler' {
    BeforeEach {
        Mock Write-OOBEMenuLog {}
        Mock Set-Content {}
        $engine = New-OSDCloudPreOOBEState
        $engine.StepDelaySeconds = 0
        $engine.Started = $true
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

    It 'installs OEM drivers before time sync and updates, then waits for Continue to OOBE' {
        1..5 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        ($script:types -join ',') | Should -Be 'DriverPack,Time,Software,Driver'
        @($engine.Tasks | Where-Object Outcome -ne Succeeded).Count | Should -Be 0
        $engine.Complete | Should -BeTrue
        1..3 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        $engine.Done | Should -BeFalse
        $engine.CloseRequested = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Done | Should -BeTrue
        Should -Invoke Set-Content -Times 1 -Exactly
    }

    It 'waits for Start before running any task' {
        $engine.Started = $false
        1..3 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        $script:types.Count | Should -Be 0
        @($engine.Tasks | Where-Object Outcome -eq Pending).Count | Should -Be 4
        Start-OSDCloudPreOOBEState -State $engine
        $engine.Started | Should -BeTrue
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        ($script:types -join ',') | Should -Be 'DriverPack'
        ($engine.Output -join "`n") | Should -BeLike '*OSDCloud PreOOBE started by technician.*'
    }

    It 'closing before Start skips every task and finishes' {
        $engine.Started = $false
        $engine.CloseRequested = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $script:types.Count | Should -Be 0
        @($engine.Tasks | Where-Object Outcome -eq Skipped).Count | Should -Be 4
        $engine.Done | Should -BeTrue
    }

    It 'skips unchecked steps when reached and still runs re-checked steps' {
        $engine.Tasks[1].Enabled = $false
        $engine.Tasks[3].Enabled = $false
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Tasks[3].Outcome | Should -Be 'Pending'
        $engine.Tasks[3].Enabled = $true
        1..4 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        ($script:types -join ',') | Should -Be 'DriverPack,Software,Driver'
        $engine.Tasks[1].Outcome | Should -Be 'Skipped'
        ($engine.Output -join "`n") | Should -BeLike '*Skipped Synchronizing internet time: unchecked by technician.*'
        $engine.Complete | Should -BeTrue
    }

    It 'skips a step unchecked during its countdown' {
        $engine.StepDelaySeconds = 10
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.StepTask | Should -Be $engine.Tasks[0]
        $engine.Tasks[0].Enabled = $false
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Tasks[0].Outcome | Should -Be 'Skipped'
        $engine.StepTask | Should -Be $engine.Tasks[1]
        $script:types.Count | Should -Be 0
    }

    It 'Start begins the counting-down step immediately' {
        $engine.StepDelaySeconds = 10
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $script:types.Count | Should -Be 0
        Start-OSDCloudPreOOBEState -State $engine
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        ($script:types -join ',') | Should -Be 'DriverPack'
        $engine.StartNow | Should -BeFalse
        ($engine.Output -join "`n") | Should -BeLike '*Starting Driver unpack / install now by technician request.*'
    }

    It 'never starts a skipped pending update and still completes' {
        $engine.Tasks[2].Outcome = 'Skipped'
        1..4 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        ($script:types -join ',') | Should -Be 'DriverPack,Time,Driver'
        $engine.Tasks[2].Outcome | Should -Be 'Skipped'
        $engine.Complete | Should -BeTrue
    }

    It 'pauses after a Windows Update startup failure and continues independent tasks on Continue' {
        Mock Start-OOBEMenuUpdateWorker { throw 'Simulated startup error' } -ParameterFilter { $Type -eq 'Software' }
        1..5 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        $engine.Tasks[2].Outcome | Should -Be 'Failed'
        $engine.Paused | Should -BeTrue
        $engine.Tasks[3].Outcome | Should -Be 'Pending'
        Resume-OSDCloudPreOOBEState -State $engine
        1..2 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        $engine.Tasks[2].Outcome | Should -Be 'Failed'
        $engine.Tasks[3].Outcome | Should -Be 'Succeeded'
        ($engine.Output -join "`n") | Should -BeLike '*Simulated startup error*calendar*'
    }

    It 'pauses after Updating Windows 11 fails and retries it after the clock is corrected' {
        $script:softwareRuns = 0
        Mock Start-OOBEMenuUpdateWorker {
            $script:types.Add($Type)
            $script:softwareRuns++
            $State.Outcome = if ($script:softwareRuns -eq 1) { 'Failed' } else { 'Succeeded' }
            $pipeline = [pscustomobject]@{ Streams = [pscustomobject]@{ Error = @() } }
            $pipeline | Add-Member ScriptMethod EndInvoke { param($handle) }
            $pipeline | Add-Member ScriptMethod Dispose {}
            $runspace = [pscustomobject]@{}
            $runspace | Add-Member ScriptMethod Dispose {}
            [pscustomobject]@{ Pipeline = $pipeline; Runspace = $runspace; Handle = [pscustomobject]@{ IsCompleted = $true } }
        } -ParameterFilter { $Type -eq 'Software' }
        1..6 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        $engine.Paused | Should -BeTrue
        $engine.PausedTask | Should -Be $engine.Tasks[2]
        $engine.Tasks[3].Outcome | Should -Be 'Pending'
        $engine.Complete | Should -BeFalse
        Resume-OSDCloudPreOOBEState -State $engine -Retry
        $engine.Paused | Should -BeFalse
        1..3 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        ($script:types -join ',') | Should -Be 'DriverPack,Time,Software,Software,Driver'
        $engine.Tasks[2].Outcome | Should -Be 'Succeeded'
        $engine.Complete | Should -BeTrue
    }

    It 'skips remaining tasks when the window closes while paused' {
        Mock Start-OOBEMenuUpdateWorker { throw 'Simulated startup error' } -ParameterFilter { $Type -eq 'Software' }
        1..5 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        $engine.Paused | Should -BeTrue
        $engine.CloseRequested = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Paused | Should -BeFalse
        $engine.Tasks[3].Outcome | Should -Be 'Skipped'
        $engine.Done | Should -BeTrue
    }

    It 'waits 10 seconds by default before starting each task' {
        (New-OSDCloudPreOOBEState).StepDelaySeconds | Should -Be 10
        $engine.StepDelaySeconds = 10
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $script:types.Count | Should -Be 0
        $engine.StepTask | Should -Be $engine.Tasks[0]
        $engine.StepRemaining | Should -Be 10
        ($engine.Output -join "`n") | Should -BeLike '*Driver unpack / install starting in 10 seconds.*'
        $engine.StepDelay = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(9.99) }
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.StepRemaining | Should -Be 1
        $script:types.Count | Should -Be 0
        $engine.StepDelay = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(10) }
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        ($script:types -join ',') | Should -Be 'DriverPack'
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Tasks[0].Outcome | Should -Be 'Succeeded'
        $engine.StepTask | Should -Be $engine.Tasks[1]
        $script:types.Count | Should -Be 1
    }

    It 'records the running OS date, time and time zone at start' {
        $engine.StartClock.TimeZoneId | Should -Be ([TimeZoneInfo]::Local.Id)
        $engine.Output[0] | Should -BeLike "Running OS clock at start: *time zone $([TimeZoneInfo]::Local.Id)*"
    }

    It 'does not force cancel OEM installation when closing and skips remaining tasks' {
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Active.Type | Should -Be 'DriverPack'
        $engine.Worker.Handle.IsCompleted = $false
        $engine.CloseRequested = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Shared.CancelRequested | Should -BeFalse
        $engine.Done | Should -BeFalse
        $engine.Worker.Handle.IsCompleted = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Done | Should -BeTrue
        $engine.Tasks[2].Outcome | Should -Be Skipped
        $script:types.Count | Should -Be 1
    }

    It 'cancels an active update cooperatively on close and waits for its completion' {
        $engine.Tasks[0].Outcome = 'NotApplicable'
        $engine.Tasks[1].Outcome = 'Succeeded'
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Worker.Handle.IsCompleted = $false
        $engine.CloseRequested = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Shared.CancelRequested | Should -BeTrue
        $engine.Done | Should -BeFalse
        $engine.Shared.Outcome = 'Cancelled'
        $engine.Worker.Handle.IsCompleted = $true
        Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
        $engine.Tasks[2].Outcome | Should -Be Cancelled
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

    It 'continues updates when internet time fails' {
        Mock Start-OOBEMenuUpdateWorker { throw 'Time source unreachable' } -ParameterFilter { $Type -eq 'Time' }
        1..5 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
        $engine.Tasks[1].Outcome | Should -Be Failed
        ($script:types -join ',') | Should -Be 'DriverPack,Software,Driver'
        $engine.Complete | Should -BeTrue
    }
}

Describe 'PreOOBE connectivity and task eligibility' {
    BeforeEach {
        Mock Write-OOBEMenuLog {}
        Mock Invoke-OOBEMenuWindowsUpdate { $State.Succeeded = $true }
        Mock Invoke-OSDCloudPreOOBEDriverPack { $State.Outcome = 'NotApplicable' }
        Mock Sync-OSDCloudPreOOBETime { $State.Outcome = 'Succeeded'; $State.Succeeded = $true }
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
        foreach ($type in 'Time','DriverPack','Software','Driver') {
            Invoke-OSDCloudPreOOBETask -Type $type -State $state -PreviewOnly
        }
        Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 0 -Exactly
        Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 0 -Exactly
        Should -Invoke Invoke-OSDCloudPreOOBEDriverPack -Times 0 -Exactly
        Should -Invoke Sync-OSDCloudPreOOBETime -Times 0 -Exactly
    }

    It 'does not gate internet time retrieval on the HTTPS connectivity probe' {
        Invoke-OSDCloudPreOOBETask -Type Time -State $state
        $state.Outcome | Should -Be Succeeded
        Should -Invoke Sync-OSDCloudPreOOBETime -Times 1 -Exactly
        Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 0 -Exactly
        Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 0 -Exactly
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
                $_.RootVisual -is [Windows.Window] -and $_.RootVisual.Title -like 'Recast Software - OSDCloud PreOOBE*'
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
                $result.TitleText = $testWindow.FindName('TitleText').Text
                $result.User = $testWindow.FindName('UserBadge').ToolTip
                $result.StepButton = $testWindow.FindName('StepButton').Content
                $result.ContinueOobe = $testWindow.FindName('ContinueOobeButton').Visibility
                $result.Steps = @($testWindow.FindName('StepPanel').Children).Count
                $result.Collapsed = $testWindow.FindName('SidebarColumn').Width.Value
                $testWindow.FindName('PaneToggleButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $result.Expanded = $testWindow.FindName('SidebarColumn').Width.Value
                $result.StepName = $testWindow.FindName('StepPanel').Children[0].Content
                $result.Resize = [Windows.Shell.WindowChrome]::GetWindowChrome($testWindow).ResizeBorderThickness.Right
                $result.Context = $testWindow.FindName('ContextText').Text
                $result.Scripts = @($testWindow.FindName('ScriptsMenuButton').ContextMenu.Items | ForEach-Object Header)
                $result.Shells = @($testWindow.FindName('ShellMenuButton').ContextMenu.Items | ForEach-Object Header)
                $result.Calendar = [Windows.Automation.AutomationProperties]::GetName($testWindow.FindName('CalendarButton'))
                $result.Time = $testWindow.FindName('TaskText1').Text
                $result.SkipSoftware = $testWindow.FindName('SkipSoftwareButton')
                $result.SkipDrivers = $testWindow.FindName('SkipDriversButton')
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
        $version = (Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\..\OSDCloud.psd1')).ModuleVersion
        $result.Title | Should -Be "Recast Software - OSDCloud PreOOBE $version (Preview)"
        $result.TitleText | Should -Be "Recast Software - OSDCloud PreOOBE $version"
        $result.User | Should -Not -BeNullOrEmpty
        $result.StepButton | Should -Be 'Start'
        $result.ContinueOobe | Should -Be ([Windows.Visibility]::Collapsed)
        $result.Steps | Should -Be 4
        $result.Collapsed | Should -Be 56
        $result.Expanded | Should -Be 220
        $result.StepName | Should -Be 'Driver unpack / install'
        $result.Resize | Should -Be 8
        $result.Context | Should -Not -BeLike '*OSDCloud by Recast*'
        $result.Topmost | Should -BeTrue
        ($result.Scripts -join ',') | Should -Be 'OOBE.cmd,SetupComplete.cmd'
        ($result.Shells -join ',') | Should -Be 'CMD Prompt,Windows PowerShell'
        $result.Calendar | Should -Be 'Date, Time and TimeZone'
        $result.Time | Should -BeLike 'Synchronizing internet time*'
        $result.SkipSoftware | Should -BeNullOrEmpty
        $result.SkipDrivers | Should -BeNullOrEmpty
        $result.Open | Should -BeTrue
        ($result.Tall - $result.Initial) | Should -Be 320
        $result.Small | Should -BeGreaterThan 0
        $result.Maximized | Should -Be ([Windows.WindowState]::Maximized)
        $result.Restored | Should -Be ([Windows.WindowState]::Normal)
    }
}
