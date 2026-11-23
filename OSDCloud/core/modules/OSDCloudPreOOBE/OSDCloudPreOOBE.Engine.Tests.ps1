Import-Module "$PSScriptRoot\OSDCloudPreOOBE.psd1" -Force
InModuleScope OSDCloudPreOOBE {
    BeforeAll {
        $Preview = $true
        Initialize-OOBEMenuNative
    }

    Describe 'PreOOBE ordered scheduler' {
        BeforeEach {
            Mock Get-OSDCloudPreOOBEApplication {}
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

        It 'appends checked applications after drivers, passes their paths, and skips unchecked applications' {
            Mock Get-OSDCloudPreOOBEApplication {
                [pscustomobject]@{ Name = 'Local App'; Path = 'C:\Windows\Setup\PreOOBE\Local App\Invoke-AppDeployToolkit.exe' }
                [pscustomobject]@{ Name = 'USB App [G:]'; Path = 'G:\OSDCloud\core\PreOOBE\USB App\Invoke-AppDeployToolkit.exe' }
            }
            $engine = New-OSDCloudPreOOBEState
            $engine.Started = $true
            $engine.StepDelaySeconds = 0
            $engine.Tasks[5].Enabled = $false
            1..7 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
            ($script:types -join ',') | Should -Be 'DriverPack,Time,Software,Driver,Application'
            $engine.Tasks[4].Name | Should -Be 'Local App'
            $engine.Tasks[4].Outcome | Should -Be Succeeded
            $engine.Tasks[5].Outcome | Should -Be Skipped
            Should -Invoke Start-OOBEMenuUpdateWorker -Times 1 -Exactly -ParameterFilter {
                $Type -eq 'Application' -and $State.ApplicationPath -eq 'C:\Windows\Setup\PreOOBE\Local App\Invoke-AppDeployToolkit.exe'
            }
            $engine.Complete | Should -BeTrue
        }

        It 'waits for an active application on close without requesting cancellation' {
            $engine.Started = $true
            $engine.Tasks[0].Type = 'Application'
            $engine.Tasks[0] | Add-Member NoteProperty Path 'G:\OSDCloud\core\PreOOBE\App\Invoke-AppDeployToolkit.exe'
            Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
            $engine.Worker.Handle.IsCompleted = $false
            $engine.CloseRequested = $true
            Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
            $engine.Shared.CancelRequested | Should -BeFalse
            $engine.Done | Should -BeFalse
            $engine.Worker.Handle.IsCompleted = $true
            Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
            $engine.Done | Should -BeTrue
            $engine.Tasks[0].Outcome | Should -Be Succeeded
        }

        It 'skips default-unchecked applications but runs a rechecked custom command with its metadata' {
            $script:customCommand = [pscustomobject]@{
                Executable = 'AgentBootstrapper.exe'; WorkingDirectory = 'G:\OSDCloud\core\PreOOBE\Agent'
                Arguments = '--certificate AgentRegistration.cer --startDeployment --wait'
            }
            Mock Get-OSDCloudPreOOBEApplication {
                [pscustomobject]@{
                    Name = 'Unchecked App'; Path = 'G:\OSDCloud\core\PreOOBE\Agent\AgentBootstrapper.exe'
                    DefaultSelected = $false; Command = $script:customCommand
                }
                [pscustomobject]@{
                    Name = 'Rechecked App'; Path = 'G:\OSDCloud\core\PreOOBE\Agent\AgentBootstrapper.exe'
                    DefaultSelected = $false; Command = $script:customCommand
                }
            }
            $engine = New-OSDCloudPreOOBEState
            $engine.Tasks[4].Enabled | Should -BeFalse
            $engine.Tasks[5].Enabled | Should -BeFalse
            $engine.Tasks[5].Enabled = $true
            $engine.Started = $true
            $engine.StepDelaySeconds = 0
            1..7 | ForEach-Object { Update-OSDCloudPreOOBEState -State $engine -PreviewOnly }
            $engine.Tasks[4].Outcome | Should -Be Skipped
            $engine.Tasks[5].Outcome | Should -Be Succeeded
            Should -Invoke Start-OOBEMenuUpdateWorker -Times 1 -Exactly -ParameterFilter {
                $Type -eq 'Application' -and $State.ApplicationCommand -eq $script:customCommand -and
                $State.ApplicationPath -eq 'G:\OSDCloud\core\PreOOBE\Agent\AgentBootstrapper.exe'
            }
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
            ($engine.Output -join "`n") | Should -BeLike '*Simulated startup error*Shell*'
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
            $engine.Output[0] | Should -Be "Running OS clock at start: $($engine.StartClock.Local.ToString('F'))."
            $engine.Output[1] | Should -Be "Time zone: $([TimeZoneInfo]::Local.Id) (UTC$($engine.StartClock.Local.ToString('zzz')))."
            $engine.Output[2] | Should -Be "UTC at start: $($engine.StartClock.Utc.ToString('o'))."
            $engine.Output[0..2] -join '' | Should -Not -Match ';'
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

        It 'shows live installer output while running and logs it in one batch per tick, including after exit' {
            Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
            $engine.Worker.Handle.IsCompleted = $false
            $engine.Shared.ProcessOutput.Enqueue('App: one')
            $engine.Shared.ProcessOutput.Enqueue('App [stderr]: two')
            Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
            $engine.Output[-2..-1] | Should -Be @('App: one', 'App [stderr]: two')
            Should -Invoke Write-OOBEMenuLog -Times 1 -Exactly -ParameterFilter {
                $Message.Count -eq 2 -and $Message[0] -eq 'App: one' -and $Message[1] -eq 'App [stderr]: two'
            }
            $engine.Shared.ProcessOutput.Enqueue('App: last')
            $engine.Worker.Handle.IsCompleted = $true
            Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
            $engine.Output | Should -Contain 'App: last'
        }

        It 'passes the application label to the worker for output prefixes' {
            $engine.Tasks = @([pscustomobject]@{
                Type = 'Application'; Name = 'Agent [G:]'; Path = 'G:\OSDCloud\core\PreOOBE\Agent\Invoke-AppDeployToolkit.exe'
                Command = $null; Enabled = $true; Outcome = 'Pending'; DurationMs = 0L; Started = $null; Finished = $null
            })
            Mock Start-OOBEMenuUpdateWorker { $script:sharedName = $State.ApplicationName; throw 'stop here' }
            Update-OSDCloudPreOOBEState -State $engine -PreviewOnly
            $script:sharedName | Should -Be 'Agent [G:]'
        }

        It 'appends output in one update and keeps only the most recent lines' {
            $box = [pscustomobject]@{ Text = ''; Appends = 0 }
            $box | Add-Member ScriptMethod AppendText { param($value) $this.Text += $value; $this.Appends++ }
            $box | Add-Member ScriptMethod ScrollToEnd {}
            $ui = @{ OutputCount = 0 }
            $output = [Collections.Generic.List[string]]::new()
            1..11 | ForEach-Object { $output.Add("line $_") }
            Add-OSDCloudPreOOBEOutputText -TextBox $box -Output $output -Ui $ui -MaximumLines 10
            $box.Appends | Should -Be 1
            ($box.Text -split "`r`n" | Where-Object { $_ }).Count | Should -Be 11
            $output.Add('line 12')
            Add-OSDCloudPreOOBEOutputText -TextBox $box -Output $output -Ui $ui -MaximumLines 10
            $box.Text | Should -Be ((3..12 | ForEach-Object { "line $_`r`n" }) -join '')
            $ui.OutputCount | Should -Be 12
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
            Mock Invoke-OSDCloudPreOOBEWirelessRecovery { $false }
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

        It 'publishes separate detail lines while keeping the primary status and literal semicolons intact' {
            $lines = @('Installing application.', 'Output: C:\Tools; Cache\install.log', 'Waiting for safe completion.')
            Write-OOBEMenuUpdateStatus -State $state -Message $lines
            $state.Status | Should -Be $lines[0]
            $state.Messages.ToArray() | Should -Be $lines
            Should -Invoke Write-OOBEMenuLog -Times 1 -Exactly -ParameterFilter {
                $Message.Count -eq 3 -and $Message[1] -eq 'Output: C:\Tools; Cache\install.log'
            }
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

        It 'offers wireless recovery after failure and starts updates only after the internet probe succeeds' {
            $script:checks = 0
            Mock Test-OSDCloudPreOOBEConnectivity {
                $script:checks++
                [pscustomobject]@{ Connected = ($script:checks -gt 1); Reason = 'offline' }
            }
            Mock Invoke-OSDCloudPreOOBEWirelessRecovery { $true }
            Invoke-OSDCloudPreOOBETask -Type Software -State $state
            $state.Outcome | Should -Be Succeeded
            Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 1 -Exactly
            Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 2 -Exactly
            Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 1 -Exactly
        }

        It 'does not treat wireless association as internet access and bounds DHCP retries' {
            Mock Test-OSDCloudPreOOBEConnectivity { [pscustomobject]@{ Connected = $false; Reason = 'captive portal' } }
            Mock Invoke-OSDCloudPreOOBEWirelessRecovery { $true }
            Mock Start-Sleep {}
            Invoke-OSDCloudPreOOBETask -Type Driver -State $state
            $state.Outcome | Should -Be Skipped
            Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 4 -Exactly
            Should -Invoke Start-Sleep -Times 2 -Exactly
            Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 0 -Exactly
        }

        It 'cancels without starting updates when closed during wireless recovery' {
            Mock Test-OSDCloudPreOOBEConnectivity { [pscustomobject]@{ Connected = $false; Reason = 'offline' } }
            Mock Invoke-OSDCloudPreOOBEWirelessRecovery { $State.CancelRequested = $true; $false }
            Invoke-OSDCloudPreOOBETask -Type Software -State $state
            $state.Outcome | Should -Be Cancelled
            Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 0 -Exactly
        }

        It 'does not offer wireless recovery when internet is already connected' {
            Invoke-OSDCloudPreOOBETask -Type Driver -State $state
            Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 0 -Exactly
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
            Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 0 -Exactly
        }

        It 'does not gate internet time retrieval on the HTTPS connectivity probe' {
            Invoke-OSDCloudPreOOBETask -Type Time -State $state
            $state.Outcome | Should -Be Succeeded
            Should -Invoke Sync-OSDCloudPreOOBETime -Times 1 -Exactly
            Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 0 -Exactly
            Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 0 -Exactly
            Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 0 -Exactly
        }

        It 'recovers failed time sync over Wi-Fi and retries time before any HTTPS probe' {
            $script:timeCalls = 0
            $script:timeOrder = [Collections.Generic.List[string]]::new()
            Mock Sync-OSDCloudPreOOBETime {
                $script:timeOrder.Add('Time')
                $script:timeCalls++
                if ($script:timeCalls -eq 1) { throw 'No network' }
                $State.Succeeded = $true
                $State.Outcome = 'Succeeded'
            }
            Mock Invoke-OSDCloudPreOOBEWirelessRecovery { $script:timeOrder.Add('Wi-Fi'); $true }
            Mock Start-Sleep {}
            Invoke-OSDCloudPreOOBETask -Type Time -State $state
            $state.Outcome | Should -Be Succeeded
            ($script:timeOrder -join ',') | Should -Be 'Time,Wi-Fi,Time'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
            Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 0 -Exactly
            Should -Invoke Invoke-OOBEMenuWindowsUpdate -Times 0 -Exactly
        }

        It 'keeps failed time sync failed when Wi-Fi recovery is skipped or no adapter is available' {
            Mock Sync-OSDCloudPreOOBETime { throw 'Time source unavailable' }
            Invoke-OSDCloudPreOOBETask -Type Time -State $state
            $state.Outcome | Should -Be Failed
            $state.Succeeded | Should -BeFalse
            Should -Invoke Sync-OSDCloudPreOOBETime -Times 1 -Exactly
            Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 1 -Exactly
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*Time source unavailable*'
        }

        It 'bounds time recovery to one dialog and one retry when the time source remains unavailable' {
            Mock Sync-OSDCloudPreOOBETime { throw 'Time source blocked' }
            Mock Invoke-OSDCloudPreOOBEWirelessRecovery { $true }
            Mock Start-Sleep {}
            Invoke-OSDCloudPreOOBETask -Type Time -State $state
            $state.Outcome | Should -Be Failed
            Should -Invoke Sync-OSDCloudPreOOBETime -Times 2 -Exactly
            Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 1 -Exactly
        }

        It 'cancels time recovery without retrying when closed during <Stage>' -TestCases @(
            @{ Stage = 'time request' }, @{ Stage = 'Wi-Fi dialog' }, @{ Stage = 'DHCP wait' }
        ) {
            param($Stage)
            Mock Sync-OSDCloudPreOOBETime {
                if ($Stage -eq 'time request') { $State.CancelRequested = $true }
                throw 'No network'
            }
            Mock Invoke-OSDCloudPreOOBEWirelessRecovery {
                if ($Stage -eq 'Wi-Fi dialog') { $State.CancelRequested = $true }
                $true
            }
            Mock Start-Sleep { $state.CancelRequested = $true }
            Invoke-OSDCloudPreOOBETask -Type Time -State $state
            $state.Outcome | Should -Be Cancelled
            Should -Invoke Sync-OSDCloudPreOOBETime -Times 1 -Exactly
            if ($Stage -eq 'time request') { Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 0 -Exactly }
            else { Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 1 -Exactly }
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
            Mock Get-OSDCloudPreOOBEApplication {}
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'C:\Windows\Temp\osdcloud-logs\Autopilot.csv' }
            Mock Get-OOBEMenuContext {
                [pscustomobject]@{ IsSystem = $false; IsInputDesktop = $true; Identity = 'Preview' }
            }
            $Preview = $true
            $script:renderLog = [Collections.Generic.List[string]]::new()
            Mock Write-OOBEMenuLog { $script:renderLog.Add($Message) }
            Mock Set-Content {}
            Mock Write-Error {}
            Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
            $result = @{ Error = $null }
            $uiProbeTimer = [Windows.Threading.DispatcherTimer]::new()
            $uiProbeTimer.Interval = [TimeSpan]::FromMilliseconds(100)
        }
        AfterEach { $uiProbeTimer.Stop() }

        It 'focuses highlighted Start and tabs through every action and offscreen application in both directions' {
            Mock Get-OSDCloudPreOOBEApplication {
                1..12 | ForEach-Object {
                    [pscustomobject]@{ Name = "Custom App $_"; Path = "G:\OSDCloud\core\PreOOBE\App$_\Invoke-AppDeployToolkit.exe" }
                }
            }
            $uiProbeTimer.Add_Tick({
                $uiProbeTimer.Stop()
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $start = $testWindow.FindName('StepButton')
                    $result.InitialFocus = [Windows.Input.Keyboard]::FocusedElement -eq $start
                    $testWindow.UpdateLayout()
                    $result.Highlight = $start.Background.Color.ToString()
                    $result.FocusBorder = $start.Template.FindName('ButtonBorder', $start).BorderThickness.Left
                    $result.Default = $start.IsDefault
                    $result.Forward = [Collections.Generic.List[object]]::new()
                    $result.Backward = [Collections.Generic.List[object]]::new()
                    foreach ($direction in 'Next','Previous') {
                        [void]$start.Focus()
                        if ($direction -eq 'Next') { $visited = $result.Forward }
                        else { $visited = $result.Backward }
                        for ($index = 0; $index -lt 40; $index++) {
                            [void]([Windows.Input.Keyboard]::FocusedElement).MoveFocus(
                                [Windows.Input.TraversalRequest]::new([Windows.Input.FocusNavigationDirection]::$direction))
                            $focused = [Windows.Input.Keyboard]::FocusedElement
                            $visited.Add($focused)
                            if ($focused -eq $start) { break }
                        }
                    }
                    $result.Expected = @(
                        foreach ($name in 'PaneToggleButton','ToolsMenuButton','ShellMenuButton','MinimizeButton',
                            'MaximizeButton','CloseButton','TaskSummaryScrollViewer','OutputTextBox','StepButton') {
                            $testWindow.FindName($name)
                        }
                        $testWindow.FindName('StepPanel').Children
                    )
                    $result.Hidden = $testWindow.FindName('ContinueOobeButton')
                }
                catch { $result.Error = "$($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)" }
                finally { $testWindow.Close() }
            })
            $uiProbeTimer.Start()
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            $result.InitialFocus | Should -BeTrue
            $result.Highlight | Should -Be '#FF31D1FF'
            $result.FocusBorder | Should -Be 3
            $result.Default | Should -BeTrue
            foreach ($control in $result.Expected) {
                $result.Forward | Should -Contain $control
                $result.Backward | Should -Contain $control
            }
            $result.Forward | Should -Not -Contain $result.Hidden
            $result.Forward[-1] | Should -Be $result.Expected[8]
            $result.Backward[-1] | Should -Be $result.Expected[8]
        }

        It 'focuses the first Tools and Shell item and reaches every menu action with Tab' {
            $uiProbeTimer.Add_Tick({
                $uiProbeTimer.Stop()
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $result.Menus = @(
                        foreach ($name in 'ToolsMenuButton','ShellMenuButton') {
                            $button = $testWindow.FindName($name)
                            [void]$button.Focus()
                            $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                            $menu = $button.ContextMenu
                            $visited = [Collections.Generic.List[object]]::new()
                            $firstFocused = [Windows.Input.Keyboard]::FocusedElement -eq $menu.Items[0]
                            for ($index = 0; $index -lt $menu.Items.Count; $index++) {
                                $visited.Add([Windows.Input.Keyboard]::FocusedElement)
                                [void]([Windows.Input.Keyboard]::FocusedElement).MoveFocus(
                                    [Windows.Input.TraversalRequest]::new([Windows.Input.FocusNavigationDirection]::Next))
                            }
                            [pscustomobject]@{ FirstFocused = $firstFocused; Expected = @($menu.Items); Visited = $visited }
                            $menu.IsOpen = $false
                        }
                    )
                }
                catch { $result.Error = $_ }
                finally { $testWindow.Close() }
            })
            $uiProbeTimer.Start()
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            foreach ($menu in $result.Menus) {
                $menu.FirstFocused | Should -BeTrue
                foreach ($item in $menu.Expected) { $menu.Visited | Should -Contain $item }
            }
        }

        It 'keeps Retry, Continue and Continue to OOBE reachable when the focused action is replaced' {
            $script:uiStateTicks = 0
            Mock Update-OSDCloudPreOOBEState {
                if ($State.CloseRequested) { $State.Done = $true; return }
                $script:uiStateTicks++
                $State.Started = $true
                $State.Paused = $script:uiStateTicks -eq 1
                $State.PausedTask = $State.Tasks[2]
                $State.Complete = $script:uiStateTicks -gt 1
            }
            $result.Phase = 0
            $uiProbeTimer.Add_Tick({
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $retry = $testWindow.FindName('RetryButton')
                    if ($result.Phase -eq 0 -and $retry.IsVisible) {
                        $result.RetryFocused = [Windows.Input.Keyboard]::FocusedElement -eq $retry
                        [void]$retry.MoveFocus([Windows.Input.TraversalRequest]::new([Windows.Input.FocusNavigationDirection]::Next))
                        $result.ContinueFocused = [Windows.Input.Keyboard]::FocusedElement -eq $testWindow.FindName('ContinueButton')
                        $result.Phase = 1
                    }
                    $continueOobe = $testWindow.FindName('ContinueOobeButton')
                    if ($result.Phase -eq 1 -and $continueOobe.IsVisible) {
                        $result.OobeFocused = [Windows.Input.Keyboard]::FocusedElement -eq $continueOobe
                        $result.OobeDefault = $continueOobe.IsDefault
                        $uiProbeTimer.Stop()
                        $testWindow.Close()
                    }
                }
                catch {
                    $result.Error = $_
                    $uiProbeTimer.Stop()
                    $testWindow.Close()
                }
            })
            $uiProbeTimer.Start()
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            $result.RetryFocused | Should -BeTrue
            $result.ContinueFocused | Should -BeTrue
            $result.OobeFocused | Should -BeTrue
            $result.OobeDefault | Should -BeTrue
        }

        It 'keeps the standard arrow visible throughout the window and both menus without enlarging it' {
            $uiProbeTimer.Add_Tick({
                $uiProbeTimer.Stop()
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $result.Cursor = $testWindow.Cursor
                    $result.Forced = $testWindow.ForceCursor
                    $result.Menus = @(
                        foreach ($name in 'ToolsMenuButton','ShellMenuButton') {
                            $menu = $testWindow.FindName($name).ContextMenu
                            [pscustomobject]@{ Cursor = $menu.Cursor; Forced = $menu.ForceCursor }
                        }
                    )
                }
                catch { $result.Error = $_ }
                finally { $testWindow.Close() }
            })
            $uiProbeTimer.Start()
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            $result.Cursor | Should -Be ([Windows.Input.Cursors]::Arrow)
            $result.Forced | Should -BeTrue
            foreach ($menu in $result.Menus) {
                $menu.Cursor | Should -Be $result.Cursor
                $menu.Forced | Should -BeTrue
            }
        }

        It 'renders discovered application checkboxes after Updating Drivers and allows unchecking' {
            Mock Get-OSDCloudPreOOBEApplication {
                1..12 | ForEach-Object {
                    [pscustomobject]@{ Name = "Custom App $_ [G:]"; Path = "G:\OSDCloud\core\PreOOBE\App$_\Invoke-AppDeployToolkit.exe" }
                }
            }
            $uiProbeTimer.Add_Tick({
                $uiProbeTimer.Stop()
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $boxes = $testWindow.FindName('StepPanel').Children
                    $result.Count = $boxes.Count
                    $result.Drivers = $boxes[3].Content
                    $result.App = $boxes[4].Content
                    $result.Checked = $boxes[4].IsChecked
                    $boxes[4].IsChecked = $false
                    $result.Enabled = $boxes[4].Tag.Enabled
                    $result.Last = $testWindow.FindName('TaskText15').Text
                    $testWindow.UpdateLayout()
                    $result.OutputHeight = $testWindow.FindName('OutputTextBox').ActualHeight
                }
                catch { $result.Error = $_ }
                finally { $testWindow.Close() }
            })
            $uiProbeTimer.Start()
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            $result.Count | Should -Be 16
            $result.Drivers | Should -Be 'Updating Drivers'
            $result.App | Should -Be 'Custom App 1 [G:]'
            $result.Checked | Should -BeTrue
            $result.Enabled | Should -BeFalse
            $result.Last | Should -Be 'Custom App 12 [G:] - Pending'
            $result.OutputHeight | Should -BeGreaterThan 0
        }

        It 'shows no horizontal scrollbar in the collapsed step sidebar' {
            $uiProbeTimer.Add_Tick({
                $uiProbeTimer.Stop()
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $testWindow.FindName('PaneToggleButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                    $testWindow.UpdateLayout()
                    $sidebar = [Windows.Media.VisualTreeHelper]::GetParent($testWindow.FindName('StepPanel'))
                    while ($sidebar -isnot [Windows.Controls.ScrollViewer]) { $sidebar = [Windows.Media.VisualTreeHelper]::GetParent($sidebar) }
                    $result.Horizontal = $sidebar.ComputedHorizontalScrollBarVisibility
                }
                catch { $result.Error = $_ }
                finally { $testWindow.Close() }
            })
            $uiProbeTimer.Start()
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            $result.Horizontal | Should -Be ([Windows.Visibility]::Collapsed)
        }

        It 'returns the focused menu button to its normal background after a click' {
            $uiProbeTimer.Add_Tick({
                $uiProbeTimer.Stop()
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $button = $testWindow.FindName('PaneToggleButton')
                    $result.Focused = $button.Focus()
                    $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                    $testWindow.UpdateLayout()
                    $result.Background = $button.Template.FindName('CaptionBorder', $button).Background.Color.ToString()
                }
                catch { $result.Error = $_ }
                finally { $testWindow.Close() }
            })
            $uiProbeTimer.Start()
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            $result.Focused | Should -BeTrue
            $result.Background | Should -Be '#00FFFFFF'
        }

        It 'renders a manifest application initially unchecked and allows selecting it' {
            Mock Get-OSDCloudPreOOBEApplication {
                [pscustomobject]@{ Name = 'Optional Agent'; Path = 'G:\OSDCloud\core\PreOOBE\Agent\AgentBootstrapper.exe'; DefaultSelected = $false }
            }
            $uiProbeTimer.Add_Tick({
                $uiProbeTimer.Stop()
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $box = $testWindow.FindName('StepPanel').Children[4]
                    $result.Checked = $box.IsChecked
                    $result.InitialEnabled = $box.Tag.Enabled
                    $box.IsChecked = $true
                    $result.Enabled = $box.Tag.Enabled
                }
                catch { $result.Error = $_ }
                finally { $testWindow.Close() }
            })
            $uiProbeTimer.Start()
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            $result.Checked | Should -BeFalse
            $result.InitialEnabled | Should -BeFalse
            $result.Enabled | Should -BeTrue
        }

        It 'opens Wi-Fi manually from Tools without starting tasks and resumes the scheduler afterward' {
            Mock Invoke-OSDCloudPreOOBEWirelessRecovery {
                $result.MainDisabled = -not $testWindow.IsEnabled
                $State.Messages.Enqueue('Manual Wi-Fi connection completed.')
                $true
            }
            Mock Start-OOBEMenuUpdateWorker { throw 'Manual Wi-Fi must not start a task' }
            $result.Ticks = 0
            $uiProbeTimer.Add_Tick({
                $result.Ticks++
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    if ($result.Ticks -eq 1) {
                        $item = $testWindow.FindName('ToolsMenuButton').ContextMenu.Items |
                            Where-Object Header -eq 'Connect to Wi-Fi'
                        $item.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
                        $result.MainRestored = $testWindow.IsEnabled
                        return
                    }
                    if ($result.Ticks -lt 5) { return }
                    $result.Output = $testWindow.FindName('OutputTextBox').Text
                    $result.Start = $testWindow.FindName('StepButton').Content
                    $uiProbeTimer.Stop()
                    $testWindow.Close()
                }
                catch {
                    $result.Error = $_
                    $uiProbeTimer.Stop()
                    $testWindow.Close()
                }
            })
            $Preview = $false
            try {
                $uiProbeTimer.Start()
                Show-OOBEMenuWindow | Should -Be 0 -Because ($script:renderLog -join '; ')
            }
            finally { $Preview = $true }
            $result.Error | Should -BeNullOrEmpty
            $result.MainDisabled | Should -BeTrue
            $result.MainRestored | Should -BeTrue
            $result.Output | Should -BeLike '*Manual Wi-Fi connection completed.*'
            $result.Start | Should -Be 'Start'
            Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 1 -Exactly
            Should -Invoke Start-OOBEMenuUpdateWorker -Times 0 -Exactly
        }

        It 'shows autopilot only when present and keeps shell and file actions inert in preview: <AutopilotExists>' -TestCases @(
            @{ AutopilotExists = $false }, @{ AutopilotExists = $true }
        ) {
            param($AutopilotExists)
            Mock Test-Path { $AutopilotExists } -ParameterFilter { $LiteralPath -eq 'C:\Windows\Temp\osdcloud-logs\Autopilot.csv' }
            Mock Set-Date { throw 'Preview must not set the clock' }
            Mock Start-Process { throw 'Preview must not launch a process' }
            Mock Invoke-OSDCloudPreOOBEWirelessRecovery { throw 'Preview must not open Wi-Fi recovery' }
            $result.Ticks = 0
            $uiProbeTimer.Add_Tick({
                $result.Ticks++
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object {
                    $_.RootVisual -is [Windows.Window] -and $_.RootVisual.Title -like 'Recast Software - OSDCloud PreOOBE*'
                } | Select-Object -ExpandProperty RootVisual)[0]
                try {
                    if ($result.Ticks -eq 1) {
                        $testWindow.FindName('ShellMenuButton').ContextMenu.Items[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
                        $items = $testWindow.FindName('ToolsMenuButton').ContextMenu.Items
                        $result.Headers = @($items | ForEach-Object Header)
                        foreach ($item in $items) {
                            $item.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
                        }
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
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            $result.Output | Should -BeLike '*Preview: would open *cmd.exe /d /k*'
            $result.Output | Should -BeLike '*Preview: would open *notepad.exe*"*\OOBE.cmd"*'
            $result.Output | Should -BeLike '*Preview: would open *notepad.exe*"*\SetupComplete.cmd"*'
            $result.Headers | Should -Contain 'Connect to Wi-Fi'
            $result.Output | Should -BeLike '*Preview: would open Connect to Wi-Fi*'
            Should -Invoke Invoke-OSDCloudPreOOBEWirelessRecovery -Times 0 -Exactly
            if ($AutopilotExists) {
                $result.Headers | Should -Contain 'Open autopilot.csv'
                $result.Output | Should -BeLike '*Preview: would open *notepad.exe*"C:\Windows\Temp\osdcloud-logs\Autopilot.csv"*'
            }
            else {
                $result.Headers | Should -Not -Contain 'Open autopilot.csv'
                $result.Output | Should -Not -BeLike '*Autopilot.csv*'
            }
            Should -Invoke Set-Date -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'starts with expanded steps and Tools without account or calendar controls; output fills height and closure returns zero' {
            $uiProbeTimer.Add_Tick({
                $uiProbeTimer.Stop()
                $testWindow = @([Windows.PresentationSource]::CurrentSources | Where-Object { $_.RootVisual -is [Windows.Window] } |
                    Select-Object -ExpandProperty RootVisual)[0]
                try {
                    $result.Title = $testWindow.Title
                    $result.Topmost = $testWindow.Topmost
                    $result.TitleText = $testWindow.FindName('TitleText').Text
                    $result.User = $testWindow.FindName('UserBadge')
                    $result.StepButton = $testWindow.FindName('StepButton').Content
                    $result.ContinueOobe = $testWindow.FindName('ContinueOobeButton').Visibility
                    $result.Steps = @($testWindow.FindName('StepPanel').Children).Count
                    $result.Expanded = $testWindow.FindName('SidebarColumn').Width.Value
                    $result.StepName = $testWindow.FindName('StepPanel').Children[0].Content
                    $result.ToggleName = [Windows.Automation.AutomationProperties]::GetName($testWindow.FindName('PaneToggleButton'))
                    $testWindow.FindName('PaneToggleButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                    $result.Collapsed = $testWindow.FindName('SidebarColumn').Width.Value
                    $result.CollapsedStep = $testWindow.FindName('StepPanel').Children[0].Content
                    $result.Resize = [Windows.Shell.WindowChrome]::GetWindowChrome($testWindow).ResizeBorderThickness.Right
                    $result.Context = $testWindow.FindName('ContextText').Text
                    $result.Tools = @($testWindow.FindName('ToolsMenuButton').ContextMenu.Items | ForEach-Object Header)
                    $result.Shells = @($testWindow.FindName('ShellMenuButton').ContextMenu.Items | ForEach-Object Header)
                    $result.Calendar = $testWindow.FindName('CalendarButton')
                    $result.Time = $testWindow.FindName('TaskText1').Text
                    $result.SkipSoftware = $testWindow.FindName('SkipSoftwareButton')
                    $result.SkipDrivers = $testWindow.FindName('SkipDriversButton')
                    $testWindow.FindName('ToolsMenuButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                    $result.Open = $testWindow.FindName('ToolsMenuButton').ContextMenu.IsOpen
                    $testWindow.FindName('ToolsMenuButton').ContextMenu.IsOpen = $false
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
            Invoke-OSDCloudPreOOBE -Preview | Should -Be 0 -Because ($script:renderLog -join '; ')
            $result.Error | Should -BeNullOrEmpty
            $version = (Import-PowerShellDataFile $OSDCloudPreOOBEModulePath).ModuleVersion
            $result.Title | Should -Be "Recast Software - OSDCloud PreOOBE $version (Preview)"
            $result.TitleText | Should -Be "Recast Software - OSDCloud PreOOBE $version"
            $result.User | Should -BeNullOrEmpty
            $result.StepButton | Should -Be 'Start'
            $result.ContinueOobe | Should -Be ([Windows.Visibility]::Collapsed)
            $result.Steps | Should -Be 4
            $result.Collapsed | Should -Be 56
            $result.Expanded | Should -Be 300
            $result.StepName | Should -Be 'Driver unpack / install'
            $result.ToggleName | Should -Be 'Collapse steps'
            $result.CollapsedStep | Should -BeNullOrEmpty
            $result.Resize | Should -Be 8
            $result.Context | Should -Be 'Preview | No network or system changes'
            $result.Topmost | Should -BeTrue
            ($result.Tools -join ',') | Should -Be 'Connect to Wi-Fi,Open oobe.cmd,Open setupcomplete.cmd'
            ($result.Shells -join ',') | Should -Be 'CMD Prompt,Windows PowerShell'
            $result.Calendar | Should -BeNullOrEmpty
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
}
