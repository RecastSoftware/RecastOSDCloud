Import-Module "$PSScriptRoot\OSDCloudPost.psd1" -Force
InModuleScope OSDCloudPost {
    BeforeAll {
        $Preview = $true
        $originalWindows = $env:WINDIR
        $originalDrive = $env:SystemDrive
    }
    AfterAll { $env:WINDIR = $originalWindows; $env:SystemDrive = $originalDrive }

    Describe 'PreOOBE OEM installer' {
        BeforeEach {
            $env:WINDIR = Join-Path $TestDrive 'Windows'
            $env:SystemDrive = 'C:'
            $downloads = Join-Path $env:WINDIR 'Temp\osdcloud-driverpack-download'
            [void][IO.Directory]::CreateDirectory($downloads)
            $manifestPath = Join-Path $TestDrive 'driver-manifest.json'
            $packagePath = Join-Path $downloads 'Surface.msi'
            [IO.File]::WriteAllText($packagePath, 'Inert package')
            $manifest = @{
                Version = 1; Manufacturer = 'Microsoft'; PackagePath = $packagePath
                FileName = 'Surface.msi'; Size = (Get-Item $packagePath).Length
                Sha256 = (Get-FileHash $packagePath -Algorithm SHA256).Hash
            }
            $manifest | ConvertTo-Json | Set-Content $manifestPath
            $state = @{ Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new(); Status = ''; Outcome = ''; RebootRequired = $false; CancelRequested = $false }
            Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $true } }
            Mock Write-OOBEMenuLog {}
            Mock Start-Process {
                $fake = [pscustomobject]@{ Id = 123; ExitCode = 0 }
                $fake | Add-Member ScriptMethod WaitForExit {}
                $fake | Add-Member ScriptMethod Dispose {}
                $fake
            }
        }

        It 'installs Surface silently without reboot and requests verbose MSI diagnostics' {
            Invoke-OSDCloudPreOOBEDriverPack -State $state -ManifestPath $manifestPath
            $state.Outcome | Should -Be Succeeded
            Should -Invoke Start-Process -Times 1 -ParameterFilter {
                $FilePath -like '*\msiexec.exe' -and $ArgumentList -like '*/qn /norestart /l*v*' -and
                $ArgumentList -like '*"*\Surface.msi"*'
            }
        }

        It 'propagates reboot-required exit 3010 without restarting' {
            Mock Start-Process {
                $fake = [pscustomobject]@{ Id = 123; ExitCode = 3010 }
                $fake | Add-Member ScriptMethod WaitForExit {}
                $fake | Add-Member ScriptMethod Dispose {}
                $fake
            }
            Invoke-OSDCloudPreOOBEDriverPack -State $state -ManifestPath $manifestPath
            $state.Outcome | Should -Be Succeeded
            $state.RebootRequired | Should -BeTrue
        }

        It 'reports native installer failures and retains the package' {
            Mock Start-Process { throw 'Simulated process failure' }
            Invoke-OSDCloudPreOOBEDriverPack -State $state -ManifestPath $manifestPath
            $state.Outcome | Should -Be Failed
            Test-Path $packagePath | Should -BeTrue
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*Simulated process failure*'
        }

        It 'treats missing manifest as not applicable' {
            Invoke-OSDCloudPreOOBEDriverPack -State $state -ManifestPath (Join-Path $TestDrive 'absent.json')
            $state.Outcome | Should -Be NotApplicable
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'rejects a mismatched hash before execution' {
            $manifest.Sha256 = '0' * 64
            $manifest | ConvertTo-Json | Set-Content $manifestPath
            Invoke-OSDCloudPreOOBEDriverPack -State $state -ManifestPath $manifestPath
            $state.Outcome | Should -Be Failed
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'rejects unsupported paths or manifest schema' {
            $manifest.PackagePath = Join-Path $TestDrive 'Outside.msi'
            $manifest | ConvertTo-Json | Set-Content $manifestPath
            Invoke-OSDCloudPreOOBEDriverPack -State $state -ManifestPath $manifestPath
            $state.Outcome | Should -Be Failed
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'uses the existing Lenovo silent extraction method and installs recursive INF drivers' {
            $packagePath = Join-Path $downloads 'Lenovo.exe'
            [IO.File]::WriteAllText($packagePath, 'Inert Lenovo package')
            $manifest.Manufacturer = 'Lenovo'
            $manifest.PackagePath = $packagePath
            $manifest.FileName = 'Lenovo.exe'
            $manifest.Size = (Get-Item $packagePath).Length
            $manifest.Sha256 = (Get-FileHash $packagePath -Algorithm SHA256).Hash
            $manifest | ConvertTo-Json | Set-Content $manifestPath
            Mock Get-ChildItem { [pscustomobject]@{ Name = 'inert.inf' } }
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'C:\Drivers' }
            Invoke-OSDCloudPreOOBEDriverPack -State $state -ManifestPath $manifestPath
            $state.Outcome | Should -Be Succeeded
            Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -like '*Lenovo.exe' -and $ArgumentList -eq '/SILENT /SUPPRESSMSGBOXES /NORESTART' }
            Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -like '*pnputil.exe' -and $ArgumentList -like '*/subdirs /install' }
        }

        It 'rejects an existing Lenovo extraction directory without modifying it' {
            $packagePath = Join-Path $downloads 'Lenovo-existing.exe'
            [IO.File]::WriteAllText($packagePath, 'Inert')
            $manifest.Manufacturer = 'Lenovo'; $manifest.PackagePath = $packagePath; $manifest.FileName = 'Lenovo-existing.exe'
            $manifest.Size = (Get-Item $packagePath).Length
            $manifest.Sha256 = (Get-FileHash $packagePath -Algorithm SHA256).Hash
            $manifest | ConvertTo-Json | Set-Content $manifestPath
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'C:\Drivers' }
            Invoke-OSDCloudPreOOBEDriverPack -State $state -ManifestPath $manifestPath
            $state.Outcome | Should -Be Failed
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*destination already exists*'
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'does not install unrelated INF files if Lenovo extraction produced none' {
            $packagePath = Join-Path $downloads 'Lenovo-empty.exe'
            [IO.File]::WriteAllText($packagePath, 'Inert')
            $manifest.Manufacturer = 'Lenovo'; $manifest.PackagePath = $packagePath; $manifest.FileName = 'Lenovo-empty.exe'
            $manifest.Size = (Get-Item $packagePath).Length
            $manifest.Sha256 = (Get-FileHash $packagePath -Algorithm SHA256).Hash
            $manifest | ConvertTo-Json | Set-Content $manifestPath
            Mock Get-ChildItem {}
            Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'C:\Drivers' }
            Invoke-OSDCloudPreOOBEDriverPack -State $state -ManifestPath $manifestPath
            $state.Outcome | Should -Be Failed
            Should -Invoke Start-Process -Times 0 -ParameterFilter { $FilePath -like '*pnputil.exe' }
        }
    }
}
