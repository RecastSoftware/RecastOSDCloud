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
        Mock Save-OSDCloudPreOOBEModule {}
        Mock Write-Host {}
        Mock Write-OSDCloudSetupMenuScript {}
    }

    It 'stages the complete module, appends OOBE and cleans up legacy SetupComplete' {
        step-update-preoobe
        Should -Invoke Save-OSDCloudPreOOBEModule -Times 1 -Exactly -ParameterFilter {
            $DestinationPath -eq 'C:\Windows\Setup\Modules\OSDCloudPreOOBE' -and
            $SourcePath -like '*\modules\OSDCloudPreOOBE'
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
        Should -Invoke Save-OSDCloudPreOOBEModule -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }

    It 'reports missing assets without writing to the Windows image' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*\modules\OSDCloudPreOOBE' }
        Mock Write-Warning {}
        step-update-preoobe
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*source is missing*' }
        Should -Invoke Save-OSDCloudPreOOBEModule -Times 0 -Exactly
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }

    It 'reports a missing applied Windows image before writing' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'C:\Windows\System32\Config\SYSTEM' }
        Mock Write-Warning {}
        step-update-preoobe
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*applied Windows image is missing*' }
        Should -Invoke Save-OSDCloudPreOOBEModule -Times 0 -Exactly
    }

    It 'reports copy errors without writing a success-shaped invocation' {
        Mock Save-OSDCloudPreOOBEModule { throw 'Disk write failed' }
        Mock Write-Warning {}
        step-update-preoobe
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*Disk write failed*' }
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }
}

Describe 'PreOOBE module staging' {
    BeforeEach {
        $package = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $source = Join-Path $package 'modules\OSDCloudPreOOBE'
        New-Item -Path (Split-Path $source) -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\..\..\modules\OSDCloudPreOOBE') -Destination $source -Recurse
        [IO.File]::WriteAllText((Join-Path $package 'OSDCloud.psd1'), "@{ ModuleVersion = '26.11.3.7' }")
        $destination = Join-Path $package 'Windows Setup\Modules\OSDCloudPreOOBE'
    }

    It 'copies every file, stamps only the destination version and imports without the parent module' {
        $manifest = Join-Path $source 'OSDCloudPreOOBE.psd1'
        $original = [IO.File]::ReadAllText($manifest)
        Save-OSDCloudPreOOBEModule -SourcePath $source -DestinationPath $destination
        foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
            $relative = $file.FullName.Substring($source.Length + 1)
            $copy = Join-Path $destination $relative
            Test-Path -LiteralPath $copy -PathType Leaf | Should -BeTrue
            if ($relative -ne 'OSDCloudPreOOBE.psd1') {
                (Get-FileHash -LiteralPath $copy).Hash | Should -Be (Get-FileHash -LiteralPath $file.FullName).Hash
            }
        }
        [IO.File]::ReadAllText($manifest) | Should -Be $original
        $stagedManifest = Join-Path $destination 'OSDCloudPreOOBE.psd1'
        (Test-ModuleManifest -Path $stagedManifest).Version | Should -Be ([version]'26.11.3.7')
        $output = & powershell.exe -NoLogo -NoProfile -STA -Command "Import-Module -Name '$stagedManifest' -ErrorAction Stop; (Get-Command OSDCloudPreOOBE).Definition; (Get-Module OSDCloudPreOOBE).Version.ToString()"
        $LASTEXITCODE | Should -Be 0
        $output | Should -Contain 'Invoke-OSDCloudPreOOBE'
        $output | Should -Contain '26.11.3.7'
    }

    It 'restages without nesting the module directory or changing file content' {
        Save-OSDCloudPreOOBEModule -SourcePath $source -DestinationPath $destination
        $first = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Get-FileHash | ForEach-Object Hash)
        Save-OSDCloudPreOOBEModule -SourcePath $source -DestinationPath $destination
        $second = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Get-FileHash | ForEach-Object Hash)
        ($second -join ',') | Should -Be ($first -join ',')
        Test-Path -LiteralPath (Join-Path $destination 'OSDCloudPreOOBE') | Should -BeFalse
    }

    It 'rejects a missing component before copying' {
        Remove-Item -LiteralPath (Join-Path $source 'private\Show-OSDCloudPreOOBEWindow.ps1')
        { Save-OSDCloudPreOOBEModule -SourcePath $source -DestinationPath $destination } |
            Should -Throw '*component is missing*'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'rejects invalid PowerShell before copying' {
        [IO.File]::WriteAllText((Join-Path $source 'public\Invoke-OSDCloudPreOOBE.ps1'), 'function Broken {')
        { Save-OSDCloudPreOOBEModule -SourcePath $source -DestinationPath $destination } |
            Should -Throw '*parsing failed*'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }
}

Describe 'Setup menu batch invocation' {
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
            $text | Should -Match 'Setup\\Modules\\OSDCloudPreOOBE\\OSDCloudPreOOBE.psd1'
            $text | Should -Match 'Import-Module.*-ErrorAction Stop; exit \(OSDCloudPreOOBE\)'
            $text | Should -Not -Match '-File'
            $text | Should -Not -Match '-Phase'
            $text | Should -Match 'Sysnative\\WindowsPowerShell'
            $text | Should -Match '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass'
            $text | Should -Match 'OSDCloudOOBEExitCode=%ERRORLEVEL%'
            $original = [byte[]]($body + $tail)
            [Convert]::ToBase64String($result[0..($original.Length - 1)]) |
                Should -Be ([Convert]::ToBase64String($original))
            $text.IndexOf('-Command') | Should -BeGreaterThan $text.IndexOf('echo existing')
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

    It 'executes the generated import command synchronously and propagates runtime status <Code>' -TestCases @(
        @{ Code = 0 }, @{ Code = 7 }
    ) {
        param($Code)
        $fakeWindows = Join-Path $TestDrive "Windows Module $Code"
        $moduleRoot = Join-Path $fakeWindows 'Setup\Modules\OSDCloudPreOOBE'
        New-Item -Path $moduleRoot -ItemType Directory -Force | Out-Null
        $marker = Join-Path $fakeWindows 'Completed.txt'
        $runtime = @'
function Invoke-OSDCloudPreOOBE {
    [CmdletBinding()]
    param ()
    Start-Sleep -Milliseconds 100
    [IO.File]::WriteAllText((Join-Path $env:SystemRoot 'Completed.txt'), 'Completed')
    return RETURN_CODE
}
Set-Alias OSDCloudPreOOBE Invoke-OSDCloudPreOOBE
Export-ModuleMember -Function Invoke-OSDCloudPreOOBE -Alias OSDCloudPreOOBE
'@
        [IO.File]::WriteAllText((Join-Path $moduleRoot 'OSDCloudPreOOBE.psm1'), $runtime.Replace('RETURN_CODE', [string]$Code))
        [IO.File]::WriteAllText((Join-Path $moduleRoot 'OSDCloudPreOOBE.psd1'),
            "@{ RootModule = 'OSDCloudPreOOBE.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = 'Invoke-OSDCloudPreOOBE'; AliasesToExport = 'OSDCloudPreOOBE' }")
        $path = Join-Path $fakeWindows 'OOBE.cmd'
        Write-OSDCloudSetupMenuScript -Path $path -Phase OOBE
        $line = [IO.File]::ReadAllLines($path) | Where-Object { $_.StartsWith('"%OSDCloudOOBEPowerShell%" ') }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = (Get-Process -Id $PID).Path
        $start.Arguments = $line.Substring('"%OSDCloudOOBEPowerShell%" '.Length)
        $start.Arguments = $start.Arguments.Replace('-Command "', '-Command "$env:SystemRoot = ' + "'$fakeWindows'; ")
        $start.UseShellExecute = $false
        $process = [Diagnostics.Process]::Start($start)
        try {
            $process.WaitForExit()
            $process.ExitCode | Should -Be $Code
            [IO.File]::ReadAllText($marker) | Should -Be 'Completed'
        }
        finally { $process.Dispose() }
    }

    It 'fails explicitly when the generated import command cannot find its module' {
        $path = Join-Path $TestDrive 'MissingModuleOOBE.cmd'
        Write-OSDCloudSetupMenuScript -Path $path -Phase OOBE
        $line = [IO.File]::ReadAllLines($path) | Where-Object { $_.StartsWith('"%OSDCloudOOBEPowerShell%" ') }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = (Get-Process -Id $PID).Path
        $start.Arguments = $line.Substring('"%OSDCloudOOBEPowerShell%" '.Length)
        $fakeWindows = Join-Path $TestDrive 'No Windows Module'
        $start.Arguments = $start.Arguments.Replace('-Command "', '-Command "$env:SystemRoot = ' + "'$fakeWindows'; ")
        $start.UseShellExecute = $false
        $start.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($start)
        try {
            $errorText = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            $process.ExitCode | Should -Be 1
            $errorText | Should -Match 'OSDCloudPreOOBE.psd1'
        }
        finally { $process.Dispose() }
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
