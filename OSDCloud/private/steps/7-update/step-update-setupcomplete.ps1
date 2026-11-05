function step-update-setupcomplete {
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    if ($env:SystemDrive -ne 'X:' -or -not $global:OSDCoreDevice.IsWinPE) {
        Write-Warning 'SetupComplete staging is only supported in WinPE; no files were changed.'
        return
    }
    try {
        if (-not (Test-Path -LiteralPath 'C:\Windows\System32\Config\SYSTEM' -PathType Leaf)) {
            throw 'The applied Windows image is missing; cannot stage SetupComplete.'
        }
        $source = Join-Path $PSScriptRoot '..\..\..\core\modules\OSDCloudSetupComplete'
        Save-OSDCloudSetupCompleteModule -SourcePath $source -DestinationPath 'C:\Windows\Setup\Modules\OSDCloudSetupComplete'
        $scriptsPath = 'C:\Windows\Setup\Scripts'
        New-Item -Path $scriptsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-OSDCloudSetupCompleteScript -Path (Join-Path $scriptsPath 'SetupComplete.cmd')
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -Format s)] [INFO] Staged OSDCloudSetupComplete and its noninteractive SetupComplete.cmd invocation."
    }
    catch {
        Write-Warning "SetupComplete staging failed: $($_.Exception.Message)"
    }
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] End"
}

function Save-OSDCloudSetupCompleteModule {
    <#
    .SYNOPSIS
        Stages the standalone SetupComplete module

    .DESCRIPTION
        Validates source files and syntax, copies the entire module, stamps the
        destination version from the parent manifest, and validates the copy.
        Does not import or execute the module. Errors terminate.

    .PARAMETER SourcePath
        Bundled OSDCloudSetupComplete directory.

    .PARAMETER DestinationPath
        Module directory under the applied Windows image.

    .EXAMPLE
        PS> Save-OSDCloudSetupCompleteModule -SourcePath $source -DestinationPath $destination

        Copies the validated module before hook installation.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Stage module"
    foreach ($relativePath in 'OSDCloudSetupComplete.psd1', 'OSDCloudSetupComplete.psm1',
        'public\Invoke-OSDCloudSetupComplete.ps1', 'private\OSDCloudSetupComplete.ps1') {
        if (-not (Test-Path -LiteralPath (Join-Path $SourcePath $relativePath) -PathType Leaf)) {
            throw "SetupComplete module component is missing: $relativePath"
        }
    }
    $sourceManifest = Join-Path $SourcePath 'OSDCloudSetupComplete.psd1'
    Test-ModuleManifest -Path $sourceManifest -ErrorAction Stop | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $SourcePath -Recurse -File -ErrorAction Stop |
        Where-Object Extension -In '.ps1', '.psm1') {
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) { throw "SetupComplete parsing failed in $($file.Name): $($parseErrors.Message -join '; ')" }
    }
    $parentManifest = Join-Path $SourcePath '..\..\..\OSDCloud.psd1'
    $version = [string](Import-PowerShellDataFile -LiteralPath $parentManifest -ErrorAction Stop).ModuleVersion
    if ($version -notmatch '^\d+(\.\d+){1,3}$') { throw "Invalid OSDCloud module version: $version" }
    [void][version]::Parse($version)
    $text = Get-Content -LiteralPath $sourceManifest -Raw -ErrorAction Stop
    $pattern = "(?m)^(\s*ModuleVersion\s*=\s*)'[^']+'"
    if ([regex]::Matches($text, $pattern).Count -ne 1) {
        throw 'SetupComplete manifest must contain exactly one ModuleVersion assignment.'
    }
    $text = [regex]::Replace($text, $pattern,
        [Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + "'$version'" })
    New-Item -Path $DestinationPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction Stop) {
        Copy-Item -LiteralPath $item.FullName -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
    }
    $destinationManifest = Join-Path $DestinationPath 'OSDCloudSetupComplete.psd1'
    [IO.File]::WriteAllText($destinationManifest, $text, [Text.UTF8Encoding]::new($false))
    Test-ModuleManifest -Path $destinationManifest -ErrorAction Stop | Out-Null
}

function Write-OSDCloudSetupCompleteScript {
    <#
    .SYNOPSIS
        Appends an idempotent noninteractive SetupComplete hook

    .DESCRIPTION
        Replaces only complete managed SetupComplete blocks, preserving unmanaged
        bytes and commands. Warns about early exits without rewriting control flow.
        The hook waits for the runtime and logs failures without restarting Windows.

    .PARAMETER Path
        Destination SetupComplete.cmd path. Its parent directory must exist.

    .EXAMPLE
        PS> Write-OSDCloudSetupCompleteScript -Path 'C:\Windows\Setup\Scripts\SetupComplete.cmd'

        Installs one managed runtime invocation.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
        Never executes the generated script. Incomplete managed markers terminate.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$Path)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Update $Path"
    # Map bytes one-to-one so existing batch content is not re-encoded.
    $encoding = [Text.Encoding]::GetEncoding(28591)
    $existing = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $encoding.GetString([IO.File]::ReadAllBytes($Path))
    } else { '' }
    $start = ':: RecastOSDCloud SetupComplete'
    $end = ':: End RecastOSDCloud SetupComplete'
    $markerPattern = '(?m)^(?:' + [regex]::Escape($start) + '|' + [regex]::Escape($end) + ')\r?$'
    $markers = [regex]::Matches($existing, $markerPattern)
    for ($index = 0; $index -lt $markers.Count; $index++) {
        $expected = if ($index % 2 -eq 0) { $start } else { $end }
        if ($markers[$index].Value.TrimEnd("`r") -ne $expected) {
            throw "Incomplete managed SetupComplete block in $Path. Repair its markers before staging."
        }
    }
    if ($markers.Count % 2 -ne 0) { throw "Incomplete managed SetupComplete block in $Path. Repair its markers before staging." }
    $pattern = '(?ms)^' + [regex]::Escape($start) + '\r?\n.*?^' + [regex]::Escape($end) + '(?:\r?\n|$)'
    $existing = [regex]::Replace($existing, $pattern, '')
    if ($existing -match '(?im)^\s*@?(?:exit(?:\s|$)|goto\s+:?eof(?:\s|$))') {
        Write-Warning "SetupComplete.cmd contains an early exit. The appended runner executes only if original commands reach the end: $Path"
    }
    $block = @'
:: RecastOSDCloud SetupComplete
set "OSDCloudSetupCompletePowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "OSDCloudSetupCompletePowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%OSDCloudSetupCompletePowerShell%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "try { Import-Module -Name (Join-Path $env:SystemRoot 'Setup\Modules\OSDCloudSetupComplete\OSDCloudSetupComplete.psd1') -ErrorAction Stop; exit (Invoke-OSDCloudSetupComplete) } catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; exit 1 }"
set "OSDCloudSetupCompleteExitCode=%ERRORLEVEL%"
if not "%OSDCloudSetupCompleteExitCode%"=="0" echo OSDCloudSetupComplete failed with exit code %OSDCloudSetupCompleteExitCode%. Continuing Windows Setup.
if not "%OSDCloudSetupCompleteExitCode%"=="0" if not exist "%SystemRoot%\Temp\osdcloud-logs" mkdir "%SystemRoot%\Temp\osdcloud-logs"
if not "%OSDCloudSetupCompleteExitCode%"=="0" echo [%DATE% %TIME%] SetupComplete invocation failed with exit code %OSDCloudSetupCompleteExitCode%.>>"%SystemRoot%\Temp\osdcloud-logs\OSDCloudSetupComplete.log"
set "OSDCloudSetupCompletePowerShell="
set "OSDCloudSetupCompleteExitCode="
:: End RecastOSDCloud SetupComplete
'@
    if ($existing -and -not $existing.EndsWith("`n")) { $existing += "`r`n" }
    [IO.File]::WriteAllBytes($Path, $encoding.GetBytes($existing + ($block -replace '\r?\n', "`r`n") + "`r`n"))
}
