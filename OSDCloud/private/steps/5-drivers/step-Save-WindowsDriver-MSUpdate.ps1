function step-Save-WindowsDriver-MSUpdate {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Checking Microsoft Update driver prerequisites'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $Step = $global:OSDCloudCurrentStep
        $DriverPackName = $global:OSDCloudWorkflowInvoke.DriverPackName
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackName: $DriverPackName; PowerShellVersion: $($PSVersionTable.PSVersion); IsVM: $IsVM; Manufacturer: $($global:OSDCoreDevice.OSDManufacturer)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Checking Microsoft Update driver download settings for '$DriverPackName'."

        if ($PSVersionTable.PSVersion.Major -ne 5) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] PowerShell 5.1 requirement was not met."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update driver downloads require Windows PowerShell 5.1. Skipping this optional step."
            return
        }
        if (($IsVM -eq $true) -and ($global:OSDCoreDevice.OSDManufacturer -match 'Microsoft')) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Microsoft Hyper-V virtual machine detected."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update drivers are not downloaded for Microsoft Hyper-V virtual machines. Skipping this optional step."
            return
        }
        if ($DriverPackName -eq 'None') {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackName is None."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] DriverPackName is None. Microsoft Update driver downloads are disabled."
            return
        }
        #=================================================
        # TODO: Resolve issue with Microsoft Update Catalog and re-enable this step
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Microsoft Update driver download branch is currently disabled by design."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update driver downloads are temporarily disabled while a catalog issue is investigated. Skipping this optional step."
        return
        #=================================================
        $Url = 'https://catalog.update.microsoft.com/Home.aspx'
        $ProgressPhase = 'Checking Microsoft Update Catalog availability'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Checking Microsoft Update Catalog availability:"
        Write-Host -ForegroundColor DarkGray "  $Url"
        try {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing Microsoft Update Catalog with HEAD request: $Url"
            $WebRequest = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Head -ErrorAction Stop
            if ($WebRequest.StatusCode -ne 200) {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update Catalog returned HTTP $($WebRequest.StatusCode). Driver downloads are being skipped."
                return
            }
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update Catalog is reachable (HTTP $($WebRequest.StatusCode))."
        }
        catch {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update Catalog availability check failed: $($_.Exception.Message)"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Skipping optional driver downloads; continuing OSDCloud."
            return
        }
        #=================================================
        if ($DriverPackName -eq 'Microsoft Update Catalog') {
            $DestinationDirectory = 'C:\Windows\Temp\osdcloud-drivers-msupdate'
            $ProgressPhase = 'Searching Microsoft Update Catalog for all device classes'
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Searching for Microsoft Update drivers for all device classes."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Matching drivers will be saved to:"
            Write-Host -ForegroundColor DarkGray "  $DestinationDirectory"
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Calling Save-MicrosoftUpdateCatalogDriver for all device classes to $DestinationDirectory."
            Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DestinationDirectory -ErrorAction Stop
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update driver search completed for all device classes."
            return
        }

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Searching Microsoft Update Catalog for critical device drivers (disk, network, and SCSI)."
        $DriverClasses = @(
            [pscustomobject]@{ Name = 'DiskDrive'; Path = 'C:\Windows\Temp\osdcloud-drivers-disk' }
            [pscustomobject]@{ Name = 'Net'; Path = 'C:\Windows\Temp\osdcloud-drivers-net' }
            [pscustomobject]@{ Name = 'SCSIAdapter'; Path = 'C:\Windows\Temp\osdcloud-drivers-scsi' }
        )
        foreach ($DriverClass in $DriverClasses) {
            $ProgressPhase = "Searching Microsoft Update Catalog for $($DriverClass.Name) drivers"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Searching for $($DriverClass.Name) drivers. Matching drivers will be saved to:"
            Write-Host -ForegroundColor DarkGray "  $($DriverClass.Path)"
            Save-MicrosoftUpdateCatalogDriver -DestinationDirectory $DriverClass.Path -PNPClass $DriverClass.Name -ErrorAction Stop
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Microsoft Update search completed for $($DriverClass.Name) drivers."
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional Microsoft Update driver step failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing OSDCloud without optional Microsoft Update drivers."
    }
    #=================================================
}
