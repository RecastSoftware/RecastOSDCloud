Import-Module "$PSScriptRoot\OSDCloudPreOOBE.psd1" -Force
InModuleScope OSDCloudPreOOBE {
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
}
