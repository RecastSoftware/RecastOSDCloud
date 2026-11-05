BeforeAll {
    . (Join-Path $PSScriptRoot 'step-update-setupcomplete.ps1')
    . (Join-Path $PSScriptRoot 'step-update-preoobe.ps1')
    $script:moduleSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\core\modules\OSDCloudSetupComplete'))
}

Describe 'SetupComplete staging guard and failure handling' {
    BeforeEach {
        $script:originalDrive = $env:SystemDrive
        $script:originalDevice = $global:OSDCoreDevice
        $env:SystemDrive = 'X:'
        $global:OSDCoreDevice = @{ IsWinPE = $true }
        Mock Test-Path { $true }
        Mock New-Item {}
        Mock Save-OSDCloudSetupCompleteModule {}
        Mock Write-OSDCloudSetupCompleteScript {}
        Mock Write-Host {}
        Mock Write-Warning {}
    }

    AfterEach {
        $env:SystemDrive = $script:originalDrive
        $global:OSDCoreDevice = $script:originalDevice
    }

    It 'stages the module before installing the hook' {
        $script:order = @()
        Mock Save-OSDCloudSetupCompleteModule { $script:order += 'module' }
        Mock Write-OSDCloudSetupCompleteScript { $script:order += 'hook' }
        step-update-setupcomplete
        $script:order | Should -Be @('module','hook')
        Should -Invoke Save-OSDCloudSetupCompleteModule -Times 1 -ParameterFilter {
            $DestinationPath -eq 'C:\Windows\Setup\Modules\OSDCloudSetupComplete'
        }
        Should -Invoke Write-OSDCloudSetupCompleteScript -Times 1 -ParameterFilter {
            $Path -eq 'C:\Windows\Setup\Scripts\SetupComplete.cmd'
        }
    }

    It 'does not stage outside WinPE' {
        $env:SystemDrive = 'C:'
        step-update-setupcomplete
        Should -Invoke Save-OSDCloudSetupCompleteModule -Times 0
        Should -Invoke Write-OSDCloudSetupCompleteScript -Times 0
        Should -Invoke Write-Warning -Times 1
    }

    It 'does not install a hook when Windows or module validation is missing' {
        Mock Test-Path { $false }
        step-update-setupcomplete
        Should -Invoke Save-OSDCloudSetupCompleteModule -Times 0
        Mock Test-Path { $true }
        Mock Save-OSDCloudSetupCompleteModule { throw 'Copy failed fixture' }
        step-update-setupcomplete
        Should -Invoke Write-OSDCloudSetupCompleteScript -Times 0
        Should -Invoke Write-Host -Times 0
        Should -Invoke Write-Warning -Times 2
    }
}

Describe 'Standalone SetupComplete module copying' {
    It 'copies the full module without executing it and stamps the parent version' {
        $destination = Join-Path $TestDrive 'Staged\OSDCloudSetupComplete'
        Save-OSDCloudSetupCompleteModule -SourcePath $script:moduleSource -DestinationPath $destination
        $manifest = Test-ModuleManifest -Path (Join-Path $destination 'OSDCloudSetupComplete.psd1') -ErrorAction Stop
        $parent = Import-PowerShellDataFile (Join-Path $script:moduleSource '..\..\..\OSDCloud.psd1')
        $manifest.Version.ToString() | Should -Be $parent.ModuleVersion
        foreach ($file in Get-ChildItem -LiteralPath $script:moduleSource -Recurse -File) {
            $relative = $file.FullName.Substring($script:moduleSource.Length + 1)
            Test-Path -LiteralPath (Join-Path $destination $relative) | Should -BeTrue
        }
    }

    It 'rejects incomplete source before creating a destination' {
        $source = Join-Path $TestDrive 'MissingSource'
        [void][IO.Directory]::CreateDirectory($source)
        $destination = Join-Path $TestDrive 'MissingDestination'
        { Save-OSDCloudSetupCompleteModule -SourcePath $source -DestinationPath $destination } |
            Should -Throw '*component is missing*'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'rejects source syntax errors before copying anything' {
        $source = Join-Path $TestDrive 'BrokenSource'
        Copy-Item -LiteralPath $script:moduleSource -Destination $source -Recurse
        [IO.File]::WriteAllText((Join-Path $source 'private\OSDCloudSetupComplete.ps1'), 'function Broken {')
        $destination = Join-Path $TestDrive 'BrokenDestination'
        { Save-OSDCloudSetupCompleteModule -SourcePath $source -DestinationPath $destination } |
            Should -Throw '*parsing failed*'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }
}

Describe 'SetupComplete batch hook preservation and coexistence' {
    It 'preserves unmanaged bytes and installs one synchronous hook across repeated staging' {
        $path = Join-Path $TestDrive 'SetupComplete.cmd'
        $encoding = [Text.Encoding]::GetEncoding(28591)
        $original = "echo OEM driver commands`r`necho $([char]233)`r`n"
        [IO.File]::WriteAllBytes($path, $encoding.GetBytes($original))
        Write-OSDCloudSetupCompleteScript -Path $path
        $first = [IO.File]::ReadAllBytes($path)
        Write-OSDCloudSetupCompleteScript -Path $path
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -Be ([Convert]::ToBase64String($first))
        $text = $encoding.GetString($first)
        $text.StartsWith($original) | Should -BeTrue
        [regex]::Matches($text, '(?m)^:: RecastOSDCloud SetupComplete\r?$').Count | Should -Be 1
        $text | Should -Match '\-NoProfile \-NonInteractive'
        $text | Should -Match 'Setup\\Modules\\OSDCloudSetupComplete\\OSDCloudSetupComplete.psd1'
        $text | Should -Not -Match '(?im)^\s*start\s|Read-Host|Restart-Computer'
    }

    It 'rejects incomplete or misordered markers without altering bytes: <Body>' -TestCases @(
        @{ Body = ":: RecastOSDCloud SetupComplete`r`necho incomplete" }
        @{ Body = ":: End RecastOSDCloud SetupComplete`r`n" }
        @{ Body = ":: RecastOSDCloud SetupComplete`r`n:: RecastOSDCloud SetupComplete`r`n:: End RecastOSDCloud SetupComplete`r`n:: End RecastOSDCloud SetupComplete`r`n" }
    ) {
        param ($Body)
        $path = Join-Path $TestDrive 'Incomplete.cmd'
        [IO.File]::WriteAllText($path, $Body)
        { Write-OSDCloudSetupCompleteScript -Path $path } | Should -Throw '*Incomplete managed*'
        [IO.File]::ReadAllText($path) | Should -Be $Body
    }

    It 'preserves the new hook while PreOOBE removes only its legacy menu in either order' {
        foreach ($order in 'PreOOBEFirst','SetupCompleteFirst') {
            $path = Join-Path $TestDrive "$order.cmd"
            [IO.File]::WriteAllText($path, "echo original`r`n:: RecastOSDCloud SetupComplete Menu`r`necho legacy`r`n:: End RecastOSDCloud SetupComplete Menu`r`n")
            if ($order -eq 'PreOOBEFirst') {
                Write-OSDCloudSetupMenuScript -Path $path -Phase SetupComplete
                Write-OSDCloudSetupCompleteScript -Path $path
            }
            else {
                Write-OSDCloudSetupCompleteScript -Path $path
                Write-OSDCloudSetupMenuScript -Path $path -Phase SetupComplete
            }
            $text = [IO.File]::ReadAllText($path)
            $text | Should -Match '^echo original'
            $text | Should -Match 'exit \(Invoke-OSDCloudSetupComplete\)'
            $text | Should -Not -Match 'echo legacy'
        }
    }

    It 'warns about early exits without changing original control flow' {
        Mock Write-Warning {}
        $path = Join-Path $TestDrive 'EarlyExit.cmd'
        $body = "echo original`r`nexit /b 0`r`n"
        [IO.File]::WriteAllText($path, $body)
        Write-OSDCloudSetupCompleteScript -Path $path
        [IO.File]::ReadAllText($path).StartsWith($body) | Should -BeTrue
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*early exit*' }
    }

    It 'logs an invocation failure after preserving and running original commands' {
        $fakeWindows = Join-Path $TestDrive 'Windows With Spaces'
        [void][IO.Directory]::CreateDirectory($fakeWindows)
        $path = Join-Path $fakeWindows 'SetupComplete.cmd'
        [IO.File]::WriteAllText($path, "echo ORIGINAL_COMMAND`r`n")
        Write-OSDCloudSetupCompleteScript -Path $path
        $wrapper = Join-Path $TestDrive 'invoke.cmd'
        [IO.File]::WriteAllText($wrapper, "@echo off`r`nset `"SystemRoot=$fakeWindows`"`r`ncall `"$path`"`r`n")
        $output = (& $env:ComSpec /d /c "`"$wrapper`"" 2>&1 | Out-String)
        $output | Should -Match 'ORIGINAL_COMMAND'
        $output | Should -Match 'OSDCloudSetupComplete failed with exit code [1-9][0-9]*'
        $output.IndexOf('ORIGINAL_COMMAND') | Should -BeLessThan $output.IndexOf('OSDCloudSetupComplete failed')
        Get-Content -LiteralPath (Join-Path $fakeWindows 'Temp\osdcloud-logs\OSDCloudSetupComplete.log') -Raw |
            Should -Match 'SetupComplete invocation failed with exit code [1-9][0-9]*'
    }

    It 'executes the generated explicit import synchronously and propagates runtime status <Code>' -TestCases @(
        @{ Code = 0 }, @{ Code = 7 }
    ) {
        param ($Code)
        $fakeWindows = Join-Path $TestDrive "Windows Module $Code"
        $moduleRoot = Join-Path $fakeWindows 'Setup\Modules\OSDCloudSetupComplete'
        [void][IO.Directory]::CreateDirectory($moduleRoot)
        $runtime = @'
function Invoke-OSDCloudSetupComplete {
    [CmdletBinding()]
    param ()
    Start-Sleep -Milliseconds 100
    [IO.File]::WriteAllText((Join-Path $env:SystemRoot 'Completed.txt'), 'Completed')
    return RETURN_CODE
}
Export-ModuleMember -Function Invoke-OSDCloudSetupComplete
'@
        [IO.File]::WriteAllText((Join-Path $moduleRoot 'OSDCloudSetupComplete.psm1'), $runtime.Replace('RETURN_CODE', [string]$Code))
        [IO.File]::WriteAllText((Join-Path $moduleRoot 'OSDCloudSetupComplete.psd1'),
            "@{ RootModule = 'OSDCloudSetupComplete.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = 'Invoke-OSDCloudSetupComplete' }")
        $path = Join-Path $fakeWindows 'SetupComplete.cmd'
        Write-OSDCloudSetupCompleteScript -Path $path
        $prefix = '"%OSDCloudSetupCompletePowerShell%" '
        $line = [IO.File]::ReadAllLines($path) | Where-Object { $_.StartsWith($prefix) }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = (Get-Process -Id $PID).Path
        $start.Arguments = $line.Substring($prefix.Length).Replace('-Command "', '-Command "$env:SystemRoot = ' + "'$fakeWindows'; ")
        $start.UseShellExecute = $false
        $process = [Diagnostics.Process]::Start($start)
        try {
            $process.WaitForExit()
            $process.ExitCode | Should -Be $Code
            [IO.File]::ReadAllText((Join-Path $fakeWindows 'Completed.txt')) | Should -Be 'Completed'
        }
        finally { $process.Dispose() }
    }
}

Describe 'Dark workflow SetupComplete integration' {
    It 'enables exactly the two intended tasks after PreOOBE and before finalization' {
        $root = Join-Path $PSScriptRoot '..\..\..\workflow'
        $references = @(Get-ChildItem -LiteralPath $root -Filter '*.json' -Recurse -File |
            Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '"command"\s*:\s*"step-update-setupcomplete"' })
        $references.Count | Should -Be 2
        foreach ($file in $references) {
            $file.FullName | Should -Match '\\recast\\tasks\\'
            $task = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $steps = @($task.steps)
            $setup = @($steps | Where-Object command -eq 'step-update-setupcomplete')
            $setup.Count | Should -Be 1
            $setup[0].skip | Should -BeFalse
            $steps.IndexOf($setup[0]) | Should -BeGreaterThan $steps.IndexOf(($steps | Where-Object command -eq 'step-update-preoobe'))
            $steps.IndexOf($setup[0]) | Should -BeLessThan $steps.IndexOf(($steps | Where-Object command -eq 'step-finalize-exportofflineosinfo'))
            $task.amd64 | Should -BeTrue
            $task.arm64 | Should -BeTrue
        }
    }
}
