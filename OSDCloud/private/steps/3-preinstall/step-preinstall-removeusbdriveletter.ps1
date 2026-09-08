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
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] USB partition count: $(@($global:OSDCloudWorkflowInvoke.USBPartitions).Count)"

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
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Removing access path $($Params.AccessPath) from Disk $($Params.DiskNumber), Partition $($Params.PartitionNumber)."
            Remove-PartitionAccessPath @Params
            Start-Sleep -Seconds 3
        }
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No USB partitions were found."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
