function step-preinstall-restoreusbdriveletter {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    if ($global:OSDCloudWorkflowInvoke.USBPartitions) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Restoring USB Drive Letters. OK."
        foreach ($Item in $global:OSDCloudWorkflowInvoke.USBPartitions) {
            $Params = @{
                AssignDriveLetter = $true
                DiskNumber        = $Item.DiskNumber
                PartitionNumber   = $Item.PartitionNumber
                ErrorAction       = 'SilentlyContinue'
            }
            Add-PartitionAccessPath @Params
            Start-Sleep -Seconds 5
        }
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
