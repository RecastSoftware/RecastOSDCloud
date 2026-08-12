function step-Save-WindowsDriver-MSUpdate {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    #=================================================
    # Step Variables
    $DriverPackName = $global:OSDCloudDeploy.DriverPackName
    #=================================================
    # Exclusions
    if ($PSVersionTable.PSVersion.Major -ne 5) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] PowerShell 5.1 is required to run this step. Skip."
        return
    }
    if (($IsVM -eq $true) -and ($global:OSDCoreDevice.OSDManufacturer -match 'Microsoft')) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Drivers is not enabled for Microsoft Hyper-V. Skip."
        return
    }
    if ($DriverPackName -eq 'None') {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Drivers is not enabled. Skip."
        return
    }
    #=================================================
    # TODO: Resolve issue with Microsoft Update Catalog and re-enable this step
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] This function is unavailable due to an issue being worked on. Skip."
    return
    #=================================================
    # Is it reachable online?
    $Url = 'https://catalog.update.microsoft.com/Home.aspx'
    try {
        $WebRequest = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Head
        if ($WebRequest.StatusCode -eq 200) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Catalog URL returned a 200 status code. OK."
        }
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Catalog URL is not reachable online and cannot be downloaded. Skip."
        return
    }
    #=================================================
    # Microsoft Update Catalog
    if ($DriverPackName -eq 'Microsoft Update Catalog') {
        $DestinationDirectory = "C:\Windows\Temp\osdcloud-drivers-msupdate"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Drivers is enabled for all devices. OK."
        Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory
        return
    }
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Drivers is enabled for critical devices. OK."

    $DestinationDirectory = "C:\Windows\Temp\osdcloud-drivers-disk"
    Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -PNPClass 'DiskDrive'

    $DestinationDirectory = "C:\Windows\Temp\osdcloud-drivers-net"
    Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -PNPClass 'Net'

    $DestinationDirectory = "C:\Windows\Temp\osdcloud-drivers-scsi"
    Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -PNPClass 'SCSIAdapter'
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
