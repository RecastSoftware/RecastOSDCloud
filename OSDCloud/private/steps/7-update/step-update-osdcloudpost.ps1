function step-update-osdcloudpost {
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    if ($env:SystemDrive -ne 'X:' -or -not $global:OSDCoreDevice.IsWinPE) {
        Write-Warning 'OSDCloudPost staging is only supported in WinPE; no files were changed.'
        return
    }
    try {
        $source = Join-Path $PSScriptRoot '..\..\..\core\modules\OSDCloudPost'
        $scriptsPath = 'C:\Windows\Setup\Scripts'
        $modulesPath = 'C:\Windows\Setup\Modules'
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "OSDCloudPost module source is missing: $source"
        }
        if (-not (Test-Path -LiteralPath 'C:\Windows\System32\Config\SYSTEM' -PathType Leaf)) {
            throw 'The applied Windows image is missing; cannot stage OSDCloudPost.'
        }
        New-Item -Path $scriptsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Save-OSDCloudPostModule -SourcePath $source -DestinationPath (Join-Path $modulesPath 'OSDCloudPost')
        foreach ($legacy in 'OSDCloudPreOOBE', 'OSDCloudSetupComplete') {
            $legacyPath = Join-Path $modulesPath $legacy
            if (Test-Path -LiteralPath $legacyPath -PathType Container) {
                Remove-Item -LiteralPath $legacyPath -Recurse -Force -ErrorAction Stop
            }
        }
        Write-OSDCloudPostSetting -Path (Join-Path $scriptsPath 'OSDCloudPost.json')
        Write-OSDCloudSetupMenuScript -Path (Join-Path $scriptsPath 'OOBE.cmd') -Phase OOBE
        Write-OSDCloudSetupMenuScript -Path (Join-Path $scriptsPath 'SetupComplete.cmd') -Phase SetupComplete
        Write-OSDCloudSetupCompleteScript -Path (Join-Path $scriptsPath 'SetupComplete.cmd')
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -Format s)] [INFO] Staged the OSDCloudPost module with its PreOOBE launch in OOBE.cmd and its SetupComplete.cmd invocation."
    }
    catch {
        Write-Warning "[$(Get-Date -Format s)] OSDCloudPost staging failed: $($_.Exception.Message)"
    }
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] End"
}

function Save-OSDCloudPostModule {
    <#
    .SYNOPSIS
        Copies the standalone OSDCloudPost module into the applied Windows image

    .DESCRIPTION
        Validates required source files and PowerShell syntax, copies the entire
        module folder, and stamps the destination manifest with the parent OSDCloud
        version. Validates the staged manifest without importing or running tasks.

    .PARAMETER SourcePath
        Source OSDCloudPost module directory inside the OSDCloud package.

    .PARAMETER DestinationPath
        Applied Windows module directory, normally under Windows\Setup\Modules.

    .EXAMPLE
        PS> Save-OSDCloudPostModule -SourcePath $source -DestinationPath $destination

        Copies and validates the module before installing the setup hooks.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.1.0
        Date:    2026-11-23

        Never imports or executes the runtime. Copy and validation errors terminate.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Stage module"
    foreach ($relativePath in 'OSDCloudPost.psd1', 'OSDCloudPost.psm1',
        'public\Invoke-OSDCloudPreOOBE.ps1', 'public\Invoke-OSDCloudSetupComplete.ps1',
        'private\Get-OSDCloudPostSetting.ps1', 'private\OSDCloudPreOOBE.ps1',
        'private\Invoke-OSDCloudPreOOBEDriverPack.ps1', 'private\Show-OSDCloudPreOOBEWindow.ps1',
        'private\OSDCloudSetupComplete.ps1') {
        if (-not (Test-Path -LiteralPath (Join-Path $SourcePath $relativePath) -PathType Leaf)) {
            throw "OSDCloudPost module component is missing: $relativePath"
        }
    }
    $sourceManifest = Join-Path $SourcePath 'OSDCloudPost.psd1'
    Test-ModuleManifest -Path $sourceManifest -ErrorAction Stop | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $SourcePath -Recurse -File -ErrorAction Stop |
        Where-Object Extension -In '.ps1', '.psm1') {
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) { throw "OSDCloudPost parsing failed in $($file.Name): $($parseErrors.Message -join '; ')" }
    }
    $parentManifest = Join-Path $SourcePath '..\..\..\OSDCloud.psd1'
    $version = [string](Import-PowerShellDataFile -LiteralPath $parentManifest -ErrorAction Stop).ModuleVersion
    if ($version -notmatch '^\d+(\.\d+){1,3}$') { throw "Invalid OSDCloud module version: $version" }
    [void][version]::Parse($version)
    $manifestText = Get-Content -LiteralPath $sourceManifest -Raw -ErrorAction Stop
    $versionPattern = "(?m)^(\s*ModuleVersion\s*=\s*)'[^']+'"
    if ([regex]::Matches($manifestText, $versionPattern).Count -ne 1) {
        throw 'OSDCloudPost manifest must contain exactly one ModuleVersion assignment.'
    }
    $manifestText = [regex]::Replace($manifestText, $versionPattern,
        [Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + "'$version'" })
    New-Item -Path $DestinationPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction Stop |
        Copy-Item -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
    $destinationManifest = Join-Path $DestinationPath 'OSDCloudPost.psd1'
    [IO.File]::WriteAllText($destinationManifest, $manifestText, [Text.UTF8Encoding]::new($false))
    Test-ModuleManifest -Path $destinationManifest -ErrorAction Stop | Out-Null
}

function Write-OSDCloudPostSetting {
    <#
    .SYNOPSIS
        Writes the deployment's OSDCloud Post selections for the first-boot runtime.
    .DESCRIPTION
        Saves which PreOOBE Windows Update tasks start checked. Values come from
        the OSDCloudDeploy selections; a missing value means checked.
    .PARAMETER Path
        Destination OSDCloudPost.json path. Its parent directory must exist.
    .EXAMPLE
        Write-OSDCloudPostSetting -Path 'C:\Windows\Setup\Scripts\OSDCloudPost.json'
    .NOTES
        Used by the WinPE staging step. Write errors terminate.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$Path)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Write $Path"
    $deploy = $global:OSDCloudDeploy
    $os = if ($null -eq $deploy -or $null -eq $deploy.PreOOBEWindowsUpdateOS) { $true } else { [bool]$deploy.PreOOBEWindowsUpdateOS }
    $drivers = if ($null -eq $deploy -or $null -eq $deploy.PreOOBEWindowsUpdateDrivers) { $true } else { [bool]$deploy.PreOOBEWindowsUpdateDrivers }
    $json = [ordered]@{
        Version = 1
        PreOOBE = [ordered]@{ WindowsUpdateOS = $os; WindowsUpdateDrivers = $drivers }
    } | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Write-OSDCloudSetupMenuScript {
    <#
    .SYNOPSIS
        Appends the OOBE menu or removes a legacy SetupComplete invocation.
    .DESCRIPTION
        Removes previously managed menu blocks, then appends exactly one OOBE
        invocation. SetupComplete is cleanup-only. Other bytes remain unchanged.
    .PARAMETER Path
        Destination OOBE.cmd or SetupComplete.cmd.
    .PARAMETER Phase
        OOBE appends the menu; SetupComplete removes only a previously managed block.
    .EXAMPLE
        Write-OSDCloudSetupMenuScript -Path 'C:\Windows\Setup\Scripts\OOBE.cmd' -Phase OOBE
    .NOTES
        Used by the WinPE staging step; never runs the destination script.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('OOBE', 'SetupComplete')][string]$Phase
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Update $Phase menu block in $Path"
    # Latin-1 maps bytes one-to-one, preserving the original body during block removal.
    $byteEncoding = [Text.Encoding]::GetEncoding(28591)
    $existing = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $byteEncoding.GetString([IO.File]::ReadAllBytes($Path))
    } else { '' }
    $identities = @("$Phase Menu")
    if ($Phase -eq 'OOBE') { $identities += 'PreOOBE' }
    foreach ($identity in $identities) {
        $marker = ":: RecastOSDCloud $identity"
        $endMarker = ":: End RecastOSDCloud $identity"
        $pattern = '(?ms)^' + [regex]::Escape($marker) + '\r?\n.*?^' + [regex]::Escape($endMarker) + '(?:\r?\n|$)'
        $existing = [regex]::Replace($existing, $pattern, '')
        if ($existing -match ('(?m)^' + [regex]::Escape($marker) + '\r?$')) {
            throw "Incomplete managed menu block in $Path. Repair its end marker before staging."
        }
    }
    if ($Phase -eq 'SetupComplete') {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $original = [IO.File]::ReadAllBytes($Path)
            if ($existing -ne $byteEncoding.GetString($original)) {
                [IO.File]::WriteAllBytes($Path, $byteEncoding.GetBytes($existing))
            }
        }
        return
    }
    if ($existing -match '(?im)^\s*@?(?:exit(?:\s|$)|goto\s+:?eof(?:\s|$))') {
        Write-Warning "OOBE.cmd contains an early exit. The appended menu runs only if the original commands reach the end: $Path"
    }
    $block = @'
:: RecastOSDCloud PreOOBE
set "OSDCloudOOBEPowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "OSDCloudOOBEPowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%OSDCloudOOBEPowerShell%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -Command "try { Import-Module -Name (Join-Path $env:SystemRoot 'Setup\Modules\OSDCloudPost\OSDCloudPost.psd1') -ErrorAction Stop; exit (OSDCloudPreOOBE) } catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; exit 1 }"
set "OSDCloudOOBEExitCode=%ERRORLEVEL%"
if not "%OSDCloudOOBEExitCode%"=="0" echo OSDCloudPreOOBE failed with exit code %OSDCloudOOBEExitCode%. Continuing Windows Setup.
if not "%OSDCloudOOBEExitCode%"=="0" if not exist "%SystemRoot%\Temp\osdcloud-logs" mkdir "%SystemRoot%\Temp\osdcloud-logs"
if not "%OSDCloudOOBEExitCode%"=="0" echo [%DATE% %TIME%] PreOOBE invocation failed with exit code %OSDCloudOOBEExitCode%.>>"%SystemRoot%\Temp\osdcloud-logs\OSDCloudPreOOBE.log"
set "OSDCloudOOBEPowerShell="
set "OSDCloudOOBEExitCode="
:: End RecastOSDCloud PreOOBE
'@
    $suffix = ($block -replace '\r?\n', "`r`n") + "`r`n"
    if ($existing -and -not $existing.EndsWith("`n")) { $existing += "`r`n" }
    $output = [IO.MemoryStream]::new()
    try {
        $suffixBytes = [Text.Encoding]::ASCII.GetBytes($suffix)
        $bodyBytes = $byteEncoding.GetBytes($existing)
        $output.Write($bodyBytes, 0, $bodyBytes.Length)
        $output.Write($suffixBytes, 0, $suffixBytes.Length)
        [IO.File]::WriteAllBytes($Path, $output.ToArray())
    }
    finally { $output.Dispose() }
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
"%OSDCloudSetupCompletePowerShell%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "try { Import-Module -Name (Join-Path $env:SystemRoot 'Setup\Modules\OSDCloudPost\OSDCloudPost.psd1') -ErrorAction Stop; exit (Invoke-OSDCloudSetupComplete) } catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; exit 1 }"
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
