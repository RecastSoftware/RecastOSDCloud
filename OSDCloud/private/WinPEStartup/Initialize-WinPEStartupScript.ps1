#requires -Version 5.1

function Initialize-WinPEStartupScript {
    <#
    .SYNOPSIS
        Executes startup scripts found on attached drives

    .DESCRIPTION
        Scans every available drive letter for a scripts subfolder. When found,
        looks for files matching the FileName pattern with .cmd or .ps1
        extensions. CMD scripts are executed synchronously with cmd.exe.
        PS1 scripts are executed in the current process by default. Use
        -NewProcess to launch them in a separate PowerShell window.

        This is the PowerShell equivalent of the main.cmd / main.ps1 /
        main-noexit.ps1 execution loops in startnet.cmd / ReStartnet.cmd.

    .PARAMETER SubfolderPath
        The relative subfolder path to search for on each drive. Defaults
        to 'WinPEStartup\scripts'.

    .PARAMETER FileName
        The file name pattern to match. Defaults to 'startnet.cmd'. Only .cmd
        and .ps1 files are executed.

    .PARAMETER NoExit
        When specified, PowerShell scripts are started with -NoExit so
        the window remains open after the script completes. Only applies
        when -NewProcess is specified.

    .PARAMETER NewProcess
        When specified, PowerShell scripts are launched in a new
        PowerShell window using Start-Process instead of executing in
        the current process.

    .EXAMPLE
        Initialize-WinPEStartupScript

        Scans all drives for WinPEStartup\scripts\startnet.cmd.

    .EXAMPLE
        Initialize-WinPEStartupScript -NoExit

        Same as above but PowerShell scripts keep the window open.

    .EXAMPLE
        Initialize-WinPEStartupScript -NewProcess

        Launches discovered PowerShell scripts in a new window.

    .EXAMPLE
        Initialize-WinPEStartupScript -FileName 'setup.*' -SubfolderPath 'MyScripts'

        Scans all drives for MyScripts\setup.cmd and setup.ps1.

    .NOTES
        Author:  David Segura
        Module:  OSDCloud
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SubfolderPath = 'WinPEStartup\scripts',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName = 'startnet.cmd',

        [Parameter(Mandatory = $false)]
        [switch]$NoExit,

        [Parameter(Mandatory = $false)]
        [switch]$NewProcess
    )

    begin {
        $skipExecution = $false
        if ($env:SystemDrive -ne 'X:') {
            Write-Warning 'Initialize-WinPEStartupScript: Not running in WinPE (SystemDrive is not X:). Exiting.'
            $skipExecution = $true
            return
        }

        Write-Verbose 'Initialize-WinPEStartupScript: Starting script scan'
    }

    process {
        if ($skipExecution) { return }
        $driveLetters = [char[]](67..90)  # C through Z

        foreach ($letter in $driveLetters) {
            $scriptFolder = '{0}:\{1}' -f $letter, $SubfolderPath

            if (-not (Test-Path -Path $scriptFolder -PathType Container)) {
                continue
            }

            Write-Verbose "Found script folder: $scriptFolder"

            $scriptFiles = Get-ChildItem -Path $scriptFolder -Filter $FileName -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer -and ($_.Extension -eq '.cmd' -or $_.Extension -eq '.ps1') }

            if (-not $scriptFiles) {
                Write-Verbose "No matching script files found in $scriptFolder"
                continue
            }

            foreach ($scriptFile in $scriptFiles) {
                switch ($scriptFile.Extension) {
                    '.cmd' {
                        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Script: $($scriptFile.FullName)"
                        Write-Verbose "Executing CMD script: $($scriptFile.FullName)"
                        Invoke-CmdScript -ScriptPath $scriptFile.FullName
                    }
                    '.ps1' {
                        if ($NewProcess -and $NoExit) {
                            $action = 'Start PowerShell script (NoExit)'
                        }
                        elseif ($NewProcess) {
                            $action = 'Start PowerShell script'
                        }
                        else {
                            $action = 'Execute PowerShell script in process'
                        }
                        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Script: $($scriptFile.FullName)"
                        Write-Verbose "Executing PowerShell script: $($scriptFile.FullName)"
                        if ($NewProcess -and $NoExit) {
                            Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoExit', '-NoLogo', '-File', $scriptFile.FullName -Wait
                        }
                        elseif ($NewProcess) {
                            Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoLogo', '-File', $scriptFile.FullName -Wait
                        }
                        else {
                            & $scriptFile.FullName
                        }
                    }
                }
            }
        }
    }

    end {
        if ($skipExecution) { return }
        Write-Verbose 'Initialize-WinPEStartupScript: Complete'
    }
}
