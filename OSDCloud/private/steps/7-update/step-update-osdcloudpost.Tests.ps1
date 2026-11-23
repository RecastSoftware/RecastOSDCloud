BeforeAll {
    . "$PSScriptRoot\step-update-osdcloudpost.ps1"
    $originalDevice = $global:OSDCoreDevice
    $originalDrive = $env:SystemDrive
}
AfterAll {
    $global:OSDCoreDevice = $originalDevice
    $env:SystemDrive = $originalDrive
}

Describe 'step-update-osdcloudpost' {
    BeforeEach {
        $env:SystemDrive = 'X:'
        $global:OSDCoreDevice = [pscustomobject]@{ IsWinPE = $true }
        Mock Test-Path { $true }
        Mock New-Item {}
        Mock Save-OSDCloudPostModule {}
        Mock Write-Host {}
        Mock Write-OSDCloudSetupMenuScript {}
        Mock Write-OSDCloudSetupCompleteScript {}
        Mock Write-OSDCloudPostSetting {}
        Mock Remove-Item {}
    }

    It 'stages the module, settings, OOBE hook and SetupComplete hook in order' {
        $script:order = @()
        Mock Save-OSDCloudPostModule { $script:order += 'module' }
        Mock Remove-Item { $script:order += "remove:$(Split-Path $LiteralPath -Leaf)" }
        Mock Write-OSDCloudPostSetting { $script:order += 'settings' }
        Mock Write-OSDCloudSetupMenuScript { $script:order += $Phase }
        Mock Write-OSDCloudSetupCompleteScript { $script:order += 'hook' }
        step-update-osdcloudpost
        ($script:order -join ',') |
            Should -Be 'module,remove:OSDCloudPreOOBE,remove:OSDCloudSetupComplete,settings,OOBE,SetupComplete,hook'
        Should -Invoke Save-OSDCloudPostModule -Times 1 -Exactly -ParameterFilter {
            $DestinationPath -eq 'C:\Windows\Setup\Modules\OSDCloudPost' -and
            $SourcePath -like '*\core\modules\OSDCloudPost'
        }
        Should -Invoke Write-OSDCloudPostSetting -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\Windows\Setup\Scripts\OSDCloudPost.json'
        }
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\Windows\Setup\Scripts\OOBE.cmd' -and $Phase -eq 'OOBE'
        }
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\Windows\Setup\Scripts\SetupComplete.cmd' -and $Phase -eq 'SetupComplete'
        }
        Should -Invoke Write-OSDCloudSetupCompleteScript -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\Windows\Setup\Scripts\SetupComplete.cmd'
        }
    }

    It 'does not stage files outside WinPE even if device metadata is stale' {
        $env:SystemDrive = 'C:'
        step-update-osdcloudpost -WarningAction SilentlyContinue
        Should -Invoke Save-OSDCloudPostModule -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }

    It 'reports missing assets without writing to the Windows image' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*\core\modules\OSDCloudPost' }
        Mock Write-Warning {}
        step-update-osdcloudpost
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*source is missing*' }
        Should -Invoke Save-OSDCloudPostModule -Times 0 -Exactly
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
    }

    It 'reports a missing applied Windows image before writing' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq 'C:\Windows\System32\Config\SYSTEM' }
        Mock Write-Warning {}
        step-update-osdcloudpost
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*applied Windows image is missing*' }
        Should -Invoke Save-OSDCloudPostModule -Times 0 -Exactly
    }

    It 'reports copy errors without writing a success-shaped invocation' {
        Mock Save-OSDCloudPostModule { throw 'Disk write failed' }
        Mock Write-Warning {}
        step-update-osdcloudpost
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*Disk write failed*' }
        Should -Invoke Write-OSDCloudSetupMenuScript -Times 0 -Exactly
        Should -Invoke Write-OSDCloudSetupCompleteScript -Times 0 -Exactly
        Should -Invoke Write-OSDCloudPostSetting -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
    }
}

Describe 'OSDCloud Post settings file' {
    BeforeEach {
        $script:originalDeploy = $global:OSDCloudDeploy
        $path = Join-Path $TestDrive 'OSDCloudPost.json'
    }
    AfterEach { $global:OSDCloudDeploy = $script:originalDeploy }

    It 'writes the deployment selections <OS>/<Drivers>' -TestCases @(
        @{ OS = $false; Drivers = $true }
        @{ OS = $true; Drivers = $false }
    ) {
        param ($OS, $Drivers)
        $global:OSDCloudDeploy = [pscustomobject]@{ PreOOBEWindowsUpdateOS = $OS; PreOOBEWindowsUpdateDrivers = $Drivers }
        Write-OSDCloudPostSetting -Path $path
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $json.Version | Should -Be 1
        $json.PreOOBE.WindowsUpdateOS | Should -Be $OS
        $json.PreOOBE.WindowsUpdateDrivers | Should -Be $Drivers
    }

    It 'defaults both tasks to checked without deployment selections' {
        $global:OSDCloudDeploy = $null
        Write-OSDCloudPostSetting -Path $path
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $json.PreOOBE.WindowsUpdateOS | Should -BeTrue
        $json.PreOOBE.WindowsUpdateDrivers | Should -BeTrue
    }

    It 'round-trips through the runtime settings reader' {
        $global:OSDCloudDeploy = [pscustomobject]@{ PreOOBEWindowsUpdateOS = $false; PreOOBEWindowsUpdateDrivers = $false }
        Write-OSDCloudPostSetting -Path $path
        $module = Join-Path $PSScriptRoot '..\..\..\core\modules\OSDCloudPost\OSDCloudPost.psd1'
        $output = & powershell.exe -NoLogo -NoProfile -Command "`$m = Import-Module -Name '$module' -PassThru -ErrorAction Stop; & `$m { function Write-OOBEMenuLog {}; `$s = Get-OSDCloudPostSetting -Path '$path'; '{0},{1}' -f `$s.WindowsUpdateOS, `$s.WindowsUpdateDrivers }"
        $output | Should -Contain 'False,False'
    }
}

Describe 'PreOOBE module staging' {
    BeforeEach {
        $package = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $source = Join-Path $package 'core\modules\OSDCloudPost'
        New-Item -Path (Split-Path $source) -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\..\..\core\modules\OSDCloudPost') -Destination $source -Recurse
        [IO.File]::WriteAllText((Join-Path $package 'OSDCloud.psd1'), "@{ ModuleVersion = '26.11.3.7' }")
        $destination = Join-Path $package 'Windows Setup\Modules\OSDCloudPost'
    }

    It 'copies every file, stamps only the destination version and imports without the parent module' {
        $manifest = Join-Path $source 'OSDCloudPost.psd1'
        $original = [IO.File]::ReadAllText($manifest)
        Save-OSDCloudPostModule -SourcePath $source -DestinationPath $destination
        foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
            $relative = $file.FullName.Substring($source.Length + 1)
            $copy = Join-Path $destination $relative
            Test-Path -LiteralPath $copy -PathType Leaf | Should -BeTrue
            if ($relative -ne 'OSDCloudPost.psd1') {
                (Get-FileHash -LiteralPath $copy).Hash | Should -Be (Get-FileHash -LiteralPath $file.FullName).Hash
            }
        }
        [IO.File]::ReadAllText($manifest) | Should -Be $original
        $stagedManifest = Join-Path $destination 'OSDCloudPost.psd1'
        (Test-ModuleManifest -Path $stagedManifest).Version | Should -Be ([version]'26.11.3.7')
        $output = & powershell.exe -NoLogo -NoProfile -STA -Command "Import-Module -Name '$stagedManifest' -ErrorAction Stop;         (Get-Command OSDCloudPreOOBE).Definition; (Get-Command Invoke-OSDCloudSetupComplete).Name; (Get-Module OSDCloudPost).Version.ToString()"
        $LASTEXITCODE | Should -Be 0
        $output | Should -Contain 'Invoke-OSDCloudPreOOBE'
                $output | Should -Contain 'Invoke-OSDCloudSetupComplete'
        $output | Should -Contain '26.11.3.7'
    }

    It 'restages without nesting the module directory or changing file content' {
        Save-OSDCloudPostModule -SourcePath $source -DestinationPath $destination
        $first = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Get-FileHash | ForEach-Object Hash)
        Save-OSDCloudPostModule -SourcePath $source -DestinationPath $destination
        $second = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Get-FileHash | ForEach-Object Hash)
        ($second -join ',') | Should -Be ($first -join ',')
        Test-Path -LiteralPath (Join-Path $destination 'OSDCloudPost') | Should -BeFalse
    }

    It 'rejects a missing component before copying' {
        Remove-Item -LiteralPath (Join-Path $source 'private\Show-OSDCloudPreOOBEWindow.ps1')
        { Save-OSDCloudPostModule -SourcePath $source -DestinationPath $destination } |
            Should -Throw '*component is missing*'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'rejects invalid PowerShell before copying' {
        [IO.File]::WriteAllText((Join-Path $source 'public\Invoke-OSDCloudPreOOBE.ps1'), 'function Broken {')
        { Save-OSDCloudPostModule -SourcePath $source -DestinationPath $destination } |
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
            $text | Should -Match 'Setup\\Modules\\OSDCloudPost\\OSDCloudPost.psd1'
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
        $moduleRoot = Join-Path $fakeWindows 'Setup\Modules\OSDCloudPost'
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
        [IO.File]::WriteAllText((Join-Path $moduleRoot 'OSDCloudPost.psm1'), $runtime.Replace('RETURN_CODE', [string]$Code))
        [IO.File]::WriteAllText((Join-Path $moduleRoot 'OSDCloudPost.psd1'),
            "@{ RootModule = 'OSDCloudPost.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = 'Invoke-OSDCloudPreOOBE'; AliasesToExport = 'OSDCloudPreOOBE' }")
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
            $errorText | Should -Match 'OSDCloudPost.psd1'
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
        $text | Should -Match 'Setup\\Modules\\OSDCloudPost\\OSDCloudPost.psd1'
        $text | Should -Not -Match '(?im)^\s*start\s|Read-Host|Restart-Computer'
    }

    It 'replaces a hook staged by the former OSDCloudSetupComplete module' {
        $path = Join-Path $TestDrive 'LegacySetupComplete.cmd'
        [IO.File]::WriteAllText($path, "echo original`r`n:: RecastOSDCloud SetupComplete`r`necho Setup\Modules\OSDCloudSetupComplete\OSDCloudSetupComplete.psd1`r`n:: End RecastOSDCloud SetupComplete`r`n")
        Write-OSDCloudSetupCompleteScript -Path $path
        $text = [IO.File]::ReadAllText($path)
        $text | Should -Match '^echo original'
        $text | Should -Not -Match 'OSDCloudSetupComplete\.psd1'
        [regex]::Matches($text, '(?m)^:: RecastOSDCloud SetupComplete\r?$').Count | Should -Be 1
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

    It 'keeps the hook while removing only the legacy SetupComplete menu' {
        $path = Join-Path $TestDrive 'Coexist.cmd'
        [IO.File]::WriteAllText($path, "echo original`r`n:: RecastOSDCloud SetupComplete Menu`r`necho legacy`r`n:: End RecastOSDCloud SetupComplete Menu`r`n")
        Write-OSDCloudSetupMenuScript -Path $path -Phase SetupComplete
        Write-OSDCloudSetupCompleteScript -Path $path
        Write-OSDCloudSetupMenuScript -Path $path -Phase SetupComplete
        $text = [IO.File]::ReadAllText($path)
        $text | Should -Match '^echo original'
        $text | Should -Match 'exit \(Invoke-OSDCloudSetupComplete\)'
        $text | Should -Not -Match 'echo legacy'
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
        $fakeWindows = Join-Path $TestDrive 'SetupComplete Windows'
        [void][IO.Directory]::CreateDirectory($fakeWindows)
        $path = Join-Path $fakeWindows 'SetupComplete.cmd'
        [IO.File]::WriteAllText($path, "echo ORIGINAL_COMMAND`r`n")
        Write-OSDCloudSetupCompleteScript -Path $path
        $wrapper = Join-Path $TestDrive 'invoke-setupcomplete.cmd'
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
        $fakeWindows = Join-Path $TestDrive "SetupComplete Module $Code"
        $moduleRoot = Join-Path $fakeWindows 'Setup\Modules\OSDCloudPost'
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
        [IO.File]::WriteAllText((Join-Path $moduleRoot 'OSDCloudPost.psm1'), $runtime.Replace('RETURN_CODE', [string]$Code))
        [IO.File]::WriteAllText((Join-Path $moduleRoot 'OSDCloudPost.psd1'),
            "@{ RootModule = 'OSDCloudPost.psm1'; ModuleVersion = '1.0.0'; FunctionsToExport = 'Invoke-OSDCloudSetupComplete' }")
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

Describe 'Dark workflow setup menu integration' {
    It 'enables the staging step exactly once before finalization in both tasks' {
        $taskRoot = Join-Path $PSScriptRoot '..\..\..\workflow\recast\tasks'
        foreach ($name in 'osdcloud.json', 'osdcloud-nofirmware.json') {
            $task = Get-Content -LiteralPath (Join-Path $taskRoot $name) -Raw | ConvertFrom-Json
            $task.amd64 | Should -BeTrue
            $task.arm64 | Should -BeTrue
            $steps = @($task.steps)
            $menu = @($steps | Where-Object command -eq 'step-update-osdcloudpost')
            $menu.Count | Should -Be 1
            $menu[0].skip | Should -BeFalse
            ($steps | Where-Object command -eq 'step-Save-WindowsDriver-DriverPack').parameters.PreOOBE | Should -BeTrue
            $steps.IndexOf($menu[0]) | Should -BeLessThan $steps.IndexOf(
                ($steps | Where-Object command -eq 'step-finalize-exportofflineosinfo')
            )
            $steps[0].command | Should -Be 'step-initialize-osdcloudworkflowtask'
            $steps[-1].command | Should -Be 'step-finalize-stoposdcloudworkflow'
            @($steps | Where-Object command -in 'step-update-preoobe', 'step-update-setupcomplete').Count | Should -Be 0
        }
    }

    It 'does not enable OSDCloudPost in any other workflow' {
            $root = Join-Path $PSScriptRoot '..\..\..\workflow'
            $references = @(Get-ChildItem -LiteralPath $root -Filter '*.json' -Recurse -File |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '"command"\s*:\s*"step-update-osdcloudpost"' })
            $references.Count | Should -Be 2
            foreach ($file in $references) { $file.FullName | Should -Match '\\recast\\tasks\\' }
    }
}
