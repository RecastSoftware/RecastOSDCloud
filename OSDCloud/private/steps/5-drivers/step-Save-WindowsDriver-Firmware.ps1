function step-Save-WindowsDriver-Firmware {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Checking firmware update prerequisites'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Checking whether Microsoft Update firmware downloads can run."

        if ($global:OSDCloudWorkflowInvoke.SkipFirmwareUpdate -eq $true) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] SkipFirmwareUpdate is true."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Firmware updates were disabled by -SkipFirmwareUpdate. Skipping this optional step."
            return
        }
        if ($PSVersionTable.PSVersion.Major -ne 5) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] PowerShell major version is $($PSVersionTable.PSVersion.Major)."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update firmware downloads require Windows PowerShell 5.1. Skipping this optional step."
            return
        }
        if ($IsVM -eq $true) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Virtual machine detected."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Firmware updates are not downloaded for virtual machines. Skipping this optional step."
            return
        }
        if ($global:OSDCoreDevice.IsOnBattery -eq $true) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Device is on battery."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Firmware updates are not downloaded while the device is on battery. Skipping this optional step."
            return
        }
        #=================================================
        $Url = 'https://catalog.update.microsoft.com/Home.aspx'
        $ProgressPhase = 'Checking Microsoft Update Catalog availability'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Checking Microsoft Update Catalog availability:"
        Write-Host -ForegroundColor DarkGray "  $Url"
        try {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing Microsoft Update Catalog with HEAD request: $Url"
            $WebRequest = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Head -ErrorAction Stop
            if ($WebRequest.StatusCode -ne 200) {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update Catalog returned HTTP $($WebRequest.StatusCode). Firmware downloads are being skipped."
                return
            }
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update Catalog is reachable (HTTP $($WebRequest.StatusCode))."
        }
        catch {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update Catalog availability check failed: $($_.Exception.Message)"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Skipping optional firmware downloads; continuing OSDCloud."
            return
        }
        #=================================================
        $DestinationDirectory = 'C:\Windows\Temp\osdcloud-drivers-firmware'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Firmware drivers will be downloaded to:"
        Write-Host -ForegroundColor DarkGray "  $DestinationDirectory"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Not all systems support firmware updates. BIOS or firmware settings may need to be enabled."

        $SystemFirmwareHardwareId = $global:OSDCoreDevice.SystemFirmwareHardwareId
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DestinationDirectory: $DestinationDirectory; SystemFirmwareHardwareId: $SystemFirmwareHardwareId"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Searching Microsoft Update Catalog for this system firmware hardware ID:"
        Write-Host -ForegroundColor DarkGray "  $SystemFirmwareHardwareId"

        $ProgressPhase = 'Downloading firmware driver matches from Microsoft Update Catalog'
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Calling Save-MicrosoftUpdateCatalogDriver for firmware hardware ID."
        Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -HardwareID $SystemFirmwareHardwareId -ErrorAction Stop
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Firmware driver catalog search completed."
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional firmware update step failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing OSDCloud without optional firmware updates."
    }
    #=================================================
}
