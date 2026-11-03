BeforeAll {
    . "$PSScriptRoot\step-update-oobemenu.ps1"
    $originalDevice = $global:OSDCoreDevice
    $originalDrive = $env:SystemDrive
}
AfterAll {
    $global:OSDCoreDevice = $originalDevice
    $env:SystemDrive = $originalDrive
}

Describe 'step-update-oobemenu' {
    BeforeEach {
        $env:SystemDrive = 'X:'
        $global:OSDCoreDevice = [pscustomobject]@{ IsWinPE = $true }
        Mock Test-Path { $true }
        Mock New-Item {}
        Mock Copy-Item {}
        Mock Write-Host {}
        Mock Write-OSDCloudSetupMenuScript {}
    }

    It 'stages one runtime script and prepends both phase invocations' {
        step-update-oobemenu
        Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {
            $Destination -eq 'C:\Windows\Setup\Scripts\Show-OSDCloudOOBEMenu.ps1' -and
            $LiteralPath -like '*\core\oobe\Show-OSDCloudOOBEMenu.ps1' -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\Windows\Setup\Scripts\OOBE.cmd' -and $Phase -eq 'OOBE'
        }
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\Windows\Setup\Scripts\SetupComplete.cmd' -and $Phase -eq 'SetupComplete'
        }
    }

    It 'does not stage files outside WinPE even if device metadata is stale' {
        $env:SystemDrive = 'C:'
        step-update-oobemenu -WarningAction SilentlyContinue
        Should -Invoke Copy-Item -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }

    It 'reports missing assets without writing to the Windows image' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*\core\oobe\*' }
        Mock Write-Warning {}
        step-update-oobemenu
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*source is missing*' }
        Should -Invoke Copy-Item -Times 0 -Exactly
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }

    It 'reports a missing applied Windows image before writing' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'C:\Windows\System32\Config\SYSTEM' }
        Mock Write-Warning {}
        step-update-oobemenu
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*applied Windows image is missing*' }
        Should -Invoke Copy-Item -Times 0 -Exactly
    }

    It 'reports copy errors without writing a success-shaped invocation' {
        Mock Copy-Item { throw 'Disk write failed' }
        Mock Write-Warning {}
        step-update-oobemenu
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*Disk write failed*' }
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }
}

Describe 'Setup menu batch invocation' {
    It 'prepends each phase before all original commands, including early exit, preserving body bytes' {
        foreach ($phase in 'OOBE', 'SetupComplete') {
            $path = Join-Path $TestDrive "$phase.cmd"
            $body = [byte[]](64, 101, 99, 104, 111, 32, 111, 102, 102, 13, 10, 233, 13, 10)
            $tail = [Text.Encoding]::ASCII.GetBytes("echo existing`r`nexit /b 0`r`n")
            [IO.File]::WriteAllBytes($path, [byte[]]($body + $tail))
            Write-OSDCloudSetupMenuScript -Path $path -Phase $phase
            $result = [IO.File]::ReadAllBytes($path)
            $text = [Text.Encoding]::GetEncoding(28591).GetString($result)
            $text | Should -Match "^:: RecastOSDCloud $phase Menu"
            $text | Should -Match "-Phase $phase"
            $text | Should -Match 'Sysnative\\WindowsPowerShell'
            $text | Should -Match '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass'
            $text | Should -Match 'OSDCloudOOBEExitCode=%ERRORLEVEL%'
            $original = [byte[]]($body + $tail)
            [Convert]::ToBase64String($result[($result.Length - $original.Length)..($result.Length - 1)]) |
                Should -Be ([Convert]::ToBase64String($original))
            $text.IndexOf('-Phase') | Should -BeLessThan $text.IndexOf('echo existing')
        }
    }

    It 'creates missing batch files and repeated staging is byte-for-byte idempotent' {
        foreach ($phase in 'OOBE', 'SetupComplete') {
            $path = Join-Path $TestDrive "$phase.cmd"
            Write-OSDCloudSetupMenuScript -Path $path -Phase $phase
            $first = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
            Write-OSDCloudSetupMenuScript -Path $path -Phase $phase
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -Be $first
            ([IO.File]::ReadAllText($path) -split ":: RecastOSDCloud $phase Menu").Count | Should -Be 2
        }
    }

    It 'moves a legacy appended OOBE menu block to the beginning without duplicating it' {
        $path = Join-Path $TestDrive 'OOBE.cmd'
        [IO.File]::WriteAllText($path, "echo original`r`n:: RecastOSDCloud OOBE Menu`r`necho legacy`r`n:: End RecastOSDCloud OOBE Menu`r`necho tail")
        Write-OSDCloudSetupMenuScript -Path $path -Phase OOBE
        $text = [IO.File]::ReadAllText($path)
        $text | Should -Match '^:: RecastOSDCloud OOBE Menu'
        $text | Should -Not -Match 'echo legacy'
        $text | Should -Match "echo original`r`necho tail$"
    }

    It 'rejects an incomplete managed block instead of duplicating or discarding user commands' {
        $path = Join-Path $TestDrive 'OOBE.cmd'
        $original = ":: RecastOSDCloud OOBE Menu`r`necho user command"
        [IO.File]::WriteAllText($path, $original)
        { Write-OSDCloudSetupMenuScript -Path $path -Phase OOBE } | Should -Throw '*Incomplete managed menu block*'
        [IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'logs missing executable failures and executes remaining commands in both phases' {
        $fakeWindows = Join-Path $TestDrive 'Windows With Spaces'
        [void][IO.Directory]::CreateDirectory($fakeWindows)
        foreach ($phase in 'OOBE', 'SetupComplete') {
            $path = Join-Path $fakeWindows "$phase.cmd"
            [IO.File]::WriteAllText($path, "echo AFTER_$phase`r`n")
            Write-OSDCloudSetupMenuScript -Path $path -Phase $phase
            $wrapper = Join-Path $TestDrive "invoke-$phase.cmd"
            [IO.File]::WriteAllText($wrapper, "@echo off`r`nset `"SystemRoot=$fakeWindows`"`r`ncall `"$path`"`r`n")
            $output = (& $env:ComSpec /d /c "`"$wrapper`"" 2>&1 | Out-String)
            $output | Should -Match "AFTER_$phase"
            $output | Should -Match "$phase menu failed with exit code [1-9][0-9]*\. Continuing Windows Setup"
            $log = [IO.File]::ReadAllText((Join-Path $fakeWindows 'Temp\osdcloud-logs\OOBEMenu.log'))
            $log | Should -Match "$phase menu invocation failed with exit code [1-9][0-9]*"
        }
    }
}

Describe 'Dark workflow setup menu integration' {
    It 'enables the staging step exactly once before finalization in both tasks' {
        $taskRoot = Join-Path $PSScriptRoot '..\..\..\workflow\recast-winui-dark\tasks'
        foreach ($name in 'osdcloud.json', 'osdcloud-nofirmware.json') {
            $task = Get-Content -LiteralPath (Join-Path $taskRoot $name) -Raw | ConvertFrom-Json
            $task.amd64 | Should -BeTrue
            $task.arm64 | Should -BeTrue
            $steps = @($task.steps)
            $menu = @($steps | Where-Object command -eq 'step-update-oobemenu')
            $menu.Count | Should -Be 1
            $menu[0].skip | Should -BeFalse
            $steps.IndexOf($menu[0]) | Should -BeLessThan $steps.IndexOf(
                ($steps | Where-Object command -eq 'step-finalize-exportofflineosinfo')
            )
            $steps[0].command | Should -Be 'step-initialize-osdcloudworkflowtask'
            $steps[-1].command | Should -Be 'step-finalize-stoposdcloudworkflow'
        }
    }
}
