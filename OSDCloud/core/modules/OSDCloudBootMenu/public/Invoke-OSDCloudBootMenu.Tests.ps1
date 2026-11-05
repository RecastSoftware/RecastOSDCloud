BeforeAll {
    . "$PSScriptRoot\Invoke-OSDCloudBootMenu.ps1"
    . "$PSScriptRoot\..\private\Assert-OSDCloudBootMenuProfile.ps1"
    . "$PSScriptRoot\..\private\ConvertFrom-OSDCloudBootMenuProfile.ps1"
    . "$PSScriptRoot\..\private\Get-OSDCloudBootMenuProfileCandidates.ps1"
    . "$PSScriptRoot\..\private\OSDCloudBootString.ps1"
    . "$PSScriptRoot\..\private\Unlock-OSDCloudBootEnvironment.ps1"
    . "$PSScriptRoot\..\private\Confirm-OSDCloudBootMenuProfilePassword.ps1"
    $script:encryptedBytes = New-Object byte[] 97
    $script:encryptedBytes[0] = 1
    $script:syntheticToken = 'OSDBS1:' + [Convert]::ToBase64String($script:encryptedBytes)
    function New-OSDCloudBootMenuChildCommand { param ($Command) $Command }
    function Initialize-WinpeStartupEnvironment { }
    function Initialize-WinpeStartupDrivers { }
    function Initialize-WinpeStartupFiles { }
    function Initialize-WinpeStartupMain { }
    function Import-WinpeStartupAssets { param ($Path, $SystemDrive) }
    function Invoke-WinpeStartupManager { param ($Step, $Value) }
    function Show-OSDCloudBootMenuProfileWindow { param ($Profiles) }
    function Expand-WinpeStartupBootPack { param ($Path, $Destination, $Prefix, $SystemDrive) }
    function Invoke-WinpeStartupBootPackScripts { param ($Path) }
    $script:originalDrive = $env:SystemDrive
    $script:originalSite = $env:BOOTMENU_TEST_SITE
    $script:originalProfile = $env:OSDCLOUDBOOTMENU_PROFILE
    $script:originalAuthor = $env:OSDCLOUDBOOT_AUTHOR
    $script:OSDCloudBootMenuDefaultsPath = Join-Path $TestDrive 'missing-defaults.json'
    $script:realStartProcess = Get-Command Start-Process -CommandType Cmdlet
}

AfterAll {
    $env:SystemDrive = $script:originalDrive
    $env:BOOTMENU_TEST_SITE = $script:originalSite
    $env:OSDCLOUDBOOTMENU_PROFILE = $script:originalProfile
    $env:OSDCLOUDBOOT_AUTHOR = $script:originalAuthor
}

Describe 'OSDCloud BootMenu schema conversion' {
    It 'retains encryptedEnv as ciphertext without prompting or decrypting' {
        Mock Read-Host { throw 'Unexpected prompt' }
        Mock Invoke-OSDCloudBootStringCrypto { throw 'Unexpected decryption' }
        $file = Join-Path $TestDrive 'encrypted.json'
        @{ schemaVersion = 1; env = @{ PLAIN = 'Synthetic' }; encryptedEnv = @{ SECRET = $syntheticToken } } |
            ConvertTo-Json | Set-Content -LiteralPath $file
        $settings = ConvertFrom-OSDCloudBootMenuProfile -Path $file
        $settings['encryptedEnv']['SECRET'] | Should -BeExactly $syntheticToken
        $settings['env'].Contains('SECRET') | Should -BeFalse
        Should -Invoke Read-Host -Times 0 -Exactly
        Should -Invoke Invoke-OSDCloudBootStringCrypto -Times 0 -Exactly
    }

    It 'rejects invalid encrypted names, values, and collisions' -ForEach @(
        @{ Entry = '"BAD-NAME":"TOKEN"' }
        @{ Entry = '"SECRET":false' }
        @{ Entry = '"SECRET":"not-a-token"' }
        @{ Entry = '"SECRET":"TOKEN","SECRET":"TOKEN"' }
        @{ Entry = '"SECRET":"TOKEN","SECR\u0045T":"TOKEN"' }
        @{ Entry = '"plain":"TOKEN"' }
    ) {
        $file = Join-Path $TestDrive 'invalid-encrypted.json'
        ('{"schemaVersion":1,"env":{"PLAIN":"Synthetic"},"encryptedEnv":{' + $Entry.Replace('TOKEN', $syntheticToken) + '}}') |
            Set-Content -LiteralPath $file
        { Assert-OSDCloudBootMenuProfile -Path $file } | Should -Throw
    }

    It 'validates and renders the new schema without running commands' {
        $file = Join-Path $TestDrive 'conversion.json'
        @'
{
  "schemaVersion": 1,
  "info": { "name": "Menu", "id": "11111111-1111-1111-1111-111111111111" },
  "env": { "BOOTMENU_TEST_SITE": "Lab" },
  "osdcloudBoot": { "requireWinPE": true, "installModule": ["OSD"] },
  "osdcloudBootStartup": {
    "wifi": false, "showPnpDevices": true, "installModules": ["OSD"],
    "startup": { "enabled": false, "commands": ["throw 'not executed'"] },
    "main": {
      "commands": [
        "Show-OSDCloudDeviceInfo",
        "Import-Module -Name OSDCloud -DisableNameChecking -ErrorAction Stop",
        "Deploy-OSDCloud"
      ],
      "noExit": true, "errorAction": "Stop"
    }
  },
  "osdcloudBootMenu": { "enabled": false, "command": "Invoke-OSDCloudBootMenu" }
}
'@ | Set-Content -LiteralPath $file
        $settings = ConvertFrom-OSDCloudBootMenuProfile -Path $file
        $settings['env']['BOOTMENU_TEST_SITE'] | Should -Be 'Lab'
        $settings['Invoke-OSDCloudBootMenu:SkipWiFi'] | Should -BeTrue
        $settings['Invoke-OSDCloudBootMenu:ShowPnpDevices'] | Should -BeTrue
        $settings['Invoke-OSDCloudBootMenu:InvokeStartupCommand'] | Should -BeNullOrEmpty
        $settings['Invoke-OSDCloudBootMenu:InvokeMainCommand'] | Should -Be @(
            'Show-OSDCloudDeviceInfo', 'Import-Module -Name OSDCloud -DisableNameChecking -ErrorAction Stop', 'Deploy-OSDCloud'
        )
        $settings['Invoke-OSDCloudBootMenu:InvokeMainCommandNoExit'] | Should -BeTrue
        $settings['Invoke-OSDCloudBootMenu:InvokeMainCommandEA'] | Should -Be 'Stop'
    }

    It 'rejects old schema sections and conflicting requirements' -ForEach @(
        @{ Section = '"bootImage":{}' }
        @{ Section = '"winpeStartup":{}' }
        @{ Section = '"osdcloud":{}' }
        @{ Section = '"osdcloudMenu":{}' }
        @{ Section = '"deployOSDCloud":{"enabled":true}' }
        @{ Section = '"osdcloudBoot":{"requireWinPE":true,"requireWinRE":true}' }
    ) {
        $file = Join-Path $TestDrive 'invalid.json'
        ('{"schemaVersion":1,' + $Section + '}') | Set-Content -LiteralPath $file
        { Assert-OSDCloudBootMenuProfile -Path $file } | Should -Throw
    }
}

Describe 'OSDCloud BootMenu runtime' {
    BeforeEach {
        $env:SystemDrive = 'X:'
        $script:commands = [System.Collections.Generic.List[string]]::new()
        $file = Join-Path $TestDrive 'osdcloudbootmenu.json'
        $script:candidate = [pscustomobject]@{ Index = 0; Profile = 'Menu'; Id = '11111111-1111-1111-1111-111111111111'; Path = $file; AssetPath = $TestDrive }
        Mock Get-OSDCloudBootMenuProfileCandidates { $script:candidate }
        Mock Initialize-WinpeStartupEnvironment { }
        Mock Initialize-WinpeStartupDrivers { }
        Mock Initialize-WinpeStartupFiles { }
        Mock Initialize-WinpeStartupMain { }
        Mock Import-WinpeStartupAssets { }
        Mock Invoke-WinpeStartupManager { }
        Mock Expand-WinpeStartupBootPack { }
        Mock Invoke-WinpeStartupBootPackScripts { }
        Mock Start-Sleep { }
        Mock Start-Transcript { }
        Mock Stop-Transcript { }
        Mock New-Item { }
        Mock Write-Warning { }
        Mock Start-Process {
            $encoded = $ArgumentList[-1]
            $script:commands.Add([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded)))
            [pscustomobject]@{ ExitCode = 0 }
        }
        @'
{"schemaVersion":1,"info":{"name":"Menu","author":"Test"},"env":{"BOOTMENU_TEST_SITE":"Lab"},"osdcloudBootStartup":{"wifi":false,"onScreenKeyboard":false,"ipConfig":false,"updateOSDCloud":false,"main":{"commands":["Write-Output 'Menu'"],"noExit":true}}}
'@ | Set-Content -LiteralPath $file
    }

    It 'applies env and nested startup settings and runs the main phase' {
        Invoke-OSDCloudBootMenu
        $env:BOOTMENU_TEST_SITE | Should -Be 'Lab'
        $env:OSDCLOUDBOOTMENU_PROFILE | Should -Be 'Menu'
        $script:commands.ToArray() | Should -Be @("Write-Output 'Menu'")
        Should -Invoke Invoke-WinpeStartupManager -Times 0 -Exactly
        Should -Invoke Import-WinpeStartupAssets -Times 1 -Exactly
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '-NoExit' }
        Should -Invoke Write-Warning -Times 0 -Exactly
    }

    It 'requires profile authentication before env unlock or selected-profile side effects' -ForEach @(
        @{ Authorize = $true }, @{ Authorize = $false }
    ) {
        $profile = Get-Content $script:candidate.Path -Raw | ConvertFrom-Json
        $profile | Add-Member password $syntheticToken
        $profile | Add-Member encryptedEnv @{ BOOTMENU_TEST_UNLOCK = $syntheticToken }
        $profile | ConvertTo-Json -Depth 10 | Set-Content $script:candidate.Path
        $script:authorized = $false
        Mock Confirm-OSDCloudBootMenuProfilePassword { $script:authorized = $Authorize; $Authorize }
        Mock Unlock-OSDCloudBootEnvironment {
            $script:authorized | Should -BeTrue
            [ordered]@{ BOOTMENU_TEST_UNLOCK = 'Synthetic unlocked' }
        }
        Mock Import-WinpeStartupAssets { $script:authorized | Should -BeTrue }
        Invoke-OSDCloudBootMenu -CLI
        Should -Invoke Confirm-OSDCloudBootMenuProfilePassword -Times 1 -Exactly -ParameterFilter { $CLI }
        $script:commands.Count | Should -Be ([int]$Authorize)
        Should -Invoke Import-WinpeStartupAssets -Times ([int]$Authorize) -Exactly
        Should -Invoke Unlock-OSDCloudBootEnvironment -Times ([int]$Authorize) -Exactly
    }

    It 'does not bypass the password gate after GUI selection' {
        $profile = Get-Content $script:candidate.Path -Raw | ConvertFrom-Json
        $profile | Add-Member password $syntheticToken
        $profile | ConvertTo-Json -Depth 10 | Set-Content $script:candidate.Path
        Mock Get-OSDCloudBootMenuProfileCandidates { $script:candidate; $script:candidate.PSObject.Copy() }
        Mock Show-OSDCloudBootMenuProfileWindow { $script:candidate }
        Mock Confirm-OSDCloudBootMenuProfilePassword { $false }
        Invoke-OSDCloudBootMenu
        Should -Invoke Confirm-OSDCloudBootMenuProfilePassword -Times 1 -Exactly -ParameterFilter { -not $CLI }
        Should -Invoke Import-WinpeStartupAssets -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'applies build Import Packs before startup and profile Import Packs after selection' {
        $script:packOrder = [System.Collections.Generic.List[string]]::new()
        Mock Expand-WinpeStartupBootPack {
            $script:packOrder.Add("expand:$Path")
            if ($Prefix -eq 'bootpack-') { 'X:\WinpeStartup\core\bootpack-build' } else { 'X:\OSDCloud\bootpack-expanded\profile' }
        }
        Mock Initialize-WinpeStartupEnvironment { $script:packOrder.Add('environment') }
        Mock Import-WinpeStartupAssets { $script:packOrder.Add("import:$($Path -join ',')") }
        Mock Invoke-WinpeStartupBootPackScripts { $script:packOrder.Add("scripts:$($Path -join ',')") }
        Invoke-OSDCloudBootMenu
        $buildIndex = $script:packOrder.IndexOf('expand:X:\OSDCloud\boot-packs')
        $buildIndex | Should -BeGreaterOrEqual 0
        $buildIndex | Should -BeLessThan $script:packOrder.IndexOf('environment')
        $profileExpand = $script:packOrder.IndexOf("expand:$(Join-Path $TestDrive 'boot-packs')")
        $profileExpand | Should -BeGreaterThan $script:packOrder.IndexOf('scripts:X:\WinpeStartup\core\bootpack-build')
        $script:packOrder.IndexOf('import:X:\OSDCloud\bootpack-expanded\profile') | Should -BeGreaterThan $profileExpand
        $script:packOrder.IndexOf('scripts:X:\OSDCloud\bootpack-expanded\profile') |
            Should -BeGreaterThan $script:packOrder.IndexOf('import:X:\OSDCloud\bootpack-expanded\profile')
        $script:commands.ToArray() | Should -Be @("Write-Output 'Menu'")
    }

    It 'does not import profile assets again when the profile has no Import Packs' {
        Invoke-OSDCloudBootMenu
        Should -Invoke Import-WinpeStartupAssets -Times 1 -Exactly
        Should -Invoke Invoke-WinpeStartupBootPackScripts -Times 1 -Exactly
    }

    It 'allows explicit arguments to override JSON' {
        Invoke-OSDCloudBootMenu -SkipWiFi:$false -InvokeMainCommand @('Explicit')
        Should -Invoke Invoke-WinpeStartupManager -Times 1 -Exactly -ParameterFilter { $Step -eq 'WiFi' }
        $script:commands.ToArray() | Should -Be @('Explicit')
    }

    It 'runs deployment when there are no profiles' {
        Mock Get-OSDCloudBootMenuProfileCandidates { }
        Invoke-OSDCloudBootMenu
        $script:commands.ToArray() | Should -Be @("Import-Module -Name OSDCloud -DisableNameChecking -ErrorAction Stop`r`nDeploy-OSDCloud")
    }

    It 'does not run startup checks or commands when the startup section is disabled' {
        '{"schemaVersion":1,"osdcloudBootStartup":{"enabled":false,"main":{"commands":["Do-Not-Run"]}}}' |
            Set-Content -LiteralPath $script:candidate.Path
        Invoke-OSDCloudBootMenu
        $script:commands.Count | Should -Be 0
        Should -Invoke Invoke-WinpeStartupManager -Times 0 -Exactly
    }

    It 'stops on malformed selected JSON without running deployment' {
        '{broken' | Set-Content -LiteralPath $script:candidate.Path
        Invoke-OSDCloudBootMenu
        $script:commands.Count | Should -Be 0
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*Failed to load profile*' }
    }

    It 'does not start anything outside WinPE' {
        $env:SystemDrive = 'C:'
        Invoke-OSDCloudBootMenu
        $script:commands.Count | Should -Be 0
        Should -Invoke Initialize-WinpeStartupEnvironment -Times 0 -Exactly
    }

    It 'does not default to deployment after profile discovery fails' {
        Mock Get-OSDCloudBootMenuProfileCandidates { throw 'Invalid menu JSON' }
        Invoke-OSDCloudBootMenu
        $script:commands.Count | Should -Be 0
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*Profile discovery failed*' }
    }

    It 'supports multiple-profile CLI selection without opening a window' {
        $script:otherCandidate = [pscustomobject]@{
            Index = 0; Profile = 'Other'; Path = Join-Path $TestDrive 'z-other.json'; AssetPath = $null
        }
        '{"schemaVersion":1,"osdcloudBootStartup":{"main":{"commands":["Other-Command"]}}}' |
            Set-Content -LiteralPath $script:otherCandidate.Path
        Mock Get-OSDCloudBootMenuProfileCandidates { $script:candidate; $script:otherCandidate }
        Mock Read-Host { '2' }
        Mock Show-OSDCloudBootMenuProfileWindow { throw 'Must not open a window' }
        Invoke-OSDCloudBootMenu -CLI
        $script:commands.ToArray() | Should -Be @('Other-Command')
        Should -Invoke Show-OSDCloudBootMenuProfileWindow -Times 0 -Exactly
    }

    It 'stops after cancelling the multiple-profile window' {
        Mock Get-OSDCloudBootMenuProfileCandidates { $script:candidate; $script:candidate.PSObject.Copy() }
        Mock Show-OSDCloudBootMenuProfileWindow { $null }
        Invoke-OSDCloudBootMenu
        $script:commands.Count | Should -Be 0
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*selection cancelled*' }
    }

    It 'unlocks before selected assets, overrides asset env, and restores after every phase' {
        $saved = $env:BOOTMENU_TEST_UNLOCK
        try {
            $env:BOOTMENU_TEST_UNLOCK = 'Synthetic original'
            $profile = Get-Content $script:candidate.Path -Raw | ConvertFrom-Json
            $profile | Add-Member encryptedEnv @{ BOOTMENU_TEST_UNLOCK = $syntheticToken }
            $profile | ConvertTo-Json -Depth 10 | Set-Content $script:candidate.Path
            Mock Unlock-OSDCloudBootEnvironment {
                $env:BOOTMENU_TEST_UNLOCK | Should -BeExactly 'Synthetic original'
                [ordered]@{ BOOTMENU_TEST_UNLOCK = 'Synthetic unlocked' }
            }
            Mock Import-WinpeStartupAssets { $env:BOOTMENU_TEST_UNLOCK = 'Synthetic asset' }
            Mock Expand-WinpeStartupBootPack { if (-not $Prefix) { 'Synthetic expanded' } }
            Mock Invoke-WinpeStartupBootPackScripts {
                if ($Path -contains 'Synthetic expanded') { $env:BOOTMENU_TEST_UNLOCK | Should -BeExactly 'Synthetic unlocked' }
            }
            Mock Start-Process {
                $env:BOOTMENU_TEST_UNLOCK | Should -BeExactly 'Synthetic unlocked'
                [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1])) | Should -Not -Match 'Synthetic unlocked'
                [pscustomobject]@{ ExitCode = 0 }
            }
            Invoke-OSDCloudBootMenu -InvokeStartupCommand 'Synthetic-Startup' -InvokeShutdownCommand 'Synthetic-Shutdown'
            Should -Invoke Start-Process -Times 3 -Exactly
            Should -Invoke Unlock-OSDCloudBootEnvironment -Times 1 -Exactly
            $env:BOOTMENU_TEST_UNLOCK | Should -BeExactly 'Synthetic original'
        }
        finally { $env:BOOTMENU_TEST_UNLOCK = $saved }
    }

    It 'restores absent variables after initialization or child failures' -ForEach @(
        @{ Failure = 'Asset' }, @{ Failure = 'Child' }
    ) {
        $saved = $env:BOOTMENU_TEST_UNLOCK
        try {
            [Environment]::SetEnvironmentVariable('BOOTMENU_TEST_UNLOCK', $null, 'Process')
            $profile = Get-Content $script:candidate.Path -Raw | ConvertFrom-Json
            $profile | Add-Member encryptedEnv @{ BOOTMENU_TEST_UNLOCK = $syntheticToken }
            $profile | ConvertTo-Json -Depth 10 | Set-Content $script:candidate.Path
            Mock Unlock-OSDCloudBootEnvironment { [ordered]@{ BOOTMENU_TEST_UNLOCK = 'Synthetic unlocked' } }
            if ($Failure -eq 'Asset') {
                Mock Import-WinpeStartupAssets { $env:BOOTMENU_TEST_UNLOCK = 'Synthetic asset'; throw 'Synthetic asset failure' }
            }
            else {
                Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
            }
            { Invoke-OSDCloudBootMenu -InvokeMainCommandEA Stop } | Should -Throw
            [Environment]::GetEnvironmentVariable('BOOTMENU_TEST_UNLOCK', 'Process') | Should -BeNullOrEmpty
            Should -Invoke Stop-Transcript -Times 1 -Exactly
        }
        finally { $env:BOOTMENU_TEST_UNLOCK = $saved }
    }

    It 'restores environment on a pipeline interruption in an isolated Windows PowerShell process' {
        $profile = Get-Content $script:candidate.Path -Raw | ConvertFrom-Json
        $profile | Add-Member encryptedEnv @{ BOOTMENU_TEST_UNLOCK = $syntheticToken }
        $profile | ConvertTo-Json -Depth 10 | Set-Content $script:candidate.Path
        $scriptPath = Join-Path $TestDrive 'interrupt.ps1'
        $resultPath = Join-Path $TestDrive 'interrupt-result.txt'
        @'
param($ModulePath, $ProfilePath, $ResultPath)
$ErrorActionPreference = 'Stop'
$module = Import-Module $ModulePath -PassThru
& $module {
    param($ProfilePath, $ResultPath)
    $script:testProfilePath = $ProfilePath
    $script:transcriptStopped = $false
    $script:profileCommandsLaunched = $false
    $env:SystemDrive = 'X:'
    $env:BOOTMENU_TEST_UNLOCK = 'Synthetic original'
    function script:Get-OSDCloudBootMenuProfileCandidates { [pscustomobject]@{ Index = 0; Path = $script:testProfilePath; AssetPath = (Split-Path $script:testProfilePath) } }
    function script:Initialize-WinpeStartupEnvironment { }
    function script:Initialize-WinpeStartupDrivers { }
    function script:Initialize-WinpeStartupFiles { }
    function script:Initialize-WinpeStartupMain { }
    function script:Expand-WinpeStartupBootPack { }
    function script:Invoke-WinpeStartupBootPackScripts { }
    function script:Start-Sleep { }
    function script:New-Item { }
    function script:Start-Transcript { }
    function script:Stop-Transcript { $script:transcriptStopped = $true }
    function script:Start-Process { $script:profileCommandsLaunched = $true; throw 'Unexpected child launch' }
    function script:Unlock-OSDCloudBootEnvironment { [ordered]@{ BOOTMENU_TEST_UNLOCK = 'Synthetic unlocked' } }
    function script:Import-WinpeStartupAssets {
        $script:interruptedAfterUnlock = $true
        $env:BOOTMENU_TEST_UNLOCK = 'Synthetic asset'
        throw [System.Management.Automation.PipelineStoppedException]::new()
    }
    try { Invoke-OSDCloudBootMenu }
    finally {
        $restored = $env:BOOTMENU_TEST_UNLOCK -ceq 'Synthetic original' -and $script:transcriptStopped -and $script:interruptedAfterUnlock -and -not $script:profileCommandsLaunched
        [IO.File]::WriteAllText($ResultPath, [string]$restored)
    }
} $ProfilePath $ResultPath
'@ | Set-Content -LiteralPath $scriptPath
        $modulePath = Join-Path $PSScriptRoot '..\OSDCloudBootMenu.psd1'
        $output = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File $scriptPath $modulePath $script:candidate.Path $resultPath 2> (Join-Path $TestDrive 'interrupt.stderr')
        Get-Content -LiteralPath $resultPath | Should -BeExactly 'True'
    }

    It 'passes unlocked variables to a real Windows PowerShell child without embedding their values' {
        $saved = $env:BOOTMENU_TEST_UNLOCK
        $password = ConvertTo-SecureString 'Synthetic integration password' -AsPlainText -Force
        try {
            $env:BOOTMENU_TEST_UNLOCK = 'Synthetic original'
            $profile = Get-Content $script:candidate.Path -Raw | ConvertFrom-Json
            $token = Invoke-OSDCloudBootStringCrypto -InputString 'Synthetic inherited' -Password $password
            $profile | Add-Member encryptedEnv @{ BOOTMENU_TEST_UNLOCK = $token }
            $profile | ConvertTo-Json -Depth 10 | Set-Content $script:candidate.Path
            $script:childErrorPath = Join-Path $TestDrive 'inheritance.stderr'
            Mock Start-Process {
                $child = & $script:realStartProcess -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -Wait -WindowStyle Hidden -RedirectStandardError $script:childErrorPath
                if ($child.ExitCode -ne 0) { throw (Get-Content $script:childErrorPath -Raw) }
                $child
            }
            $resultPath = Join-Path $TestDrive 'child-environment.txt'
            $command = "[IO.File]::WriteAllText('$($resultPath.Replace("'", "''"))', `$env:BOOTMENU_TEST_UNLOCK)"
            Invoke-OSDCloudBootMenu -EnvironmentPassword $password -InvokeMainCommand $command -InvokeMainCommandNoExit:$false -InvokeMainCommandEA Stop
            Get-Content -LiteralPath $resultPath | Should -BeExactly 'Synthetic inherited'
            $env:BOOTMENU_TEST_UNLOCK | Should -BeExactly 'Synthetic original'
        }
        finally { $env:BOOTMENU_TEST_UNLOCK = $saved; $password.Dispose() }
    }

    It 'does not run selected assets or child commands after a cancelled or failed unlock' -ForEach @(
        @{ Cancel = $true }, @{ Cancel = $false }
    ) {
        $profile = Get-Content $script:candidate.Path -Raw | ConvertFrom-Json
        $profile | Add-Member encryptedEnv @{ BOOTMENU_TEST_UNLOCK = $syntheticToken }
        $profile | ConvertTo-Json -Depth 10 | Set-Content $script:candidate.Path
        Mock Unlock-OSDCloudBootEnvironment {
            if ($Cancel) { throw [OperationCanceledException]::new('Synthetic cancellation') }
            throw [Security.Cryptography.CryptographicException]::new('Synthetic authentication failure')
        }
        if ($Cancel) { Invoke-OSDCloudBootMenu }
        else { { Invoke-OSDCloudBootMenu } | Should -Throw }
        Should -Invoke Import-WinpeStartupAssets -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Stop-Transcript -Times 1 -Exactly
    }

    It 'forwards an explicit SecureString without owning or disposing it' {
        $profile = Get-Content $script:candidate.Path -Raw | ConvertFrom-Json
        $profile | Add-Member password $syntheticToken
        $profile | Add-Member encryptedEnv @{ BOOTMENU_TEST_UNLOCK = $syntheticToken }
        $profile | ConvertTo-Json -Depth 10 | Set-Content $script:candidate.Path
        $script:suppliedPassword = ConvertTo-SecureString 'Synthetic supplied' -AsPlainText -Force
        try {
            Mock Confirm-OSDCloudBootMenuProfilePassword {
                [object]::ReferenceEquals($Password, $script:suppliedPassword) | Should -BeTrue
                $true
            }
            Mock Unlock-OSDCloudBootEnvironment {
                [object]::ReferenceEquals($Password, $script:suppliedPassword) | Should -BeTrue
                [ordered]@{ BOOTMENU_TEST_UNLOCK = 'Synthetic unlocked' }
            }
            Invoke-OSDCloudBootMenu -EnvironmentPassword $script:suppliedPassword -ProfilePassword $script:suppliedPassword
            Should -Invoke Confirm-OSDCloudBootMenuProfilePassword -Times 1 -Exactly -ParameterFilter { $Password.Length -gt 0 }
            Should -Invoke Unlock-OSDCloudBootEnvironment -Times 1 -Exactly -ParameterFilter { $Password.Length -gt 0 }
            $script:suppliedPassword.Length | Should -BeGreaterThan 0
        }
        finally { $script:suppliedPassword.Dispose() }
    }
}

Describe 'OSDCloud BootMenu discovery' {
    It 'searches only OSDCloud profile roots with X first followed by C through Z' {
        $script:searchedRoots = [System.Collections.Generic.List[string]]::new()
        Mock Test-Path {
            $script:searchedRoots.Add($LiteralPath)
            $false
        }
        @(Get-OSDCloudBootMenuProfileCandidates).Count | Should -Be 0
        $expected = @('X:\OSDCloud\core\bootmenu-profiles') + @(
            [char[]](67..90) | Where-Object { $_ -ne 'X' } |
                ForEach-Object { '{0}:\OSDCloud\core\bootmenu-profiles' -f $_ }
        )
        $script:searchedRoots.ToArray() | Should -Be $expected
    }

    It 'uses info identity, ignores legacy JSON and deduplicates GUIDs' {
        $root = Join-Path $TestDrive 'OSDCloud\core\bootmenu-profiles'
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'Folder'), (Join-Path $root 'Legacy'), (Join-Path $root 'Duplicate') -Force
        $json = '{"schemaVersion":1,"info":{"name":"Display Name","id":"11111111-1111-1111-1111-111111111111"}}'
        $json | Set-Content -LiteralPath (Join-Path $root 'Folder\osdcloudbootmenu.json')
        $json | Set-Content -LiteralPath (Join-Path $root 'Duplicate\osdcloudbootmenu.json')
        '{}' | Set-Content -LiteralPath (Join-Path $root 'Legacy\winpestartup.json')
        $createdDrive = -not (Get-PSDrive -Name X -ErrorAction SilentlyContinue)
        if ($createdDrive) { $null = New-PSDrive -Name X -PSProvider FileSystem -Root $TestDrive }
        Mock Test-Path { $LiteralPath -eq 'X:\OSDCloud\core\bootmenu-profiles' } -ParameterFilter { $LiteralPath -match '^[A-Z]:\\OSDCloud\\core\\bootmenu-profiles$' }
        try { $items = @(Get-OSDCloudBootMenuProfileCandidates) }
        finally { if ($createdDrive) { Remove-PSDrive -Name X } }
        $items.Count | Should -Be 1
        $items[0].Profile | Should -Be 'Display Name'
        $items[0].Id | Should -Be '11111111-1111-1111-1111-111111111111'
        $items[0].Path | Should -Match 'osdcloudbootmenu.json$'
    }
}
