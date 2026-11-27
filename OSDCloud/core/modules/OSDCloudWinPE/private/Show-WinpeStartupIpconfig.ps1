<#
.SYNOPSIS
    Displays IP configuration details in WinPE.

.DESCRIPTION
    Runs ipconfig /all to display network adapter and addressing details.
    This function is typically used during WinpeStartup troubleshooting.

.EXAMPLE
    Show-WinpeStartupIpconfig

    Displays full adapter and IP configuration details.

.OUTPUTS
    System.Void

.NOTES
    This function is intended for WinPE diagnostics.
    Output is provided by the native ipconfig utility.

.LINK
    ipconfig
#>
function Show-WinpeStartupIpconfig {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $host.ui.RawUI.WindowTitle = "[$(Get-Date -format s)] OSDCloud - IPConfig - Network Configuration"
    #=================================================
    Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] ipconfig /all"
    ipconfig /all
    #=================================================
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
