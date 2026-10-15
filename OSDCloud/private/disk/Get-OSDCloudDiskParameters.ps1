function Get-OSDCloudDiskParameters {
    <#
    .SYNOPSIS
        Resolves deployment partition settings into disk helper parameters.
    .DESCRIPTION
        Reads DiskLabelOS, DiskLabelRecovery, DiskSizeSystem, DiskSizeOS, and
        DiskSizeRecovery from OSDCloudDeploy or OSDCloudWorkflowInvoke. Older
        objects retain the existing defaults. Recovery force takes precedence
        over skip and virtual-machine detection.
    .PARAMETER Settings
        Deployment or workflow state containing the optional disk properties.
    .PARAMETER RecoveryPartitionForce
        Enables recovery even when skipped or running on a virtual machine.
    .PARAMETER RecoveryPartitionSkip
        Disables recovery unless forced.
    .PARAMETER IsVirtualMachine
        Whether recovery should be disabled by default for a virtual machine.
    .EXAMPLE
        Get-OSDCloudDiskParameters -Settings $global:OSDCloudWorkflowInvoke
    .OUTPUTS
        System.Collections.Hashtable
    .NOTES
        Returns a hashtable for New-OSDCloudDisk and Test-OSDCloudDiskLayout.
        DiskSizeOS is null when automatic Windows sizing is requested.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter(Mandatory)]
        [System.Object]$Settings,

        [System.Boolean]$RecoveryPartitionForce = [bool]$Settings.RecoveryPartition.Force,
        [System.Boolean]$RecoveryPartitionSkip = [bool]$Settings.RecoveryPartition.Skip,
        [System.Boolean]$IsVirtualMachine = ($global:OSDCoreDevice.IsVM -eq $true -or $IsVM -eq $true)
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Resolving disk customization and recovery policy."

    $parameters = @{
        PartitionStyle = 'GPT'
        LabelWindows = if ($null -ne $Settings.DiskLabelOS) { $Settings.DiskLabelOS } else { 'OS' }
        LabelRecovery = if ($null -ne $Settings.DiskLabelRecovery) { $Settings.DiskLabelRecovery } else { 'Recovery' }
        SizeSystemGpt = if ($null -ne $Settings.DiskSizeSystem) { $Settings.DiskSizeSystem } else { 500MB }
        SizeRecovery = if ($null -ne $Settings.DiskSizeRecovery) { $Settings.DiskSizeRecovery } else { 2000MB }
        NoRecoveryPartition = ($IsVirtualMachine -or $RecoveryPartitionSkip) -and -not $RecoveryPartitionForce
    }
    if ($null -ne $Settings.DiskSizeOS) {
        $parameters.SizeWindows = $Settings.DiskSizeOS
    }
    return $parameters
}
