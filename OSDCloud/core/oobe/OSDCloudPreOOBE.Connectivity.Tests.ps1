BeforeAll { . "$PSScriptRoot\OSDCloudPreOOBE.ps1" -Preview }

Describe 'Bounded Microsoft connectivity probe' {
    BeforeEach {
        Mock Write-OOBEMenuLog {}
        $state = @{ Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new(); CancelRequested = $false }
        $script:probe = @{ Content = 'Microsoft Connect Test'; Code = 200; Completes = $true; Calls = 0; Disposals = 0; WaitMs = 0; Url = '' }
        Mock New-Object {
            $headers = [pscustomobject]@{}
            $headers | Add-Member ScriptMethod TryAddWithoutValidation { param($name,$value) return $true }
            $client = [pscustomobject]@{ Timeout = $null; MaxResponseContentBufferSize = 0; DefaultRequestHeaders = $headers }
            $client | Add-Member ScriptMethod GetAsync {
                param($url)
                $script:probe.Calls++; $script:probe.Url = $url
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

    It 'accepts only the expected Microsoft response and disposes transport resources' {
        $result = Test-OSDCloudPreOOBEConnectivity -State $state
        $result.Connected | Should -BeTrue
        $script:probe.Calls | Should -Be 1
        $script:probe.WaitMs | Should -Be 5000
        $script:probe.Client.Timeout.TotalSeconds | Should -Be 5
        $script:probe.Client.MaxResponseContentBufferSize | Should -Be 64
        $script:probe.Disposals | Should -Be 2
        $script:probe.Url | Should -Be 'https://www.msftconnecttest.com/connecttest.txt'
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
}
