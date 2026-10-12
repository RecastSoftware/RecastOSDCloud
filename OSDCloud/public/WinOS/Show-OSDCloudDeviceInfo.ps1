<#
.SYNOPSIS
Displays comprehensive WinPE and device hardware information during OS deployment startup.

.DESCRIPTION
Displays detailed hardware and environment information from the initialized OSDCoreDevice snapshot in Windows PE including system specifications, device identifiers, processor details, memory configuration, disk drives, and network adapters. Initialize-OSDCoreDevice owns hardware collection and diagnostic exports. Validates system memory requirements and provides warnings if minimum specifications are not met. If initialization fails, warns and displays unavailable inventory without querying hardware independently.

.PARAMETER None
This function does not accept any parameters.

.EXAMPLE
Show-OSDCloudDeviceInfo
Runs Show-OSDCloudDeviceInfo to display comprehensive WinPE and device information including hardware specifications and device identifiers.

.OUTPUTS
None. This function displays system information to the console but does not return objects.

.NOTES
This function is designed for use in Windows PE startup environments and performs the following operations:

Information Displayed:
- OSDCloud PowerShell Module version
- WinPE version, architecture, and computer name
- Device manufacturer and model
- BIOS information
- Processor name and logical core count
- Total physical memory in GB, configured speed (or reported speed), and DIMM count
- Disk drive device IDs, sizes in whole decimal GB, and models
- Network adapter MAC addresses followed by names and bracketed assigned IPv4 addresses

Note: Serial number and UUID output are suppressed for privacy reasons.

System Requirements:
- Minimum 6 GB of physical memory recommended
- Issues warning if memory is less than 6 GB

Log Files Created by Initialize-OSDCoreDevice:
- Stores device information in $env:TEMP\osdcloud-logs directory
- Win32_DiskDrive.txt: Complete disk drive information
- Win32_NetworkAdapter.txt: Complete network adapter information
- Win32_PhysicalMemory.txt: Complete installed memory module information

External Functions:
- Get-OSDCloudModuleVersion: Retrieves the loaded OSDCloud module version.
- Initialize-OSDCoreDevice: Collects device hardware details and populates
  $global:OSDCoreDevice.

PowerShell cmdlets used:
- Get-Date, Write-Host, Write-Verbose, and Write-Warning: Display operation
  status, device information, and recoverable errors.

The function updates the window title to '[OSDCloud] - WinPE and Device Information' to indicate the current operation status.
#>
function Show-OSDCloudDeviceInfo {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $commandName = $MyInvocation.MyCommand.Name
    $deviceInfo = $null
    $deviceInitialized = $false

    Write-Verbose "[$(Get-Date -format s)] [$commandName] Start: preparing to display WinPE and device information."

    try {
        try {
            $host.ui.RawUI.WindowTitle = "[$(Get-Date -format s)] OSDCloud WinPE and Device Information"
            Write-Verbose "[$(Get-Date -format s)] [$commandName] Updated the console window title."
        }
        catch {
            Write-Warning -WarningAction Continue "[$(Get-Date -format s)] [$commandName] Unable to update the console window title: $($_.Exception.Message)"
        }

        $OSDCloudModuleVersion = 'Unavailable'
        try {
            Write-Verbose "[$(Get-Date -format s)] [$commandName] Retrieving the loaded OSDCloud module version."
            $moduleVersion = Get-OSDCloudModuleVersion -ErrorAction Stop
            if ($null -ne $moduleVersion) {
                $OSDCloudModuleVersion = $moduleVersion.ToString()
                Write-Verbose "[$(Get-Date -format s)] [$commandName] Retrieved OSDCloud module version $OSDCloudModuleVersion."
            }
            else {
                Write-Warning -WarningAction Continue "[$(Get-Date -format s)] [$commandName] The OSDCloud module version was not available."
            }
        }
        catch {
            Write-Warning -WarningAction Continue "[$(Get-Date -format s)] [$commandName] Unable to retrieve the OSDCloud module version: $($_.Exception.Message)"
        }
        Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] OSDCloud PowerShell Module $OSDCloudModuleVersion"

        try {
            Write-Verbose "[$(Get-Date -format s)] [$commandName] Initializing the OSDCore device inventory."
            Initialize-OSDCoreDevice -ErrorAction Stop | Out-Null
            if ($null -eq $global:OSDCoreDevice) {
                throw 'OSDCore device initialization did not produce a device inventory.'
            }
            $deviceInfo = $global:OSDCoreDevice
            $deviceInitialized = $true
            Write-Verbose "[$(Get-Date -format s)] [$commandName] OSDCore device inventory initialization completed."
        }
        catch {
            Write-Warning -WarningAction Continue "[$(Get-Date -format s)] [$commandName] Unable to initialize the OSDCore device inventory: $($_.Exception.Message)"
        }

        foreach ($item in $deviceInfo.NetworkAdapters) {
            if ($null -ne $item.GUID) {
                $ipv4Display = if ($item.IPv4Addresses.Count -gt 0) { " [$($item.IPv4Addresses -join ', ')]" } else { '' }
                Write-Host -ForegroundColor DarkGray "NetAdapter $($item.MACAddress): $($item.Name)$ipv4Display"
            }
        }

        $winPEVersion = if ($null -ne $deviceInfo) { $deviceInfo.OSVersion } else { 'Unavailable' }
        $osArchitecture = if ($null -ne $deviceInfo) { $deviceInfo.NativeOSArchitecture } else { 'Unavailable' }
        $computerName = if ($null -ne $deviceInfo) { $deviceInfo.ComputerName } else { 'Unavailable' }
        Write-Verbose "[$(Get-Date -format s)] [$commandName] Displaying operating system and device identity information."
        Write-Host -ForegroundColor DarkGray "Host: $computerName | $winPEVersion $osArchitecture"

        if ($deviceInitialized -and $null -ne $deviceInfo) {
            Write-Host -ForegroundColor DarkGray "Device: $($deviceInfo.OSDManufacturer) | $($deviceInfo.OSDProduct) | $($deviceInfo.OSDModel)"
            Write-Host -ForegroundColor DarkGray "BIOS: $($deviceInfo.BiosVersion) | $($deviceInfo.BiosReleaseDate)"
        }
        else {
            Write-Verbose "[$(Get-Date -format s)] [$commandName] Skipping device identity display because the OSDCore device inventory is unavailable."
        }

        foreach ($item in $deviceInfo.Processors) {
            Write-Host -ForegroundColor DarkGray "Processor: $($item.Name) | $($item.NumberOfLogicalProcessors) Logical"
        }

        if ($null -ne $deviceInfo -and $null -ne $deviceInfo.TotalPhysicalMemory) {
            $totalMemoryGB = [math]::Round($deviceInfo.TotalPhysicalMemory / 1GB)
            $memoryModules = @($deviceInfo.PhysicalMemory | Where-Object { $null -ne $_ })
            $memorySpeeds = @($memoryModules | ForEach-Object {
                if ($_.ConfiguredClockSpeed -gt 0) { $_.ConfiguredClockSpeed }
                elseif ($_.Speed -gt 0) { $_.Speed }
            } | Sort-Object -Unique)
            $memorySpeedDisplay = if ($memorySpeeds.Count -gt 0) { "$($memorySpeeds -join ', ') MHz" } else { 'Speed unavailable' }
            $dimmDisplay = if ($memoryModules.Count -eq 1) { '1 DIMM' } elseif ($memoryModules.Count -gt 1) { "$($memoryModules.Count) DIMMs" } else { 'DIMM count unavailable' }
            Write-Host -ForegroundColor DarkGray "Memory: $totalMemoryGB GB Total | $dimmDisplay at $memorySpeedDisplay"
            Write-Verbose "[$(Get-Date -format s)] [$commandName] Reported $totalMemoryGB GB of physical memory."
            if ($totalMemoryGB -lt 6) {
                Write-Warning -WarningAction Continue "OSDCloud WinPE requires at least 6 GB of memory to function properly. Errors are expected."
            }
        }
        else {
            Write-Warning -WarningAction Continue "[$(Get-Date -format s)] [$commandName] Physical memory information is unavailable."
        }

        foreach ($item in $deviceInfo.DiskDrives) {
            $diskSizeDisplay = if ($null -ne $item.Size) { "$([math]::Round($item.Size / 1000000000))GB" } else { 'Size unavailable' }
            Write-Host -ForegroundColor DarkGray "Disk:  $($item.DeviceID) | $diskSizeDisplay $($item.Model)"
        }
    }
    catch {
        Write-Warning -WarningAction Continue "[$(Get-Date -format s)] [$commandName] An unexpected error interrupted device information display: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "[$(Get-Date -format s)] [$commandName] End: device information display finished."
    }
}
