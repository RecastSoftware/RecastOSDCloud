function Initialize-OSDCoreDevice {
    <#
    .SYNOPSIS
        Initializes the OSDCore device inventory and diagnostics context.

    .DESCRIPTION
        Initialize-OSDCoreDevice collects local hardware, firmware, TPM, keyboard,
        disk, USB cache, and network information from CIM, environment variables,
        and UEFI checks. It creates diagnostic artifacts in
        $env:TEMP\osdcloud-logs, clears stale OSDCoreDevice snapshot files before
        collection, normalizes key identity values such as
        manufacturer/model/product, and builds $global:OSDCoreDevice as an
        ordered property bag used by deployment and workflow orchestration
        functions.

        OSDCloud environment values can override the reported OSD manufacturer,
        model, product, OS architecture, and processor architecture. The device
        snapshot includes the raw SMBIOS UUID and EndpointSHA, a SHA256 hash used by
        downstream telemetry callers when a stable privacy-preserving identifier
        is needed.

        The function is intended for internal module initialization and is called
        before workflow execution so downstream steps can rely on a consistent
        device state snapshot.

    .EXAMPLE
    Initialize-OSDCoreDevice

        Collects current device metadata, creates or updates
        $global:OSDCoreDevice, removes stale device snapshot files, and writes
        current log artifacts for troubleshooting.


    .EXAMPLE
    Initialize-OSDCoreDevice -Verbose

        Runs initialization and emits additional details about discovered disks,
        network adapters, keyboard selection, and support checks.

    .INPUTS
    None. You cannot pipe input to this function.

    .OUTPUTS
    None. This function does not emit pipeline output.

    .NOTES
        Side effects:
        - Clears the current PowerShell error collection.
        - Attempts to sync date/time (best effort) through Sync-OSDCoreDateTime.
                - Removes stale OSDCoreDevice.xml and OSDCoreDevice.json files from
                    $env:TEMP\osdcloud-logs before collecting a new snapshot.
                - Writes diagnostic logs and current device snapshots to
                    $env:TEMP\osdcloud-logs.
        - Attempts to stage logs in an OSDCloudLogs destination when available.
        - Updates global state in $global:OSDCoreDevice.

        Changelog:
        - 2026-08-13 | pending | Add OSDeploy identity and license properties.
            Added nullable idOSDeployDevice, idRegisteredEmail, and idRegisteredLicense values
            from WinPE environment variables or local license discovery.
        - 2026-08-13 | pending | Add EndpointSHA and clear stale device snapshot files.
            Removed existing OSDCoreDevice output files before collecting device state
            and added EndpointSHA as a SHA256 hash of the device UUID.
        - 2026-08-12 | pending | Infer AutoOSLanguageCode from keyboard layout.
            Used Convert-KeyboardLayoutToLanguageCode with the detected KeyboardLayout
            to populate AutoOSLanguageCode in the OSDCoreDevice snapshot.
        - 2026-08-12 | pending | Move DeploymentDisk selection to deployment initialization.
            Removed deployment disk target selection from device inventory so
            Initialize-DeployOSDCloud selects the deployment disk from LocalDisk.
        - 2026-08-11 | pending | Populate local disk inventory in OSDCoreDevice.
            Assigned filtered online local disk, partition, and volume objects before
            exporting the device snapshot.
        - 2026-08-11 | pending | Populate USB disk inventory in OSDCoreDevice.
            Assigned filtered online USB disk objects to USBDisk before exporting
            the device snapshot.
        - 2026-08-06 | pending | Export OSDCoreDevice CLIXML to TEMP.
            Added Export-Clixml output to $env:TEMP\OSDCoreDevice.xml so
            callers and support workflows can consume a typed device snapshot.
        - 2026-08-05 | pending | Report unknown values for empty identity fields.
            Normalized OSDManufacturer, OSDModel, and OSDProduct values written
            to OSDCoreDevice so null/whitespace values are emitted as Unknown.
        - 2026-08-05 | pending | Resolve OS catalog provider selection overwrite.
            Replaced unconditional dual assignment of OSDCoreOperatingSystems with
            command-aware selection logic that uses the available provider function
            and throws a descriptive error when neither provider is present.
        - 2026-08-05 | ef3e4fb | Core catalog initialization wiring update.
            Integrated initializer into the broader core startup path and aligned
            device state dependencies for downstream catalog and workflow logic.
        - 2026-08-04 | 538d747 | Initial OSDCoreDevice initializer introduced.
            Added core CIM collection, log export pipeline, normalization helpers,
            and baseline global property map for workflow consumers.

        Maintainer guidance:
        - Add a new changelog entry in this NOTES section for every functional
            behavior change in this function.
        - Keep entries in reverse chronological order using this format:
            YYYY-MM-DD | <short-hash> | <summary>
    #>
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    # Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] [$($MyInvocation.MyCommand.Name)]"
    #=================================================
    try {
        Sync-OSDCoreDateTime -ThresholdMinutes 5 -Force -ErrorAction Stop
    }
    catch {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to sync date/time: $($_.Exception.Message)"
    }
    #=================================================
    # Set the osdcloud-logs Path
    $LogsPath = "$env:TEMP\osdcloud-logs"
    if (-not (Test-Path -Path $LogsPath)) {
        New-Item -Path $LogsPath -ItemType Directory -Force | Out-Null
    }
    #=================================================
    # Real Architecture
    $ProcessorArchitecture = $env:PROCESSOR_ARCHITECTURE
    #=================================================
    # ipconfig
    ipconfig | Out-File (Join-Path -Path $LogsPath -ChildPath 'Network_IPConfig.txt') -Width 4096 -Force
    #=================================================
    # Win32_BaseBoard
    $classWin32BaseBoard = Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -Property *
    $classWin32BaseBoard | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_BaseBoard.txt') -Width 4096 -Force
    $BaseBoardProduct = $classWin32BaseBoard.Product | ConvertTo-TrimmedString
    #=================================================
    # Win32_Battery
    try {
        $classWin32Battery = Get-CimInstance -ClassName Win32_Battery | Select-Object -Property *
        $classWin32Battery | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_Battery.txt') -Width 4096 -Force
    }
    catch {
        $classWin32Battery = $null
    }

    [System.Boolean]$IsOnBattery = $false
    if ($classWin32Battery) {
        $IsOnBattery = ($classWin32Battery.BatteryStatus -contains 1)
    }
    #=================================================
    # Win32_BIOS
    $classWin32BIOS = Get-CimInstance -ClassName Win32_BIOS | Select-Object -Property *
    $classWin32BIOS | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_BIOS.txt') -Width 4096 -Force
    #=================================================
    # Win32_ComputerSystem
    $classWin32ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -Property *
    $classWin32ComputerSystem | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_ComputerSystem.txt') -Width 4096 -Force
    $ComputerManufacturer = $classWin32ComputerSystem.Manufacturer | ConvertTo-TrimmedString
    $ComputerModel = $classWin32ComputerSystem.Model | ConvertTo-TrimmedString
    $ComputerSystemFamily = $classWin32ComputerSystem.SystemFamily | ConvertTo-TrimmedString
    $ComputerSystemSKU = $classWin32ComputerSystem.SystemSKUNumber | ConvertTo-TrimmedString
    #=================================================
    # Win32_ComputerSystemProduct
    $classWin32ComputerSystemProduct = Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object -Property *
    $classWin32ComputerSystemProduct | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_ComputerSystemProduct.txt') -Width 4096 -Force
    $ComputerSystemProduct = $classWin32ComputerSystemProduct.Version | ConvertTo-TrimmedString
    #=================================================
    # Win32_DiskDrive
    $classWin32DiskDrive = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object -Property *
    $classWin32DiskDrive | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_DiskDrive.txt') -Width 4096 -Force
    foreach ($Item in $classWin32DiskDrive) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Disk: $($Item.Model) [$($Item.DeviceID)]"
    }
    #=================================================
    # Win32_Environment
    $classWin32Environment = Get-CimInstance -ClassName Win32_Environment | Select-Object -Property * | Sort-Object Name
    $classWin32Environment | Where-Object { $_.SystemVariable -eq $true } | Select-Object -Property Name, VariableValue | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_Environment-System.txt') -Width 4096 -Force
    #=================================================
    # Win32_Keyboard
    try {
        $classWin32Keyboard = Get-CimInstance -ClassName Win32_Keyboard -ErrorAction Stop | Select-Object -Property *
        $classWin32Keyboard | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_Keyboard.txt') -Width 4096 -Force

        # A device can expose multiple keyboard endpoints. Prefer entries with
        # a populated layout and stable ordering, then use the first candidate.
        $keyboardCandidates = @($classWin32Keyboard) | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.Layout) -or -not [string]::IsNullOrWhiteSpace($_.Name)
        } | Sort-Object -Property @(
            @{ Expression = { [string]::IsNullOrWhiteSpace($_.Layout) } ; Descending = $false },
            @{ Expression = { [string]$_.Name } ; Descending = $false },
            @{ Expression = { [string]$_.DeviceID } ; Descending = $false }
        )

        $primaryKeyboard = $keyboardCandidates | Select-Object -First 1
        if ($primaryKeyboard) {
            $KeyboardLayout = [System.String]$primaryKeyboard.Layout
            $KeyboardName = [System.String]$primaryKeyboard.Name

            if ($keyboardCandidates.Count -gt 1) {
                Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Multiple keyboards detected ($($keyboardCandidates.Count)). Using '$KeyboardName' with layout '$KeyboardLayout'."
            }
        }
        else {
            $KeyboardLayout = $null
            $KeyboardName = $null
        }
    }
    catch {
        $classWin32Keyboard = $null
        $KeyboardLayout = $null
        $KeyboardName = $null
    }

    $AutoOSLanguageCode = 'en-us'
    #=================================================
    # Win32_NetworkAdapter
    $classWin32NetworkAdapter = Get-CimInstance -ClassName Win32_NetworkAdapter | Select-Object -Property *
    $classWin32NetworkAdapter | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_NetworkAdapter.txt') -Width 4096 -Force

    $NetworkAdapterGuid = $classWin32NetworkAdapter | Where-Object { $null -ne $_.GUID }
    if ($NetworkAdapterGuid) {
        foreach ($Item in $NetworkAdapterGuid) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] NetAdapter: $($Item.Name) [$($Item.MACAddress)]"
        }
    }
    #=================================================
    # Win32_NetworkAdapterConfiguration
    $classWin32NetworkAdapterConfiguration = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true } | Select-Object -Property *
    $classWin32NetworkAdapterConfiguration | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_NetworkAdapterConfiguration.txt') -Width 4096 -Force

    foreach ($Item in $classWin32NetworkAdapterConfiguration) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] NetAdapterConfig: $($Item.IPAddress) [$($Item.Description)]"
    }
    $NetIPAddress = @()
    $NetMacAddress = @()
    $NetGateways = @()
    $classWin32NetworkAdapterConfiguration | ForEach-Object {
        $_.IPAddress | ForEach-Object { $NetIPAddress += $_ }
        $_.MacAddress | ForEach-Object { $NetMacAddress += $_ }
        $_.DefaultIPGateway | ForEach-Object { $NetGateways += $_ }
    }
    #=================================================
    # Win32_OperatingSystem
    $classWin32OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -Property *
    $classWin32OperatingSystem | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_OperatingSystem.txt') -Width 4096 -Force
    $OSArchitecture = $classWin32OperatingSystem.OSArchitecture | ConvertTo-TrimmedString
    #=================================================
    # Win32_PnPEntity
    $classWin32PnPEntity = Get-CimInstance -ClassName Win32_PnPEntity | Select-Object -Property *
    $classWin32PnPEntityError = $classWin32PnPEntity | Where-Object { $_.Status -eq 'Error' } | Sort-Object HardwareID -Unique | Sort-Object Name

    if ($classWin32PnPEntityError) {
        $classWin32PnPEntityError | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_PnPEntityError.txt') -Width 4096 -Force
    }

    $SystemFirmwareDevice = $classWin32PnPEntity | Where-Object ClassGuid -eq '{f2e7dd72-6468-4e36-b6f1-6488f42c1b52}' | Where-Object Caption -match 'System'
    if ($SystemFirmwareDevice) {
        $GuidPattern = '\{?(([0-9a-f]){8}-([0-9a-f]){4}-([0-9a-f]){4}-([0-9a-f]){4}-([0-9a-f]){12})\}?'
        $SystemFirmwareResource = ($SystemFirmwareDevice.PNPDeviceID | Select-String -Pattern $GuidPattern -AllMatches | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value)
        $SystemFirmwareHardwareId = $SystemFirmwareResource -replace '[{}]', ''
    }
    else {
        $SystemFirmwareDevice = $null
        $SystemFirmwareResource = $null
        $SystemFirmwareHardwareId = $null
    }
    #=================================================
    # Win32_Processor
    $classWin32Processor = Get-CimInstance -ClassName Win32_Processor | Select-Object -Property *
    $classWin32Processor | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_Processor.txt') -Width 4096 -Force

    foreach ($Item in $classWin32Processor) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Processor: $($Item.Name) [$($Item.NumberOfLogicalProcessors) Logical]"
    }
    #=================================================
    # Win32_SystemEnclosure
    $classWin32SystemEnclosure = Get-CimInstance -ClassName Win32_SystemEnclosure | Select-Object -Property *
    $classWin32SystemEnclosure | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_SystemEnclosure.txt') -Width 4096 -Force
    #=================================================
    # Win32_SystemTimeZone
    $classWin32SystemTimeZone = Get-CimInstance -ClassName Win32_SystemTimeZone | Select-Object -Property *
    $classWin32SystemTimeZone | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_SystemTimeZone.txt') -Width 4096 -Force
    #=================================================
    # Win32_TimeZone
    $classWin32TimeZone = Get-CimInstance -ClassName Win32_TimeZone | Select-Object -Property *
    $classWin32TimeZone | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_TimeZone.txt') -Width 4096 -Force
    #=================================================
    # TPM
    $IsAutopilotSpec = $false
    $IsTpmSpec = $false
    $classWin32Tpm = @{}
    try {
        $classWin32Tpm = Get-CimInstance -Namespace 'ROOT\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        $classWin32Tpm | Out-File (Join-Path -Path $LogsPath -ChildPath 'Win32_Tpm.txt') -Width 4096 -Force
        $DeviceTpmIsActivated = $($classWin32Tpm.IsActivated_InitialValue)
        $DeviceTpmIsEnabled = $($classWin32Tpm.IsEnabled_InitialValue)
        $DeviceTpmIsOwned = $($classWin32Tpm.IsOwned_InitialValue)
        $DeviceTpmManufacturerIdTxt = $($classWin32Tpm.ManufacturerIdTxt)
        $DeviceTpmManufacturerVersion = $($classWin32Tpm.ManufacturerVersion)
        $DeviceTpmSpecVersion = $($classWin32Tpm.SpecVersion)
    }
    catch {
        $classWin32Tpm = $null
        $DeviceTpmIsActivated = $false
        $DeviceTpmIsEnabled = $false
        $DeviceTpmIsOwned = $false
        $DeviceTpmManufacturerIdTxt = $null
        $DeviceTpmManufacturerVersion = $null
        $DeviceTpmSpecVersion = $null

        Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] [NOT SUPPORTED] TPM is not supported on this device."
        Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] [NOT SUPPORTED] Intune Autopilot is not supported on this device."
    }

    if ($DeviceTpmSpecVersion) {
        $majorVersion = $DeviceTpmSpecVersion.Split(',')[0] -as [int]
        if ($majorVersion -lt 2) {
            Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] [NOT SUPPORTED] TPM version is lower than 2.0 on this device."
            Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] [NOT SUPPORTED] Intune Autopilot is not supported on this device."
        }
        else {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] TPM 2.0 is supported on this device."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Intune Autopilot is supported on this device."
            $IsAutopilotSpec = $true
            $IsTpmSpec = $true
        }
    }
    #=================================================
    # Secure Boot Information
    # https://github.com/richardhicks/uefi/blob/main/Get-UEFICertificate.ps1
    try {
        $SecureBootStatus = Confirm-SecureBootUEFI
    }
    catch {
        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Unable to access UEFI Secure Boot information."
        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] This system may not support UEFI or Secure Boot."
    }
    if ($SecureBootStatus -eq $true) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Secure Boot is enabled on this device."

        if (Get-Command -Name Get-SecureBootUEFI -ErrorAction Ignore) {
            try {
                $dbVariable = Get-SecureBootUEFI -Name DB -ErrorAction Stop
                $kekVariable = Get-SecureBootUEFI -Name KEK -ErrorAction Stop

                $dbBytes = $dbVariable.Bytes
                $kekBytes = $kekVariable.Bytes

                if (-not $dbBytes -or -not $kekBytes) {
                    Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Secure Boot certificates could not be read (missing DB or KEK bytes). Skipping certificate presence checks."
                }
                else {
                    $utf8Encoding = [System.Text.Encoding]::GetEncoding(
                        'utf-8',
                        [System.Text.EncoderFallback]::ReplacementFallback,
                        [System.Text.DecoderFallback]::ReplacementFallback
                    )

                    $dbText = $utf8Encoding.GetString($dbBytes)
                    if ([string]::IsNullOrWhiteSpace($dbText)) {
                        $dbText = [System.Text.Encoding]::ASCII.GetString($dbBytes)
                    }
                    $WinUEFIca2023 = $dbText -match 'Windows UEFI CA 2023'
                    if ($WinUEFIca2023) {
                        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Windows UEFI CA 2023 is present."
                    }
                    else {
                        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Windows UEFI CA 2023 is not present."
                    }
                    $MsUEFIca2023 = $dbText -match 'Microsoft UEFI CA 2023'
                    if ($MsUEFIca2023) {
                        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft UEFI CA 2023 is present."
                    }
                    else {
                        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Microsoft UEFI CA 2023 is not present."
                    }

                    $kekText = $utf8Encoding.GetString($kekBytes)
                    if ([string]::IsNullOrWhiteSpace($kekText)) {
                        $kekText = [System.Text.Encoding]::ASCII.GetString($kekBytes)
                    }
                    $MsKEKca2023 = $kekText -match 'Microsoft Corporation KEK 2K CA 2023'
                    if ($MsKEKca2023) {
                        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Corporation KEK 2K CA 2023 is present."
                    }
                    else {
                        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Microsoft Corporation KEK 2K CA 2023 is not present."
                    }
                }
            }
            catch {
                Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Unable to query Secure Boot certificate variables (DB/KEK): $($_.Exception.Message). Skipping certificate presence checks."
            }
        }
    }
    elseif ($SecureBootStatus -eq $false) {
        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Secure Boot is not enabled."
    }
    #=================================================
    # Identify Serial Number with multiple fallback methods due to variability in how different manufacturers populate WMI classes
    $serialNumberCandidates = @(
        $classWin32BIOS.SerialNumber,
        $classWin32SystemEnclosure.SerialNumber,
        $classWin32ComputerSystemProduct.IdentifyingNumber,
        $classWin32BaseBoard.SerialNumber
    )
    $SerialNumber = $null
    foreach ($candidate in $serialNumberCandidates) {
        $SerialNumber = $candidate | ConvertTo-TrimmedString
        if (-not [string]::IsNullOrWhiteSpace($SerialNumber)) {
            break
        }
    }
    #=================================================
    # IsUEFI
    [System.Boolean]$IsUEFI = $false
    if ($env:firmware_type -eq 'UEFI') {
        $IsUEFI = $true
    }
    elseif ($env:firmware_type -eq 'Legacy') {
        $IsUEFI = $false
    }
    elseif ($env:SystemDrive -eq 'X:') {
        Start-Process -WindowStyle Hidden -FilePath wpeutil.exe -ArgumentList ('updatebootinfo') -Wait
        $IsUEFI = (Get-ItemProperty -Path HKLM:\System\CurrentControlSet\Control).PEFirmwareType -eq 2
    }
    else {
        if ($null -eq (Get-ItemProperty HKLM:\System\CurrentControlSet\Control\SecureBoot\State -ErrorAction SilentlyContinue)) {
            $IsUEFI = $false
        }
        else {
            $IsUEFI = $true
        }
    }
    #=================================================
    # IsVM
    [System.Boolean]$IsVM = $false
    $vmDetectionSources = @(
        $classWin32ComputerSystem.Model,
        $classWin32ComputerSystem.Manufacturer,
        $classWin32ComputerSystem.SystemFamily,
        $classWin32ComputerSystemProduct.Name,
        $classWin32ComputerSystemProduct.Vendor,
        $classWin32ComputerSystemProduct.Version
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $vmPattern = '(?i)(virtual machine|vmware|hyper-v|hyperv|kvm|qemu|xen|virtualbox|bhyve|parallels|gce|google compute engine|amazon ec2|azure|bochs|openstack|ovirt|rhev|kubevirt|ahv|nutanix)'
    [System.Boolean]$IsVM = ($vmDetectionSources -join ' ') -match $vmPattern
    #=================================================
    # IsWinPE
    [System.Boolean]$IsWinPE = $false
    if ($env:SystemDrive -eq 'X:') {
        $IsWinPE = $true
    }
    #=================================================
    # ChassisType
    $ComputerSystemType = $classWin32SystemEnclosure | ForEach-Object {
        if ($_.ChassisTypes[0] -in "8", "9", "10", "11", "12", "14", "18", "21") { "Laptop" }
        if ($_.ChassisTypes[0] -in "3", "4", "5", "6", "7", "15", "16") { "Desktop" }
        if ($_.ChassisTypes[0] -in "23") { "Server" }
        if ($_.ChassisTypes[0] -in "34", "35", "36") { "Small Form Factor" }
        if ($_.ChassisTypes[0] -in "13", "31", "32", "30") { "Tablet" }
    }
    [System.Boolean]$IsDesktop = $ComputerSystemType -contains 'Desktop'
    [System.Boolean]$IsLaptop = $ComputerSystemType -contains 'Laptop'
    [System.Boolean]$IsServer = $ComputerSystemType -contains 'Server'
    [System.Boolean]$IsSFF = $ComputerSystemType -contains 'Small Form Factor'
    [System.Boolean]$IsTablet = $ComputerSystemType -contains 'Tablet'
    #=================================================
    # TotalPhysicalMemoryGB
    $TotalPhysicalMemoryGB = [math]::Round(
        $classWin32ComputerSystem.TotalPhysicalMemory / 1GB,
        0,
        [System.MidpointRounding]::AwayFromZero
    )
    if ($TotalPhysicalMemoryGB -lt 6) {
        Write-Warning "[$(Get-Date -format s)] OSDCloud Workflow requires at least 8 GB of memory to function properly. Errors are expected."
    }
    #=================================================
    # OA3Tool for Hardware Hash (Autopilot)
    $HardwareHash = $null
    if (Get-Command 'oa3tool.exe' -ErrorAction Ignore) {
        $oa3cfg = @"
<OA3>
    <FileBased>
        <InputKeyXMLFile>$env:TEMP\OA3_Input.xml</InputKeyXMLFile>
    </FileBased>
    <OutputData>
        <AssembledBinaryFile>$env:TEMP\OA3.bin</AssembledBinaryFile>
        <ReportedXMLFile>$env:TEMP\OA3.xml</ReportedXMLFile>
    </OutputData>
</OA3>
"@

        $oa3input = @"
<?xml version="1.0"?>
<Key>
    <ProductKey>XXXXX-XXXXX-XXXXX-XXXXX-XXXXX</ProductKey>
    <ProductKeyID>0000000000000</ProductKeyID>
    <ProductKeyState>0</ProductKeyState>
</Key>
"@

        $oa3cfg | Out-File -FilePath "$env:TEMP\OA3.cfg" -Encoding utf8 -Force
        $oa3input | Out-File -FilePath "$env:TEMP\OA3_Input.xml" -Encoding utf8 -Force
        $null = oa3tool.exe /Report /ConfigFile="$env:TEMP\OA3.cfg" /LogTrace="$env:TEMP\OA3_Report.xml" /NoKeyCheck
        if (Test-Path "$env:TEMP\OA3.xml") {
            $HardwareHash = Get-Content "$env:TEMP\OA3.xml" -Raw | Select-String -Pattern '<HardwareHash>(.*?)</HardwareHash>' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value }

            Copy-Item -Path "$env:TEMP\OA3.xml" -Destination (Join-Path -Path $LogsPath -ChildPath 'OA3.xml') -Force -ErrorAction SilentlyContinue
            Copy-Item -Path "$env:TEMP\OA3_Report.xml" -Destination (Join-Path -Path $LogsPath -ChildPath 'OA3_Report.xml') -Force -ErrorAction SilentlyContinue
            if ($HardwareHash) {
                $null = oa3tool.exe /DecodeHwHash="$HardwareHash" /LogTrace="$env:TEMP\OA3_Decode.xml"
                $null = oa3tool.exe /ValidateHwHash="$HardwareHash" /LogTrace="$env:TEMP\OA3_Validate.xml"
                $csvContent = @()
                $csvContent += [PSCustomObject]@{
                    'Device Serial Number' = $SerialNumber
                    'Windows Product ID'   = ''
                    'Hardware Hash'        = $HardwareHash
                }
                $csvContent | ConvertTo-Csv -NoTypeInformation | ForEach-Object { $_ -replace '"', '' } | Out-File -FilePath "$env:TEMP\Autopilot.csv" -Force -Encoding utf8
                Copy-Item -Path "$env:TEMP\Autopilot.csv" -Destination (Join-Path -Path $LogsPath -ChildPath 'Autopilot.csv') -Force -ErrorAction SilentlyContinue
                Copy-Item -Path "$env:TEMP\OA3_Decode.xml" -Destination (Join-Path -Path $LogsPath -ChildPath 'OA3_Decode.xml') -Force -ErrorAction SilentlyContinue
                Copy-Item -Path "$env:TEMP\OA3_Validate.xml" -Destination (Join-Path -Path $LogsPath -ChildPath 'OA3_Validate.xml') -Force -ErrorAction SilentlyContinue
            }
        }
    }
    #=================================================
    # OSD Properties with normalization and aliasing for known manufacturers and models to ensure consistent values for OSDCloud workflows and reporting
    $OSDManufacturer = $classWin32ComputerSystem.Manufacturer | ConvertTo-TrimmedString
    $OSDModel = $classWin32ComputerSystem.Model | ConvertTo-TrimmedString
    $OSDProduct = $classWin32ComputerSystemProduct.Version | ConvertTo-TrimmedString
    #=================================================
    # Normalize Aliases for Known Manufacturers and Models
    switch -Regex ($OSDManufacturer) {
        'Acer' {
            $OSDManufacturer = 'Acer'
            $OSDProduct = $BaseBoardProduct
            break
        }
        'ASUS|ASUSTeK' {
            $OSDManufacturer = 'ASUS'
            $OSDProduct = $BaseBoardProduct
            break
        }
        'Dell' {
            $OSDManufacturer = 'Dell'
            $OSDProduct = $ComputerSystemSKU
            break
        }
        'Fujitsu' {
            $OSDManufacturer = 'Fujitsu'
            $OSDProduct = $BaseBoardProduct
            break
        }
        'Gigabyte' {
            $OSDManufacturer = 'Gigabyte'
            $OSDProduct = $BaseBoardProduct
            break
        }
        'Lenovo' {
            $OSDManufacturer = 'Lenovo'
            $OSDModel = $ComputerSystemProduct
            if (-not [string]::IsNullOrWhiteSpace($ComputerModel) -and $ComputerModel.Length -ge 4) {
                $OSDProduct = $ComputerModel.Substring(0, 4)
            }
            else {
                $OSDProduct = $ComputerModel
            }
            break
        }
        'Hewlett|Packard|^HP$' {
            $OSDManufacturer = 'HP'
            $OSDProduct = $BaseBoardProduct
            break
        }
        'Microsoft' {
            $OSDManufacturer = 'Microsoft'
            if ($OSDModel -match 'Virtual') {
                $OSDProduct = $ComputerSystemProduct
            }
            else {
                $OSDProduct = $ComputerSystemSKU
            }
            break
        }
        'Panasonic' { $OSDManufacturer = 'Panasonic'; break }
        'to be filled' { $OSDManufacturer = 'OEM'; break }
    }

    if ([string]::IsNullOrWhiteSpace($OSDManufacturer) -or $OSDManufacturer -match '^to be filled$') {
        $OSDManufacturer = 'OEM'
    }
    if ([string]::IsNullOrWhiteSpace($OSDModel) -or $OSDModel -match '^to be filled$') {
        $OSDModel = 'OEM'
    }
    if ([string]::IsNullOrWhiteSpace($OSDProduct)) {
        $OSDProduct = 'Unknown'
    }
    #=================================================
    # Disk Information
    # Include only disks that are online and available.
    $GetDisk = Get-Disk |
    Where-Object {
        $_.IsOffline -eq $false -and
        $_.OperationalStatus -eq 'Online'
    } |
    Sort-Object DiskNumber |
    Select-Object -Property *

    $USBDisk = $GetDisk | Where-Object { $_.BusType -eq 'USB' }
    $LocalDisk = $GetDisk | Where-Object { $_.BusType -notin 'File Backed Virtual', 'MAX', 'Microsoft Reserved', 'USB', 'Virtual' }

    $usbDiskNumbers = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($disk in $USBDisk) {
        [void]$usbDiskNumbers.Add([int]$disk.DiskNumber)
    }
    $localDiskNumbers = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($disk in $LocalDisk) {
        [void]$localDiskNumbers.Add([int]$disk.DiskNumber)
    }

    # Partition Information
    $GetPartition = Get-Partition |
    Sort-Object DiskNumber, PartitionNumber |
    Select-Object -Property *, @{
        Name       = 'IsUSB'
        Expression = { $usbDiskNumbers.Contains([int]$_.DiskNumber) }
    }, @{
        Name       = 'IsLocal'
        Expression = { $localDiskNumbers.Contains([int]$_.DiskNumber) }
    }
    # USB Partitions
    $USBPartition = $GetPartition | Where-Object { $_.IsUSB -eq $true }
    $LocalPartition = $GetPartition | Where-Object { $_.IsLocal -eq $true }

    # USBVolume
    $usbDriveLetters = $USBPartition |
    ForEach-Object { $_.AccessPaths } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object {
        if ($_ -match '^(?<DriveLetter>[A-Z]):\\$') {
            $Matches.DriveLetter
        }
    } |
    Sort-Object -Unique

    $USBVolume = $null
    if ($usbDriveLetters) {
        $USBVolume = Get-Volume -DriveLetter $usbDriveLetters -ErrorAction SilentlyContinue |
        Sort-Object DriveLetter -Unique
    }
    $USBCache = $null
    if ($USBVolume) {
        $USBCache = $USBVolume | Where-Object { $_.FileSystem -eq 'NTFS' } | Select-Object -First 1
    }

    # LocalVolume
    $localDriveLetters = $LocalPartition |
    ForEach-Object { $_.AccessPaths } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object {
        if ($_ -match '^(?<DriveLetter>[A-Z]):\\$') {
            $Matches.DriveLetter
        }
    } |
    Sort-Object -Unique

    $LocalVolume = $null
    if ($localDriveLetters) {
        $LocalVolume = Get-Volume -DriveLetter $localDriveLetters -ErrorAction SilentlyContinue |
        Sort-Object DriveLetter -Unique
    }
    #=================================================
    #   OSDCloudEnv
    #=================================================
    # Use OSDCloudEnv to override these properties:
    # OSDManufacturer
    # OSDModel
    # OSDProduct
    # OSArchitecture
    if ($global:OSDCloudEnv) {
        if ($global:OSDCloudEnv.OSDManufacturer) {
            $OSDManufacturer = $global:OSDCloudEnv.OSDManufacturer
        }
        if ($global:OSDCloudEnv.OSDModel) {
            $OSDModel = $global:OSDCloudEnv.OSDModel
        }
        if ($global:OSDCloudEnv.OSDProduct) {
            $OSDProduct = $global:OSDCloudEnv.OSDProduct
        }
        if ($global:OSDCloudEnv.OSArchitecture) {
            $OSArchitecture = $global:OSDCloudEnv.OSArchitecture
        }
        if ($global:OSDCloudEnv.ProcessorArchitecture) {
            $ProcessorArchitecture = $global:OSDCloudEnv.ProcessorArchitecture
        }
    }
    #=================================================
    #   OSDeploy and Recast Registration Information
    #=================================================
    $deviceUUID = [System.String]$classWin32ComputerSystemProduct.UUID
    $EndpointSHA = $null
    if (-not [string]::IsNullOrWhiteSpace($deviceUUID)) {
        $EndpointSHA = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($deviceUUID))).Replace("-", "")
    }

    $idOSDeployDevice = $null
    if (-not [string]::IsNullOrWhiteSpace($env:ID_OSDEPLOYDEVICE)) {
        $idOSDeployDevice = [System.String]$env:ID_OSDEPLOYDEVICE
    }

    $idOSDeployBuild = $null
    if (-not [string]::IsNullOrWhiteSpace($env:ID_OSDEPLOYBUILD)) {
        $idOSDeployBuild = [System.String]$env:ID_OSDEPLOYBUILD
    }

    $idRegisteredEmail = $null
    if (-not [string]::IsNullOrWhiteSpace($env:ID_REGISTEREDEMAIL)) {
        $idRegisteredEmail = [System.String]$env:ID_REGISTEREDEMAIL
    }

    $idRegisteredLicense = $null
    if (-not [string]::IsNullOrWhiteSpace($env:ID_REGISTEREDLICENSE)) {
        $idRegisteredLicense = [System.String]$env:ID_REGISTEREDLICENSE
    }

    if ([string]::IsNullOrWhiteSpace($idRegisteredEmail) -or [string]::IsNullOrWhiteSpace($idRegisteredLicense)) {
        try {
            if (-not $global:OSDCoreLicense.License) {
                Initialize-OSDCoreLicense
            }
            if ([string]::IsNullOrWhiteSpace($idRegisteredEmail) -and -not [string]::IsNullOrWhiteSpace($global:OSDCoreLicense.License.Email)) {
                $idRegisteredEmail = [System.String]$global:OSDCoreLicense.License.Email
            }
            if ([string]::IsNullOrWhiteSpace($idRegisteredLicense) -and -not [string]::IsNullOrWhiteSpace($global:OSDCoreLicense.License.LicenseGuid)) {
                $idRegisteredLicense = [System.String]$global:OSDCoreLicense.License.LicenseGuid
            }
        }
        catch {}
    }

    #=================================================
    #   OSLanguage
    #=================================================
    if ($global:OSDCoreLicense.IsRegistered) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDCloud is registered to $idRegisteredEmail"
        if (Get-Command -Name 'Convert-KeyboardLayoutToLanguageCode' -ErrorAction Ignore) {
            $AutoOSLanguageCode = Convert-KeyboardLayoutToLanguageCode -KeyboardLayout $KeyboardLayout -FallbackLanguageCode 'en-US' -LowerCase
        }
    }
    else {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Skipping AutoOSLanguageCode keyboard conversion because OSDCloud is not registered."
    }

    $reportedOSDManufacturer = if ([string]::IsNullOrWhiteSpace($OSDManufacturer)) { 'Unknown' } else { [System.String]$OSDManufacturer }
    $reportedOSDModel = if ([string]::IsNullOrWhiteSpace($OSDModel)) { 'Unknown' } else { [System.String]$OSDModel }
    $reportedOSDProduct = if ([string]::IsNullOrWhiteSpace($OSDProduct)) { 'Unknown' } else { [System.String]$OSDProduct }

    $global:OSDCoreDevice = $null
    $global:OSDCoreDevice = [ordered]@{
        OSDManufacturer          = $reportedOSDManufacturer
        OSDModel                 = $reportedOSDModel
        OSDProduct               = $reportedOSDProduct
        AutoOSLanguageCode       = $AutoOSLanguageCode
        BaseBoardProduct         = [System.String]$BaseBoardProduct
        BiosReleaseDate          = [System.String]$classWin32BIOS.ReleaseDate
        BiosVersion              = [System.String]$classWin32BIOS.SMBIOSBIOSVersion
        ComputerManufacturer     = [System.String]$ComputerManufacturer
        ComputerModel            = [System.String]$ComputerModel
        ComputerName             = $classWin32ComputerSystem.Name
        ComputerSystemFamily     = [System.String]$ComputerSystemFamily
        ComputerSystemProduct    = [System.String]$ComputerSystemProduct
        ComputerSystemSKU        = [System.String]$ComputerSystemSKU
        ComputerSystemType       = [System.String]$ComputerSystemType
        HardwareHash             = [System.String]$HardwareHash
        IsAutopilotSpec          = [System.Boolean]$IsAutopilotSpec
        IsDesktop                = [System.Boolean]$IsDesktop
        IsLaptop                 = [System.Boolean]$IsLaptop
        IsOnBattery              = [System.Boolean]$IsOnBattery
        IsServer                 = [System.Boolean]$IsServer
        IsSFF                    = [System.Boolean]$IsSFF
        IsTablet                 = [System.Boolean]$IsTablet
        IsTpmSpec                = [System.Boolean]$IsTpmSpec
        IsUEFI                   = [System.Boolean]$IsUEFI
        IsVM                     = [System.Boolean]$IsVM
        IsWinPE                  = [System.Boolean]$IsWinPE
        KeyboardLayout           = $KeyboardLayout
        KeyboardName             = $KeyboardName
        LocalDisk                = $LocalDisk
        LocalPartition           = $LocalPartition
        LocalVolume              = $LocalVolume
        NetGateways              = $NetGateways
        NetIPAddress             = $NetIPAddress
        NetMacAddress            = $NetMacAddress
        OSArchitecture           = $OSArchitecture
        OSVersion                = $classWin32OperatingSystem.Version
        ProcessorArchitecture    = $ProcessorArchitecture
        SerialNumber             = $SerialNumber
        SystemFirmwareHardwareId = $SystemFirmwareHardwareId
        TimeZone                 = $classWin32TimeZone.StandardName
        TotalPhysicalMemoryGB    = $TotalPhysicalMemoryGB
        TpmIsActivated           = $DeviceTpmIsActivated
        TpmIsEnabled             = $DeviceTpmIsEnabled
        TpmIsOwned               = $DeviceTpmIsOwned
        TpmManufacturerIdTxt     = $DeviceTpmManufacturerIdTxt
        TpmManufacturerVersion   = $DeviceTpmManufacturerVersion
        TpmSpecVersion           = $DeviceTpmSpecVersion
        USBCache                 = $USBCache
        USBDisk                  = $USBDisk
        USBPartition             = $USBPartition
        USBVolume                = $USBVolume
        UUID                     = $deviceUUID
        EndpointSHA              = [System.String]$EndpointSHA #Device UUID SHA256
        idOSDeployDevice         = $idOSDeployDevice
        idOSDeployBuild          = $idOSDeployBuild
        idRegisteredEmail        = $idRegisteredEmail
        idRegisteredLicense      = $idRegisteredLicense
    }
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Ready: OSDCoreDevice"
    #=================================================
    # Export OSDCoreDevice to XML and JSON for use in other scripts or workflows
    $OSDCoreDeviceClixmlPath = Join-Path -Path $LogsPath -ChildPath 'OSDCoreDevice.xml'
    if (Test-Path -LiteralPath $OSDCoreDeviceClixmlPath) {
        Remove-Item -LiteralPath $OSDCoreDeviceClixmlPath -Force -ErrorAction SilentlyContinue
    }
    $global:OSDCoreDevice | Export-Clixml -Path $OSDCoreDeviceClixmlPath -Force

    $OSDCoreDeviceJsonPath = Join-Path -Path $LogsPath -ChildPath 'OSDCoreDevice.json'
    if (Test-Path -LiteralPath $OSDCoreDeviceJsonPath) {
        Remove-Item -LiteralPath $OSDCoreDeviceJsonPath -Force -ErrorAction SilentlyContinue
    }
    $global:OSDCoreDevice | ConvertTo-Json -Depth 10 | Out-File $OSDCoreDeviceJsonPath -Force -Encoding utf8
    #=================================================
    # OSDCloudLogs
    # Look for available drives (USB, mapped network drives, and local drives) with at least 1 GB of free space and write permissions for the current user to copy logs.
    $OSDCloudLogsDrive = $null

    foreach ($Drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' })) {
        $DriveLetter = $Drive.Name
        $OSDCloudLogsCheckPath = "$DriveLetter`:\OSDCloudLogs"

        try {
            if (Test-Path -Path $OSDCloudLogsCheckPath) {
                $DriveInfo = New-Object System.IO.DriveInfo($DriveLetter)
                if ($DriveInfo.AvailableFreeSpace -ge 1GB) {
                    $OSDCloudLogsDrive = [PSCustomObject]@{
                        DriveLetter          = $DriveLetter
                        AvailableFreeSpaceGB = [math]::Round($DriveInfo.AvailableFreeSpace / 1GB, 1)
                    }
                    break
                }
            }
        }
        catch {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to access drive $DriveLetter"
        }
    }

    if ($OSDCloudLogsDrive) {
        $OSDCloudLogsPath = "$($OSDCloudLogsDrive.DriveLetter):\OSDCloudLogs\$SerialNumber"
        if (-not (Test-Path -Path $OSDCloudLogsPath)) {
            New-Item -Path $OSDCloudLogsPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
        # If folder doesn't exist, then the drive likely doesn't have write permissions for the current user, so skip copying logs to avoid errors
        if (Test-Path -Path $OSDCloudLogsPath) {
            Get-ChildItem -Path $LogsPath -File | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $(Join-Path -Path $OSDCloudLogsPath -ChildPath $_.Name) -Force
            }
        }
    }
    #=================================================
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
