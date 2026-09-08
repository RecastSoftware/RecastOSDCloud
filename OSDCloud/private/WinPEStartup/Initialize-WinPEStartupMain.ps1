#requires -Version 5.1

function Initialize-WinPEStartupMain {
    <#
    .SYNOPSIS
        Runs wpeinit and wpeutil to initialize the WinPE environment

    .DESCRIPTION
        Executes wpeinit.exe for hardware initialization, then runs
        wpeutil DisableFirewall and wpeutil UpdateBootInfo. This is the
        PowerShell equivalent of the wpeinit/wpeutil block in
        startnet.cmd / ReStartnet.cmd.

    .EXAMPLE
        Initialize-WinPEStartupMain

        Runs wpeinit and wpeutil initialization commands.

    .EXAMPLE
        Initialize-WinPEStartupMain -Verbose

        Runs initialization with detailed progress output.

    .NOTES
        Author:  David Segura
        Module:  OSDCloud
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    begin {
        $skipExecution = $false
        if ($env:SystemDrive -ne 'X:') {
            Write-Warning 'Initialize-WinPEStartupMain: Not running in WinPE (SystemDrive is not X:). Exiting.'
            $skipExecution = $true
            return
        }

        Write-Verbose 'Initialize-WinPEStartupMain: Starting'
    }

    process {
        if ($skipExecution) { return }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Initialize wpeinit"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Initialize wpeutil"
        Write-Verbose 'Running wpeinit.exe'
        Invoke-WpeInit
        Start-Sleep -Seconds 2 # Wait for wpeinit to complete before running wpeutil commands

        Write-Verbose 'Running wpeutil DisableFirewall'
        Invoke-WpeUtil -Command 'DisableFirewall'
        Start-Sleep -Seconds 2 # Wait for wpeutil DisableFirewall to complete before running wpeutil UpdateBootInfo

        Write-Verbose 'Running wpeutil UpdateBootInfo'
        Invoke-WpeUtil -Command 'UpdateBootInfo'
        Start-Sleep -Seconds 2 # Wait for wpeutil UpdateBootInfo to complete before proceeding

        # Reassign USB drive letters to the next available letter starting at H.
        Write-Verbose 'Running Set-WinPEStartupUSBDriveLetter'
        Set-WinPEStartupUSBDriveLetter
        Start-Sleep -Seconds 2 # Wait for Set-WinPEStartupUSBDriveLetter to complete before proceeding

        Write-Verbose 'Running wpeutil UpdateBootInfo'
        Invoke-WpeUtil -Command 'UpdateBootInfo'
        Start-Sleep -Seconds 2 # Wait for Set-WinPEStartupUSBDriveLetter to complete before proceeding

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Initialize network"
        ipconfig /release | Out-Null
        ipconfig /renew  | Out-Null

        # Open a new powershell session minimized with no logo
        Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoLogo', '-WindowStyle', 'Minimized'
    }

    end {
        if ($skipExecution) { return }
        Write-Verbose 'Initialize-WinPEStartupMain: Complete'
    }
}
