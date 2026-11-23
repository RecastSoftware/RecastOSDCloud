Import-Module "$PSScriptRoot\OSDCloudPost.psd1" -Force
InModuleScope OSDCloudPost {
    BeforeAll { $Preview = $true }

    Describe 'Bounded Microsoft connectivity probe' {
        BeforeEach {
            Mock Write-OOBEMenuLog {}
            $state = @{ Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new(); CancelRequested = $false }
            $script:probe = @{ Content = 'Microsoft Connect Test'; Code = 200; Completes = $true; Calls = 0; Disposals = 0; WaitMs = 0; Urls = [Collections.Generic.List[string]]::new() }
            Mock New-Object {
                $headers = [pscustomobject]@{}
                $headers | Add-Member ScriptMethod TryAddWithoutValidation { param($name,$value) return $true }
                $client = [pscustomobject]@{ Timeout = $null; MaxResponseContentBufferSize = 0; DefaultRequestHeaders = $headers }
                $client | Add-Member ScriptMethod GetAsync {
                    param($url, $option)
                    $script:probe.Calls++; $script:probe.Urls.Add($url)
                    $read = [pscustomobject]@{}
                    $read | Add-Member ScriptMethod GetAwaiter { return $this }
                    $read | Add-Member ScriptMethod GetResult { return $script:probe.Content }
                    $content = [pscustomobject]@{ Read = $read }
                    $content | Add-Member ScriptMethod ReadAsStringAsync { return $this.Read }
                    $response = [pscustomobject]@{ StatusCode = $script:probe.Code; Content = $content }
                    $response | Add-Member ScriptMethod Dispose { $script:probe.Disposals++ }
                    $request = [pscustomobject]@{ Response = $response }
                    $request | Add-Member ScriptMethod Wait { param($milliseconds) $script:probe.WaitMs = $milliseconds; return $script:probe.Completes }
                    $request | Add-Member ScriptMethod GetAwaiter { return $this }
                    $request | Add-Member ScriptMethod GetResult { return $this.Response }
                    return $request
                }
                $client | Add-Member ScriptMethod CancelPendingRequests {}
                $client | Add-Member ScriptMethod Dispose { $script:probe.Disposals++ }
                $script:probe.Client = $client
                return $client
            } -ParameterFilter { $TypeName -eq 'System.Net.Http.HttpClient' }
        }

        It 'accepts the expected NCSI content over HTTP, validates HTTPS, and disposes transport resources' {
            $result = Test-OSDCloudPreOOBEConnectivity -State $state
            $result.Connected | Should -BeTrue
            $script:probe.Calls | Should -Be 2
            $script:probe.WaitMs | Should -Be 5000
            $script:probe.Client.Timeout.TotalSeconds | Should -Be 5
            $script:probe.Client.MaxResponseContentBufferSize | Should -Be 64
            $script:probe.Disposals | Should -Be 3
            $script:probe.Urls[0] | Should -Be 'http://www.msftconnecttest.com/connecttest.txt'
            $script:probe.Urls[1] | Should -Be 'https://sls.update.microsoft.com/'
        }

        It 'rejects captive portals and retries only twice' {
            $script:probe.Content = 'Login required'
            $result = Test-OSDCloudPreOOBEConnectivity -State $state
            $result.Connected | Should -BeFalse
            $result.Reason | Should -BeLike '*captive portal*'
            $script:probe.Calls | Should -Be 2
        }

        It 'rejects redirects rather than treating them as internet connectivity' {
            $script:probe.Code = 302
            $result = Test-OSDCloudPreOOBEConnectivity -State $state
            $result.Connected | Should -BeFalse
            $script:probe.Calls | Should -Be 2
        }

        It 'bounds request waits to two attempts of five seconds and reports timeout' {
            $script:probe.Completes = $false
            $result = Test-OSDCloudPreOOBEConnectivity -State $state
            $result.Connected | Should -BeFalse
            $result.Reason | Should -BeLike '*timed out*'
            ($script:probe.Calls * $script:probe.WaitMs) | Should -Be 10000
        }

        It 'does not create a request when cancellation was already requested' {
            $state.CancelRequested = $true
            $result = Test-OSDCloudPreOOBEConnectivity -State $state
            $result.Connected | Should -BeFalse
            Should -Invoke New-Object -Times 0 -Exactly
        }

        It 'runs TLS and clock troubleshooting only for certificate failures' {
            Mock Write-OSDCloudPreOOBETlsDiagnostic {}
            Mock Test-OSDCloudPreOOBEClockShift { [pscustomobject]@{ Connected = $false } }
            $script:probe.Completes = $false
            Test-OSDCloudPreOOBEConnectivity -State $state | Out-Null
            Should -Invoke Write-OSDCloudPreOOBETlsDiagnostic -Times 0 -Exactly
            $script:probe.Completes = $true
            $script:probe.Client = $null
            Mock New-Object {
                $client = [pscustomobject]@{ Timeout = $null; MaxResponseContentBufferSize = 0; DefaultRequestHeaders = [pscustomobject]@{} }
                $client.DefaultRequestHeaders | Add-Member ScriptMethod TryAddWithoutValidation { return $true }
                $client | Add-Member ScriptMethod GetAsync {
                    throw [Net.Http.HttpRequestException]::new('An error occurred while sending the request.',
                        [Security.Authentication.AuthenticationException]::new('The remote certificate is invalid according to the validation procedure.'))
                }
                $client | Add-Member ScriptMethod Dispose {}
                return $client
            } -ParameterFilter { $TypeName -eq 'System.Net.Http.HttpClient' }
            $result = Test-OSDCloudPreOOBEConnectivity -State $state
            $result.Connected | Should -BeFalse
            $result.CertificateError | Should -BeTrue
            Should -Invoke Write-OSDCloudPreOOBETlsDiagnostic -Times 1 -Exactly
            Should -Invoke Test-OSDCloudPreOOBEClockShift -Times 1 -Exactly
            Test-OSDCloudPreOOBEConnectivity -State $state -NoDiagnostics | Out-Null
            Should -Invoke Test-OSDCloudPreOOBEClockShift -Times 1 -Exactly
            Mock Test-OSDCloudPreOOBEClockShift { [pscustomobject]@{ Connected = $true } }
            (Test-OSDCloudPreOOBEConnectivity -State $state).Connected | Should -BeTrue
        }
    }

    Describe 'Clock shift troubleshooting' {
        BeforeEach {
            Mock Write-OOBEMenuLog {}
            Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $true } }
            $state = @{ Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new(); CancelRequested = $false; ClockTestActive = $false }
            $script:clockSets = [Collections.Generic.List[datetime]]::new()
            $script:activeDuringProbe = [Collections.Generic.List[bool]]::new()
            Mock Set-OSDCloudPreOOBEUtcClock { $script:clockSets.Add($UtcTime); $UtcTime }
            Mock Test-OSDCloudPreOOBEConnectivity { $script:activeDuringProbe.Add($State.ClockTestActive); [pscustomobject]@{ Connected = $false; Reason = 'certificate invalid' } }
        }

        It 'probes at +1 hour and -1 hour, restores the clock, then probes again' {
            $start = [datetime]::UtcNow
            $result = Test-OSDCloudPreOOBEClockShift -State $state
            $script:clockSets.Count | Should -Be 3
            ($script:clockSets[0] - $start).TotalMinutes | Should -BeGreaterThan 59
            ($script:clockSets[0] - $start).TotalMinutes | Should -BeLessThan 61
            ($start - $script:clockSets[1]).TotalMinutes | Should -BeGreaterThan 59
            ($start - $script:clockSets[1]).TotalMinutes | Should -BeLessThan 61
            [Math]::Abs(($script:clockSets[2] - $start).TotalSeconds) | Should -BeLessThan 5
            Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 3 -Exactly -ParameterFilter { $Attempts -eq 1 -and $NoDiagnostics }
            ($script:activeDuringProbe -join ',') | Should -Be 'True,True,False'
            $state.ClockTestActive | Should -BeFalse
            $result.Connected | Should -BeFalse
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*+1 hour failed*-1 hour failed*restored*unlikely to be the cause*'
        }

        It 'reports when only a shifted clock connects' {
            Mock Test-OSDCloudPreOOBEConnectivity { [pscustomobject]@{ Connected = ($script:clockSets.Count -eq 1); Reason = 'certificate invalid' } }
            Test-OSDCloudPreOOBEClockShift -State $state | Out-Null
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*+1 hour connected*works only with a shifted clock*'
        }

        It 'always restores the clock when a probe throws' {
            Mock Test-OSDCloudPreOOBEConnectivity { throw 'probe crashed' }
            { Test-OSDCloudPreOOBEClockShift -State $state } | Should -Throw '*probe crashed*'
            $script:clockSets.Count | Should -Be 2
            $state.ClockTestActive | Should -BeFalse
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*restored UTC*'
        }

        It 'does not change the clock without SYSTEM' {
            Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $false } }
            Test-OSDCloudPreOOBEClockShift -State $state | Should -BeNullOrEmpty
            Should -Invoke Set-OSDCloudPreOOBEUtcClock -Times 0 -Exactly
        }
    }

    Describe 'UTC clock setter' {
        It 'sets UTC through local time in the running time zone and verifies it' {
            $script:setDate = [datetime]::Now
            Mock Set-Date { $script:setDate = $Date }
            Mock Get-Date { [datetime]::SpecifyKind($script:setDate, [DateTimeKind]::Local) }
            $target = [datetime]::new(2026, 11, 3, 14, 9, 0, [DateTimeKind]::Utc)
            $after = Set-OSDCloudPreOOBEUtcClock -UtcTime $target
            $script:setDate.Kind | Should -Be Local
            $script:setDate | Should -Be ([TimeZoneInfo]::ConvertTimeFromUtc($target, [TimeZoneInfo]::Local))
            $after | Should -Be $target
        }

        It 'fails verification when the clock does not change' {
            Mock Set-Date {}
            Mock Get-Date { [datetime]::new(2020, 1, 1, 0, 0, 0, [DateTimeKind]::Local) }
            { Set-OSDCloudPreOOBEUtcClock -UtcTime ([datetime]::UtcNow) } | Should -Throw '*verification failed*'
        }
    }

    Describe 'User-facing task errors' {
        It 'shows only the innermost message and logs the full exception' {
            $web = [Net.WebException]::new("The remote name could not be resolved: 'www.google.com'")
            $wrapped = [Management.Automation.MethodInvocationException]::new('Exception calling "Wait"', [AggregateException]::new($web))
            Get-OSDCloudPreOOBEErrorMessage -Exception $wrapped | Should -Be "The remote name could not be resolved: 'www.google.com'"
        }

        It 'keeps stack traces out of the task output' {
            $script:logged = [Collections.Generic.List[string]]::new()
            Mock Write-OOBEMenuLog { $script:logged.Add($Message) }
            Mock Test-OSDCloudPreOOBEConnectivity { throw [AggregateException]::new([Net.WebException]::new('Name not resolved')) }
            $state = [hashtable]::Synchronized(@{ Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new(); CancelRequested = $false; RebootRequired = $false; Succeeded = $false; Outcome = 'Running'; DurationMs = 0L })
            Invoke-OSDCloudPreOOBETask -Type Software -State $state
            $output = $state.Messages.ToArray() -join "`n"
            $output | Should -BeLike '*Software task failed: Name not resolved*'
            $output | Should -Not -BeLike '*AggregateException*'
            ($script:logged -join "`n") | Should -BeLike '*System.AggregateException*'
        }
    }

    Describe 'Wireless recovery eligibility' {
        BeforeEach {
            $Preview = $false
            $state = @{ Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new(); CancelRequested = $false }
            Mock Write-OOBEMenuLog {}
            Mock Get-CimInstance { [pscustomobject]@{ NdisPhysicalMedium = 9 } }
            Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
            Mock Start-Service {}
            Mock Show-OSDCloudPreOOBEWireless { $true }
        }
        AfterEach { $Preview = $true }

        It 'offers the dialog only for physical wireless adapters' {
            Invoke-OSDCloudPreOOBEWirelessRecovery -State $state | Should -BeTrue
            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ClassName -eq 'MSFT_NetAdapter' -and $Filter -eq 'HardwareInterface = TRUE'
            }
            Should -Invoke Show-OSDCloudPreOOBEWireless -Times 1 -Exactly
            Mock Get-CimInstance { [pscustomobject]@{ NdisPhysicalMedium = 14 } }
            Invoke-OSDCloudPreOOBEWirelessRecovery -State $state | Should -BeFalse
            Should -Invoke Show-OSDCloudPreOOBEWireless -Times 1 -Exactly
        }

        It 'starts a stopped WLAN service before opening the dialog' {
            $service = [pscustomobject]@{ Status = 'Stopped' }
            $service | Add-Member ScriptMethod WaitForStatus { param($status, $timeout) }
            Mock Get-Service { $service }
            Invoke-OSDCloudPreOOBEWirelessRecovery -State $state | Should -BeTrue
            Should -Invoke Start-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'WlanSvc' }
        }

        It 'does not access hardware or display a dialog in preview or after cancellation' {
            $Preview = $true
            Invoke-OSDCloudPreOOBEWirelessRecovery -State $state | Should -BeFalse
            $Preview = $false
            $state.CancelRequested = $true
            Invoke-OSDCloudPreOOBEWirelessRecovery -State $state | Should -BeFalse
            Should -Invoke Get-CimInstance -Times 0 -Exactly
            Should -Invoke Show-OSDCloudPreOOBEWireless -Times 0 -Exactly
        }

        It 'reports wireless failures without leaking exception data and permits offline continuation' {
            Mock Show-OSDCloudPreOOBEWireless { throw 'sensitive profile data' }
            Invoke-OSDCloudPreOOBEWirelessRecovery -State $state | Should -BeFalse
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*could not start*continuing offline*'
            ($state.Messages.ToArray() -join "`n") | Should -Not -BeLike '*sensitive*'
            Should -Invoke Write-OOBEMenuLog -Times 0 -Exactly -ParameterFilter { $Message -like '*sensitive*' }
        }
    }

    Describe 'Temporary wireless profiles' {
        BeforeAll { Initialize-OSDCloudPreOOBEWireless }

        It 'builds in-memory WPA personal profiles with escaped credentials and the original SSID bytes' {
            $network = [Recast.PreOOBE.Wireless+Network]::new()
            $network.Auth = 6
            $network.Cipher = 4
            $network.SsidHex = '436166652026203C'
            $password = 'test&<password>'
            [xml]$wirelessProfile = [Recast.PreOOBE.Wireless]::ProfileXml($network, $password)
            $wirelessProfile.WLANProfile.SSIDConfig.SSID.hex | Should -Be $network.SsidHex
            $wirelessProfile.WLANProfile.MSM.security.sharedKey.keyMaterial | Should -Be $password
            $wirelessProfile.WLANProfile.MSM.security.authEncryption.authentication | Should -Be WPA2PSK
            $network.Auth = 9
            ([xml][Recast.PreOOBE.Wireless]::ProfileXml($network, $password)).WLANProfile.MSM.security.authEncryption.authentication |
                Should -Be WPA3SAE
        }

        It 'omits credentials for open networks and rejects unsupported enterprise or invalid personal credentials' {
            $network = [Recast.PreOOBE.Wireless+Network]::new()
            $network.SsidHex = '43616665'
            $network.Auth = 1
            [xml]$wirelessProfile = [Recast.PreOOBE.Wireless]::ProfileXml($network, 'ignored')
            $wirelessProfile.WLANProfile.MSM.security.sharedKey | Should -BeNullOrEmpty
            $network.Auth = 5
            $network.Cipher = 4
            { [Recast.PreOOBE.Wireless]::ProfileXml($network, 'password') } | Should -Throw '*saved Windows Wi-Fi profile*'
            $network.Auth = 6
            { [Recast.PreOOBE.Wireless]::ProfileXml($network, 'short') } | Should -Throw '*8 to 63*'
        }
    }

    Describe 'Wireless dialog automation' -Tag Interactive {
        BeforeEach {
            $Preview = $false
            Initialize-OSDCloudPreOOBEWireless
            Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
            $state = @{ Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new(); CancelRequested = $false }
            $script:associated = $false
            $script:disposed = $false
            $script:connectCalls = 0
            Mock Write-OOBEMenuLog {}
            $fakeWireless = [pscustomobject]@{}
            $fakeWireless | Add-Member ScriptMethod Scan {}
            $fakeWireless | Add-Member ScriptMethod Networks {
                $network = [Recast.PreOOBE.Wireless+Network]::new()
                $network.InterfaceId = [guid]'00000000-0000-0000-0000-000000000001'
                $network.Name = 'Test Wi-Fi'
                $network.SsidHex = '54657374'
                $network.Auth = 6
                $network.Cipher = 4
                $network.Connectable = $true
                $network.Connected = $script:associated
                return $network
            }
            $fakeWireless | Add-Member ScriptMethod Connect {
                param($network, $password)
                $script:connectCalls++
                $script:associated = $true
            }
            $fakeWireless | Add-Member ScriptMethod Dispose { $script:disposed = $true }
            Mock New-Object { $fakeWireless } -ParameterFilter { $TypeName -eq 'Recast.PreOOBE.Wireless' }
            $probe = [Windows.Threading.DispatcherTimer]::new()
            $probe.Interval = [TimeSpan]::FromMilliseconds(100)
            $result = @{ Error = $null }
        }
        AfterEach { $probe.Stop(); $Preview = $true }

        It 'renders network selection and a masked password, then returns association without logging the password' {
            $probe.Add_Tick({
                $probe.Stop()
                $dialog = @([Windows.PresentationSource]::CurrentSources | ForEach-Object RootVisual |
                    Where-Object Title -eq 'OSDCloud PreOOBE - Connect to Wi-Fi')[0]
                try {
                    $dialog.FindName('Networks').SelectedIndex = 0
                    $result.PasswordBox = $dialog.FindName('Password') -is [Windows.Controls.PasswordBox]
                    $dialog.FindName('Password').Password = 'private-test-key'
                    $dialog.FindName('Connect').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                    $result.Cleared = $dialog.FindName('Password').Password.Length -eq 0
                }
                catch { $result.Error = $_; if ($dialog) { $dialog.Close() } }
            })
            $probe.Start()
            Show-OSDCloudPreOOBEWireless -State $state | Should -BeTrue
            $result.Error | Should -BeNullOrEmpty
            $result.PasswordBox | Should -BeTrue
            $result.Cleared | Should -BeTrue
            $script:connectCalls | Should -Be 1
            $script:disposed | Should -BeTrue
            ($state.Messages.ToArray() -join "`n") | Should -Not -BeLike '*private-test-key*'
        }

        It 'closes on cooperative cancellation without connecting and disposes native resources' {
            $probe.Add_Tick({ $probe.Stop(); $state.CancelRequested = $true })
            $probe.Start()
            Show-OSDCloudPreOOBEWireless -State $state | Should -BeFalse
            $script:connectCalls | Should -Be 0
            $script:disposed | Should -BeTrue
        }

        It 'keeps the dialog open below the idle limit and skips at 120 seconds' {
            $result.Phase = 0
            $probe.Add_Tick({
                $dialog = @([Windows.PresentationSource]::CurrentSources | ForEach-Object RootVisual |
                    Where-Object Title -eq 'OSDCloud PreOOBE - Connect to Wi-Fi')[0]
                try {
                    if ($result.Phase -eq 0) {
                        $ui.Ticks = 3
                        $ui.Idle = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(119) }
                        $result.Phase = 1
                        $probe.Interval = [TimeSpan]::FromMilliseconds(1500)
                    }
                    else {
                        $result.OpenBelowLimit = $dialog.IsVisible
                        $ui.Idle = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(120) }
                        $probe.Stop()
                    }
                }
                catch { $result.Error = $_; $probe.Stop(); if ($dialog) { $dialog.Close() } }
            })
            $probe.Start()
            Show-OSDCloudPreOOBEWireless -State $state | Should -BeFalse
            $result.Error | Should -BeNullOrEmpty
            $result.OpenBelowLimit | Should -BeTrue
            $script:connectCalls | Should -Be 0
            $script:disposed | Should -BeTrue
        }

        It 'allows retry at the 25-second association limit and Skip closes without success' {
            $result.Phase = 0
            $probe.Add_Tick({
                $dialog = @([Windows.PresentationSource]::CurrentSources | ForEach-Object RootVisual |
                    Where-Object Title -eq 'OSDCloud PreOOBE - Connect to Wi-Fi')[0]
                try {
                    if ($result.Phase -eq 0) {
                        $dialog.FindName('Networks').SelectedIndex = 0
                        $dialog.FindName('Password').Password = 'private-test-key'
                        $dialog.FindName('Connect').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                        $script:associated = $false
                        $ui.Attempt = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(24) }
                        $result.Phase = 1
                        $probe.Interval = [TimeSpan]::FromMilliseconds(1500)
                    }
                    elseif ($result.Phase -eq 1) {
                        $result.DisabledBelowLimit = -not $dialog.FindName('Connect').IsEnabled
                        $ui.Attempt = [pscustomobject]@{ Elapsed = [TimeSpan]::FromSeconds(25) }
                        $result.Phase = 2
                    }
                    else {
                        $result.RetryEnabled = $dialog.FindName('Connect').IsEnabled
                        $result.Status = $dialog.FindName('Status').Text
                        $probe.Stop()
                        $dialog.FindName('Skip').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                    }
                }
                catch { $result.Error = $_; $probe.Stop(); if ($dialog) { $dialog.Close() } }
            })
            $probe.Start()
            Show-OSDCloudPreOOBEWireless -State $state | Should -BeFalse
            $result.Error | Should -BeNullOrEmpty
            $result.DisabledBelowLimit | Should -BeTrue
            $result.RetryEnabled | Should -BeTrue
            $result.Status | Should -BeLike '*timed out*retry or Skip*'
            $script:disposed | Should -BeTrue
        }
    }
}
