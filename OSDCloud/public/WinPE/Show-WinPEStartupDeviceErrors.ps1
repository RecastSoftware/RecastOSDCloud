function Show-WinPEStartupDeviceErrors {
    <#
    .SYNOPSIS
        Displays WinPE Plug and Play device errors.

    .DESCRIPTION
        Queries Win32_PnPEntity and shows devices where status is not OK.
        The function writes a short warning that the window will close,
        displays results in table format, waits 5 seconds, then exits.

    .EXAMPLE
        Show-WinPEStartupDeviceErrors

        Displays detected device errors during WinPEStartup.

    .OUTPUTS
        System.Void

    .NOTES
        This function is intended for WinPE diagnostics.
        The command exits the host process after displaying results.
    #>
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $host.ui.RawUI.WindowTitle = "[$(Get-Date -format s)] OSDCloud - WinPE Device Hardware Errors (automatically close in 5 seconds)"
    #=================================================
    $Results = Get-CimInstance -ClassName Win32_PnPEntity | Select-Object Status, PNPClass, DeviceID, Name, Manufacturer | Where-Object Status -ne 'OK' | Sort-Object PNPClass, DeviceID

    if ($Results) {
        Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] WinPE Device Hardware Errors"
        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] This window will automatically close in 5 seconds"
        Write-Output $Results | Format-Table

        <#
        $USBDrive = Get-DeviceUSBVolume | Where-Object { ($_.FileSystemLabel -match "OSDCloud|USB-DATA") } | Where-Object { $_.SizeGB -ge 16 } | Where-Object { $_.SizeRemainingGB -ge 10 } | Select-Object -First 1
        if ($USBDrive) {
            [System.String]$SerialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber.Trim()
            $USBPath = "$($USBDrive.DriveLetter):\OSDCloudLogs\$SerialNumber\PEStartup"
            if (-not (Test-Path -Path $USBPath)) {
                New-Item -Path $USBPath -ItemType Directory -Force | Out-Null
            }
            $Results | Export-clixml -Path "$USBPath\HardwareErrors.xml" -Force
            $Results | Convertto-Json -Depth 10 | Out-File "$USBPath\HardwareErrors.json" -Force -Encoding UTF8
        }
        #>

        Start-Sleep -Seconds 5
    }
    exit 0
    #=================================================
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
