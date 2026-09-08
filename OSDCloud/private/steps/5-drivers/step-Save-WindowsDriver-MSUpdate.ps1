function step-Save-WindowsDriver-MSUpdate {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    # Step Variables
    $DriverPackName = $global:OSDCloudWorkflowInvoke.DriverPackName
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackName: $DriverPackName; PowerShellVersion: $($PSVersionTable.PSVersion); IsVM: $IsVM; Manufacturer: $($global:OSDCoreDevice.OSDManufacturer)"
    #=================================================
    # Exclusions
    if ($PSVersionTable.PSVersion.Major -ne 5) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] PowerShell 5.1 requirement was not met."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] PowerShell 5.1 is required to run this step. Skip."
        return
    }
    if (($IsVM -eq $true) -and ($global:OSDCoreDevice.OSDManufacturer -match 'Microsoft')) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Microsoft Hyper-V virtual machine detected."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Drivers is not enabled for Microsoft Hyper-V. Skip."
        return
    }
    if ($DriverPackName -eq 'None') {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackName is None."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Drivers is not enabled. Skip."
        return
    }
    #=================================================
    # TODO: Resolve issue with Microsoft Update Catalog and re-enable this step
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Microsoft Update driver download branch is currently disabled by design."
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] This function is unavailable due to an issue being worked on. Skip."
    return
    #=================================================
    # Is it reachable online?
    $Url = 'https://catalog.update.microsoft.com/Home.aspx'
    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing Microsoft Update Catalog with HEAD request: $Url"
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
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Calling Save-MicrosoftUpdateCatalogDriver for all device classes to $DestinationDirectory."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Drivers is enabled for all devices. OK."
        Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory
        return
    }
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Update Drivers is enabled for critical devices. OK."

    $DestinationDirectory = "C:\Windows\Temp\osdcloud-drivers-disk"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Saving DiskDrive drivers to $DestinationDirectory."
    Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -PNPClass 'DiskDrive'

    $DestinationDirectory = "C:\Windows\Temp\osdcloud-drivers-net"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Saving Net drivers to $DestinationDirectory."
    Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -PNPClass 'Net'

    $DestinationDirectory = "C:\Windows\Temp\osdcloud-drivers-scsi"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Saving SCSIAdapter drivers to $DestinationDirectory."
    Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -PNPClass 'SCSIAdapter'
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
