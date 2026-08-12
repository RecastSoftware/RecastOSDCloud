function step-test-targetdisk {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    #=================================================
    #region Main
    if ($env:SystemDrive -eq 'X:') {
        $global:OSDCloudWorkflowInvoke.GetDiskFixed = Get-DeviceLocalDisk | Where-Object { $_.IsBoot -eq $false } | Sort-Object Number
    }
    else {
        $global:OSDCloudWorkflowInvoke.GetDiskFixed = Get-DeviceLocalDisk | Sort-Object Number
    }


    if ($global:OSDCloudWorkflowInvoke.GetDiskFixed) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Fixed Disk is valid. OK."
    }
    else {
        Write-Warning "[$(Get-Date -format s)] Unable to detect a Fixed Disk."
        Write-Warning "[$(Get-Date -format s)] WinPE may need additional Disk, SCSI or Raid Drivers."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #endregion
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
