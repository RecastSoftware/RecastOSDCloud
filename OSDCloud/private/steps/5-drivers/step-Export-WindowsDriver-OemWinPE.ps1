function step-Export-WindowsDriver-OemWinPE {
    [CmdletBinding()]
    param ()
    #=================================================
    # Start the step
    $Message = "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    Write-Debug -Message $Message; Write-Verbose -Message $Message
    # Get the configuration of the step
    $Step = $global:OSDCloudCurrentStep
    #=================================================
    # Output Path
    $OutputPath = "C:\Windows\Temp\osdcloud-drivers-winpe"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OutputPath: $OutputPath"
    if (-not (Test-Path -Path $OutputPath)) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating output path: $OutputPath"
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    $LogPath = "C:\Windows\Temp\osdcloud-logs"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] LogPath: $LogPath"
    if (-not (Test-Path -Path $LogPath)) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating log path: $LogPath"
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    #=================================================
    # Build the list of devices using pnputil.exe, as the /format xml switch is not supported in older versions of WinPE.
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running pnputil.exe /enum-devices /connected"
    $output = & pnputil.exe /enum-devices /connected
    $devices = @()
    $currentDevice = @{}
    foreach ($line in $output) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            # Blank line means end of current device
            if ($currentDevice.Count -gt 0) {
                $devices += [PSCustomObject]$currentDevice
                $currentDevice = @{}
            }
        }
        elseif ($line -like "*:*") {
            # Parse key-value pair
            $key, $value = $line -split ':\s*', 2
            $key = $key.Trim() -replace '\s+', '' # Remove spaces from key
            $value = $value.Trim()
            $currentDevice[$key] = $value
        }
    }
    # Add last device if exists
    if ($currentDevice.Count -gt 0) {
        $devices += [PSCustomObject]$currentDevice
    }
    $PnputilDevices = $devices | Where-Object { $_.DriverName -match 'oem' } | Sort-Object DriverName -Unique | Sort-Object ClassName
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OEM pnputil device count: $(@($PnputilDevices).Count)"

    # Classes to Export
    $ExportClass = @(
        '1394',
        'DiskDrive',
        'HDC',
        'HIDClass',
        'Keyboard',
        'Mouse',
        'MTD',
        'Multifunction',
        'Net',
        'NvmeDisk',
        'SCSIAdapter',
        'Securitydevices',
        'System',
        'Volume',
        'USB',
        'USBDevice'
    )
    #=================================================
    # Export OEM Drivers
    if ($PnputilDevices) {
        foreach ($OemDriver in $PnputilDevices) {
            #=================================================
            # Normalize Manufacturer Name
            $ManufacturerName = $OemDriver.ManufacturerName -as [string]
            if ([string]::IsNullOrWhiteSpace($ManufacturerName)) {
                $ManufacturerName = 'Unknown'
            }
            $ManufacturerName = $ManufacturerName.Trim()
            if ($ManufacturerName -match 'Dell' -or $OemDriver.Description -match 'Dell') {
                $ManufacturerName = 'Dell'
            }
            if ($ManufacturerName -match 'HP' -or $OemDriver.Description -match 'HP') {
                $ManufacturerName = 'HP'
            }
            if ($ManufacturerName -match 'Intel' -or $OemDriver.Description -match 'Intel' -or $OemDriver.InstanceID -match 'VEN_8086') {
                $ManufacturerName = 'Intel'
            }
            if ($ManufacturerName -match 'Logitech' -or $OemDriver.Description -match 'Logitech' -or $OemDriver.InstanceID -match 'VID_046D') {
                $ManufacturerName = 'Logitech'
            }
            if ($ManufacturerName -match 'Qualcomm|Snapdragon' -or $OemDriver.Description -match 'Qualcomm|Snapdragon' -or $OemDriver.InstanceID -match 'QCOM') {
                $ManufacturerName = 'Qualcomm'
            }
            if ($ManufacturerName -match 'Realtek' -or $OemDriver.Description -match 'Realtek' -or $OemDriver.InstanceID -match 'VEN_10EC') {
                $ManufacturerName = 'Realtek'
            }
            #=================================================
            # Normalize Foldername
            $FolderName = $OemDriver.DeviceDescription -replace '[\\/:*?"<>|#]', ''
            $FolderName = $FolderName -replace [regex]::Escape($ManufacturerName), ''
            $FolderName = $FolderName -replace '\(standard system devices\)', ''
            $FolderName = [regex]::Replace($FolderName, '\s*\(.*?\)\s*', ' ')
            $FolderName = [regex]::Replace($FolderName, '\s+', ' ')
            $FolderName = $FolderName.Trim()
            #=================================================
            # Export WinPE Drivers
            if ($ExportClass -notcontains $OemDriver.ClassName) {
                Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Skipping class $($OemDriver.ClassName) because it is not in ExportClass."
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] [$($OemDriver.ClassName)] $ManufacturerName $($OemDriver.DeviceDescription)"
                continue
            }
            Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [$($OemDriver.ClassName)] $ManufacturerName $($OemDriver.DeviceDescription)"
            $ExportPath = "$OutputPath\$($OemDriver.ClassName)\$($ManufacturerName) $($FolderName)"
            if (-not (Test-Path -Path $ExportPath)) {
                Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating export path: $ExportPath"
                New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
            }
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Exporting driver $($OemDriver.DriverName) to $ExportPath"
            $null = & pnputil.exe /export-driver $OemDriver.DriverName $ExportPath
            #=================================================
        }
        $PnputilDevices | Out-File -FilePath "$OutputPath\pnputil.txt" -Encoding utf8
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No OEM pnputil devices were found to export."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
