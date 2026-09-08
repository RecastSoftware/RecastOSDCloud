function step-preinstall-restoreusbdriveletter {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] USB partition count: $(@($global:OSDCloudWorkflowInvoke.USBPartitions).Count)"

    if ($global:OSDCloudWorkflowInvoke.USBPartitions) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Restoring USB Drive Letters. OK."
        foreach ($Item in $global:OSDCloudWorkflowInvoke.USBPartitions) {
            $Params = @{
                AssignDriveLetter = $true
                DiskNumber        = $Item.DiskNumber
                PartitionNumber   = $Item.PartitionNumber
                ErrorAction       = 'SilentlyContinue'
            }
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Restoring drive letter on Disk $($Params.DiskNumber), Partition $($Params.PartitionNumber)."
            Add-PartitionAccessPath @Params
            Start-Sleep -Seconds 5
        }
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No saved USB partitions were found."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
