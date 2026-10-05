function Show-WinPEStartupDevices {
    <#
    .SYNOPSIS
        Displays WinPE Plug and Play device inventory.

    .DESCRIPTION
        Queries Win32_PnPEntity and displays device class, status, IDs,
        and manufacturer details in table format. Also copies the source
        query command to the clipboard for reuse.

    .EXAMPLE
        Show-WinPEStartupDevices

        Displays Plug and Play hardware information in WinPE.

    .OUTPUTS
        System.Void

    .NOTES
        This function is intended for WinPE diagnostics.
    #>
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $host.ui.RawUI.WindowTitle = "[$(Get-Date -format s)] OSDCloud - WinPE Device Hardware"
    #=================================================
    $Results = Get-CimInstance -ClassName Win32_PnPEntity | Select-Object PNPClass, Status, DeviceID, Name, Manufacturer | Sort-Object PNPClass, DeviceID

    if ($Results) {
        Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] WinPE Device Hardware"
        $Command = "Get-CimInstance -ClassName Win32_PnPEntity | Select-Object PNPClass, Status, DeviceID, Name, Manufacturer | Sort-Object PNPClass, DeviceID"
        Write-Host -ForegroundColor DarkGray $Command
        Set-Clipboard -Value $Command
        Write-Output $Results | Format-Table
        <#
        $USBDrive = Get-DeviceUSBVolume | Where-Object { ($_.FileSystemLabel -match "OSDCloud|USB-DATA") } | Where-Object { $_.SizeGB -ge 16 } | Where-Object { $_.SizeRemainingGB -ge 10 } | Select-Object -First 1
        if ($USBDrive) {
            [System.String]$SerialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber.Trim()
            $USBPath = "$($USBDrive.DriveLetter):\OSDCloudLogs\$SerialNumber\PEStartup"
            if (-not (Test-Path -Path $USBPath)) {
                New-Item -Path $USBPath -ItemType Directory -Force | Out-Null
            }
            $Results | Export-clixml -Path "$USBPath\Hardware.xml" -Force
            $Results | Convertto-Json -Depth 10 | Out-File "$USBPath\Hardware.json" -Force -Encoding UTF8
        }
        #>
    }
    else {
        exit 0
    }
    #=================================================
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
