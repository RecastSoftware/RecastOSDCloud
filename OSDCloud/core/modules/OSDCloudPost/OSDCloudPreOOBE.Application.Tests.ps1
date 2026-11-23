Import-Module "$PSScriptRoot\OSDCloudPost.psd1" -Force
InModuleScope OSDCloudPost {
    BeforeAll { $Preview = $true }

    Describe 'PreOOBE application discovery' {
        BeforeEach {
            $originalRoot = $env:SystemRoot
            $env:SystemRoot = Join-Path $TestDrive 'Windows'
            $script:discoveryLog = [Collections.Generic.List[string]]::new()
            Mock Write-OOBEMenuLog { $script:discoveryLog.Add($Message) }
            Mock Write-Warning {}
        }
        AfterEach {
            $env:SystemRoot = $originalRoot
        }

        It 'finds only immediate toolkit folders, local first, and labels drive-hosted applications' {
            $local = Join-Path $env:SystemRoot 'Setup\PreOOBE'
            $usb = Join-Path $TestDrive 'USB'
            $script:usbPath = $usb
            foreach ($folder in @("$local\My App", "$local\No Toolkit", "$local\Nested\Child", "$usb\My App")) {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
            }
            foreach ($folder in @("$local\My App", "$local\Nested\Child", "$usb\My App")) {
                New-Item -Path (Join-Path $folder 'Invoke-AppDeployToolkit.exe') -ItemType File | Out-Null
            }
            Mock Test-Path { $LiteralPath -eq 'G:\OSDCloud\post\PreOOBE' } -ParameterFilter {
                $LiteralPath -match '^[A-Z]:\\OSDCloud\\post\\PreOOBE$'
            }
            Mock Get-ChildItem { Get-ChildItem -LiteralPath $script:usbPath } -ParameterFilter {
                $LiteralPath -eq 'G:\OSDCloud\post\PreOOBE'
            }
            $apps = @(Get-OSDCloudPreOOBEApplication)
            $apps.Count | Should -Be 2 -Because ($script:discoveryLog -join '; ')
            $apps[0].Name | Should -Be 'My App'
            $apps[0].Path | Should -Be "$local\My App\Invoke-AppDeployToolkit.exe"
            $apps[1].Name | Should -Be 'My App [G:]'
            Should -Invoke Test-Path -Times 26 -Exactly -ParameterFilter {
                $LiteralPath -match '^[A-Z]:\\OSDCloud\\post\\PreOOBE$'
            }
            Should -Invoke Test-Path -Times 0 -Exactly -ParameterFilter {
                $LiteralPath -match '^[A-Z]:\\OSDCloud\\PreOOBE$'
            }
        }

        It 'reports an unreadable root and continues searching later drives' {
            Mock Test-Path {
                if ($LiteralPath -eq 'G:\OSDCloud\post\PreOOBE') { throw 'Drive unavailable' }
                $LiteralPath -eq 'H:\OSDCloud\post\PreOOBE' -or $LiteralPath -like '*Invoke-AppDeployToolkit.exe'
            }
            $script:laterPath = Join-Path $TestDrive 'Later App'
            Mock Get-ChildItem { [pscustomobject]@{ Name = 'Later App'; FullName = $script:laterPath; PSIsContainer = $true } }
            $apps = @(Get-OSDCloudPreOOBEApplication)
            $apps.Count | Should -Be 1 -Because ($script:discoveryLog -join '; ')
            $apps[0].Name | Should -Be 'Later App [H:]'
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*G:*Drive unavailable*' }
        }
    }

    Describe 'PreOOBE custom application discovery' {
        BeforeAll {
            # Windows PowerShell loads its JSON assembly using the real SystemRoot.
            '{"Version":1}' | ConvertFrom-Json | Out-Null
        }
        BeforeEach {
            $originalRoot = $env:SystemRoot
            $env:SystemRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $package = Join-Path $env:SystemRoot 'Setup\PreOOBE\A Custom App'
            New-Item -Path $package -ItemType Directory -Force | Out-Null
            $exe = Join-Path $package 'AgentBootstrapper.exe'
            New-Item -Path $exe -ItemType File | Out-Null
            $manifestPath = Join-Path $package 'OSDCloudPreOOBE.json'
            $manifest = @{
                Version = 1; Executable = 'AgentBootstrapper.exe'
                Arguments = '--certificate AgentRegistration.cer --startDeployment --wait'
                DefaultSelected = $false
            }
            $script:manifestDiscoveryLog = [Collections.Generic.List[string]]::new()
            Mock Write-OOBEMenuLog { $script:manifestDiscoveryLog.Add($Message) }
            Mock Write-Warning {}
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -match '^[A-Z]:\\OSDCloud\\post\\PreOOBE$' }
            Mock Get-CimInstance { [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'Latitude 7450' } }
            Mock Get-ItemPropertyValue { 'ARM64' }
        }
        AfterEach { $env:SystemRoot = $originalRoot }

        It 'discovers the manifest once, overrides toolkit detection and preserves literal command metadata' {
            New-Item -Path (Join-Path $package 'Invoke-AppDeployToolkit.exe') -ItemType File | Out-Null
            $manifest.Name = 'Workspace Agent'
            $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath
            $apps = @(Get-OSDCloudPreOOBEApplication)
            $apps.Count | Should -Be 1 -Because ($script:manifestDiscoveryLog -join '; ')
            $apps[0].Name | Should -Be 'Workspace Agent'
            $apps[0].Path | Should -Be $exe
            $apps[0].DefaultSelected | Should -BeFalse
            $apps[0].Command.WorkingDirectory | Should -Be $package
            $apps[0].Command.Arguments | Should -Be $manifest.Arguments
            Should -Invoke Get-CimInstance -Times 0
            Should -Invoke Get-ItemPropertyValue -Times 0
        }

        It 'defaults to folder name, checked selection and no arguments' {
            @{ Version = 1; Executable = 'AgentBootstrapper.exe' } |
                ConvertTo-Json | Set-Content -LiteralPath $manifestPath
            $apps = @(Get-OSDCloudPreOOBEApplication)
            $apps[0].Name | Should -Be 'A Custom App'
            $apps[0].DefaultSelected | Should -BeTrue
            $apps[0].Command.Arguments | Should -Be ''
            $apps[0].Command.CopyToLocal | Should -BeFalse
        }

        It 'preserves an explicit CopyToLocal request' {
            $manifest.CopyToLocal = $true
            $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
            @(Get-OSDCloudPreOOBEApplication)[0].Command.CopyToLocal | Should -BeTrue
        }

        It 'matches case-insensitive patterns with OR within fields and AND across fields using native architecture' {
            $manifest.Conditions = @{
                ComputerManufacturer = 'dell*'
                ComputerModel = @('Precision*', 'latitude*')
                OSArchitecture = @('amd64', 'arm64')
            }
            $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath
            $oldArchitecture = $env:PROCESSOR_ARCHITECTURE
            try {
                $env:PROCESSOR_ARCHITECTURE = 'AMD64'
                $apps = @(Get-OSDCloudPreOOBEApplication)
                $apps.Count | Should -Be 1
                Should -Invoke Get-ItemPropertyValue -Times 1 -Exactly -ParameterFilter {
                    $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -and
                    $Name -eq 'PROCESSOR_ARCHITECTURE'
                }
            }
            finally { $env:PROCESSOR_ARCHITECTURE = $oldArchitecture }
        }

        It 'hides a nonmatch in any field: <Field>' -TestCases @(
            @{ Field = 'ComputerManufacturer'; Value = 'HP*' }
            @{ Field = 'ComputerModel'; Value = @('Precision*', 'OptiPlex*') }
            @{ Field = 'OSArchitecture'; Value = 'amd64' }
        ) {
            param($Field, $Value)
            $manifest.Conditions = @{ ComputerManufacturer = 'Dell*'; ComputerModel = 'Latitude*'; OSArchitecture = 'arm64' }
            $manifest.Conditions[$Field] = $Value
            $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath
            @(Get-OSDCloudPreOOBEApplication).Count | Should -Be 0
            Should -Invoke Write-Warning -Times 0
        }

        It 'caches device facts across eligible packages' {
            $manifest.Conditions = @{ ComputerManufacturer = 'Dell*'; ComputerModel = 'Latitude*'; OSArchitecture = 'arm64' }
            $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath
            $second = Join-Path (Split-Path $package -Parent) 'B Custom App'
            Copy-Item -LiteralPath $package -Destination $second -Recurse
            @(Get-OSDCloudPreOOBEApplication).Count | Should -Be 2
            Should -Invoke Get-CimInstance -Times 1 -Exactly
            Should -Invoke Get-ItemPropertyValue -Times 1 -Exactly
        }

        It 'reports failed device queries, excludes affected packages and still discovers unconditional packages' {
            $manifest.Conditions = @{ ComputerManufacturer = 'Dell*' }
            $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath
            $second = Join-Path (Split-Path $package -Parent) 'B Conditioned App'
            Copy-Item -LiteralPath $package -Destination $second -Recurse
            $third = Join-Path (Split-Path $package -Parent) 'C Unconditional App'
            Copy-Item -LiteralPath $package -Destination $third -Recurse
            $manifest.Remove('Conditions')
            $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $third 'OSDCloudPreOOBE.json')
            Mock Get-CimInstance { throw 'Device query unavailable' }
            $apps = @(Get-OSDCloudPreOOBEApplication)
            $apps.Count | Should -Be 1
            $apps[0].Name | Should -Be 'C Unconditional App'
            Should -Invoke Get-CimInstance -Times 1 -Exactly
            Should -Invoke Write-Warning -Times 2 -Exactly -ParameterFilter { $Message -like '*Device query unavailable*' }
        }

        It 'reports unavailable architecture instead of using process architecture' {
            $manifest.Conditions = @{ OSArchitecture = 'arm64' }
            $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath
            Mock Get-ItemPropertyValue { throw 'Registry unavailable' }
            @(Get-OSDCloudPreOOBEApplication).Count | Should -Be 0
            Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*Registry unavailable*' }
        }

        It 'rejects invalid manifest <Json>, never falls back to toolkit, and continues to siblings' -TestCases @(
            @{ Json = '{' }
            @{ Json = 'null' }
            @{ Json = '[{"Version":1,"Executable":"AgentBootstrapper.exe"}]' }
            @{ Json = '{"Version":2,"Executable":"AgentBootstrapper.exe"}' }
            @{ Json = '{"Version":"1","Executable":"AgentBootstrapper.exe"}' }
            @{ Json = '{"Version":1}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","Name":""}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","Arguments":[]}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","DefaultSelected":"false"}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","CopyToLocal":"true"}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","Condition":{}}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","Conditions":null}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","Conditions":{"Manufacturer":"Dell*"}}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","Conditions":{"ComputerModel":[]}}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","Conditions":{"ComputerModel":[true]}}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","Conditions":{"ComputerModel":""}}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe","Conditions":{"OSArchitecture":"x64"}}' }
            @{ Json = '{"Version":1,"Executable":"..\\AgentBootstrapper.exe"}' }
            @{ Json = '{"Version":1,"Executable":"C:\\AgentBootstrapper.exe"}' }
            @{ Json = '{"Version":1,"Executable":"\\AgentBootstrapper.exe"}' }
            @{ Json = '{"Version":1,"Executable":"AgentBootstrapper.exe:other.exe"}' }
            @{ Json = '{"Version":1,"Executable":"install.ps1"}' }
            @{ Json = '{"Version":1,"Executable":"Missing.exe"}' }
        ) {
            param($Json)
            Set-Content -LiteralPath $manifestPath -Value $Json
            New-Item -Path (Join-Path $package 'Invoke-AppDeployToolkit.exe') -ItemType File | Out-Null
            $sibling = Join-Path (Split-Path $package -Parent) 'B Valid App'
            New-Item -Path $sibling -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $sibling 'Invoke-AppDeployToolkit.exe') -ItemType File | Out-Null
            $apps = @(Get-OSDCloudPreOOBEApplication)
            $apps.Count | Should -Be 1
            $apps[0].Name | Should -Be 'B Valid App'
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*A Custom App*' }
        }

        It 'rejects traversal to an existing executable in a similarly named sibling directory' {
            $outside = "$package Extra"
            New-Item -Path $outside -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $outside 'AgentBootstrapper.exe') -ItemType File | Out-Null
            $manifest.Executable = '..\A Custom App Extra\AgentBootstrapper.exe'
            $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
            @(Get-OSDCloudPreOOBEApplication).Count | Should -Be 0
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*outside its package*' }
        }

        It 'rejects a reparse point executable' {
            Mock Get-Item { [pscustomobject]@{ Attributes = [IO.FileAttributes]::ReparsePoint } } -ParameterFilter { $LiteralPath -eq $exe }
            $manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
            @(Get-OSDCloudPreOOBEApplication).Count | Should -Be 0
            Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*reparse point*' }
        }
    }

    Describe 'PreOOBE application installation' {
        BeforeEach {
            $originalDrive = $env:SystemDrive
            $originalWindows = $env:WINDIR
            $env:SystemDrive = 'C:'
            $env:WINDIR = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $package = Join-Path $TestDrive 'My App'
            New-Item -Path $package -ItemType Directory -Force | Out-Null
            $exe = Join-Path $package 'Invoke-AppDeployToolkit.exe'
            New-Item -Path $exe -ItemType File -Force | Out-Null
            $state = [hashtable]::Synchronized(@{
                ApplicationPath = $exe; Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new()
                CancelRequested = $false; RebootRequired = $false; Succeeded = $false
                Outcome = 'Pending'; InstallationActive = $false
            })
            Mock Write-OOBEMenuLog {}
            Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $true } }
            Mock Test-OSDCloudPreOOBEConnectivity { throw 'Local applications must not require connectivity' }
            $process = [pscustomobject]@{ Id = 123; ExitCode = 0; Disposed = $false }
            $process | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
            $script:appProcess = $process
            Mock Start-Process { $script:appProcess }
        }
        AfterEach {
            $env:SystemDrive = $originalDrive
            $env:WINDIR = $originalWindows
        }

        It 'installs silently from the package directory, waits for completion and records reboot requirements' {
            $process.ExitCode = 3010
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be Succeeded -Because ($state.Messages.ToArray() -join '; ')
            $state.RebootRequired | Should -BeTrue
            $state.InstallationActive | Should -BeFalse
            $process.Disposed | Should -BeTrue
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $exe -and $WorkingDirectory -eq $package -and
                $ArgumentList -eq '-DeploymentType Install -DeployMode Silent' -and $Wait -and $PassThru
            }
            Should -Invoke Test-OSDCloudPreOOBEConnectivity -Times 0 -Exactly
        }

        It 'reports a failed installer rather than success and releases its process' {
            $process.ExitCode = 1603
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be Failed
            $state.Succeeded | Should -BeFalse
            $process.Disposed | Should -BeTrue
            $state.InstallationActive | Should -BeFalse
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*exit code 1603*'
        }

        It 'runs custom arguments from the package root even for a nested executable and handles exit <Code>' -TestCases @(
            @{ Code = 0; Outcome = 'Succeeded'; Reboot = $false }
            @{ Code = 3010; Outcome = 'Succeeded'; Reboot = $true }
            @{ Code = 1603; Outcome = 'Failed'; Reboot = $false }
        ) {
            param($Code, $Outcome, $Reboot)
            $bin = Join-Path $package 'Agent Files'
            New-Item -Path $bin -ItemType Directory -Force | Out-Null
            $customExe = Join-Path $bin 'AgentBootstrapper.exe'
            New-Item -Path $customExe -ItemType File -Force | Out-Null
            $arguments = '--certificate "Agent Registration.cer" --startDeployment --wait'
            $state.ApplicationCommand = [pscustomobject]@{
                Executable = 'Agent Files\AgentBootstrapper.exe'; WorkingDirectory = $package; Arguments = $arguments
            }
            $state.ApplicationPath = $customExe
            $process.ExitCode = $Code
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be $Outcome -Because ($state.Messages.ToArray() -join '; ')
            $state.RebootRequired | Should -Be $Reboot
            $state.InstallationActive | Should -BeFalse
            $process.Disposed | Should -BeTrue
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $customExe -and $WorkingDirectory -eq $package -and
                $ArgumentList -eq $arguments -and $Wait -and $PassThru
            }
        }

        It 'omits ArgumentList when a custom application has no arguments' {
            $state.ApplicationCommand = [pscustomobject]@{
                Executable = 'Invoke-AppDeployToolkit.exe'; WorkingDirectory = $package; Arguments = ''
            }
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be Succeeded
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { -not $ArgumentList }
        }

        It 'streams prefixed stdout and stderr lines while the installer is still running' {
            $state.ProcessOutput = [Collections.Concurrent.ConcurrentQueue[string]]::new()
            $state.ApplicationName = 'My App [G:]'
            # Mock bodies do not share the test's script scope, so exchange live state globally.
            $global:OSDCloudPreOOBELiveTest = [hashtable]::Synchronized(@{
                Queue = $state.ProcessOutput; Process = $process; SeenWhileRunning = $false
            })
            Mock Start-Process {
                $live = $global:OSDCloudPreOOBELiveTest
                $stream = [IO.FileStream]::new($RedirectStandardOutput, 'Create', 'Write', 'Read')
                $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
                try {
                    $writer.Write("first line`r`n"); $writer.Flush()
                    $watch = [Diagnostics.Stopwatch]::StartNew()
                    while (-not $live.SeenWhileRunning -and $watch.Elapsed.TotalSeconds -lt 10) {
                        $live.SeenWhileRunning = @($live.Queue.ToArray() -like '*] first line').Count -gt 0
                        Start-Sleep -Milliseconds 50
                    }
                    $writer.Write("[2026-11-23 07:06:24.427] [Info] Agent started`r`n[2026-11-23 07:06:25.001] [Debug] Probe failed`r`n")
                    $writer.Write("progress 50%`rprogress 100%`n`n$('x' * 1500)`ntrailing partial")
                }
                finally { $writer.Dispose() }
                [IO.File]::WriteAllText($RedirectStandardError, "warning line`n", [Text.Encoding]::Unicode)
                $live.Process
            }
            try {
                Invoke-OSDCloudPreOOBETask -Type Application -State $state
                $seenWhileRunning = $global:OSDCloudPreOOBELiveTest.SeenWhileRunning
            }
            finally { Remove-Variable -Name OSDCloudPreOOBELiveTest -Scope Global -ErrorAction SilentlyContinue }
            $state.Outcome | Should -Be Succeeded -Because ($state.Messages.ToArray() -join '; ')
            $seenWhileRunning | Should -BeTrue -Because ("output: " + ($state.ProcessOutput.ToArray() -join ' | ') +
                "; messages: " + ($state.Messages.ToArray() -join ' | '))
            $lines = $state.ProcessOutput.ToArray()
            $stamp = '^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\] '
            $text = $lines -replace $stamp
            $text[0..4] | Should -Be @('first line', 'Agent started', '[Debug] Probe failed', 'progress 50%', 'progress 100%')
            $lines[1] | Should -Be '[2026-11-23T07:06:24] Agent started'
            $text[5] | Should -Be "$('x' * 1000) ... [truncated]"
            $text | Should -Contain 'trailing partial'
            $text | Should -Contain '[stderr] warning line'
            $lines | ForEach-Object { $_ | Should -Match $stamp }
            $lines.Count | Should -Be 8
            ($state.Messages.ToArray() -replace $stamp) | Should -Not -Contain 'first line'
            ($state.Messages.ToArray() -replace $stamp) | Should -Contain ('-' * 72)
            $state.Messages.ToArray() | Where-Object { $_ -like '*] Starting My App `[G:`]' } | Should -Not -BeNullOrEmpty
            $state.Messages.ToArray() | Where-Object { $_ -like '*] Finished My App `[G:`] in *s.' } | Should -Not -BeNullOrEmpty
        }

        It 'installs normally when live output cannot start or stop cleanly: <Case>' -TestCases @(
            @{ Case = 'start'; Expected = '*Live installer output unavailable*' }
            @{ Case = 'stop'; Expected = '*Live installer output stopped early: reader stuck*' }
        ) {
            param($Case, $Expected)
            if ($Case -eq 'start') { Mock Start-OSDCloudPreOOBEOutputTail { throw 'no runspace' } }
            else {
                Mock Start-OSDCloudPreOOBEOutputTail { @{} }
                Mock Stop-OSDCloudPreOOBEOutputTail { 'reader stuck' }
            }
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be Succeeded
            ($state.Messages.ToArray() -join "`n") | Should -BeLike $Expected
            Should -Invoke Start-Process -Times 1 -Exactly
        }

        It 'stops live output when the installer cannot be started' {
            Mock Start-OSDCloudPreOOBEOutputTail { @{ Marker = $true } }
            Mock Stop-OSDCloudPreOOBEOutputTail {}
            Mock Start-Process { throw 'Access denied' }
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be Failed
            $state.InstallationActive | Should -BeFalse
            Should -Invoke Stop-OSDCloudPreOOBEOutputTail -Times 1 -Exactly -ParameterFilter { $Tail.Marker }
        }

        It 'copies ISO-style content to writable Temp storage and retains it after exit <Code>' -TestCases @(
            @{ Code = 0; Outcome = 'Succeeded' }
            @{ Code = 1603; Outcome = 'Failed' }
        ) {
            param($Code, $Outcome)
            $nested = Join-Path $package 'Content\Data'
            New-Item -Path $nested -ItemType Directory -Force | Out-Null
            $payload = Join-Path $nested "payload-$Code.txt"
            Set-Content -LiteralPath $payload -Value 'payload'
            $sourcePayload = Get-Item -LiteralPath $payload
            $sourcePayload.Attributes = [IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::Hidden
            Set-Content -LiteralPath (Join-Path $package 'AgentRegistration.cer') -Value 'certificate'
            $arguments = '--certificate AgentRegistration.cer --startDeployment --wait'
            $state.ApplicationCommand = [pscustomobject]@{
                Executable = 'Invoke-AppDeployToolkit.exe'; WorkingDirectory = $package; Arguments = $arguments; CopyToLocal = $true
            }
            $process.ExitCode = $Code
            Mock Start-Process {
                $readOnlyItems = @(Get-ChildItem -LiteralPath $WorkingDirectory -Recurse -Force |
                    Where-Object { $_.Attributes -band [IO.FileAttributes]::ReadOnly })
                if ($readOnlyItems.Count) { throw 'Copied files are still read-only when the installer starts.' }
                $script:appProcess
            }
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be $Outcome -Because ($state.Messages.ToArray() -join '; ')
            $copies = @(Get-ChildItem -LiteralPath (Join-Path $env:WINDIR 'Temp\OSDCloudOOBE') -Directory)
            $copies.Count | Should -Be 1
            $copy = $copies[0].FullName
            $copies[0].Name | Should -Be 'My App'
            $copiedPayload = Join-Path $copy "Content\Data\payload-$Code.txt"
            Get-Content -LiteralPath $copiedPayload | Should -Be 'payload'
            $copiedAttributes = (Get-Item -LiteralPath $copiedPayload -Force).Attributes
            ($copiedAttributes -band [IO.FileAttributes]::ReadOnly) | Should -Be 0
            ($copiedAttributes -band [IO.FileAttributes]::Hidden) | Should -Not -Be 0
            ((Get-Item -LiteralPath $payload -Force).Attributes -band [IO.FileAttributes]::ReadOnly) | Should -Not -Be 0
            Test-Path -LiteralPath (Join-Path $copy 'AgentRegistration.cer') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $package 'AgentRegistration.cer') | Should -BeTrue
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq (Join-Path $copy 'Invoke-AppDeployToolkit.exe') -and
                $WorkingDirectory -eq $copy -and $ArgumentList -eq $arguments
            }
        }

        It 'keeps earlier copies and installer-created files when the same application runs again' {
            $state.ApplicationCommand = [pscustomobject]@{
                Executable = 'Invoke-AppDeployToolkit.exe'; WorkingDirectory = $package; Arguments = ''; CopyToLocal = $true
            }
            $destination = Join-Path $env:WINDIR 'Temp\OSDCloudOOBE\My App'
            1..3 | ForEach-Object {
                Set-Content -LiteralPath (Join-Path $package 'version.txt') -Value $_
                Invoke-OSDCloudPreOOBETask -Type Application -State $state
                $state.Outcome | Should -Be Succeeded -Because ($state.Messages.ToArray() -join '; ')
                $copy = if ($_ -eq 1) { $destination } else { "$destination-$_" }
                Set-Content -LiteralPath (Join-Path $copy 'installer-created.txt') -Value 'retained'
            }
            1..3 | ForEach-Object {
                $copy = if ($_ -eq 1) { $destination } else { "$destination-$_" }
                Get-Content -LiteralPath (Join-Path $copy 'version.txt') | Should -Be "$_"
                Get-Content -LiteralPath (Join-Path $copy 'installer-created.txt') | Should -Be 'retained'
            }
        }

        It 'refuses to copy a package containing a reparse point' {
            $state.ApplicationCommand = [pscustomobject]@{
                Executable = 'Invoke-AppDeployToolkit.exe'; WorkingDirectory = $package; Arguments = ''; CopyToLocal = $true
            }
            Mock Get-ChildItem {
                [pscustomobject]@{ FullName = (Join-Path $package 'Linked'); Attributes = [IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint }
            } -ParameterFilter { $Recurse }
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be Failed
            Test-Path -LiteralPath (Join-Path $env:WINDIR 'Temp\OSDCloudOOBE') | Should -BeFalse
            Should -Invoke Start-Process -Times 0
        }

        It 'revalidates a removed custom executable before installation' {
            $state.ApplicationCommand = [pscustomobject]@{
                Executable = 'Invoke-AppDeployToolkit.exe'; WorkingDirectory = $package; Arguments = '--wait'
            }
            Remove-Item -LiteralPath $exe
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be Failed
            Should -Invoke Start-Process -Times 0
        }

        It 'reports a removed application without launching another package' {
            Remove-Item -LiteralPath $exe
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be Failed
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'keeps the custom application worker inert in preview' {
            $state.ApplicationCommand = [pscustomobject]@{
                Executable = 'AgentBootstrapper.exe'; WorkingDirectory = $package
                Arguments = '--certificate AgentRegistration.cer --startDeployment --wait'; CopyToLocal = $true
            }
            $worker = Start-OOBEMenuUpdateWorker -Type Application -State $state -PreviewOnly
            try { $worker.Pipeline.EndInvoke($worker.Handle) | Out-Null }
            finally { $worker.Pipeline.Dispose(); $worker.Runspace.Dispose() }
            $state.Outcome | Should -Be Succeeded
            Should -Invoke Start-Process -Times 0 -Exactly
            Test-Path -LiteralPath (Join-Path $env:WINDIR 'Temp\osdcloud-logs') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $env:WINDIR 'Temp\OSDCloudOOBE') | Should -BeFalse
        }
    }
}
