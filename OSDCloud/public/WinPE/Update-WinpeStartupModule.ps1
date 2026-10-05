<#
.SYNOPSIS
    Updates a PowerShell module from the PowerShell Gallery.

.DESCRIPTION
    Installs the latest version of a specified PowerShell module by using
    Install-Module with AllUsers scope, then imports the module with Force.
    A short countdown is displayed before installation begins.

.PARAMETER Name
    Specifies the module name to install or update.

.EXAMPLE
    Update-WinPEStartupModule -Name OSDCloud

    Installs or updates the OSDCloud module and imports it.

.EXAMPLE
    Update-WinPEStartupModule -Name PSDiskPart

    Installs or updates the PSDiskPart module after the countdown.

.OUTPUTS
    System.Void

.NOTES
    This function is intended for WinPEStartup workflows.
    Installation uses AllUsers scope, Force, and SkipPublisherCheck.
#>
function Update-WinPEStartupModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Name
    )
    #=================================================
    $Error.Clear()
    $host.ui.RawUI.WindowTitle = "[$(Get-Date -format s)] OSDCloud - Update PowerShell Module: $Name (close this window to cancel)"
    #=================================================
    Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] Update PowerShell Module: $Name"
    Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] Close this window to cancel (starting in 10 seconds)"
    Start-Sleep -Seconds 10
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $Name $($GalleryPSModule.Version) [AllUsers]"
    Install-Module $Name -Scope AllUsers -Force -SkipPublisherCheck
    Import-Module $Name -Force
    #=================================================
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
