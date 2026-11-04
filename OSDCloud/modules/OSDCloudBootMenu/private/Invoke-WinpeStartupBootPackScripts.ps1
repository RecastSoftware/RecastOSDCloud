#requires -Version 5.1

function Expand-WinpeStartupBootPack {
    <#
    .SYNOPSIS
        Expands OSDCloud Import Packs in WinPE.

    .DESCRIPTION
        Finds Pack folders (bootpack.cab and bootpack.json) directly below Path and expands
        each Import Pack with expand.exe to <Destination>\<Prefix><id>. An existing expansion
        folder for the same id is replaced. The sidecar and embedded manifests are validated,
        must have the same id, and every manifest item must exist after expansion.

        Expanded Import Packs use the WinpeStartup asset layout: *.env at the root,
        winpe-reg\*.reg, winpe-root-cer\*.cer, and scripts\*.cmd or scripts\*.ps1.
        Invalid, Build, or failed Packs warn and are skipped.

        Requires a valid Recast license (Test-WinpeStartupAssetLicense). Without one, or
        when not running in WinPE, nothing is expanded and nothing is returned.

    .PARAMETER Path
        Folder that contains one subfolder per Pack, such as X:\OSDCloud\boot-packs.

    .PARAMETER Destination
        Folder that receives the expanded Pack folders.

    .PARAMETER Prefix
        Prefix for each expanded Pack folder name. The default is no prefix.

    .PARAMETER SystemDrive
        System drive captured by the caller. Defaults to the current SystemDrive.

    .EXAMPLE
        Expand-WinpeStartupBootPack -Path 'X:\OSDCloud\boot-packs' -Destination 'X:\WinpeStartup\core' -Prefix 'bootpack-'

        Expands build-level Import Packs into WinpeStartup Core asset folders.

    .OUTPUTS
        System.String. Returns the expanded Pack folder paths in Pack folder name order.

    .NOTES
        Requires WinPE and expand.exe.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter()]
        [string]$Prefix = '',

        [Parameter()]
        [string]$SystemDrive = $env:SystemDrive
    )

    if ($SystemDrive -ne 'X:') { return }
    if (-not (Test-WinpeStartupAssetLicense)) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $packFolders = @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bootpack.cab') -PathType Leaf } |
            Sort-Object Name)
    if ($packFolders.Count -eq 0) { return }

    foreach ($packFolder in $packFolders) {
        try {
            $sidecarPath = Join-Path $packFolder.FullName 'bootpack.json'
            Assert-OSDCloudBootPackManifest -Path $sidecarPath
            $sidecar = Get-Content -LiteralPath $sidecarPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($sidecar.type -ne 'Import') { throw "Pack '$($sidecar.info.name)' is not an Import Pack." }

            $packId = ([guid]$sidecar.info.id).ToString()
            $expandPath = Join-Path $Destination "$Prefix$packId"
            if (Test-Path -LiteralPath $expandPath) { Remove-Item -LiteralPath $expandPath -Recurse -Force -ErrorAction Stop }
            $null = New-Item -ItemType Directory -Path $expandPath -Force -ErrorAction Stop

            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] Expanding Import Pack '$($sidecar.info.name)' to $expandPath"
            $cabPath = Join-Path $packFolder.FullName 'bootpack.cab'
            $null = & expand.exe "$cabPath" -F:* "$expandPath" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "expand.exe exited with code $LASTEXITCODE." }

            $manifestPath = Join-Path $expandPath 'bootpack.json'
            Assert-OSDCloudBootPackManifest -Path $manifestPath
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (([guid]$manifest.info.id).ToString() -ne $packId -or $manifest.type -ne 'Import') {
                throw 'The cab manifest does not match bootpack.json.'
            }
            foreach ($item in @($manifest.items)) {
                if (-not (Test-Path -LiteralPath (Join-Path $expandPath ($item.source -replace '/', '\')) -PathType Leaf)) {
                    throw "Item '$($item.source)' is missing from the cab."
                }
            }
            $expandPath
        }
        catch {
            Write-Warning "Expand-WinpeStartupBootPack: Skipping Pack '$($packFolder.FullName)': $($_.Exception.Message)"
            if ($expandPath -and (Test-Path -LiteralPath $expandPath)) {
                Remove-Item -LiteralPath $expandPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        finally {
            $expandPath = $null
        }
    }
}

function Invoke-WinpeStartupBootPackScripts {
    <#
    .SYNOPSIS
        Runs Execute scripts from expanded OSDCloud Import Packs.

    .DESCRIPTION
        Reads bootpack.json in each expanded Pack folder and runs Script items whose action
        is Execute, in Pack order and then manifest order. .cmd files run with cmd.exe /c.
        .ps1 files run with Windows PowerShell using -NoProfile -ExecutionPolicy Bypass -File.
        Each script runs with its folder as the working directory and must exit before the
        next script starts. Script items with action Copy are left in the scripts folder.
        Missing scripts, failures, and non-zero exit codes warn and continue.

    .PARAMETER Path
        Expanded Pack folders returned by Expand-WinpeStartupBootPack. An empty list is allowed.

    .EXAMPLE
        Invoke-WinpeStartupBootPackScripts -Path 'X:\OSDCloud\bootpack-expanded\0c7df66a-7f10-474c-976c-a4586b76633e'

        Runs the Execute scripts from the expanded Pack.

    .OUTPUTS
        None.

    .NOTES
        Requires WinPE with cmd.exe and Windows PowerShell.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Path
    )

    foreach ($packPath in @($Path | Where-Object { $_ })) {
        try {
            $manifest = Get-Content -LiteralPath (Join-Path $packPath 'bootpack.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Warning "Invoke-WinpeStartupBootPackScripts: Failed to read the manifest in '$packPath'."
            continue
        }
        foreach ($item in @($manifest.items | Where-Object { $_.kind -eq 'Script' -and $_.action -eq 'Execute' })) {
            $scriptPath = Join-Path $packPath ($item.source -replace '/', '\')
            if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                Write-Warning "Invoke-WinpeStartupBootPackScripts: Script not found: $scriptPath"
                continue
            }
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] Running Import Pack script '$($manifest.info.name)': $($item.source)"
            try {
                $startParameters = @{
                    WorkingDirectory = Split-Path -Path $scriptPath -Parent
                    NoNewWindow      = $true
                    Wait             = $true
                    PassThru         = $true
                    ErrorAction      = 'Stop'
                }
                if ($scriptPath -like '*.cmd') {
                    $startParameters.FilePath = Join-Path $env:SystemRoot 'System32\cmd.exe'
                    $startParameters.ArgumentList = "/c `"`"$scriptPath`"`""
                }
                else {
                    $startParameters.FilePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
                    $startParameters.ArgumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
                }
                $process = Start-Process @startParameters
                if ($process.ExitCode -ne 0) {
                    Write-Warning "Invoke-WinpeStartupBootPackScripts: '$($item.source)' exited with code $($process.ExitCode)."
                }
            }
            catch {
                Write-Warning "Invoke-WinpeStartupBootPackScripts: Failed to run '$scriptPath': $($_.Exception.Message)"
            }
        }
    }
}
