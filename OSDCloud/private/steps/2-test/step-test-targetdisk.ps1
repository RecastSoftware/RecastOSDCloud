function step-test-targetdisk {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    #=================================================
    if ($global:OSDCoreDevice.LocalDisk) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Fixed Disk is valid. OK."
    }
    else {
        Write-Warning "[$(Get-Date -format s)] Unable to detect a Fixed Disk."
        Write-Warning "[$(Get-Date -format s)] WinPE may need additional Disk, SCSI or Raid Drivers."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
