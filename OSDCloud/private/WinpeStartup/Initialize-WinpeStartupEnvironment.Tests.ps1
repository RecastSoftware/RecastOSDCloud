BeforeAll {
    . "$PSScriptRoot\..\core-license\Get-OSDCoreLicense.ps1"
    . "$PSScriptRoot\Test-WinpeStartupAssetLicense.ps1"
    . "$PSScriptRoot\Import-WinpeStartupAssets.ps1"
    . "$PSScriptRoot\Initialize-WinpeStartupEnvironment.ps1"
    . "$PSScriptRoot\..\..\public\WinPE\Invoke-WinpeStartup.ps1"
    . "$PSScriptRoot\..\Get-WinpeStartupProfileCandidates.ps1"
    . "$PSScriptRoot\Initialize-WinpeStartupDrivers.ps1"
    . "$PSScriptRoot\Initialize-WinpeStartupFiles.ps1"
    . "$PSScriptRoot\Initialize-WinpeStartupMain.ps1"

    function New-CoreEnvironmentFixture {
        <#
        .SYNOPSIS
            Creates a Core environment test fixture.

        .DESCRIPTION
            Creates a file under the test WinpeStartup Core directory and
            returns its path.

        .PARAMETER RelativePath
            Path of the fixture file relative to the Core directory.

        .PARAMETER Lines
            Content lines to write to the fixture file.

        .EXAMPLE
            New-CoreEnvironmentFixture -RelativePath 'main\.env' -Lines @('SETTING=value')

        .NOTES
            Used by Initialize-WinpeStartupEnvironment tests.
        #>
        [CmdletBinding()]
        param (
            [string]$RelativePath,
            [string[]]$Lines
        )

        $Error.Clear()
        $path = Join-Path -Path $fixtureRoot -ChildPath "WinpeStartup\core\$RelativePath"
        [System.IO.Directory]::CreateDirectory((Split-Path -Path $path -Parent)) | Out-Null
        Set-Content -LiteralPath $path -Value $Lines -Encoding UTF8
        return $path
    }

    function New-ProfileAssetFixture {
        <#
        .SYNOPSIS
            Creates an asset in the selected profile folder.
        .DESCRIPTION
            Writes synthetic asset content without invoking native import tools.
        .PARAMETER RelativePath
            File path relative to the selected profile folder.
        .PARAMETER Lines
            Synthetic file contents.
        .EXAMPLE
            New-ProfileAssetFixture '.env' @('WSCORE_TEST_PROFILE=value')
        .NOTES
            Used by selected-profile asset tests.
        #>
        [CmdletBinding()]
        param (
            [string]$RelativePath,
            [string[]]$Lines
        )
        $Error.Clear()
        $path = Join-Path -Path $selectedAssetPath -ChildPath $RelativePath
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
        Mock Get-OSDCoreLicense { [pscustomobject]@{ IsValid = $true } }
        Mock Set-ItemProperty {}
        Mock Write-Host {}
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
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
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match '^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\] \[PASS\] Initialize env$'
        }
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
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match '^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\] \[FAIL\] Initialize env$'
        }
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter {
            $Object -match '\[PASS\] Initialize env$'
        }
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
        Should -Invoke Start-Process -Times 0 -Exactly
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

    It 'imports hidden registry files and root certificates with quoted paths from multiple Core folders' {
        $registryPath = New-CoreEnvironmentFixture 'main folder\winpe-reg\settings file.reg' @('synthetic')
        $certificatePath = New-CoreEnvironmentFixture 'main folder\winpe-root-cer\root file.cer' @('synthetic')
        New-CoreEnvironmentFixture 'additional\winpe-reg\extra.reg' @('synthetic') | Out-Null
        New-CoreEnvironmentFixture 'additional\winpe-root-cer\extra.cer' @('synthetic') | Out-Null
        [System.IO.File]::SetAttributes($registryPath, [System.IO.FileAttributes]::Hidden)
        [System.IO.File]::SetAttributes($certificatePath, [System.IO.FileAttributes]::Hidden)
        [System.IO.File]::SetAttributes((Split-Path $registryPath -Parent), [System.IO.FileAttributes]::Hidden)
        [System.IO.File]::SetAttributes((Split-Path $certificatePath -Parent), [System.IO.FileAttributes]::Hidden)

        $output = @(Initialize-WinpeStartupEnvironment)

        $output.Count | Should -Be 0
        Should -Invoke Start-Process -Times 4 -Exactly
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'reg.exe' -and $ArgumentList.Count -eq 2 -and
            $ArgumentList[0] -eq 'import' -and $ArgumentList[1] -eq "`"$registryPath`"" -and
            $Wait -and $PassThru -and $NoNewWindow -and $ErrorAction -eq 'Stop' -and
            -not [string]::IsNullOrWhiteSpace($RedirectStandardOutput) -and
            -not [string]::IsNullOrWhiteSpace($RedirectStandardError)
        }
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'certutil.exe' -and $ArgumentList.Count -eq 3 -and
            $ArgumentList[0] -eq '-addstore' -and $ArgumentList[1] -eq 'root' -and
            $ArgumentList[2] -eq "`"$certificatePath`"" -and
            $Wait -and $PassThru -and $NoNewWindow -and $ErrorAction -eq 'Stop' -and
            -not [string]::IsNullOrWhiteSpace($RedirectStandardOutput) -and
            -not [string]::IsNullOrWhiteSpace($RedirectStandardError)
        }
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match '^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\] \[PASS\] Initialize certificates$'
        }
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match '^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\] \[PASS\] Initialize registry$'
        }
    }

    It 'imports environment files before registry files and certificates and sorts native imports within each type' {
        $paths = @(
            New-CoreEnvironmentFixture 'z-last\winpe-root-cer\z.cer' @('synthetic')
            New-CoreEnvironmentFixture 'z-last\winpe-reg\z.reg' @('synthetic')
            New-CoreEnvironmentFixture 'a-first\winpe-root-cer\a.cer' @('synthetic')
            New-CoreEnvironmentFixture 'a-first\winpe-reg\a.reg' @('synthetic')
        )
        $environmentPath = New-CoreEnvironmentFixture 'a-first\.env' @('WSCORE_TEST_IMPORT_ORDER=loaded')
        $calls = [System.Collections.Generic.List[string]]::new()
        Mock Get-Content {
            $calls.Add("env $LiteralPath")
            'WSCORE_TEST_IMPORT_ORDER=loaded'
        } -ParameterFilter { $LiteralPath -eq $environmentPath }
        Mock Start-Process {
            $calls.Add("$FilePath $($ArgumentList -join ' ')")
            [pscustomobject]@{ ExitCode = 0 }
        }

        Initialize-WinpeStartupEnvironment

        $calls.Count | Should -Be 5
        $calls[0] | Should -Be "env $environmentPath"
        $calls[1] | Should -Be "reg.exe import `"$($paths[3])`""
        $calls[2] | Should -Be "reg.exe import `"$($paths[1])`""
        $calls[3] | Should -Be "certutil.exe -addstore root `"$($paths[2])`""
        $calls[4] | Should -Be "certutil.exe -addstore root `"$($paths[0])`""
    }

    It 'does not import files at incorrect levels or with incorrect extensions' {
        foreach ($relativePath in @(
            'winpe-reg\root.reg'
            'winpe-root-cer\root.cer'
            'main\file.reg'
            'main\file.cer'
            'main\nested\winpe-reg\deep.reg'
            'main\nested\winpe-root-cer\deep.cer'
            'main\winpe-reg\nested\deep.reg'
            'main\winpe-root-cer\nested\deep.cer'
            'main\winpe-reg\ignore.txt'
            'main\winpe-root-cer\ignore.txt'
        )) {
            New-CoreEnvironmentFixture $relativePath @('synthetic') | Out-Null
        }

        Initialize-WinpeStartupEnvironment

        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'warns on nonzero tool exit codes and continues with remaining imports under ErrorAction Stop' {
        $failedRegistry = New-CoreEnvironmentFixture 'main\winpe-reg\a-failed.reg' @('synthetic')
        $failedCertificate = New-CoreEnvironmentFixture 'main\winpe-root-cer\a-failed.cer' @('synthetic')
        New-CoreEnvironmentFixture 'main\winpe-reg\z-valid.reg' @('synthetic') | Out-Null
        New-CoreEnvironmentFixture 'main\winpe-root-cer\z-valid.cer' @('synthetic') | Out-Null
        Mock Start-Process {
            if ($ArgumentList[-1] -like '*a-failed*') {
                return [pscustomobject]@{ ExitCode = 1 }
            }
            return [pscustomobject]@{ ExitCode = 0 }
        }
        $warnings = @()

        Initialize-WinpeStartupEnvironment -ErrorAction Stop -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -Be 2
        $warnings[0].ToString() | Should -Match ([regex]::Escape($failedRegistry))
        $warnings[1].ToString() | Should -Match ([regex]::Escape($failedCertificate))
        ($warnings | Out-String) | Should -Match 'exit code 1'
        Should -Invoke Start-Process -Times 4 -Exactly
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter {
            $Object -match '\[PASS\] Initialize certificates$'
        }
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match '^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\] \[FAIL\] Initialize certificates$'
        }
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter {
            $Object -match '\[PASS\] Initialize registry$'
        }
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match '^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\] \[FAIL\] Initialize registry$'
        }
    }

    It 'warns on process launch errors and continues with subsequent registry and certificate files' {
        New-CoreEnvironmentFixture 'main\winpe-reg\a-failed.reg' @('synthetic') | Out-Null
        New-CoreEnvironmentFixture 'main\winpe-root-cer\a-failed.cer' @('synthetic') | Out-Null
        New-CoreEnvironmentFixture 'main\winpe-reg\z-valid.reg' @('synthetic') | Out-Null
        New-CoreEnvironmentFixture 'main\winpe-root-cer\z-valid.cer' @('synthetic') | Out-Null
        Mock Start-Process {
            if ($ArgumentList[-1] -like '*a-failed*') {
                throw 'Tool could not start'
            }
            [pscustomobject]@{ ExitCode = 0 }
        }
        $warnings = @()

        Initialize-WinpeStartupEnvironment -ErrorAction Stop -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -Be 2
        ($warnings | Out-String) | Should -Match 'reg.exe'
        ($warnings | Out-String) | Should -Match 'certutil.exe'
        Should -Invoke Start-Process -Times 4 -Exactly
    }

    It 'warns on import folder discovery errors and continues with other Core folders' {
        New-CoreEnvironmentFixture 'broken\winpe-reg\file.reg' @('synthetic') | Out-Null
        New-CoreEnvironmentFixture 'broken\winpe-root-cer\file.cer' @('synthetic') | Out-Null
        New-CoreEnvironmentFixture 'main\winpe-reg\file.reg' @('synthetic') | Out-Null
        New-CoreEnvironmentFixture 'main\winpe-root-cer\file.cer' @('synthetic') | Out-Null
        $brokenRegistry = Join-Path $fixtureCorePath 'broken\winpe-reg'
        $brokenCertificates = Join-Path $fixtureCorePath 'broken\winpe-root-cer'
        Mock Get-ChildItem { throw 'Cannot enumerate folder' } -ParameterFilter {
            $LiteralPath -eq $brokenRegistry -or $LiteralPath -eq $brokenCertificates
        }
        $warnings = @()

        Initialize-WinpeStartupEnvironment -ErrorAction Stop -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings.Count | Should -Be 2
        ($warnings | Out-String) | Should -Match 'Failed to discover'
        Should -Invoke Start-Process -Times 2 -Exactly
    }

    It 'allows missing or empty import folders without warnings or native tool calls' {
        [System.IO.Directory]::CreateDirectory((Join-Path $fixtureCorePath 'main\winpe-reg')) | Out-Null
        [System.IO.Directory]::CreateDirectory((Join-Path $fixtureCorePath 'main\winpe-root-cer')) | Out-Null
        [System.IO.Directory]::CreateDirectory((Join-Path $fixtureCorePath 'additional')) | Out-Null
        $warnings = @()

        Initialize-WinpeStartupEnvironment -WarningVariable warnings

        $warnings.Count | Should -Be 0
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    Describe 'Unlicensed WinpeStartup assets' {
        BeforeEach {
            $selectedAssetPath = Join-Path $fixtureRoot 'WinpeStartup\profiles\Selected profile'
            $profilePath = Join-Path $selectedAssetPath 'winpestartup.json'
            New-ProfileAssetFixture 'winpestartup.json' @(
                '{"Environment":{"WSCORE_TEST_UNLICENSED":"json"},"Invoke-WinpeStartup:InvokeStartupCommand":"Write-Output synthetic"}'
            ) | Out-Null
            New-ProfileAssetFixture '.env' @('WSCORE_TEST_UNLICENSED=unexpected-profile') | Out-Null
            New-ProfileAssetFixture 'winpe-reg\settings.reg' @('synthetic') | Out-Null
            New-ProfileAssetFixture 'winpe-root-cer\root.cer' @('synthetic') | Out-Null
            New-CoreEnvironmentFixture 'main\.env' @('WSCORE_TEST_UNLICENSED=unexpected-core') | Out-Null
            New-CoreEnvironmentFixture 'main\winpe-reg\settings.reg' @('synthetic') | Out-Null
            New-CoreEnvironmentFixture 'main\winpe-root-cer\root.cer' @('synthetic') | Out-Null
            $script:OSDCloudPSDefaultParameterValuesPath = Join-Path $fixtureRoot 'absent-defaults.json'
            Mock Get-OSDCoreLicense { $null }
            Mock Get-WinpeStartupProfileCandidates {
                [pscustomobject]@{ Profile = 'Selected'; Path = $profilePath; AssetPath = $selectedAssetPath; Index = 0 }
            }
            Mock Initialize-WinpeStartupDrivers {}
            Mock Initialize-WinpeStartupFiles {}
            Mock Initialize-WinpeStartupMain {}
            Mock Start-Sleep {}
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
            Mock Get-ChildItem { throw 'Unlicensed asset discovery must not run' }
            Mock Get-Content { throw 'Unlicensed asset reads must not run' } -ParameterFilter {
                $LiteralPath -like '*.env'
            }
            Mock Get-Content { [System.IO.File]::ReadAllText($LiteralPath) } -ParameterFilter {
                $LiteralPath -eq $profilePath
            }
        }

        It 'retains JSON settings and shell setup for <State> licensing with <SelectionMode>' -TestCases @(
            @{ State = 'missing'; SelectionMode = 'automatic' }
            @{ State = 'invalid'; SelectionMode = 'automatic' }
            @{ State = 'failed lookup'; SelectionMode = 'automatic' }
            @{ State = 'missing'; SelectionMode = 'menu' }
            @{ State = 'invalid'; SelectionMode = 'menu' }
            @{ State = 'failed lookup'; SelectionMode = 'menu' }
            @{ State = 'missing'; SelectionMode = 'legacy' }
        ) {
            param ($State, $SelectionMode)
            if ($State -eq 'invalid') {
                Mock Get-OSDCoreLicense { [pscustomobject]@{ IsValid = $false; Email = 'synthetic@example.invalid' } }
            }
            elseif ($State -eq 'failed lookup') {
                Mock Get-OSDCoreLicense { throw 'Synthetic lookup failure' }
            }
            if ($SelectionMode -eq 'menu') {
                Mock Get-WinpeStartupProfileCandidates {
                    @(
                        [pscustomobject]@{ Profile = 'Selected'; Path = $profilePath; AssetPath = $selectedAssetPath; Index = 0 }
                        [pscustomobject]@{ Profile = 'ZOther'; Path = "$profilePath.other"; AssetPath = "$selectedAssetPath.other"; Index = 0 }
                    )
                }
                Mock Read-Host { '1' }
            }
            elseif ($SelectionMode -eq 'legacy') {
                Mock Get-WinpeStartupProfileCandidates {
                    [pscustomobject]@{ Profile = 'Legacy'; Path = $profilePath; Index = 0 }
                }
            }
            $output = @(Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -ErrorAction Stop 2>&1 3>&1)

            $output.Count | Should -Be 0
            $env:WSCORE_TEST_UNLICENSED | Should -Be 'json'
            $env:USERPROFILE | Should -Be 'X:\windows\system32\config\systemprofile'
            Should -Invoke New-Item -Times 6 -Exactly -ParameterFilter { $Path -ne 'X:\Windows\Temp' }
            Should -Invoke Set-ItemProperty -Times 2 -Exactly
            Should -Invoke Initialize-WinpeStartupMain -Times 1 -Exactly
            Should -Invoke Get-Content -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $profilePath }
            Should -Invoke Get-Content -Times 0 -Exactly -ParameterFilter { $LiteralPath -like '*.env' }
            Should -Invoke Get-ChildItem -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly -ParameterFilter { $FilePath -in @('reg.exe', 'certutil.exe') }
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'powershell.exe' }
            Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter {
                $Object -match '\[(PASS|FAIL)\] Initialize (env|registry|certificates)'
            }
        }

        It 'quietly gates direct importer calls before discovery and status output' {
            $warnings = @()
            $importErrors = @()

            $output = @(Import-WinpeStartupAssets -Path $selectedAssetPath -DiscoverySucceeded $false `
                -WarningVariable warnings -ErrorVariable importErrors -ErrorAction Stop)

            $output.Count | Should -Be 0
            $warnings.Count | Should -Be 0
            $importErrors.Count | Should -Be 0
            Should -Invoke Get-ChildItem -Times 0 -Exactly
            Should -Invoke Get-Content -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
            Should -Invoke Write-Host -Times 0 -Exactly
        }
    }

    Describe 'Selected WinpeStartup profile assets' {
        BeforeEach {
            $selectedAssetPath = Join-Path $fixtureRoot 'WinpeStartup\profiles\Selected profile'
            $profilePath = Join-Path $selectedAssetPath 'winpestartup.json'
            New-ProfileAssetFixture 'winpestartup.json' @('{}') | Out-Null
            $script:OSDCloudPSDefaultParameterValuesPath = Join-Path $fixtureRoot 'absent-defaults.json'
            Mock Get-WinpeStartupProfileCandidates {
                [pscustomobject]@{ Profile = 'Selected profile'; Path = $profilePath; AssetPath = $selectedAssetPath; Index = 0 }
            }
            Mock Initialize-WinpeStartupDrivers {}
            Mock Initialize-WinpeStartupFiles {}
            Mock Initialize-WinpeStartupMain {}
            Mock Start-Sleep {}
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
        }

        It 'applies Core, shell, JSON, then profile files before native imports and child commands' {
            New-CoreEnvironmentFixture 'main\.env' @(
                'WSCORE_TEST_PRECEDENCE=core'
                'WSCORE_TEST_CORE_ONLY=retained'
                'USERPROFILE=core-shell'
                'SystemDrive=core-override'
            ) | Out-Null
            $coreRegistry = New-CoreEnvironmentFixture 'main\winpe-reg\core.reg' @('synthetic')
            $coreCertificate = New-CoreEnvironmentFixture 'main\winpe-root-cer\core.cer' @('synthetic')
            New-ProfileAssetFixture 'winpestartup.json' @(
                '{"Environment":{"WSCORE_TEST_PRECEDENCE":"json","WSCORE_TEST_JSON_ONLY":"retained","USERPROFILE":"json-shell","SystemDrive":"json-override"}}'
            ) | Out-Null
            New-ProfileAssetFixture '.env' @(
                'WSCORE_TEST_PRECEDENCE=profile-file'
                'USERPROFILE=profile-file-shell'
            ) | Out-Null
            $profileRegistry = New-ProfileAssetFixture 'winpe-reg\profile file.reg' @('synthetic')
            $profileCertificate = New-ProfileAssetFixture 'winpe-root-cer\profile file.cer' @('synthetic')
            $calls = [System.Collections.Generic.List[object]]::new()
            Mock Start-Process {
                $calls.Add([pscustomobject]@{
                    Tool = $FilePath
                    Arguments = $ArgumentList
                    Value = $env:WSCORE_TEST_PRECEDENCE
                    Shell = $env:USERPROFILE
                })
                [pscustomobject]@{ ExitCode = 0 }
            }

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -InvokeStartupCommand 'Write-Output synthetic' -InvokeMainCommand 'Write-Output synthetic' `
                -InvokeShutdownCommand 'Write-Output synthetic'

            $calls.Count | Should -Be 7
            $calls[0].Arguments[-1] | Should -Be "`"$coreRegistry`""
            $calls[1].Arguments[-1] | Should -Be "`"$coreCertificate`""
            $calls[0].Value | Should -Be 'core'
            $calls[0].Shell | Should -Be 'X:\windows\system32\config\systemprofile'
            $calls[2].Arguments[-1] | Should -Be "`"$profileRegistry`""
            $calls[3].Arguments[-1] | Should -Be "`"$profileCertificate`""
            foreach ($call in $calls.GetRange(2, 5)) {
                $call.Value | Should -Be 'profile-file'
                $call.Shell | Should -Be 'profile-file-shell'
            }
            @($calls | Where-Object Tool -eq 'powershell.exe').Count | Should -Be 3
            $env:WSCORE_TEST_CORE_ONLY | Should -Be 'retained'
            $env:WSCORE_TEST_JSON_ONLY | Should -Be 'retained'
            $env:SystemDrive | Should -Be 'json-override'
            Should -Invoke Set-ItemProperty -Times 2 -Exactly
            Should -Invoke Stop-Transcript -Times 1 -Exactly
        }

        It 'loads only selected immediate assets including hidden files in sorted order' {
            $envFile = New-ProfileAssetFixture '.env' @('WSCORE_TEST_PROFILE_ORDER=first')
            New-ProfileAssetFixture 'application.env' @('WSCORE_TEST_PROFILE_ORDER=last') | Out-Null
            $registryA = New-ProfileAssetFixture 'winpe-reg\a file.reg' @('synthetic')
            $registryZ = New-ProfileAssetFixture 'winpe-reg\z.reg' @('synthetic')
            $certificateA = New-ProfileAssetFixture 'winpe-root-cer\a.cer' @('synthetic')
            $certificateZ = New-ProfileAssetFixture 'winpe-root-cer\z.cer' @('synthetic')
            New-ProfileAssetFixture 'nested\unexpected.env' @('WSCORE_TEST_EXCLUDED=unexpected') | Out-Null
            New-ProfileAssetFixture 'winpe-reg\nested\unexpected.reg' @('synthetic') | Out-Null
            New-ProfileAssetFixture 'winpe-root-cer\nested\unexpected.cer' @('synthetic') | Out-Null
            New-ProfileAssetFixture 'unexpected.reg' @('synthetic') | Out-Null
            New-ProfileAssetFixture 'unexpected.cer' @('synthetic') | Out-Null
            New-ProfileAssetFixture 'winpe-reg\unexpected.txt' @('synthetic') | Out-Null
            New-ProfileAssetFixture '..\Unselected\.env' @('WSCORE_TEST_EXCLUDED=unexpected') | Out-Null
            New-ProfileAssetFixture '..\Unselected\winpe-reg\unexpected.reg' @('synthetic') | Out-Null
            New-ProfileAssetFixture '..\Unselected\winpe-root-cer\unexpected.cer' @('synthetic') | Out-Null
            foreach ($path in @($envFile, $registryA, $certificateA, $selectedAssetPath)) {
                [System.IO.File]::SetAttributes($path, [System.IO.FileAttributes]::Hidden)
            }
            $calls = [System.Collections.Generic.List[string]]::new()
            Mock Start-Process {
                $env:WSCORE_TEST_PROFILE_ORDER | Should -Be 'last'
                $calls.Add("$FilePath $($ArgumentList -join ' ')")
                [pscustomobject]@{ ExitCode = 0 }
            }
            Mock Get-WinpeStartupProfileCandidates {
                @(
                    [pscustomobject]@{ Profile = 'Selected profile'; Path = $profilePath; AssetPath = $selectedAssetPath; Index = 0 }
                    [pscustomobject]@{ Profile = 'Unselected'; Path = (Join-Path (Split-Path $selectedAssetPath -Parent) 'Unselected\winpestartup.json'); AssetPath = (Join-Path (Split-Path $selectedAssetPath -Parent) 'Unselected'); Index = 0 }
                )
            }
            Mock Read-Host { '1' }

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud

            $env:WSCORE_TEST_PROFILE_ORDER | Should -Be 'last'
            $env:WSCORE_TEST_EXCLUDED | Should -BeNullOrEmpty
            $calls.Count | Should -Be 4
            $calls[0] | Should -Be "reg.exe import `"$registryA`""
            $calls[1] | Should -Be "reg.exe import `"$registryZ`""
            $calls[2] | Should -Be "certutil.exe -addstore root `"$certificateA`""
            $calls[3] | Should -Be "certutil.exe -addstore root `"$certificateZ`""
        }

        It 'keeps JSON environment values when profile assets are missing' {
            New-ProfileAssetFixture 'winpestartup.json' @('{"env":{"WSCORE_TEST_PRECEDENCE":"json"}}') | Out-Null
            $warnings = @()

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -WarningVariable warnings -WarningAction SilentlyContinue

            $env:WSCORE_TEST_PRECEDENCE | Should -Be 'json'
            $warnings.Count | Should -Be 0
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'skips assets for legacy root-level <FileName> profiles' -TestCases @(
            @{ FileName = 'Legacy.json' }
            @{ FileName = 'winpestartup.json' }
        ) {
            param ($FileName)
            $legacyPath = Join-Path (Split-Path $selectedAssetPath -Parent) $FileName
            Set-Content -LiteralPath $legacyPath -Value '{"env":{"WSCORE_TEST_PRECEDENCE":"legacy"}}'
            New-ProfileAssetFixture '..\.env' @('WSCORE_TEST_PRECEDENCE=unexpected') | Out-Null
            New-ProfileAssetFixture '..\winpe-reg\unexpected.reg' @('synthetic') | Out-Null
            New-ProfileAssetFixture '..\winpe-root-cer\unexpected.cer' @('synthetic') | Out-Null
            Mock Get-WinpeStartupProfileCandidates {
                [pscustomobject]@{ Profile = 'Legacy'; Path = $legacyPath; Index = 0 }
            }

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud

            $env:WSCORE_TEST_PRECEDENCE | Should -Be 'legacy'
            Should -Invoke Start-Process -Times 0 -Exactly
        }

        It 'does not import profile assets when no profile is discovered' {
            New-ProfileAssetFixture '.env' @('WSCORE_TEST_EXCLUDED=unexpected') | Out-Null
            Mock Get-WinpeStartupProfileCandidates { @() }
            Mock Import-WinpeStartupAssets {} -ParameterFilter { $Path -contains $selectedAssetPath }

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud

            $env:WSCORE_TEST_EXCLUDED | Should -BeNullOrEmpty
            Should -Invoke Import-WinpeStartupAssets -Times 0 -Exactly -ParameterFilter { $Path -contains $selectedAssetPath }
        }

        It 'does not import selected assets for invalid JSON <Content>' -TestCases @(
            @{ Content = '{invalid' }
            @{ Content = '{"env":{},"Environment":{}}' }
        ) {
            param ($Content)
            New-ProfileAssetFixture 'winpestartup.json' @($Content) | Out-Null
            Mock Import-WinpeStartupAssets {} -ParameterFilter { $Path -contains $selectedAssetPath }
            $warnings = @()

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings | Out-String) | Should -Match 'Failed to load profile'
            Should -Invoke Import-WinpeStartupAssets -Times 0 -Exactly -ParameterFilter { $Path -contains $selectedAssetPath }
        }

        It 'does not import profile assets after cancellation with <Selection>' -TestCases @(
            @{ Selection = '' }
            @{ Selection = 'q' }
        ) {
            param ($Selection)
            Mock Get-WinpeStartupProfileCandidates {
                @(
                    [pscustomobject]@{ Profile = 'Selected'; Path = $profilePath; AssetPath = $selectedAssetPath; Index = 0 }
                    [pscustomobject]@{ Profile = 'Other'; Path = "$profilePath.other"; AssetPath = "$selectedAssetPath.other"; Index = 0 }
                )
            }
            Mock Read-Host { $Selection }
            Mock Import-WinpeStartupAssets {} -ParameterFilter { $Path -contains $selectedAssetPath }
            $warnings = @()

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings | Out-String) | Should -Match 'Profile selection cancelled'
            Should -Invoke Import-WinpeStartupAssets -Times 0 -Exactly -ParameterFilter { $Path -contains $selectedAssetPath }
        }

        It 'continues profile imports after <Failure> without exposing environment values' -TestCases @(
            @{ Failure = 'environment discovery' }
            @{ Failure = 'environment read' }
            @{ Failure = 'registry discovery' }
            @{ Failure = 'registry launch' }
            @{ Failure = 'registry exit' }
            @{ Failure = 'certificate discovery' }
            @{ Failure = 'certificate launch' }
            @{ Failure = 'certificate exit' }
        ) {
            param ($Failure)
            $environmentPath = New-ProfileAssetFixture '.env' @('WSCORE_TEST_FAILURE=synthetic-private-value')
            New-ProfileAssetFixture 'z.env' @('WSCORE_TEST_SURVIVOR=retained') | Out-Null
            $registryPath = New-ProfileAssetFixture 'winpe-reg\a.reg' @('synthetic')
            New-ProfileAssetFixture 'winpe-reg\z.reg' @('synthetic') | Out-Null
            $certificatePath = New-ProfileAssetFixture 'winpe-root-cer\a.cer' @('synthetic')
            New-ProfileAssetFixture 'winpe-root-cer\z.cer' @('synthetic') | Out-Null
            switch ($Failure) {
                'environment discovery' {
                    Mock Get-ChildItem { throw 'Synthetic discovery failure' } -ParameterFilter {
                        $LiteralPath -eq $selectedAssetPath -and $Filter -eq '*.env'
                    }
                }
                'environment read' {
                    Mock Get-Content { throw 'Synthetic read failure' } -ParameterFilter { $LiteralPath -eq $environmentPath }
                }
                'registry discovery' {
                    Mock Get-ChildItem { throw 'Synthetic discovery failure' } -ParameterFilter {
                        $LiteralPath -eq (Join-Path $selectedAssetPath 'winpe-reg')
                    }
                }
                'certificate discovery' {
                    Mock Get-ChildItem { throw 'Synthetic discovery failure' } -ParameterFilter {
                        $LiteralPath -eq (Join-Path $selectedAssetPath 'winpe-root-cer')
                    }
                }
                default {
                    Mock Start-Process {
                        if ($Failure -like '*launch') {
                            throw 'Synthetic launch failure'
                        }
                        [pscustomobject]@{ ExitCode = 1 }
                    } -ParameterFilter {
                        ($Failure -like 'registry*' -and $ArgumentList[-1] -eq "`"$registryPath`"") -or
                        ($Failure -like 'certificate*' -and $ArgumentList[-1] -eq "`"$certificatePath`"")
                    }
                }
            }
            $warnings = @()

            $messages = @(Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -InvokeStartupCommand 'Write-Output synthetic' -ErrorAction Stop -Verbose `
                -WarningVariable warnings -WarningAction SilentlyContinue 4>&1)

            $warnings.Count | Should -BeGreaterThan 0
            ($warnings | Out-String) | Should -Not -Match 'synthetic-private-value'
            ($messages | Out-String) | Should -Not -Match 'synthetic-private-value'
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'powershell.exe' }
            if ($Failure -ne 'environment discovery') {
                $env:WSCORE_TEST_SURVIVOR | Should -Be 'retained'
            }
            if ($Failure -notlike 'registry*') {
                Should -Invoke Start-Process -Times 2 -Exactly -ParameterFilter { $FilePath -eq 'reg.exe' }
            }
            if ($Failure -notlike 'certificate*') {
                Should -Invoke Start-Process -Times 2 -Exactly -ParameterFilter { $FilePath -eq 'certutil.exe' }
            }
            if ($Failure -like 'registry *' -and $Failure -ne 'registry discovery') {
                Should -Invoke Start-Process -Times 2 -Exactly -ParameterFilter { $FilePath -eq 'reg.exe' }
            }
            if ($Failure -like 'certificate *' -and $Failure -ne 'certificate discovery') {
                Should -Invoke Start-Process -Times 2 -Exactly -ParameterFilter { $FilePath -eq 'certutil.exe' }
            }
        }

        It 'warns for invalid profile environment entries and continues with literal valid assignments' {
            New-ProfileAssetFixture '.env' @(
                'not-an-assignment'
                'WSCORE_TEST_INVALID="unclosed synthetic-private-value'
                'WSCORE_TEST_LITERAL=$env:SystemDrive'
                'WSCORE_TEST_SURVIVOR=retained'
            ) | Out-Null
            $warnings = @()

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -WarningVariable warnings -WarningAction SilentlyContinue

            $warnings.Count | Should -Be 2
            ($warnings | Out-String) | Should -Match 'at line 1'
            ($warnings | Out-String) | Should -Match 'at line 2'
            ($warnings | Out-String) | Should -Not -Match 'synthetic-private-value'
            $env:WSCORE_TEST_LITERAL | Should -Be '$env:SystemDrive'
            $env:WSCORE_TEST_SURVIVOR | Should -Be 'retained'
        }

        It 'passes profile file values to a real child process without machine persistence' {
            $machineBefore = [System.Environment]::GetEnvironmentVariable('WSCORE_TEST_CHILD', 'Machine')
            New-ProfileAssetFixture '.env' @('WSCORE_TEST_CHILD=profile-child') | Out-Null
            Import-WinpeStartupAssets -Path $selectedAssetPath

            $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('$env:WSCORE_TEST_CHILD'))
            $childValue = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -EncodedCommand $encodedCommand

            $childValue | Should -Be 'profile-child'
            [System.Environment]::GetEnvironmentVariable('WSCORE_TEST_CHILD', 'Machine') | Should -Be $machineBefore
        }

        It 'does not import assets outside WinPE' {
            $env:SystemDrive = 'C:'
            Mock Get-ChildItem {}
            $warnings = @()

            Import-WinpeStartupAssets -Path $selectedAssetPath -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings | Out-String) | Should -Match 'Not running in WinPE'
            Should -Invoke Get-ChildItem -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
        }
    }

    Describe 'Invoke-WinpeStartup transcript lifecycle' {
        BeforeEach {
            $script:OSDCloudPSDefaultParameterValuesPath = Join-Path -Path $fixtureRoot -ChildPath 'absent-defaults.json'
            Mock Initialize-WinpeStartupEnvironment {}
            Mock Initialize-WinpeStartupDrivers {}
            Mock Initialize-WinpeStartupFiles {}
            Mock Initialize-WinpeStartupMain {}
            Mock Get-WinpeStartupProfileCandidates { @() }
            Mock Start-Sleep {}
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
        }

        It 'stops the transcript after successful startup' {
            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud

            Should -Invoke Start-Transcript -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'X:\Windows\Temp\winpestartup.log' -and $Force -and $ErrorAction -eq 'Stop'
            }
            Should -Invoke Stop-Transcript -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
        }

        It 'continues startup when starting the transcript fails' {
            Mock Start-Transcript { throw 'Synthetic transcript start failure' }
            $warnings = @()

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings | Out-String) | Should -Match 'Failed to start log'
            Should -Invoke Stop-Transcript -Times 0 -Exactly
            Should -Invoke Initialize-WinpeStartupMain -Times 1 -Exactly
        }

        It 'warns when stopping the transcript fails' {
            Mock Stop-Transcript { throw 'Synthetic transcript stop failure' }
            $warnings = @()

            Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                -WarningVariable warnings -WarningAction SilentlyContinue

            ($warnings | Out-String) | Should -Match 'Failed to stop log'
            Should -Invoke Stop-Transcript -Times 1 -Exactly
        }

        It 'stops the transcript when a startup command terminates with an error' {
            Mock Start-Process { throw 'Synthetic process launch failure' } -ParameterFilter {
                $FilePath -eq 'powershell.exe'
            }

            {
                Invoke-WinpeStartup -SkipOnScreenKeyboard -SkipWiFi -SkipIPConfig -SkipUpdateOSDCloud `
                    -InvokeStartupCommand 'Write-Output test' -InvokeStartupCommandEA Stop
            } | Should -Throw

            Should -Invoke Stop-Transcript -Times 1 -Exactly
        }
    }
}
