BeforeAll {
    . "$PSScriptRoot\Initialize-WinpeStartupEnvironment.ps1"
    . "$PSScriptRoot\..\..\public\WinPE\Invoke-WinpeStartup.ps1"
    . "$PSScriptRoot\..\Get-WinpeStartupProfileCandidates.ps1"
    . "$PSScriptRoot\Initialize-WinpeStartupDrivers.ps1"
    . "$PSScriptRoot\Initialize-WinpeStartupFiles.ps1"
    . "$PSScriptRoot\Initialize-WinpeStartupMain.ps1"

    function New-CoreEnvironmentFixture {
        param (
            [string]$RelativePath,
            [string[]]$Lines
        )

        $path = Join-Path -Path $fixtureRoot -ChildPath "WinpeStartup\core\$RelativePath"
        [System.IO.Directory]::CreateDirectory((Split-Path -Path $path -Parent)) | Out-Null
        Set-Content -LiteralPath $path -Value $Lines -Encoding UTF8
        return $path
    }
}

Describe 'Initialize-WinpeStartupEnvironment Core environment files' {
    BeforeEach {
        $savedEnvironment = [System.Environment]::GetEnvironmentVariables('Process')
        $env:SystemDrive = 'X:'
        $fixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
        $fixtureCorePath = Join-Path -Path $fixtureRoot -ChildPath 'WinpeStartup\core'

        Mock Join-Path {
            if ($Path -eq 'X:' -and $ChildPath -eq 'WinpeStartup\core') {
                return $fixtureCorePath
            }
            return "$($Path.TrimEnd('\'))\$ChildPath"
        } -ParameterFilter { $Path -like 'X:*' }
        Mock New-Item {}
        Mock Set-ItemProperty {}
        Mock Write-Host {}
    }

    AfterEach {
        $currentEnvironment = [System.Environment]::GetEnvironmentVariables('Process')
        foreach ($name in @($currentEnvironment.Keys)) {
            if (-not $savedEnvironment.Contains($name)) {
                [System.Environment]::SetEnvironmentVariable($name, $null, 'Process')
            }
        }
        foreach ($name in $savedEnvironment.Keys) {
            [System.Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
        }
    }

    It 'loads hidden .env and application.env from a hidden immediate Core folder' {
        $path = New-CoreEnvironmentFixture -RelativePath 'main\.env' -Lines @(
            '# DATABASE SETTINGS'
            'WSCORE_TEST_DB_HOST=localhost'
            'WSCORE_TEST_DB_PORT=5432'
            'WSCORE_TEST_FEATURE=true'
            'WSCORE_TEST_QUOTED="synthetic value"'
            "WSCORE_TEST_SINGLE='synthetic string'"
        )
        $applicationPath = New-CoreEnvironmentFixture -RelativePath 'main\application.env' -Lines @(
            '# APPLICATION CONFIGURATION'
            'WSCORE_TEST_NODE_ENV=development'
            'WSCORE_TEST_PORT=3000'
            'WSCORE_TEST_DEBUG=true'
        )
        [System.IO.File]::SetAttributes($path, [System.IO.FileAttributes]::Hidden)
        [System.IO.File]::SetAttributes((Split-Path $applicationPath -Parent), [System.IO.FileAttributes]::Hidden)

        $output = @(Initialize-WinpeStartupEnvironment)

        $output.Count | Should -Be 0
        $env:WSCORE_TEST_DB_HOST | Should -Be 'localhost'
        $env:WSCORE_TEST_DB_PORT | Should -Be '5432'
        $env:WSCORE_TEST_FEATURE | Should -Be 'true'
        $env:WSCORE_TEST_QUOTED | Should -Be 'synthetic value'
        $env:WSCORE_TEST_SINGLE | Should -Be 'synthetic string'
        $env:WSCORE_TEST_NODE_ENV | Should -Be 'development'
        $env:WSCORE_TEST_PORT | Should -Be '3000'
        $env:WSCORE_TEST_DEBUG | Should -Be 'true'
    }

    It 'sorts full paths across folders and lets the last file and line win' {
        New-CoreEnvironmentFixture 'z-last\.env' @('WSCORE_TEST_ORDER=last folder') | Out-Null
        New-CoreEnvironmentFixture 'a-first\z.env' @('WSCORE_TEST_ORDER=later file') | Out-Null
        New-CoreEnvironmentFixture 'a-first\.env' @('WSCORE_TEST_ORDER=first file') | Out-Null
        New-CoreEnvironmentFixture 'z-last\application.env' @(
            'WSCORE_TEST_ORDER=first line'
            'WSCORE_TEST_ORDER=last line'
        ) | Out-Null
        Mock Get-ChildItem {
            @(
                [pscustomobject]@{ FullName = (Join-Path $fixtureCorePath 'z-last') }
                [pscustomobject]@{ FullName = (Join-Path $fixtureCorePath 'a-first') }
            )
        } -ParameterFilter { $LiteralPath -eq $fixtureCorePath -and $Directory }

        Initialize-WinpeStartupEnvironment

        $env:WSCORE_TEST_ORDER | Should -Be 'last line'
    }

    It 'ignores root-level, nested, non-env and profile-folder files' {
        New-CoreEnvironmentFixture '.env' @('WSCORE_TEST_ROOT=unexpected') | Out-Null
        New-CoreEnvironmentFixture 'main\nested\deeper.env' @('WSCORE_TEST_NESTED=unexpected') | Out-Null
        New-CoreEnvironmentFixture 'main\settings.txt' @('WSCORE_TEST_TEXT=unexpected') | Out-Null
        New-CoreEnvironmentFixture 'main\.env' @('WSCORE_TEST_INCLUDED=yes') | Out-Null
        $profilesPath = Join-Path $fixtureRoot 'WinpeStartup\profiles'
        [System.IO.Directory]::CreateDirectory($profilesPath) | Out-Null
        Set-Content -LiteralPath (Join-Path $profilesPath '.env') -Value 'WSCORE_TEST_PROFILE_FILE=unexpected'

        Initialize-WinpeStartupEnvironment

        $env:WSCORE_TEST_INCLUDED | Should -Be 'yes'
        $env:WSCORE_TEST_ROOT | Should -BeNullOrEmpty
        $env:WSCORE_TEST_NESTED | Should -BeNullOrEmpty
        $env:WSCORE_TEST_TEXT | Should -BeNullOrEmpty
        $env:WSCORE_TEST_PROFILE_FILE | Should -BeNullOrEmpty
    }

    It 'parses whitespace, quotes and embedded equals without evaluating content' {
        New-CoreEnvironmentFixture 'main\literal.env' @(
            ''
            '   # ignored comment'
            '  WSCORE_TEST_SPACES =  value  '
            'WSCORE_TEST_EQUALS=a=b=c'
            'WSCORE_TEST_INNER="  inner space  "'
            'WSCORE_TEST_HASH=value # literal'
            'WSCORE_TEST_LITERAL=$env:SystemDrive'
            'WSCORE_TEST_COMMAND=$(throw "must not execute")'
            'WSCORE_TEST_ESCAPE="line\ntext"'
        ) | Out-Null

        Initialize-WinpeStartupEnvironment

        $env:WSCORE_TEST_SPACES | Should -Be 'value'
        $env:WSCORE_TEST_EQUALS | Should -Be 'a=b=c'
        $env:WSCORE_TEST_INNER | Should -Be '  inner space  '
        $env:WSCORE_TEST_HASH | Should -Be 'value # literal'
        $env:WSCORE_TEST_LITERAL | Should -Be '$env:SystemDrive'
        $env:WSCORE_TEST_COMMAND | Should -Be '$(throw "must not execute")'
        $env:WSCORE_TEST_ESCAPE | Should -Be 'line\ntext'
    }

    It 'applies empty assignments using current runtime semantics' {
        $env:WSCORE_TEST_EMPTY = 'previous'
        $env:WSCORE_TEST_EMPTY_QUOTED = 'previous'
        New-CoreEnvironmentFixture 'main\.env' @(
            'WSCORE_TEST_EMPTY='
            'WSCORE_TEST_EMPTY_QUOTED=""'
        ) | Out-Null

        Initialize-WinpeStartupEnvironment

        $env:WSCORE_TEST_EMPTY | Should -BeNullOrEmpty
        $env:WSCORE_TEST_EMPTY_QUOTED | Should -BeNullOrEmpty
    }

    It 'changes only process scope and passes imported values to child PowerShell' {
        $machineValue = [System.Environment]::GetEnvironmentVariable('WSCORE_TEST_CHILD', 'Machine')
        $userValue = [System.Environment]::GetEnvironmentVariable('WSCORE_TEST_CHILD', 'User')
        New-CoreEnvironmentFixture 'main\.env' @('WSCORE_TEST_CHILD=child-inherited-value') | Out-Null

        Initialize-WinpeStartupEnvironment
        $executable = (Get-Process -Id $PID).Path
        $childValue = & $executable -NoLogo -NoProfile -Command '$env:WSCORE_TEST_CHILD'

        $LASTEXITCODE | Should -Be 0
        $childValue | Should -Be 'child-inherited-value'
        [System.Environment]::GetEnvironmentVariable('WSCORE_TEST_CHILD', 'Machine') | Should -Be $machineValue
        [System.Environment]::GetEnvironmentVariable('WSCORE_TEST_CHILD', 'User') | Should -Be $userValue
    }

    It 'warns with source and line numbers for invalid entries and continues without leaking content' {
        $path = New-CoreEnvironmentFixture 'main\.env' @(
            'sensitive-synthetic-no-equals'
            '=sensitive-synthetic-value'
            'export WSCORE_TEST_EXPORT=sensitive-synthetic-value'
            'WSCORE_TEST_BAD="sensitive-synthetic-value'
            "WSCORE_TEST_NUL=sensitive$([char]0)synthetic"
            'WSCORE_TEST_AFTER_INVALID=valid'
        )
        $warnings = @()

        Initialize-WinpeStartupEnvironment -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -Be 5
        for ($index = 0; $index -lt $warnings.Count; $index++) {
            $warnings[$index].ToString() | Should -Match ([regex]::Escape($path))
            $warnings[$index].ToString() | Should -Match "line $($index + 1)"
        }
        ($warnings | Out-String) | Should -Not -Match 'sensitive|synthetic'
        $env:WSCORE_TEST_EXPORT | Should -BeNullOrEmpty
        $env:WSCORE_TEST_BAD | Should -BeNullOrEmpty
        $env:WSCORE_TEST_NUL | Should -BeNullOrEmpty
        $env:WSCORE_TEST_AFTER_INVALID | Should -Be 'valid'
    }

    It 'does not log imported values on the verbose stream' {
        New-CoreEnvironmentFixture 'main\.env' @('WSCORE_TEST_VERBOSE=sensitive-synthetic-value') | Out-Null

        $messages = Initialize-WinpeStartupEnvironment -Verbose 4>&1

        ($messages | Out-String) | Should -Match 'Loaded environment entry'
        ($messages | Out-String) | Should -Not -Match 'sensitive-synthetic-value'
    }

    It 'warns on read failure and continues with other files' {
        $failedPath = New-CoreEnvironmentFixture 'main\.env' @('WSCORE_TEST_UNREADABLE=unexpected')
        New-CoreEnvironmentFixture 'main\application.env' @('WSCORE_TEST_AFTER_READ_FAILURE=yes') | Out-Null
        Mock Get-Content { throw 'sensitive-synthetic-exception' } -ParameterFilter { $LiteralPath -eq $failedPath }
        $warnings = @()

        Initialize-WinpeStartupEnvironment -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -Be 1
        $warnings[0].ToString() | Should -Match 'Failed to read'
        ($warnings | Out-String) | Should -Not -Match 'sensitive-synthetic-exception'
        $env:WSCORE_TEST_AFTER_READ_FAILURE | Should -Be 'yes'
    }

    It 'warns on folder discovery failure and continues with other folders' {
        New-CoreEnvironmentFixture 'broken\.env' @('WSCORE_TEST_UNDISCOVERED=unexpected') | Out-Null
        New-CoreEnvironmentFixture 'main\.env' @('WSCORE_TEST_AFTER_DISCOVERY_FAILURE=yes') | Out-Null
        $brokenPath = Join-Path $fixtureCorePath 'broken'
        Mock Get-ChildItem { throw 'sensitive-synthetic-exception' } -ParameterFilter { $LiteralPath -eq $brokenPath }
        $warnings = @()

        Initialize-WinpeStartupEnvironment -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -Be 1
        $warnings[0].ToString() | Should -Match 'Failed to discover environment files'
        ($warnings | Out-String) | Should -Not -Match 'sensitive-synthetic-exception'
        $env:WSCORE_TEST_AFTER_DISCOVERY_FAILURE | Should -Be 'yes'
    }

    It 'warns on Core discovery failure but retains shell initialization' {
        Mock Test-Path { throw 'sensitive-synthetic-exception' } -ParameterFilter { $LiteralPath -eq $fixtureCorePath }
        $warnings = @()

        Initialize-WinpeStartupEnvironment -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -Be 1
        $warnings[0].ToString() | Should -Match 'Failed to discover Core folders'
        ($warnings | Out-String) | Should -Not -Match 'sensitive-synthetic-exception'
        $env:USERPROFILE | Should -Be 'X:\windows\system32\config\systemprofile'
        Should -Invoke Set-ItemProperty -Times 2 -Exactly
    }

    It 'warns on PS 5.1 oversized-name assignment failure and continues' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') {
        $oversizedName = 'N' * 32768
        New-CoreEnvironmentFixture 'main\.env' @(
            "$oversizedName=sensitive-synthetic-value"
            'WSCORE_TEST_AFTER_SET_FAILURE=yes'
        ) | Out-Null
        $warnings = @()

        Initialize-WinpeStartupEnvironment -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -Be 1
        $warnings[0].ToString() | Should -Match 'Failed to set environment entry.*line 1'
        ($warnings | Out-String) | Should -Not -Match 'sensitive-synthetic-value'
        $env:WSCORE_TEST_AFTER_SET_FAILURE | Should -Be 'yes'
    }

    It 'allows missing Core content without warnings and preserves existing setup' {
        $warnings = @()

        Initialize-WinpeStartupEnvironment -WarningVariable warnings

        $warnings.Count | Should -Be 0
        $env:APPDATA | Should -Be 'X:\windows\system32\config\systemprofile\AppData\Roaming'
        $env:LOCALAPPDATA | Should -Be 'X:\windows\system32\config\systemprofile\AppData\Local'
        $env:HOMEDRIVE | Should -Be 'X:'
        $env:HOMEPATH | Should -Be '\windows\system32\config\systemprofile'
        Should -Invoke New-Item -Times 6 -Exactly
        Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'USERDATA' -and $Value -eq 'X:\Windows\System32\Config\SystemProfile'
        }
        Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'ExecutionPolicy' -and $Value -eq 'Bypass'
        }
    }

    It 'allows empty Core folders without warnings' {
        [System.IO.Directory]::CreateDirectory((Join-Path $fixtureCorePath 'empty')) | Out-Null
        $warnings = @()

        Initialize-WinpeStartupEnvironment -WarningVariable warnings

        $warnings.Count | Should -Be 0
    }

    It 'preserves shell variable precedence over Core assignments' {
        New-CoreEnvironmentFixture 'main\.env' @(
            'APPDATA=core-default'
            'USERPROFILE=core-default'
            'HOMEDRIVE=core-default'
        ) | Out-Null

        Initialize-WinpeStartupEnvironment

        $env:APPDATA | Should -Be 'X:\windows\system32\config\systemprofile\AppData\Roaming'
        $env:USERPROFILE | Should -Be 'X:\windows\system32\config\systemprofile'
        $env:HOMEDRIVE | Should -Be 'X:'
    }

    It 'does not run initialization outside WinPE' {
        $env:SystemDrive = 'C:'
        $warnings = @()

        Initialize-WinpeStartupEnvironment -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -Be 1
        $warnings[0].ToString() | Should -Match 'Not running in WinPE'
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
    }

    It 'allows the selected startup profile to override Core process values' {
        New-CoreEnvironmentFixture 'main\.env' @(
            'WSCORE_TEST_PRECEDENCE=core-default'
            'WSCORE_TEST_CORE_ONLY=retained'
        ) | Out-Null
        $profilePath = Join-Path $fixtureRoot 'profile.json'
        Set-Content -LiteralPath $profilePath -Value '{"env":{"WSCORE_TEST_PRECEDENCE":"profile-value"}}'
        $script:OSDCloudPSDefaultParameterValuesPath = Join-Path $fixtureRoot 'absent-defaults.json'
        Mock Get-WinpeStartupProfileCandidates {
            [pscustomobject]@{ Profile = 'Test'; Path = $profilePath; Index = 0 }
        }
        Mock Initialize-WinpeStartupDrivers {}
        Mock Initialize-WinpeStartupFiles {}
        Mock Initialize-WinpeStartupMain {}
        Mock Start-Sleep {}

        Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud

        $env:WSCORE_TEST_PRECEDENCE | Should -Be 'profile-value'
        $env:WSCORE_TEST_CORE_ONLY | Should -Be 'retained'
    }
}
