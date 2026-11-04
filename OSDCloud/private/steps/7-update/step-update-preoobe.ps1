function step-update-preoobe {
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    if ($env:SystemDrive -ne 'X:' -or -not $global:OSDCoreDevice.IsWinPE) {
        Write-Warning 'OOBE menu staging is only supported in WinPE; no files were changed.'
        return
    }
    try {
        $source = Join-Path $PSScriptRoot '..\..\..\modules\OSDCloudPreOOBE'
        $scriptsPath = 'C:\Windows\Setup\Scripts'
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "PreOOBE module source is missing: $source"
        }
        if (-not (Test-Path -LiteralPath 'C:\Windows\System32\Config\SYSTEM' -PathType Leaf)) {
            throw 'The applied Windows image is missing; cannot stage the OOBE menu.'
        }
        New-Item -Path $scriptsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Save-OSDCloudPreOOBEModule -SourcePath $source -DestinationPath 'C:\Windows\Setup\Modules\OSDCloudPreOOBE'
        Write-OSDCloudSetupMenuScript -Path (Join-Path $scriptsPath 'OOBE.cmd') -Phase OOBE
        Write-OSDCloudSetupMenuScript -Path (Join-Path $scriptsPath 'SetupComplete.cmd') -Phase SetupComplete
        Write-Host -ForegroundColor DarkGray '[INFO] Staged the OSDCloudPreOOBE module and appended its launch to OOBE.cmd; removed any legacy SetupComplete menu invocation.'
    }
    catch {
        Write-Warning "[$(Get-Date -Format s)] PreOOBE staging failed: $($_.Exception.Message)"
    }
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] End"
}

function Save-OSDCloudPreOOBEModule {
    <#
    .SYNOPSIS
        Copies the standalone PreOOBE module into the applied Windows image

    .DESCRIPTION
        Validates required source files and PowerShell syntax, copies the entire
        module folder, and stamps the destination manifest with the parent OSDCloud
        version. Validates the staged manifest without importing or running tasks.

    .PARAMETER SourcePath
        Source OSDCloudPreOOBE module directory inside the OSDCloud package.

    .PARAMETER DestinationPath
        Applied Windows module directory, normally under Windows\Setup\Modules.

    .EXAMPLE
        PS> Save-OSDCloudPreOOBEModule -SourcePath $source -DestinationPath $destination

        Copies and validates the module before installing an OOBE hook.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-03

        Never imports or executes the runtime. Copy and validation errors terminate.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Stage module"
    foreach ($relativePath in 'OSDCloudPreOOBE.psd1', 'OSDCloudPreOOBE.psm1',
        'public\Invoke-OSDCloudPreOOBE.ps1', 'private\OSDCloudPreOOBE.ps1',
        'private\Invoke-OSDCloudPreOOBEDriverPack.ps1', 'private\Show-OSDCloudPreOOBEWindow.ps1') {
        if (-not (Test-Path -LiteralPath (Join-Path $SourcePath $relativePath) -PathType Leaf)) {
            throw "PreOOBE module component is missing: $relativePath"
        }
    }
    $sourceManifest = Join-Path $SourcePath 'OSDCloudPreOOBE.psd1'
    Test-ModuleManifest -Path $sourceManifest -ErrorAction Stop | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $SourcePath -Recurse -File -ErrorAction Stop |
        Where-Object Extension -In '.ps1', '.psm1') {
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) { throw "PreOOBE parsing failed in $($file.Name): $($parseErrors.Message -join '; ')" }
    }
    $parentManifest = Join-Path $SourcePath '..\..\OSDCloud.psd1'
    $version = [string](Import-PowerShellDataFile -LiteralPath $parentManifest -ErrorAction Stop).ModuleVersion
    if ($version -notmatch '^\d+(\.\d+){1,3}$') { throw "Invalid OSDCloud module version: $version" }
    [void][version]::Parse($version)
    $manifestText = Get-Content -LiteralPath $sourceManifest -Raw -ErrorAction Stop
    $versionPattern = "(?m)^(\s*ModuleVersion\s*=\s*)'[^']+'"
    if ([regex]::Matches($manifestText, $versionPattern).Count -ne 1) {
        throw 'PreOOBE manifest must contain exactly one ModuleVersion assignment.'
    }
    $manifestText = [regex]::Replace($manifestText, $versionPattern,
        [Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + "'$version'" })
    New-Item -Path $DestinationPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction Stop |
        Copy-Item -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
    $destinationManifest = Join-Path $DestinationPath 'OSDCloudPreOOBE.psd1'
    [IO.File]::WriteAllText($destinationManifest, $manifestText, [Text.UTF8Encoding]::new($false))
    Test-ModuleManifest -Path $destinationManifest -ErrorAction Stop | Out-Null
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
"%OSDCloudOOBEPowerShell%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -Command "try { Import-Module -Name (Join-Path $env:SystemRoot 'Setup\Modules\OSDCloudPreOOBE\OSDCloudPreOOBE.psd1') -ErrorAction Stop; exit (OSDCloudPreOOBE) } catch { Write-Error -ErrorRecord $_ -ErrorAction Continue; exit 1 }"
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
