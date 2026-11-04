function Invoke-OSDCloudPreOOBE {
    <#
    .SYNOPSIS
        Runs technician tasks before Windows OOBE continues

    .DESCRIPTION
        Displays the standalone PreOOBE window using inbox Windows PowerShell 5.1
        and WPF on AMD64 or ARM64. Normal execution requires SYSTEM and an STA
        thread. If necessary, imports this module in a visible SYSTEM child process.

        Waits for the technician to select Start before running OEM drivers, time
        synchronization, Windows updates, driver updates, and selected custom
        applications. Waits for Continue to OOBE after completion; never reboots.
        Closing the window safely skips remaining tasks. Importing the module
        does not start the runtime.

    .PARAMETER Preview
        Simulates tasks and tools without network access, installations, clock
        changes, or SYSTEM tool launches. Writes diagnostics and results to TEMP.

    .PARAMETER InteractiveChild
        Internal SYSTEM desktop-launch flag. Requires ReadyEvent; not for manual use.

    .PARAMETER ReadyEvent
        Internal SYSTEM-only readiness event. Requires InteractiveChild and a name
        matching Global\RecastOSDCloud.OOBE.<GUID>.

    .EXAMPLE
        PS> Invoke-OSDCloudPreOOBE

        Runs synchronously as SYSTEM during Windows Setup.

    .EXAMPLE
        PS> OSDCloudPreOOBE -Preview

        Uses the launch alias for an inert local-console preview.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Int32. Returns zero on normal closure, one on startup failure, or
        the interactive child process exit code. Does not exit the calling host.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-03

        Requires inbox Windows PowerShell 5.1 with -STA. Does not require the
        parent OSDCloud module, downloaded tools, or an interactive user logon.
        Alias: OSDCloudPreOOBE.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [switch]$Preview,
        [Parameter(DontShow)][switch]$InteractiveChild,
        [Parameter(DontShow)]
        [ValidatePattern('^Global\\RecastOSDCloud\.OOBE\.[0-9a-f-]{36}$')]
        [string]$ReadyEvent
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start"
    if ($script:OSDCloudPreOOBERunning) {
        Write-Error -Message 'OSDCloudPreOOBE is already running in this module instance.' -ErrorAction Continue
        return 1
    }
    $script:OSDCloudPreOOBERunning = $true
    $script:Preview = [bool]$Preview
    $script:InteractiveChild = [bool]$InteractiveChild
    $script:ReadyEvent = $ReadyEvent
    try {
        return Invoke-OOBEMenu -ModulePath $script:OSDCloudPreOOBEModulePath
    }
    finally {
        $script:Preview = $false
        $script:InteractiveChild = $false
        $script:ReadyEvent = $null
        $script:OSDCloudPreOOBERunning = $false
    }
}
