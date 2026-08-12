function step-Save-WindowsDriver-Firmware {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    #=================================================
    if ($global:OSDCloudDeploy.SkipFirmwareUpdate -eq $true) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Firmware update steps were disabled by -SkipFirmwareUpdate. Skip."
        return
    }
    if ($PSVersionTable.PSVersion.Major -ne 5) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] PowerShell 5.1 is required to run this step. Skip."
        return
    }
    if ($IsVM -eq $true) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Firmware is not enabled for Virtual Machines. Skip."
        return
    }
    if ($global:OSDCoreDevice.IsOnBattery -eq $true) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Firmware is not enabled for devices on battery power"
        return
    }
    #=================================================
    # Is it reachable online?
    $Url = 'https://catalog.update.microsoft.com/Home.aspx'
    try {
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
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] System Firmware Hardware ID: $SystemFirmwareHardwareId"

    Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -HardwareID $SystemFirmwareHardwareId
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
