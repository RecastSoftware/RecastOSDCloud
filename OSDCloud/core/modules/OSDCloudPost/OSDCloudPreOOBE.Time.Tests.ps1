Import-Module "$PSScriptRoot\OSDCloudPost.psd1" -Force
InModuleScope OSDCloudPost {
    BeforeAll { $Preview = $true }

    Describe 'PreOOBE internet time bootstrap' {
        BeforeEach {
            Mock Write-OOBEMenuLog {}
            Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $true } }
            $state = @{ Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new(); CancelRequested = $false; Outcome = 'Running'; Succeeded = $false }
            $script:timeProbe = @{
                Date = [datetimeoffset]'2026-11-03T12:00:00Z'; Age = $null; Code = 200
                Completes = $true; Calls = 0; WaitMs = 0; Disposals = 0
                Local = [datetime]'2020-01-01T00:00:00Z'; Cancel = $false
            }
            Mock Get-Date { $script:timeProbe.Local }
            # Emulates Windows PowerShell Set-Date: SetLocalTime uses the DateTime fields and ignores Kind.
            Mock Set-Date { $script:timeProbe.Local = [datetime]::SpecifyKind($Date, [DateTimeKind]::Local) }
            Mock Set-TimeZone {}
            Mock New-Object {
                $client = [pscustomobject]@{ Timeout = $null }
                $client | Add-Member ScriptMethod SendAsync {
                    param($request,$option)
                    $script:timeProbe.Calls++
                    $script:timeProbe.Url = $request.RequestUri.AbsoluteUri
                    $script:timeProbe.Method = $request.Method.Method
                    $script:timeProbe.Option = $option
                    $script:timeProbe.Cache = $request.Headers.CacheControl.ToString()
                    if ($script:timeProbe.Cancel) { $state.CancelRequested = $true }
                    $response = [pscustomobject]@{
                        StatusCode = $script:timeProbe.Code
                        Headers = [pscustomobject]@{ Date = $script:timeProbe.Date; Age = $script:timeProbe.Age }
                    }
                    $response | Add-Member ScriptMethod Dispose { $script:timeProbe.Disposals++ }
                    $pending = [pscustomobject]@{ Response = $response }
                    $pending | Add-Member ScriptMethod Wait { param($milliseconds) $script:timeProbe.WaitMs = $milliseconds; return $script:timeProbe.Completes }
                    $pending | Add-Member ScriptMethod GetAwaiter { return $this }
                    $pending | Add-Member ScriptMethod GetResult { return $this.Response }
                    return $pending
                }
                $client | Add-Member ScriptMethod CancelPendingRequests {}
                $client | Add-Member ScriptMethod Dispose { $script:timeProbe.Disposals++ }
                $script:timeProbe.Client = $client
                return $client
            } -ParameterFilter { $TypeName -eq 'System.Net.Http.HttpClient' }
        }

        It 'repairs a years-old clock using UTC HTTP time without TLS or changing the time zone' {
            Sync-OSDCloudPreOOBETime -State $state
            $state.Outcome | Should -Be Succeeded
            $script:timeProbe.Url | Should -Be 'http://www.google.com/'
            $script:timeProbe.Method | Should -Be HEAD
            $script:timeProbe.Option | Should -Be ([Net.Http.HttpCompletionOption]::ResponseHeadersRead)
            $script:timeProbe.Cache | Should -BeLike '*no-cache*'
            $script:timeProbe.Cache | Should -BeLike '*no-store*'
            $script:timeProbe.WaitMs | Should -Be 5000
            $script:timeProbe.Client.Timeout.TotalSeconds | Should -Be 5
            $script:timeProbe.Disposals | Should -Be 2
            Should -Invoke Set-Date -Times 1 -Exactly -ParameterFilter {
                $Date.Kind -eq [DateTimeKind]::Local -and
                $Date -eq [TimeZoneInfo]::ConvertTimeFromUtc($script:timeProbe.Date.UtcDateTime, [TimeZoneInfo]::Local)
            }
            $script:timeProbe.Local.ToUniversalTime() | Should -Be $script:timeProbe.Date.UtcDateTime
            Should -Invoke Set-TimeZone -Times 0 -Exactly
            $lines = $state.Messages.ToArray() -replace '^\[[^\]]+\] '
            $lines | Should -Contain "Clock before: $(([datetime]'2020-01-01T00:00:00Z').ToUniversalTime().ToString('o'))"
            $lines | Should -Contain "Internet UTC: $($script:timeProbe.Date.UtcDateTime.ToString('o'))"
            @($lines | Where-Object { $_ -like 'Correction: * seconds.' }).Count | Should -Be 1
            $lines | Should -Contain 'Internet time synchronized.'
            $lines | Should -Contain "Time zone $([TimeZoneInfo]::Local.Id) unchanged."
        }

        It 'rejects missing, invalid or cached dates and redirects: <Case>' -TestCases @(
            @{ Case = 'missing' }, @{ Case = 'invalid' }, @{ Case = 'cached' }, @{ Case = 'redirect' }
        ) {
            param($Case)
            switch ($Case) {
                missing { $script:timeProbe.Date = $null }
                invalid { $script:timeProbe.Date = [datetimeoffset]'2000-01-01T00:00:00Z' }
                cached { $script:timeProbe.Age = [TimeSpan]::FromMinutes(10) }
                redirect { $script:timeProbe.Code = 302 }
            }
            { Sync-OSDCloudPreOOBETime -State $state } | Should -Throw
            $script:timeProbe.Calls | Should -Be 2
            Should -Invoke Set-Date -Times 0 -Exactly
        }

        It 'bounds unavailable time sources to two five-second attempts and logs timeout' {
            $script:timeProbe.Completes = $false
            { Sync-OSDCloudPreOOBETime -State $state } | Should -Throw '*timed out*'
            ($script:timeProbe.Calls * $script:timeProbe.WaitMs) | Should -Be 10000
            Should -Invoke Set-Date -Times 0 -Exactly
        }

        It 'does not set the clock if closure requests cancellation during retrieval' {
            $script:timeProbe.Cancel = $true
            Sync-OSDCloudPreOOBETime -State $state
            $state.Outcome | Should -Be Cancelled
            Should -Invoke Set-Date -Times 0 -Exactly
        }

        It 'does not create a request when already cancelled' {
            $state.CancelRequested = $true
            Sync-OSDCloudPreOOBETime -State $state
            $state.Outcome | Should -Be Cancelled
            Should -Invoke New-Object -Times 0 -Exactly
            Should -Invoke Set-Date -Times 0 -Exactly
        }

        It 'requires SYSTEM before retrieving or changing time' {
            Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $false } }
            { Sync-OSDCloudPreOOBETime -State $state } | Should -Throw '*require*SYSTEM*'
            Should -Invoke New-Object -Times 0 -Exactly
            Should -Invoke Set-Date -Times 0 -Exactly
        }

        It 'reports failure instead of success if setting the clock is denied' {
            Mock Set-Date { throw 'Privilege denied' }
            Invoke-OSDCloudPreOOBETask -Type Time -State $state
            $state.Outcome | Should -Be Failed
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*Privilege denied*'
        }

        It 'verifies the clock was actually corrected' {
            Mock Set-Date {}
            Invoke-OSDCloudPreOOBETask -Type Time -State $state
            $state.Outcome | Should -Be Failed
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*Clock verification failed*'
        }
    }
}
