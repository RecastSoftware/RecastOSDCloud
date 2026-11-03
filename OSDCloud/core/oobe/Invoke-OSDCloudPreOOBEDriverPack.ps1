function Invoke-OSDCloudPreOOBEDriverPack {
    <#
    .SYNOPSIS
        Installs the explicitly staged Lenovo or Surface driver pack.
    .DESCRIPTION
        Validates manifest, package size and hash. Logs native process results.
        Never restarts Windows or kills an active installer.
    .PARAMETER State
        Shared task progress and reboot state.
    .PARAMETER ManifestPath
        Staged package manifest, not an arbitrary command list.
    .EXAMPLE
        Invoke-OSDCloudPreOOBEDriverPack -State $state
    .NOTES
        Requires SYSTEM in full Windows. Failed artifacts are retained.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][hashtable]$State,
        [string]$ManifestPath = (Join-Path $env:WINDIR 'Setup\Scripts\OSDCloudPreOOBE.DriverPack.json')
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $State.Succeeded = $false
    try {
        if ($env:SystemDrive -eq 'X:' -or -not (Get-OOBEMenuContext).IsSystem) {
            throw 'PreOOBE driver installation requires SYSTEM in full Windows.'
        }
        if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
            $State.Outcome = 'NotApplicable'
            Write-OOBEMenuUpdateStatus -State $State -Message 'No staged Lenovo/Surface driver task.'
            return
        }
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($manifest.Version -ne 1 -or $manifest.Manufacturer -notin 'Lenovo','Microsoft' -or
            $manifest.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$manifest.Size -le 0) {
            throw 'Invalid PreOOBE driver manifest schema.'
        }
        $root = [IO.Path]::GetFullPath((Join-Path $env:WINDIR 'Temp\osdcloud-driverpack-download')) + '\'
        $package = [IO.Path]::GetFullPath([string]$manifest.PackagePath)
        if (-not $package.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($package) -ne $manifest.FileName -or $package -match '["\r\n]') {
            throw 'Driver package must be an explicitly staged local file.'
        }
        $extension = if ($manifest.Manufacturer -eq 'Lenovo') { '.exe' } else { '.msi' }
        if ([IO.Path]::GetExtension($package) -ne $extension) { throw 'Driver package extension does not match manufacturer.' }
        $file = Get-Item -LiteralPath $package -ErrorAction Stop
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Driver package cannot be a reparse point.' }
        if ($file.Length -ne [long]$manifest.Size -or
            (Get-FileHash -LiteralPath $package -Algorithm SHA256 -ErrorAction Stop).Hash -ne $manifest.Sha256) {
            throw 'Staged driver package size or SHA-256 does not match.'
        }
        Write-OOBEMenuUpdateStatus -State $State -Message "Validated $($manifest.Manufacturer) package: $package; $($file.Length) bytes; SHA256 $($manifest.Sha256)."
        if ($State.CancelRequested) { $State.Outcome = 'Cancelled'; return }
        $logs = Join-Path $env:WINDIR 'Temp\osdcloud-logs'
        [void][IO.Directory]::CreateDirectory($logs)
        $runId = [guid]::NewGuid().ToString('N')
        $runProcess = {
            param ([string]$Executable, [string]$Arguments, [string]$Label)
            $output = Join-Path $logs "PreOOBE-$runId-$Label.stdout.log"
            $errors = Join-Path $logs "PreOOBE-$runId-$Label.stderr.log"
            Write-OOBEMenuUpdateStatus -State $State -Message "Starting $Label`: $Executable $Arguments; output $output; errors $errors."
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -PassThru -NoNewWindow `
                -RedirectStandardOutput $output -RedirectStandardError $errors -ErrorAction Stop
            try {
                Write-OOBEMenuUpdateStatus -State $State -Message "$Label PID $($process.Id); waiting for safe completion."
                $process.WaitForExit()
                $code = $process.ExitCode
                foreach ($path in $output,$errors) {
                    if (Test-Path -LiteralPath $path -PathType Leaf) {
                        Get-Content -LiteralPath $path -ErrorAction Stop | ForEach-Object {
                            if ($_ -ne '') { Write-OOBEMenuUpdateStatus -State $State -Message "$Label`: $_" }
                        }
                        $State.InstallationActive = $true
                    }
                }
                Write-OOBEMenuUpdateStatus -State $State -Message "$Label exit $code; duration $($watch.ElapsedMilliseconds) ms."
                if ($code -eq 3010) { $State.RebootRequired = $true }
                elseif ($code -ne 0) { throw "$Label failed with exit code $code." }
            }
            finally { $process.Dispose() }
        }
        $native = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { 'Sysnative' } else { 'System32' }
        if ($manifest.Manufacturer -eq 'Microsoft') {
            $msiLog = Join-Path $logs "PreOOBE-$runId-Surface.msi.log"
            & $runProcess (Join-Path $env:WINDIR "$native\msiexec.exe") "/i `"$package`" /qn /norestart /l*v `"$msiLog`"" 'Surface'
        }
        else {
            $expand = Join-Path $env:SystemDrive 'Drivers'
            if (Test-Path -LiteralPath $expand) {
                throw "Lenovo extraction destination already exists: $expand. Refusing to mix staged drivers with existing content."
            }
            & $runProcess $package '/SILENT /SUPPRESSMSGBOXES /NORESTART' 'LenovoExtract'
            $infs = @(Get-ChildItem -LiteralPath $expand -Filter '*.inf' -Recurse -File -ErrorAction Stop)
            if ($infs.Count -eq 0) { throw "Lenovo extraction produced no INF files in $expand." }
            Write-OOBEMenuUpdateStatus -State $State -Message "Installing $($infs.Count) extracted INF files from $expand."
            & $runProcess (Join-Path $env:WINDIR "$native\pnputil.exe") "/add-driver `"$expand\*.inf`" /subdirs /install" 'LenovoInstall'
            Write-OOBEMenuUpdateStatus -State $State -Message "Retaining extracted drivers for diagnostics: $expand."
        }
        $State.Succeeded = $true
        $State.Outcome = 'Succeeded'
    }
    catch {
        $State.Outcome = 'Failed'
        Write-OOBEMenuLog -Message "Driver unpack/install failed: $($_.Exception.ToString())"
        Write-OOBEMenuUpdateStatus -State $State -Message "Driver unpack/install failed: $(Get-OSDCloudPreOOBEErrorMessage -Exception $_.Exception) Staged artifacts retained."
    }
    finally { $State.InstallationActive = $false }
}
