function Invoke-OSDCloudSetupComplete {
    <#
    .SYNOPSIS
        Runs configured SetupComplete scripts without a GUI

    .DESCRIPTION
        Requires SYSTEM in full Windows using Windows PowerShell 5.1.
        Searches immediate package folders under SystemRoot\Setup\SetupComplete,
        then A: through Z: under OSDCloud\post\SetupComplete, sorted by folder name
        within each root. Requires OSDCloudSetupComplete.json in each package.

        Runs enabled matching scripts sequentially in noninteractive child processes.
        The script root and working directory are the package folder, or its
        retained local copy when CopyToLocal is enabled. Continues after failures.
        Logs diagnostics and child output under SystemRoot\Temp\osdcloud-logs.
        Every invocation runs eligible packages again. Never reboots or exits
        the caller. Importing the module does not run scripts.

    .EXAMPLE
        PS> Invoke-OSDCloudSetupComplete

        Runs all eligible packages synchronously as SYSTEM.

    .EXAMPLE
        PS> $status = Invoke-OSDCloudSetupComplete -Verbose

        Captures the overall status while displaying verbose diagnostics.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Int32. Zero when no failures occurred, otherwise one. Child exit
        3010 is successful with a logged reboot requirement, not an automatic reboot.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
        Standalone; does not require the parent OSDCloud module or PowerShell 7.
        Packages are trusted SYSTEM code, not sandboxed. Scripts must be silent,
        wait for their own work, and throw or exit nonzero on failure.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $mutex = $null
    $acquired = $false
    $status = 0
    $count = 0
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-OSDCloudSetupCompleteContext
        $mutex = [Threading.Mutex]::new($false, 'Global\RecastOSDCloud.SetupComplete')
        try { $acquired = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] {
            $acquired = $true
            Write-OSDCloudSetupCompleteLog -Message 'Recovered abandoned SetupComplete execution mutex.'
        }
        if (-not $acquired) { throw 'OSDCloudSetupComplete is already running.' }
        $run = [guid]::NewGuid().ToString('N')
        Write-OSDCloudSetupCompleteLog -Message "Run $run started; module=$script:OSDCloudSetupCompleteVersion"
        $context = @{}
        foreach ($root in Get-OSDCloudSetupCompleteRoot) {
            try {
                if (-not (Test-Path -LiteralPath $root -PathType Container -ErrorAction Stop)) { continue }
                Write-OSDCloudSetupCompleteLog -Message "Discovering packages in $root"
                foreach ($folder in Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop | Sort-Object Name) {
                    try {
                        if (-not (Test-Path -LiteralPath (Join-Path $folder.FullName 'OSDCloudSetupComplete.json') -ErrorAction Stop)) {
                            Write-OSDCloudSetupCompleteLog -Message "Skipped folder without configuration: $($folder.FullName)"
                            continue
                        }
                        $package = Read-OSDCloudSetupCompleteManifest -Folder $folder.FullName -Context $context
                        if (-not $package) { continue }
                        $count++
                        $code = Invoke-OSDCloudSetupCompletePackage -Package $package
                        if ($code -notin 0,3010) { $status = 1 }
                    }
                    catch {
                        $status = 1
                        $message = "Package failed in $($folder.FullName): $($_.Exception.Message)"
                        Write-Warning -Message $message
                        Write-OSDCloudSetupCompleteLog -Message $message
                    }
                }
            }
            catch {
                $status = 1
                $message = "Discovery failed in $root`: $($_.Exception.Message)"
                Write-Warning -Message $message
                Write-OSDCloudSetupCompleteLog -Message $message
            }
        }
        Write-OSDCloudSetupCompleteLog -Message "Run $run completed; packages=$count; status=$status; elapsed=$($watch.Elapsed)"
        return $status
    }
    catch {
        $message = "SetupComplete failed: $($_.Exception.Message)"
        Write-Error -Message $message -ErrorAction Continue
        if ($acquired) {
            try { Write-OSDCloudSetupCompleteLog -Message $message }
            catch { Write-Error -Message "SetupComplete logging failed: $($_.Exception.Message)" -ErrorAction Continue }
        }
        return 1
    }
    finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        if ($mutex) { $mutex.Dispose() }
    }
}
