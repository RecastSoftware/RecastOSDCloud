BeforeAll {
    . "$PSScriptRoot\step-update-preoobe.ps1"
    $originalDevice = $global:OSDCoreDevice
    $originalDrive = $env:SystemDrive
}
AfterAll {
    $global:OSDCoreDevice = $originalDevice
    $env:SystemDrive = $originalDrive
}

Describe 'step-update-preoobe' {
    BeforeEach {
        $env:SystemDrive = 'X:'
        $global:OSDCoreDevice = [pscustomobject]@{ IsWinPE = $true }
        Mock Test-Path { $true }
        Mock New-Item {}
        Mock Save-OSDCloudPreOOBERuntime {}
        Mock Write-Host {}
        Mock Write-OSDCloudSetupMenuScript {}
    }

    It 'stages one runtime script, appends OOBE and cleans up legacy SetupComplete' {
        step-update-preoobe
        Should -Invoke Save-OSDCloudPreOOBERuntime -Times 1 -Exactly -ParameterFilter {
            $DestinationPath -eq 'C:\Windows\Setup\Scripts\OSDCloudPreOOBE.ps1' -and
            $SourcePath -like '*\core\oobe\OSDCloudPreOOBE.ps1'
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
        step-update-preoobe -WarningAction SilentlyContinue
        Should -Invoke Save-OSDCloudPreOOBERuntime -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }

    It 'reports missing assets without writing to the Windows image' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*\core\oobe\*' }
        Mock Write-Warning {}
        step-update-preoobe
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*source is missing*' }
        Should -Invoke Save-OSDCloudPreOOBERuntime -Times 0 -Exactly
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }

    It 'reports a missing applied Windows image before writing' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'C:\Windows\System32\Config\SYSTEM' }
        Mock Write-Warning {}
        step-update-preoobe
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*applied Windows image is missing*' }
        Should -Invoke Save-OSDCloudPreOOBERuntime -Times 0 -Exactly
    }

    It 'reports copy errors without writing a success-shaped invocation' {
        Mock Save-OSDCloudPreOOBERuntime { throw 'Disk write failed' }
        Mock Write-Warning {}
        step-update-preoobe
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*Disk write failed*' }
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }
}

Describe 'Setup menu batch invocation' {
    It 'bundles all components into one parseable standalone script' {
        $source = Join-Path $PSScriptRoot '..\..\..\core\oobe\OSDCloudPreOOBE.ps1'
        $destination = Join-Path $TestDrive 'OSDCloudPreOOBE.ps1'
        Save-OSDCloudPreOOBERuntime -SourcePath $source -DestinationPath $destination
        $text = [IO.File]::ReadAllText($destination)
        $text | Should -Not -Match '#region PreOOBE components'
        $version = (Import-PowerShellDataFile (Join-Path $PSScriptRoot '..\..\..\OSDCloud.psd1')).ModuleVersion
        $text | Should -Match ([regex]::Escape("`$OSDCloudPreOOBEVersion = '$version'"))
        $text | Should -Not -Match 'OSDCloud\.psd1'
        $text | Should -Match 'function Invoke-OSDCloudPreOOBEDriverPack'
        $text | Should -Match 'function Show-OOBEMenuWindow'
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($destination,[ref]$tokens,[ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'appends OOBE after all original commands preserving body bytes' {
        foreach ($phase in 'OOBE') {
            $path = Join-Path $TestDrive "$phase.cmd"
            $body = [byte[]](64, 101, 99, 104, 111, 32, 111, 102, 102, 13, 10, 233, 13, 10)
            $tail = [Text.Encoding]::ASCII.GetBytes("echo existing`r`n")
            [IO.File]::WriteAllBytes($path, [byte[]]($body + $tail))
            Write-OSDCloudSetupMenuScript -Path $path -Phase $phase
            $result = [IO.File]::ReadAllBytes($path)
            $text = [Text.Encoding]::GetEncoding(28591).GetString($result)
            $text | Should -Match ":: End RecastOSDCloud PreOOBE`r`n$"
            $text | Should -Match 'OSDCloudPreOOBE.ps1'
            $text | Should -Not -Match '-Phase'
            $text | Should -Match 'Sysnative\\WindowsPowerShell'
            $text | Should -Match '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass'
            $text | Should -Match 'OSDCloudOOBEExitCode=%ERRORLEVEL%'
            $original = [byte[]]($body + $tail)
            [Convert]::ToBase64String($result[0..($original.Length - 1)]) |
                Should -Be ([Convert]::ToBase64String($original))
            $text.IndexOf('-File') | Should -BeGreaterThan $text.IndexOf('echo existing')
        }
    }

    It 'creates missing batch files and repeated staging is byte-for-byte idempotent' {
        foreach ($phase in 'OOBE') {
            $path = Join-Path $TestDrive "$phase.cmd"
            Write-OSDCloudSetupMenuScript -Path $path -Phase $phase
            $first = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
            Write-OSDCloudSetupMenuScript -Path $path -Phase $phase
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -Be $first
            ([IO.File]::ReadAllText($path) -split ":: RecastOSDCloud PreOOBE").Count | Should -Be 2
        }
    }

    It 'moves a legacy OOBE block to the end without duplicating it' {
        $path = Join-Path $TestDrive 'OOBE.cmd'
        [IO.File]::WriteAllText($path, "echo original`r`n:: RecastOSDCloud OOBE Menu`r`necho legacy`r`n:: End RecastOSDCloud OOBE Menu`r`necho tail")
        Write-OSDCloudSetupMenuScript -Path $path -Phase OOBE
        $text = [IO.File]::ReadAllText($path)
        $text | Should -Match ":: End RecastOSDCloud PreOOBE`r`n$"
        $text | Should -Not -Match 'echo legacy'
        $text | Should -Match "^echo original`r`necho tail`r`n:: RecastOSDCloud PreOOBE"
    }

    It 'rejects an incomplete managed block instead of duplicating or discarding user commands' {
        $path = Join-Path $TestDrive 'OOBE.cmd'
        $original = ":: RecastOSDCloud OOBE Menu`r`necho user command"
        [IO.File]::WriteAllText($path, $original)
        { Write-OSDCloudSetupMenuScript -Path $path -Phase OOBE } | Should -Throw '*Incomplete managed menu block*'
        [IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'moves a prepended OOBE block to the end and remains idempotent with no original trailing newline' {
        $path = Join-Path $TestDrive 'OOBE.cmd'
        [IO.File]::WriteAllText($path, ":: RecastOSDCloud OOBE Menu`r`necho legacy`r`n:: End RecastOSDCloud OOBE Menu`r`necho original")
        Write-OSDCloudSetupMenuScript -Path $path -Phase OOBE
        $first = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
        [IO.File]::ReadAllText($path) | Should -Match "^echo original`r`n:: RecastOSDCloud PreOOBE"
        Write-OSDCloudSetupMenuScript -Path $path -Phase OOBE
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -Be $first
    }

    It 'rejects incomplete legacy SetupComplete blocks without modifying them' {
        $path = Join-Path $TestDrive 'SetupComplete.cmd'
        $original = ":: RecastOSDCloud SetupComplete Menu`r`necho original"
        [IO.File]::WriteAllText($path, $original)
        { Write-OSDCloudSetupMenuScript -Path $path -Phase SetupComplete } | Should -Throw '*Incomplete managed menu block*'
        [IO.File]::ReadAllText($path) | Should -Be $original
    }

    It 'does not create or alter unmanaged SetupComplete scripts' {
        $path = Join-Path $TestDrive 'UnmanagedSetupComplete.cmd'
        Write-OSDCloudSetupMenuScript -Path $path -Phase SetupComplete
        Test-Path -LiteralPath $path | Should -BeFalse
        $bytes = [byte[]](64, 101, 99, 104, 111, 32, 233)
        [IO.File]::WriteAllBytes($path, $bytes)
        Write-OSDCloudSetupMenuScript -Path $path -Phase SetupComplete
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -Be ([Convert]::ToBase64String($bytes))
    }

    It 'removes only the legacy SetupComplete block preserving original commands' {
        $path = Join-Path $TestDrive 'SetupComplete.cmd'
        $body = "echo original`r`necho tail"
        [IO.File]::WriteAllText($path, ":: RecastOSDCloud SetupComplete Menu`r`necho legacy`r`n:: End RecastOSDCloud SetupComplete Menu`r`n$body")
        Write-OSDCloudSetupMenuScript -Path $path -Phase SetupComplete
        [IO.File]::ReadAllText($path) | Should -Be $body
        Write-OSDCloudSetupMenuScript -Path $path -Phase SetupComplete
        [IO.File]::ReadAllText($path) | Should -Be $body
    }

    It 'warns about early exit without changing the original control flow' {
        Mock Write-Warning {}
        $path = Join-Path $TestDrive 'OOBE.cmd'
        [IO.File]::WriteAllText($path, "echo original`r`nexit /b 0`r`n")
        Write-OSDCloudSetupMenuScript -Path $path -Phase OOBE
        [IO.File]::ReadAllText($path) | Should -Match "^echo original`r`nexit /b 0`r`n:: RecastOSDCloud"
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*early exit*' }
    }

    It 'logs missing executable failures after running the original OOBE commands' {
        $fakeWindows = Join-Path $TestDrive 'Windows With Spaces'
        [void][IO.Directory]::CreateDirectory($fakeWindows)
        foreach ($phase in 'OOBE') {
            $path = Join-Path $fakeWindows "$phase.cmd"
            [IO.File]::WriteAllText($path, "echo AFTER_$phase`r`n")
            Write-OSDCloudSetupMenuScript -Path $path -Phase $phase
            $wrapper = Join-Path $TestDrive "invoke-$phase.cmd"
            [IO.File]::WriteAllText($wrapper, "@echo off`r`nset `"SystemRoot=$fakeWindows`"`r`ncall `"$path`"`r`n")
            $output = (& $env:ComSpec /d /c "`"$wrapper`"" 2>&1 | Out-String)
            $output | Should -Match "AFTER_$phase"
            $output | Should -Match "OSDCloudPreOOBE failed with exit code [1-9][0-9]*\. Continuing Windows Setup"
            $output.IndexOf("AFTER_$phase") | Should -BeLessThan $output.IndexOf("OSDCloudPreOOBE failed")
            $log = [IO.File]::ReadAllText((Join-Path $fakeWindows 'Temp\osdcloud-logs\OSDCloudPreOOBE.log'))
            $log | Should -Match "PreOOBE invocation failed with exit code [1-9][0-9]*"
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
            $menu = @($steps | Where-Object command -eq 'step-update-preoobe')
            $menu.Count | Should -Be 1
            $menu[0].skip | Should -BeFalse
            ($steps | Where-Object command -eq 'step-Save-WindowsDriver-DriverPack').parameters.PreOOBE | Should -BeTrue
            $steps.IndexOf($menu[0]) | Should -BeLessThan $steps.IndexOf(
                ($steps | Where-Object command -eq 'step-finalize-exportofflineosinfo')
            )
            $steps[0].command | Should -Be 'step-initialize-osdcloudworkflowtask'
            $steps[-1].command | Should -Be 'step-finalize-stoposdcloudworkflow'
        }
    }

    It 'does not enable PreOOBE in any other workflow' {
            $root = Join-Path $PSScriptRoot '..\..\..\workflow'
            $references = @(Get-ChildItem -LiteralPath $root -Filter '*.json' -Recurse -File |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '"command"\s*:\s*"step-update-preoobe"' })
            $references.Count | Should -Be 2
            foreach ($file in $references) { $file.FullName | Should -Match '\\recast-winui-dark\\tasks\\' }
    }
}
