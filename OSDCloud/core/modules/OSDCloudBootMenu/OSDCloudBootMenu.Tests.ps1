BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot 'OSDCloudBootMenu.psd1') -Force -ErrorAction Stop
}

BeforeAll {
    $script:moduleRoot = $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'OSDCloudBootMenu.psd1') -Force -ErrorAction Stop
    $script:windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

AfterAll {
    Remove-Module OSDCloudBootMenu -Force -ErrorAction SilentlyContinue
}

Describe 'Standalone BootMenu process isolation' {
    It 'keeps command ownership out of the parent manifest and all runtime files in the payload inventory' {
        $parentManifest = Import-PowerShellDataFile (Join-Path $moduleRoot '..\..\..\OSDCloud.psd1') -ErrorAction Stop
        $parentManifest.FunctionsToExport | Should -Not -Contain 'Invoke-OSDCloudBootMenu'
        $parentManifest.FunctionsToExport | Should -Not -Contain 'Test-OSDCloudBootMenu'
        $manifest = Import-PowerShellDataFile (Join-Path $moduleRoot 'OSDCloudBootMenu.psd1')
        foreach ($file in @(Get-ChildItem (Join-Path $moduleRoot 'private'), (Join-Path $moduleRoot 'public') -Filter '*.ps1' -File |
                    Where-Object { $_.Name -notlike '*.Tests.ps1' })) {
            $relativePath = $file.FullName.Substring($moduleRoot.Length + 1)
            $manifest.FileList | Should -Contain $relativePath
        }
    }

    It 'imports a relocated payload without OSDCloud or startup side effects' {
        $isolatedRoot = Join-Path $TestDrive "relocated O'Brien\OSDCloudBootMenu"
        $null = New-Item -Path $isolatedRoot -ItemType Directory -Force
        Copy-Item -Path (Join-Path $moduleRoot '*') -Destination $isolatedRoot -Recurse -Force
        $manifestPath = (Join-Path $isolatedRoot 'OSDCloudBootMenu.psd1').Replace("'", "''")
        $child = @"
Import-Module Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility -ErrorAction Stop
`$env:PSModulePath = Join-Path `$PSHOME 'Modules'
`$PSModuleAutoLoadingPreference = 'None'
function global:Start-Process { throw 'Unexpected process launch during import' }
function global:Start-Transcript { throw 'Unexpected startup during import' }
`$module = Import-Module '$manifestPath' -PassThru -ErrorAction Stop
if (Get-Module OSDCloud) { throw 'OSDCloud was loaded' }
`$commands = @(Get-Command -Module OSDCloudBootMenu)
if (`$commands.Count -ne 2) { throw 'Unexpected exports' }
`$scriptText = & `$module { New-OSDCloudBootMenuChildCommand -Command '(Get-Command Initialize-WinpeStartupEnvironment).ModuleName' -Private }
`$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(`$scriptText))
`$result = & '$windowsPowerShell' -NoProfile -EncodedCommand `$encoded
if (`$LASTEXITCODE -ne 0 -or `$result -ne 'OSDCloudBootMenu') { throw 'Private child helper did not resolve' }
'isolated-import-and-child-ok'
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
        $result = & $windowsPowerShell -NoProfile -EncodedCommand $encoded
        $LASTEXITCODE | Should -Be 0
        $result | Should -Be 'isolated-import-and-child-ok'
    }

    Describe 'Standalone BootMenu bundled profiles' {
        InModuleScope OSDCloudBootMenu {
            It 'validates every bundled profile without changing command or environment types' {
                $root = Join-Path (Split-Path $script:OSDCloudBootMenuModulePath -Parent) 'core\bootmenu-profiles'
                foreach ($file in @(Get-ChildItem $root -Filter osdcloudbootmenu.json -Recurse -File)) {
                    { Assert-OSDCloudBootMenuProfile -Path $file.FullName } | Should -Not -Throw
                    ConvertFrom-OSDCloudBootMenuProfile -Path $file.FullName | Should -BeOfType ([System.Collections.Specialized.OrderedDictionary])
                }
            }
        }
    }

    Describe 'Standalone BootMenu shell initialization' {
        InModuleScope OSDCloudBootMenu {
            It 'keeps ungated shell setup without discovering licensed assets' {
                $savedEnvironment = @{}
                foreach ($name in @('SystemDrive', 'APPDATA', 'HOMEDRIVE', 'HOMEPATH', 'LOCALAPPDATA', 'USERPROFILE')) {
                    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
                }
                try {
                    $env:SystemDrive = 'X:'
                    Mock Test-WinpeStartupAssetLicense { $false }
                    Mock Get-ChildItem { throw 'Unexpected licensed discovery' }
                    Mock Import-WinpeStartupAssets { throw 'Unexpected licensed import' }
                    Mock New-Item { }
                    Mock Set-ItemProperty { }
                    Mock Join-Path { ([string]$Path).TrimEnd('\') + '\' + $ChildPath }
                    Initialize-WinpeStartupEnvironment
                    $env:USERPROFILE | Should -Be 'X:\windows\system32\config\systemprofile'
                    Should -Invoke Set-ItemProperty -Times 2 -Exactly
                    Should -Invoke Get-ChildItem -Times 0 -Exactly
                    Should -Invoke Import-WinpeStartupAssets -Times 0 -Exactly
                }
                finally {
                    foreach ($name in $savedEnvironment.Keys) {
                        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
                    }
                }
            }
        }
    }

    It 'reports a missing OSDCloud action dependency as a child failure' {
        $command = & (Get-Module OSDCloudBootMenu) {
            New-OSDCloudBootMenuChildCommand -Command @'
$env:PSModulePath = Join-Path $env:TEMP ('BootMenuAbsent-' + [guid]::NewGuid().ToString('N'))
Import-Module -Name OSDCloud -ErrorAction Stop
'unexpected-action-ran'
'@
        }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $errorPath = Join-Path $TestDrive 'missing-dependency.stderr'
        $outputPath = Join-Path $TestDrive 'missing-dependency.stdout'
        $process = Start-Process -FilePath $windowsPowerShell -ArgumentList @('-NoProfile', '-EncodedCommand', $encoded) `
            -RedirectStandardError $errorPath -RedirectStandardOutput $outputPath -PassThru -Wait
        $process.ExitCode | Should -Be 1
        (Get-Content $errorPath -Raw) | Should -Match 'OSDCloud'
        (Get-Content $outputPath -Raw) | Should -BeNullOrEmpty
    }

    It 'executes the private network utilities in Windows PowerShell without importing OSDCloud' {
        $resultPath = Join-Path $TestDrive "network utilities O'Brien.txt"
        $escapedPath = $resultPath.Replace("'", "''")
        $command = @"
function script:ipconfig {
    param([string]`$Option)
    if (`$Option -ne '/all') { throw 'Unexpected IPConfig operation' }
    Add-Content -LiteralPath '$escapedPath' -Value 'ipconfig-ok'
}
function script:Test-OSDCloudInternetConnection { `$false }
function script:Test-Path { `$true }
function script:Start-Sleep { }
function script:Invoke-OSDCloudWifi { Add-Content -LiteralPath '$escapedPath' -Value 'wifi-ok' }
function script:hostname { 'BootMenuTest' }
function script:Test-Connection { [pscustomobject]@{ IPV4Address = [ipaddress]'192.0.2.1' } }
Show-WinpeStartupIpconfig
Show-WinpeStartupWifi
if (Get-Module OSDCloud) { throw 'Unexpected OSDCloud dependency' }
"@
        & (Get-Module OSDCloudBootMenu) {
            param($Command)
            Invoke-PEStartupCommand -Command $Command -WindowStyle Hidden -Wait
        } $command

        Get-Content -LiteralPath $resultPath | Should -Be @('ipconfig-ok', 'wifi-ok')
    }
}

Describe 'Module-owned BootMenu runtime' {
    InModuleScope OSDCloudBootMenu {
        BeforeEach {
            $script:savedSystemDrive = $env:SystemDrive
            $env:SystemDrive = 'X:'
            Mock Initialize-WinpeStartupEnvironment { }
            Mock Initialize-WinpeStartupDrivers { }
            Mock Initialize-WinpeStartupFiles { }
            Mock Initialize-WinpeStartupMain { }
            Mock Test-WinpeStartupAssetLicense { $false }
            Mock Get-OSDCloudBootMenuProfileCandidates { }
            Mock Start-Sleep { }
            Mock Start-Transcript { }
            Mock Stop-Transcript { }
            Mock New-Item { }
            Mock Start-Process { throw 'Unexpected child launch' }
            Mock Import-Module { throw 'Unexpected parent module import' }
        }
        AfterEach {
            $env:SystemDrive = $script:savedSystemDrive
        }

        It 'runs standalone startup without importing OSDCloud' {
            Invoke-OSDCloudBootMenu -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud -InvokeMainCommand @()
            Should -Invoke Initialize-WinpeStartupEnvironment -Times 1 -Exactly
            Should -Invoke Initialize-WinpeStartupDrivers -Times 1 -Exactly
            Should -Invoke Initialize-WinpeStartupFiles -Times 1 -Exactly
            Should -Invoke Initialize-WinpeStartupMain -Times 1 -Exactly
            Should -Invoke Import-Module -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'gates BootPack and asset discovery before filesystem access' {
            Mock Test-Path { throw 'Unexpected asset discovery' }
            Mock Get-ChildItem { throw 'Unexpected asset enumeration' }
            Mock Write-Warning { }
            @(Expand-WinpeStartupBootPack -Path 'X:\OSDCloud\boot-packs' -Destination 'X:\WinpeStartup\core').Count | Should -Be 0
            Import-WinpeStartupAssets -Path @('X:\selected') -SystemDrive 'X:'
            Should -Invoke Test-Path -Times 0 -Exactly
            Should -Invoke Get-ChildItem -Times 0 -Exactly
            Should -Invoke Write-Warning -Times 0 -Exactly
        }

        It 'imports the current manifest in every command phase' {
            $script:phaseCommands = [System.Collections.Generic.List[string]]::new()
            Mock Start-Process {
                $script:phaseCommands.Add([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1])))
                [pscustomobject]@{ ExitCode = 0 }
            }
            Invoke-OSDCloudBootMenu -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -InvokeStartupCommand "'startup'" -InvokeMainCommand "'main'" -InvokeShutdownCommand "'shutdown'"
            $script:phaseCommands.Count | Should -Be 3
            foreach ($command in $script:phaseCommands) {
                $command | Should -Match ([regex]::Escape($script:OSDCloudBootMenuModulePath))
                $command | Should -Match 'Import-Module.*-PassThru -ErrorAction Stop'
            }
            $script:phaseCommands[0] | Should -Match "'startup'"
            $script:phaseCommands[1] | Should -Match "'main'"
            $script:phaseCommands[2] | Should -Match "'shutdown'"
        }

        It 'launches <Command> directly with private module resolution and the requested window behavior' -ForEach @(
            @{ Command = 'Show-WinpeStartupWifi'; Style = 'Normal'; Run = 'Synchronous'; NoExit = $false; Wait = $true; ExpectedWait = $true }
            @{ Command = 'Show-WinpeStartupIpconfig'; Style = 'Minimized'; Run = 'Asynchronous'; NoExit = $true; Wait = $false; ExpectedWait = $false }
            @{ Command = 'Show-WinpeStartupDeviceErrors'; Style = 'Normal'; Run = 'Synchronous'; NoExit = $true; Wait = $true; ExpectedWait = $true }
            @{ Command = 'Show-WinpeStartupIpconfig'; Style = 'Minimized'; Run = 'Asynchronous'; NoExit = $true; Wait = $true; ExpectedWait = $false }
        ) {
            $script:utilityCommand = $null
            Mock Start-Process {
                $script:utilityCommand = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]))
                [pscustomobject]@{ ExitCode = 0 }
            }

            Invoke-PEStartupCommand -Command $Command -WindowStyle $Style -Run $Run -NoExit:$NoExit -Wait:$Wait

            $script:utilityCommand | Should -Match '& \$bootMenuModule'
            $script:utilityCommand | Should -Match ([regex]::Escape($Command))
            $script:utilityCommand | Should -Match ([regex]::Escape($script:OSDCloudBootMenuModulePath))
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -and
                $WindowStyle -eq $Style -and [bool]$Wait -eq $ExpectedWait -and [bool]$PassThru -eq $ExpectedWait -and
                $ArgumentList -contains '-NoProfile' -and
                ($ArgumentList -contains '-NoExit') -eq $NoExit -and $ArgumentList -contains '-EncodedCommand'
            }
        }

        It 'reports synchronous utility failures instead of returning as though startup succeeded' {
            Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }

            { Invoke-PEStartupCommand -Command 'Show-WinpeStartupWifi' -Wait } |
                Should -Throw "*Show-WinpeStartupWifi*exited with code 1*"
        }

        It 'surfaces utility process launch errors' {
            Mock Start-Process { throw 'Synthetic process launch failure' }

            { Invoke-PEStartupCommand -Command 'Show-WinpeStartupIpconfig' } |
                Should -Throw '*Synthetic process launch failure*'
        }
    }
}
