BeforeAll {
    . "$PSScriptRoot\Show-OSDCloudOOBEMenu.ps1" -Preview
    Initialize-OOBEMenuNative
    $menuScriptPath = "$PSScriptRoot\Show-OSDCloudOOBEMenu.ps1"
}

Describe 'Standalone OOBE menu startup' {
    BeforeEach {
        $Preview = $false
        $Phase = 'OOBE'
        $InteractiveChild = $false
        $ReadyEvent = $null
        Mock Write-OOBEMenuLog {}
        Mock Write-Error {}
        Mock Show-OOBEMenuWindow { 0 }
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{
                IsSystem = $true
                Identity = 'NT AUTHORITY\SYSTEM'
                SessionId = 1
                Station = 'WinSta0'
                Desktop = 'Default'
                ConsoleSession = 1
                IsInputDesktop = $true
            }
        }
    }

    It 'returns zero after a normal visible menu closure without launching a bridge' {
        Mock Invoke-OOBEMenuChild { throw 'Unexpected child launch' }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath | Should -Be 0
        Should -Invoke Show-OOBEMenuWindow -Times 1 -Exactly
        Should -Invoke Invoke-OOBEMenuChild -Times 0 -Exactly
    }

    It 'propagates the session child exit code without showing a hidden parent menu' {
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{ IsSystem = $true; IsInputDesktop = $false; SessionId = 0 }
        }
        Mock Invoke-OOBEMenuChild { 7 }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath | Should -Be 7
        Should -Invoke Invoke-OOBEMenuChild -Times 1 -Exactly -ParameterFilter {
            $ScriptPath -eq $menuScriptPath
        }
        Should -Invoke Show-OOBEMenuWindow -Times 0 -Exactly
    }

    It 'logs menu creation failure and returns nonzero' {
        Mock Show-OOBEMenuWindow { throw 'WPF unavailable' }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Write-OOBEMenuLog -Times 1 -ParameterFilter {
            $Message -like '*startup failed*WPF unavailable*'
        }
    }

    It 'returns nonzero if the native session launcher fails' {
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{ IsSystem = $true; IsInputDesktop = $false }
        }
        Mock Invoke-OOBEMenuChild { throw 'No console session is available' }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Show-OOBEMenuWindow -Times 0 -Exactly
    }

    It 'rejects non-SYSTEM execution outside preview' {
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{ IsSystem = $false; IsInputDesktop = $true }
        }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Show-OOBEMenuWindow -Times 0 -Exactly
    }

    It 'does not cross sessions in preview' {
        $Preview = $true
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{ IsSystem = $false; IsInputDesktop = $false }
        }
        Mock Invoke-OOBEMenuChild {}
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Invoke-OOBEMenuChild -Times 0 -Exactly
    }

    It 'rejects internal child mode without its readiness event' {
        $InteractiveChild = $true
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Show-OOBEMenuWindow -Times 0 -Exactly
    }

    It 'resolves native PowerShell and cmd paths to existing inbox executables' {
        Get-OOBEMenuNativePath -PowerShell | Should -BeLike '*\WindowsPowerShell\v1.0\powershell.exe'
        Get-OOBEMenuNativePath | Should -BeLike '*\cmd.exe'
        Test-Path -LiteralPath (Get-OOBEMenuNativePath -PowerShell) | Should -BeTrue
    }

    It 'reports a missing inbox executable instead of returning an invalid path' {
        Mock Test-Path { $false }
        { Get-OOBEMenuNativePath -PowerShell } | Should -Throw '*Inbox executable is missing*'
    }
}

Describe 'SetupComplete clock validation' {
    BeforeEach {
        Mock Write-OOBEMenuLog {}
        Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $true } }
        Mock Set-TimeZone {}
        Mock Set-Date {}
    }

    It 'previews all clock settings without changing anything' {
        Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId 'UTC' -PreviewOnly |
            Should -Be 'Preview: would set 2030-06-15 14:30:00 (UTC).'
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'applies the chosen local time as the correct UTC instant after setting the selected time zone' {
        Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId 'Eastern Standard Time' |
            Should -BeLike 'Date, time, and time zone set to *'
        Should -Invoke Set-TimeZone -Times 1 -Exactly -ParameterFilter { $Id -eq 'Eastern Standard Time' -and $ErrorAction -eq 'Stop' }
        Should -Invoke Set-Date -Times 1 -Exactly -ParameterFilter {
            $Date.ToString('yyyy-MM-dd HH:mm:ss') -eq '2030-06-15 18:30:00' -and
            $Date.Kind -eq [DateTimeKind]::Utc -and $ErrorAction -eq 'Stop'
        }
    }

    It 'rejects invalid time format before changing time or zone' {
        foreach ($time in '25:00:00', '2:30 PM', '14:30', 'invalid') {
            { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time $time -TimeZoneId UTC } |
                Should -Throw '*HH:mm:ss*'
        }
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'rejects invalid zones before changing the clock' {
        { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId 'Invalid Zone' } | Should -Throw
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'rejects daylight-saving gaps and repeated hours' {
        { Set-OOBEMenuClock -Date ([datetime]'2030-03-10') -Time '02:30:00' -TimeZoneId 'Eastern Standard Time' } |
            Should -Throw '*daylight-saving*'
        { Set-OOBEMenuClock -Date ([datetime]'2030-11-03') -Time '01:30:00' -TimeZoneId 'Eastern Standard Time' } |
            Should -Throw '*daylight-saving*'
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'does not attempt to set the clock after a time-zone failure' {
        Mock Set-TimeZone { throw 'Time zone update failed' }
        { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId UTC } |
            Should -Throw '*Time zone update failed*'
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'surfaces a date failure explicitly after a successful zone change' {
        Mock Set-Date { throw 'Clock update failed' }
        { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId UTC } |
            Should -Throw '*Clock update failed*'
        Should -Invoke Write-OOBEMenuLog -Times 1 -ParameterFilter { $Message -like 'Time zone set*' }
    }

    It 'rejects non-SYSTEM clock changes' {
        Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $false } }
        { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId UTC } |
            Should -Throw '*require SYSTEM*'
        Should -Invoke Set-TimeZone -Times 0 -Exactly
    }

    It 'rejects dates outside the Windows system clock range before changing the time zone' {
        { Set-OOBEMenuClock -Date ([datetime]'1500-06-15') -Time '14:30:00' -TimeZoneId UTC } |
            Should -Throw '*1601*'
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }
}

Describe 'OOBE menu local console rendering' -Tag 'Interactive' {
    BeforeEach {
        $Preview = $true
        $Phase = 'OOBE'
        Mock Write-OOBEMenuLog {}
        Mock Write-Error {}
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
        $uiState = @{ Error = $null; Status = ''; Width = 0; Height = 0; Focused = $false }
        $uiTimer = [System.Windows.Threading.DispatcherTimer]::new(
            [System.Windows.Threading.DispatcherPriority]::ApplicationIdle
        )
        $uiTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    }
    AfterEach { $uiTimer.Stop() }

    It 'launches an inert native child and propagates its exact exit status' {
        $inert = [Recast.OOBE.Native]::Launch((Get-OOBEMenuNativePath), '/d /c exit 37', $true, 0)
        try {
            $inert.Wait(10000) | Should -BeTrue
            $inert.ExitCode | Should -Be 37
        }
        finally {
            if (-not $inert.Wait(0)) { $inert.Terminate(); [void]$inert.Wait(5000) }
            $inert.Dispose()
        }
    }

    It 'renders at minimum size, keeps shell preview inert, and returns zero on Continue' {
        $uiTimer.Add_Tick({
                $uiTimer.Stop()
                $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                        Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                        Select-Object -ExpandProperty RootVisual)[0]
                try {
                    if (-not $testWindow) { throw 'No rendered WPF menu window was found.' }
                    $testWindow.Width = 480
                    $testWindow.Height = 360
                    $testWindow.UpdateLayout()
                    $uiState.Width = $testWindow.ActualWidth
                    $uiState.Height = $testWindow.ActualHeight
                    $uiState.Title = $testWindow.Title
                    $uiState.PageTitleVisibility = $testWindow.FindName('PageTitleText').Visibility
                    $uiState.UpdateVisibility = $testWindow.FindName('WindowsUpdateButton').Visibility
                    $uiState.Left = $testWindow.Left
                    $uiState.Top = $testWindow.Top
                    $uiState.MinimizeStyle = $testWindow.FindName('MinimizeButton').Style
                    $uiState.ClockVisibility = $testWindow.FindName('ClockButton').Visibility
                    $button = $testWindow.FindName('CommandButton')
                    [void]$button.Focus()
                    $uiState.Focused = $button.IsKeyboardFocused
                    $button.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                    $uiState.Status = $testWindow.FindName('StatusText').Text
                    $testWindow.FindName('PowerShellButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.PowerShellStatus = $testWindow.FindName('StatusText').Text
                    $testWindow.FindName('ContinueButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                }
                catch { $uiState.Error = $_; if ($testWindow) { $testWindow.Close() } }
            })
        $uiTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
        $uiState.Width | Should -Be 480
        $uiState.Height | Should -Be 360
        $uiState.Title | Should -Be 'OSDCloud - OOBE.cmd (Preview)'
        $uiState.PageTitleVisibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $uiState.UpdateVisibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $uiState.Left | Should -Be ($workArea.Left + [Math]::Min(20, [Math]::Max(0, $workArea.Width - [Math]::Min(640, $workArea.Width))))
        $uiState.Top | Should -Be ($workArea.Top + [Math]::Min(20, [Math]::Max(0, $workArea.Height - [Math]::Min(480, $workArea.Height))))
        $uiState.MinimizeStyle | Should -BeOfType ([System.Windows.Style])
        $uiState.ClockVisibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $uiState.Focused | Should -BeTrue
        $uiState.Status | Should -BeLike 'Preview: would open *cmd.exe /d /k'
        $uiState.PowerShellStatus | Should -BeLike 'Preview: would open *powershell.exe -NoLogo -NoProfile -NoExit -STA'
    }

    It 'uses BootMenu caption buttons, collapsible left shortcuts, and inert Notepad actions' {
        $uiTimer.Add_Tick({
                $uiTimer.Stop()
                $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                        Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                        Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $uiState.CaptionBackground = $testWindow.FindName('MinimizeButton').Background.ToString()
                    $uiState.CaptionWidth = $testWindow.FindName('MinimizeButton').Width
                    $uiState.CaptionBorder = $testWindow.FindName('MinimizeButton').BorderThickness.Left
                    $testWindow.FindName('PaneToggleButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.SidebarWidth = $testWindow.FindName('SidebarColumn').Width.Value
                    $uiState.LabelVisibility = $testWindow.FindName('CommandLabel').Visibility
                    $testWindow.FindName('OpenOOBEButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.OOBEStatus = $testWindow.FindName('StatusText').Text
                    $testWindow.FindName('OpenSetupCompleteButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.SetupStatus = $testWindow.FindName('StatusText').Text
                    $testWindow.FindName('MaximizeButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.Maximized = $testWindow.WindowState
                    $testWindow.FindName('MaximizeButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.Restored = $testWindow.WindowState
                }
                catch { $uiState.Error = $_ }
                finally { if ($testWindow) { $testWindow.Close() } }
            })
        $uiTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
        $uiState.CaptionBackground | Should -Be '#00FFFFFF'
        $uiState.CaptionWidth | Should -Be 46
        $uiState.CaptionBorder | Should -Be 0
        $uiState.SidebarWidth | Should -Be 56
        $uiState.LabelVisibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $uiState.OOBEStatus | Should -BeLike 'Preview: would open *notepad.exe "*\Setup\Scripts\oobe.cmd"'
        $uiState.SetupStatus | Should -BeLike 'Preview: would open *notepad.exe "*\Setup\Scripts\setupcomplete.cmd"'
        $uiState.Maximized | Should -Be ([System.Windows.WindowState]::Maximized)
        $uiState.Restored | Should -Be ([System.Windows.WindowState]::Normal)
    }

    It 'renders SetupComplete with clock controls and previews Apply without changing the host' {
        $Phase = 'SetupComplete'
        Mock Set-TimeZone {}
        Mock Set-Date {}
        $uiTimer.Add_Tick({
                $uiTimer.Stop()
                $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                        Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                        Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $uiState.Title = $testWindow.Title
                    $testWindow.FindName('ClockButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.ClockVisible = $testWindow.FindName('ClockPage').Visibility
                    $zones = $testWindow.FindName('TimeZoneComboBox')
                    $zones.IsDropDownOpen = $true
                    $testWindow.UpdateLayout()
                    $uiState.DropDownOpen = $zones.IsDropDownOpen
                    $zones.IsDropDownOpen = $false
                    $testWindow.FindName('DatePicker').SelectedDate = [datetime]'2030-06-15'
                    $testWindow.FindName('TimeTextBox').Text = '14:30:00'
                    $testWindow.FindName('TimeZoneComboBox').SelectedValue = 'UTC'
                    $testWindow.FindName('ApplyClockButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.Status = $testWindow.FindName('StatusText').Text
                    $testWindow.FindName('TimeTextBox').Text = 'invalid'
                    $testWindow.FindName('ApplyClockButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.InvalidTimeStatus = $testWindow.FindName('StatusText').Text
                    $testWindow.Width = 480
                    $testWindow.Height = 360
                    $testWindow.UpdateLayout()
                    $uiState.ClockColumns = $testWindow.FindName('ClockDateTimeGrid').Columns
                    $uiState.StillVisible = $testWindow.IsVisible
                }
                catch { $uiState.Error = $_ }
                finally { if ($testWindow) { $testWindow.Close() } }
            })
        $uiTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
        $uiState.Title | Should -Be 'OSDCloud - SetupComplete.cmd (Preview)'
        $uiState.ClockVisible | Should -Be ([System.Windows.Visibility]::Visible)
        $uiState.DropDownOpen | Should -BeTrue
        $uiState.Status | Should -Be 'Preview: would set 2030-06-15 14:30:00 (UTC).'
        $uiState.InvalidTimeStatus | Should -BeLike '*Unable to apply clock settings*HH:mm:ss*'
        $uiState.ClockColumns | Should -Be 1
        $uiState.StillVisible | Should -BeTrue
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'keeps the menu open and displays a shell-launch failure' {
        Mock Get-OOBEMenuNativePath { throw 'Executable unavailable' }
        $uiTimer.Add_Tick({
                $uiTimer.Stop()
                $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                        Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                        Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $testWindow.FindName('CommandButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.Status = $testWindow.FindName('StatusText').Text
                    $uiState.Visible = $testWindow.IsVisible
                }
                catch { $uiState.Error = $_ }
                finally { if ($testWindow) { $testWindow.Close() } }
            })
        $uiTimer.Start()
        Show-OOBEMenuWindow -ErrorAction SilentlyContinue | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
        $uiState.Status | Should -BeLike '*Unable to open shell*Executable unavailable*'
        $uiState.Visible | Should -BeTrue
    }

    It 'offers both SetupComplete update actions while preview never starts an update worker' {
        $Phase = 'SetupComplete'
        Mock Start-OOBEMenuUpdateWorker { throw 'Preview must not start WUA' }
        $uiTimer.Add_Tick({
                $uiTimer.Stop()
                $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                        Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                        Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $uiState.Title = $testWindow.Title
                    $uiState.SoftwareVisibility = $testWindow.FindName('WindowsUpdateButton').Visibility
                    $uiState.DriverVisibility = $testWindow.FindName('DriverUpdateButton').Visibility
                    $testWindow.FindName('WindowsUpdateButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.SoftwareStatus = $testWindow.FindName('StatusText').Text
                    $testWindow.FindName('DriverUpdateButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.DriverStatus = $testWindow.FindName('StatusText').Text
                    $uiState.UpdateTitle = $testWindow.FindName('PageTitleText').Text
                    $testWindow.FindName('PaneToggleButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.UpdateLabelVisibility = $testWindow.FindName('WindowsUpdateLabel').Visibility
                }
                catch { $uiState.Error = $_ }
                finally { if ($testWindow) { $testWindow.Close() } }
            })
        $uiTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
        $uiState.Title | Should -Be 'OSDCloud - SetupComplete.cmd (Preview)'
        $uiState.SoftwareVisibility | Should -Be ([System.Windows.Visibility]::Visible)
        $uiState.DriverVisibility | Should -Be ([System.Windows.Visibility]::Visible)
        $uiState.UpdateLabelVisibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $uiState.SoftwareStatus | Should -BeLike 'Preview: would search, download and install Software updates*'
        $uiState.DriverStatus | Should -BeLike 'Preview: would search, download and install Driver updates*'
        $uiState.UpdateTitle | Should -Be 'Windows Update - Drivers'
        Should -Invoke Start-OOBEMenuUpdateWorker -Times 0 -Exactly
    }

    It 'surfaces worker startup failure without blocking menu closure' {
        $Phase = 'SetupComplete'
        $Preview = $false
        Mock Start-OOBEMenuUpdateWorker { throw 'Worker unavailable' }
        $uiTimer.Add_Tick({
                $uiTimer.Stop()
                $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                        Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                        Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $testWindow.FindName('WindowsUpdateButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.Status = $testWindow.FindName('StatusText').Text
                    $uiState.Enabled = $testWindow.FindName('WindowsUpdateButton').IsEnabled
                }
                catch { $uiState.Error = $_ }
                finally { if ($testWindow) { $testWindow.Close() } }
            })
        $uiTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
        $uiState.Status | Should -BeLike '*Unable to start Windows Update*Worker unavailable*'
        $uiState.Enabled | Should -BeTrue
    }

    It 'requests cancellation on closure, waits safely for the worker, then exits zero' {
        $Phase = 'SetupComplete'
        $Preview = $false
        Mock Start-OOBEMenuUpdateWorker {
            param($Type, $State)
            $uiState.WorkerState = $State
            $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
            $runspace.Open()
            $pipeline = [PowerShell]::Create()
            $pipeline.Runspace = $runspace
            [void]$pipeline.AddScript(@'
param($state)
$deadline = [Diagnostics.Stopwatch]::StartNew()
while (-not $state.CancelRequested -and $deadline.Elapsed.TotalSeconds -lt 5) {
            Start-Sleep -Milliseconds 20
}
Start-Sleep -Milliseconds 100
$state.Status = 'Cancelled safely.'
$state.Messages.Enqueue($state.Status)
'@).AddArgument($State)
            return [pscustomobject]@{ Pipeline = $pipeline; Runspace = $runspace; Handle = $pipeline.BeginInvoke() }
        }
        $uiTimer.Add_Tick({
                $uiTimer.Stop()
                $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                        Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                        Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $testWindow.FindName('WindowsUpdateButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    $uiState.UpdatesDisabled = -not $testWindow.FindName('DriverUpdateButton').IsEnabled
                    $testWindow.Close()
                    $uiState.DeferredClosure = $testWindow.IsVisible
                    $uiState.CancelRequested = $uiState.WorkerState.CancelRequested
                }
                catch { $uiState.Error = $_; if ($testWindow) { $testWindow.Close() } }
            })
        $uiTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
        $uiState.UpdatesDisabled | Should -BeTrue
        $uiState.DeferredClosure | Should -BeTrue
        $uiState.CancelRequested | Should -BeTrue
        $uiState.WorkerState.Status | Should -Be 'Cancelled safely.'
        Should -Invoke Start-OOBEMenuUpdateWorker -Times 1 -Exactly
    }

    It 'reports asynchronous worker errors and restores controls without closing the menu' {
        $Phase = 'SetupComplete'
        $Preview = $false
        $uiState.Started = $false
        $uiState.Ticks = 0
        Mock Start-OOBEMenuUpdateWorker {
            $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
            $runspace.Open()
            $pipeline = [PowerShell]::Create()
            $pipeline.Runspace = $runspace
            [void]$pipeline.AddScript("throw 'Simulated worker failure'")
            return [pscustomobject]@{ Pipeline = $pipeline; Runspace = $runspace; Handle = $pipeline.BeginInvoke() }
        }
        $uiTimer.Add_Tick({
            $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                Select-Object -ExpandProperty RootVisual)[0]
            try {
                $uiState.Ticks++
                if (-not $uiState.Started) {
                    $uiState.Started = $true
                    $testWindow.FindName('WindowsUpdateButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                    return
                }
                if (-not $testWindow.FindName('WindowsUpdateButton').IsEnabled -and $uiState.Ticks -lt 50) { return }
                $uiTimer.Stop()
                $uiState.Status = $testWindow.FindName('StatusText').Text
                $uiState.Enabled = $testWindow.FindName('WindowsUpdateButton').IsEnabled
                $uiState.Visible = $testWindow.IsVisible
                $testWindow.Close()
            }
            catch { $uiState.Error = $_; $uiTimer.Stop(); if ($testWindow) { $testWindow.Close() } }
        })
        $uiTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
        $uiState.Status | Should -BeLike '*Windows Update worker failed*Simulated worker failure*'
        $uiState.Enabled | Should -BeTrue
        $uiState.Visible | Should -BeTrue
    }

    It 'returns zero when Escape closes the menu' {
        $uiTimer.Add_Tick({
                $uiTimer.Stop()
                $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                        Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                        Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $key = [System.Windows.Input.KeyEventArgs]::new(
                        [System.Windows.Input.Keyboard]::PrimaryDevice,
                        [System.Windows.PresentationSource]::FromVisual($testWindow), 0,
                        [System.Windows.Input.Key]::Escape
                    )
                    $key.RoutedEvent = [System.Windows.UIElement]::PreviewKeyDownEvent
                    $testWindow.RaiseEvent($key)
                    $uiState.Handled = $key.Handled
                }
                catch { $uiState.Error = $_; if ($testWindow) { $testWindow.Close() } }
            })
        $uiTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
        $uiState.Handled | Should -BeTrue
    }

    It 'returns zero when the title-bar close button closes the menu' {
        $uiTimer.Add_Tick({
                $uiTimer.Stop()
                $testWindow = @([System.Windows.PresentationSource]::CurrentSources |
                        Where-Object { $_.RootVisual -is [System.Windows.Window] } |
                        Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $testWindow.FindName('CloseButton').RaiseEvent(
                        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    )
                }
                catch { $uiState.Error = $_; if ($testWindow) { $testWindow.Close() } }
            })
        $uiTimer.Start()
        Show-OOBEMenuWindow | Should -Be 0
        $uiState.Error | Should -BeNullOrEmpty
    }
}
