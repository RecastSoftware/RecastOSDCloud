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
        $source = Join-Path $PSScriptRoot '..\..\..\core\oobe\OSDCloudPreOOBE.ps1'
        $scriptsPath = 'C:\Windows\Setup\Scripts'
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "OOBE menu source is missing: $source"
        }
        if (-not (Test-Path -LiteralPath 'C:\Windows\System32\Config\SYSTEM' -PathType Leaf)) {
            throw 'The applied Windows image is missing; cannot stage the OOBE menu.'
        }
        New-Item -Path $scriptsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Save-OSDCloudPreOOBERuntime -SourcePath $source -DestinationPath (Join-Path $scriptsPath 'OSDCloudPreOOBE.ps1')
        Write-OSDCloudSetupMenuScript -Path (Join-Path $scriptsPath 'OOBE.cmd') -Phase OOBE
        Write-OSDCloudSetupMenuScript -Path (Join-Path $scriptsPath 'SetupComplete.cmd') -Phase SetupComplete
        Write-Host -ForegroundColor DarkGray '[INFO] Staged OSDCloudPreOOBE at the end of OOBE.cmd; removed any legacy SetupComplete menu invocation.'
    }
    catch {
        Write-Warning "[$(Get-Date -Format s)] PreOOBE staging failed: $($_.Exception.Message)"
    }
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] End"
}

function Save-OSDCloudPreOOBERuntime {
        <#
        .SYNOPSIS
            Bundles the runtime components into one standalone setup script.
        .DESCRIPTION
            Validates the exact loader marker and parses the assembled source before writing.
        .PARAMETER SourcePath
            Source runtime in the module.
        .PARAMETER DestinationPath
            Applied Windows setup script destination.
        .EXAMPLE
            Save-OSDCloudPreOOBERuntime -SourcePath $source -DestinationPath $destination
        .NOTES
            Does not import or execute the runtime.
        #>
        [CmdletBinding()]
        param ([Parameter(Mandatory)][string]$SourcePath, [Parameter(Mandatory)][string]$DestinationPath)
        $Error.Clear()
        Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Bundle runtime"
        $content = Get-Content -LiteralPath $SourcePath -Raw -ErrorAction Stop
        $components = foreach ($name in 'Invoke-OSDCloudPreOOBEDriverPack.ps1','Show-OSDCloudPreOOBEWindow.ps1') {
            Get-Content -LiteralPath (Join-Path (Split-Path $SourcePath) $name) -Raw -ErrorAction Stop
        }
        $loader = '(?ms)^#region PreOOBE components\r?\n.*?^#endregion'
        if ([regex]::Matches($content, $loader).Count -ne 1) { throw 'PreOOBE component loader was not found exactly once.' }
        $bundle = [regex]::Replace($content, $loader, [Text.RegularExpressions.MatchEvaluator]{ param($match) $components -join "`r`n" })
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($bundle, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) { throw "PreOOBE bundle parsing failed: $($parseErrors.Message -join '; ')" }
        [IO.File]::WriteAllText($DestinationPath, $bundle, [Text.UTF8Encoding]::new($false))
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
"%OSDCloudOOBEPowerShell%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%SystemRoot%\Setup\Scripts\OSDCloudPreOOBE.ps1"
set "OSDCloudOOBEExitCode=%ERRORLEVEL%"
if not "%OSDCloudOOBEExitCode%"=="0" echo OSDCloudPreOOBE failed with exit code %OSDCloudOOBEExitCode%. Continuing Windows Setup.
if not "%OSDCloudOOBEExitCode%"=="0" if not exist "%SystemRoot%\Temp\osdcloud-logs" mkdir "%SystemRoot%\Temp\osdcloud-logs"
if not "%OSDCloudOOBEExitCode%"=="0" echo [%DATE% %TIME%] PreOOBE invocation failed with exit code %OSDCloudOOBEExitCode%.>>"%SystemRoot%\Temp\osdcloud-logs\OSDCloudPreOOBE.log"
set "OSDCloudOOBEPowerShell="
set "OSDCloudOOBEExitCode="
:: End RecastOSDCloud PreOOBE
'@
    $suffix = (($block -f $Phase) -replace '\r?\n', "`r`n") + "`r`n"
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
