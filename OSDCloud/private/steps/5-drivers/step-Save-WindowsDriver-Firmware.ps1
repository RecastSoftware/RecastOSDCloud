function step-Save-WindowsDriver-Firmware {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    if ($global:OSDCloudWorkflowInvoke.SkipFirmwareUpdate -eq $true) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] SkipFirmwareUpdate is true."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Firmware update steps were disabled by -SkipFirmwareUpdate. Skip."
        return
    }
    if ($PSVersionTable.PSVersion.Major -ne 5) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] PowerShell major version is $($PSVersionTable.PSVersion.Major)."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] PowerShell 5.1 is required to run this step. Skip."
        return
    }
    if ($IsVM -eq $true) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Virtual machine detected."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Firmware is not enabled for Virtual Machines. Skip."
        return
    }
    if ($global:OSDCoreDevice.IsOnBattery -eq $true) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Device is on battery."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Firmware is not enabled for devices on battery power"
        return
    }
    #=================================================
    # Is it reachable online?
    $Url = 'https://catalog.update.microsoft.com/Home.aspx'
    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing Microsoft Update Catalog with HEAD request: $Url"
        $WebRequest = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Head
        if ($WebRequest.StatusCode -eq 200) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Catalog returned a 200 status code. OK."
        }
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Catalog is not reachable. Skip."
        return
    }

    <#
    $FirmwarePath = "C:\Windows\Temp\osdcloud-drivers-firmware"

    $Params = @{
        Path        = $FirmwarePath
        ItemType    = 'Directory'
        Force       = $true
        ErrorAction = 'SilentlyContinue'
    }

    if (-not (Test-Path $Params.Path)) {
        New-Item @Params | Out-Null
    }
    #>

    $DestinationDirectory = "C:\Windows\Temp\osdcloud-drivers-firmware"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Firmware Updates will be downloaded from Microsoft Update Catalog to $DestinationDirectory"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Not all systems support a driver Firmware Update"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] BIOS or Firmware Settings may need to be enabled for Firmware Updates"

    $SystemFirmwareHardwareId = $global:OSDCoreDevice.SystemFirmwareHardwareId
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DestinationDirectory: $DestinationDirectory; SystemFirmwareHardwareId: $SystemFirmwareHardwareId"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] System Firmware Hardware ID: $SystemFirmwareHardwareId"

    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Calling Save-MicrosoftUpdateCatalogDriver for firmware hardware ID."
    Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -HardwareID $SystemFirmwareHardwareId
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
