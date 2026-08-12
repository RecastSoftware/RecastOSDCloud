function step-preinstall-removeusbdriveletter {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    <#
        https://docs.microsoft.com/en-us/powershell/module/storage/remove-partitionaccesspath
        Partition Access Paths are being removed from USB Drive Letters
        This prevents issues when Drive Letters are reassigned
    #>

    # Store the USB Partitions
    $global:OSDCloudWorkflowInvoke.USBPartitions = Get-DeviceUSBPartition

    # Remove USB Drive Letters
    if ($global:OSDCloudWorkflowInvoke.USBPartitions) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing USB Drive Letters. OK."
        foreach ($Item in $global:OSDCloudWorkflowInvoke.USBPartitions) {
            $Params = @{
                AccessPath      = "$($Item.DriveLetter):"
                DiskNumber      = $Item.DiskNumber
                PartitionNumber = $Item.PartitionNumber
                ErrorAction     = 'SilentlyContinue'
            }
            Remove-PartitionAccessPath @Params
            Start-Sleep -Seconds 3
        }
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
