#requires -Version 5.1

function Initialize-WinPEStartupDrivers {
    <#
    .SYNOPSIS
        Loads drivers from $WinPEDriver$ folders found on any attached drive

    .DESCRIPTION
        Scans every available drive letter for a $WinPEDriver$ folder. When
        found, recursively discovers all .inf files and loads each one using
        drvload.exe. Multiple drives can contribute drivers; all matches are
        processed.

        This is the PowerShell equivalent of the $WinPEDriver$ driver-loading
        loop in startnet.cmd / ReStartnet.cmd.

    .PARAMETER SubfolderPath
        The relative subfolder path to search for on each drive. Defaults
        to 'WinPEStartup\Drivers'.

    .EXAMPLE
        Initialize-WinPEStartupDrivers

        Scans all drive letters and loads every .inf found under $WinPEDriver$.

    .EXAMPLE
        Initialize-WinPEStartupDrivers -SubfolderPath 'MyDrivers'

        Scans all drive letters for a subfolder path MyDrivers instead of
        the default WinPEStartup\Drivers.

    .EXAMPLE
        Initialize-WinPEStartupDrivers -Verbose

        Loads drivers with detailed progress showing each drive and .inf file.

    .NOTES
        Author:  David Segura
        Module:  OSDCloud
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SubfolderPath = 'WinPEStartup\Drivers'
    )

    begin {
        $skipExecution = $false
        if ($env:SystemDrive -ne 'X:') {
            Write-Warning 'Initialize-WinPEStartupDrivers: Not running in WinPE (SystemDrive is not X:). Exiting.'
            $skipExecution = $true
            return
        }

        Write-Verbose 'Initialize-WinPEStartupDrivers: Starting driver scan'
    }

    process {
        if ($skipExecution) { return }
        $driveLetters = [char[]](67..90)  # C through Z

        foreach ($letter in $driveLetters) {
            $driverFolder = '{0}:\{1}' -f $letter, $SubfolderPath

            if (Test-Path -Path $driverFolder -PathType Container) {
                Write-Verbose "Found driver folder: $driverFolder"

                $infFiles = Get-ChildItem -Path $driverFolder -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer }

                if (-not $infFiles) {
                    Write-Verbose "No .inf files found in $driverFolder"
                    continue
                }
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Drivers: $driverFolder"

                foreach ($inf in $infFiles) {
                    # Write-Verbose "Loading driver: $($inf.FullName)"
                    Invoke-DrvLoad -InfPath $inf.FullName
                }
            }
        }
    }

    end {
        if ($skipExecution) { return }
        Write-Verbose 'Initialize-WinPEStartupDrivers: Complete'
    }
}
