Import-Module "$PSScriptRoot\OSDCloudPreOOBE.psd1" -Force
InModuleScope OSDCloudPreOOBE {
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
            $local = Join-Path $env:SystemRoot 'Setup\PostOOBE'
            $usb = Join-Path $TestDrive 'USB'
            $script:usbPath = $usb
            foreach ($folder in @("$local\My App", "$local\No Toolkit", "$local\Nested\Child", "$usb\My App")) {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
            }
            foreach ($folder in @("$local\My App", "$local\Nested\Child", "$usb\My App")) {
                New-Item -Path (Join-Path $folder 'Invoke-AppDeployToolkit.exe') -ItemType File | Out-Null
            }
            Mock Test-Path { $LiteralPath -eq 'G:\OSDCloud\PostOOBE' } -ParameterFilter {
                $LiteralPath -match '^[A-Z]:\\OSDCloud\\PostOOBE$'
            }
            Mock Get-ChildItem { Get-ChildItem -LiteralPath $script:usbPath } -ParameterFilter {
                $LiteralPath -eq 'G:\OSDCloud\PostOOBE'
            }
            $apps = @(Get-OSDCloudPreOOBEApplication)
            $apps.Count | Should -Be 2 -Because ($script:discoveryLog -join '; ')
            $apps[0].Name | Should -Be 'My App'
            $apps[0].Path | Should -Be "$local\My App\Invoke-AppDeployToolkit.exe"
            $apps[1].Name | Should -Be 'My App [G:]'
            Should -Invoke Test-Path -Times 26 -Exactly -ParameterFilter {
                $LiteralPath -match '^[A-Z]:\\OSDCloud\\PostOOBE$'
            }
        }

        It 'reports an unreadable root and continues searching later drives' {
            Mock Test-Path {
                if ($LiteralPath -eq 'G:\OSDCloud\PostOOBE') { throw 'Drive unavailable' }
                $LiteralPath -eq 'H:\OSDCloud\PostOOBE' -or $LiteralPath -like '*Invoke-AppDeployToolkit.exe'
            }
            $script:laterPath = Join-Path $TestDrive 'Later App'
            Mock Get-ChildItem { [pscustomobject]@{ Name = 'Later App'; FullName = $script:laterPath; PSIsContainer = $true } }
            $apps = @(Get-OSDCloudPreOOBEApplication)
            $apps.Count | Should -Be 1 -Because ($script:discoveryLog -join '; ')
            $apps[0].Name | Should -Be 'Later App [H:]'
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*G:*Drive unavailable*' }
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

        It 'reports a removed application without launching another package' {
            Remove-Item -LiteralPath $exe
            Invoke-OSDCloudPreOOBETask -Type Application -State $state
            $state.Outcome | Should -Be Failed
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'keeps the application worker inert in preview' {
            $worker = Start-OOBEMenuUpdateWorker -Type Application -State $state -PreviewOnly
            try { $worker.Pipeline.EndInvoke($worker.Handle) | Out-Null }
            finally { $worker.Pipeline.Dispose(); $worker.Runspace.Dispose() }
            $state.Outcome | Should -Be Succeeded
            Should -Invoke Start-Process -Times 0 -Exactly
            Test-Path -LiteralPath (Join-Path $env:WINDIR 'Temp\osdcloud-logs') | Should -BeFalse
        }
    }
}
