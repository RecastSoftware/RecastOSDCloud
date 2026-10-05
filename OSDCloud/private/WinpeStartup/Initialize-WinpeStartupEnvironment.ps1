#requires -Version 5.1

function Initialize-WinPEStartupEnvironment {
    <#
    .SYNOPSIS
        Initializes the WinPE shell environment for OS deployment

    .DESCRIPTION
        Creates required shell profile folders, sets process-level environment
        variables, and writes registry keys needed by Windows PE before any
        PowerShell modules or deployment scripts run.

        This function is the PowerShell equivalent of the environment-setup
        section in startnet.cmd / ReStartnet.cmd and should be called early
        in the WinPE boot sequence.

        Actions performed:
          - Creates shell profile directories under SystemDrive
          - Sets APPDATA, HOMEDRIVE, HOMEPATH, LOCALAPPDATA, USERPROFILE
          - Writes the USERDATA registry value to the Session Manager Environment key
          - Sets the PowerShell execution policy to Bypass via registry

    .EXAMPLE
        Initialize-WinPEStartupEnvironment

        Creates all shell folders, sets environment variables, and writes
        registry keys for the current WinPE session.

    .EXAMPLE
        Initialize-WinPEStartupEnvironment -Verbose

        Runs the full environment initialization with detailed progress output.

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
            Write-Warning 'Initialize-WinPEStartupEnvironment: Not running in WinPE (SystemDrive is not X:). Exiting.'
            $skipExecution = $true
            return
        }

        Write-Verbose 'Initialize-WinPEStartupEnvironment: Starting WinPE environment initialization'

        $systemDrive = $env:SystemDrive
        $profileRoot = Join-Path -Path $systemDrive -ChildPath 'windows\system32\config\systemprofile'
    }

    process {
        if ($skipExecution) { return }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Initialize WinPEStartup"
        # ── Shell Folders ───────────────────────────────────────────────
        $shellFolders = @(
            Join-Path -Path $systemDrive -ChildPath 'Program Files\WindowsPowerShell\Scripts'
            Join-Path -Path $profileRoot -ChildPath 'AppData\Local'
            Join-Path -Path $profileRoot -ChildPath 'AppData\Roaming'
            Join-Path -Path $profileRoot -ChildPath 'Desktop'
            Join-Path -Path $profileRoot -ChildPath 'Documents\WindowsPowerShell'
            Join-Path -Path $systemDrive -ChildPath 'windows\system32\WindowsPowerShell\v1.0\Scripts'
        )

        foreach ($folder in $shellFolders) {
            New-Item -Path $folder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            # Write-Verbose "Created folder: $folder"
        }

        # ── Environment Variables (process scope) ───────────────────────
        $env:APPDATA      = Join-Path -Path $profileRoot -ChildPath 'AppData\Roaming'
        $env:HOMEDRIVE    = $systemDrive
        $env:HOMEPATH     = '\windows\system32\config\systemprofile'
        $env:LOCALAPPDATA = Join-Path -Path $profileRoot -ChildPath 'AppData\Local'
        $env:USERPROFILE  = $profileRoot

        Write-Verbose "Set APPDATA      = $env:APPDATA"
        Write-Verbose "Set HOMEDRIVE    = $env:HOMEDRIVE"
        Write-Verbose "Set HOMEPATH     = $env:HOMEPATH"
        Write-Verbose "Set LOCALAPPDATA = $env:LOCALAPPDATA"
        Write-Verbose "Set USERPROFILE  = $env:USERPROFILE"

        # ── Registry: USERDATA environment variable ─────────────────────
        $userDataPath  = Join-Path -Path $systemDrive -ChildPath 'Windows\System32\Config\SystemProfile'
        $envRegKeyPath = 'HKLM:\SYSTEM\ControlSet001\Control\Session Manager\Environment'

        Set-ItemProperty -Path $envRegKeyPath -Name 'USERDATA' -Value $userDataPath -Type String -Force
        Write-Verbose "Set registry USERDATA = $userDataPath"

        # ── Registry: PowerShell execution policy ───────────────────────
        $psRegKeyPath = 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'

        Set-ItemProperty -Path $psRegKeyPath -Name 'ExecutionPolicy' -Value 'Bypass' -Type String -Force
        Write-Verbose 'Set registry ExecutionPolicy = Bypass'
    }

    end {
        if ($skipExecution) { return }
        Write-Verbose 'Initialize-WinPEStartupEnvironment: Complete'
    }
}
