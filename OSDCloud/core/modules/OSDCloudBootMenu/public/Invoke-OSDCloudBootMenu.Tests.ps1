BeforeAll {
    . "$PSScriptRoot\Invoke-OSDCloudBootMenu.ps1"
    . "$PSScriptRoot\..\private\Assert-OSDCloudBootMenuProfile.ps1"
    . "$PSScriptRoot\..\private\ConvertFrom-OSDCloudBootMenuProfile.ps1"
    . "$PSScriptRoot\..\private\Get-OSDCloudBootMenuProfileCandidates.ps1"
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
}

AfterAll {
    $env:SystemDrive = $script:originalDrive
    $env:BOOTMENU_TEST_SITE = $script:originalSite
    $env:OSDCLOUDBOOTMENU_PROFILE = $script:originalProfile
    $env:OSDCLOUDBOOT_AUTHOR = $script:originalAuthor
}

Describe 'OSDCloud BootMenu schema conversion' {
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
