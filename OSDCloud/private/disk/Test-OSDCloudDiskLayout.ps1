function Test-OSDCloudDiskLayout {
    <#
    .SYNOPSIS
        Validates partition labels, sizes, and target disk capacity.
    .DESCRIPTION
        Fails before disk clearing when the requested layout cannot fit. Reserves
        system, GPT MSR, enabled recovery, and alignment/metadata space. Without
        SizeWindows, retains the existing automatic Windows sizing behavior.
    .PARAMETER DiskSize
        Total target disk capacity in bytes, before clearing.
    .PARAMETER PartitionStyle
        GPT or MBR partition layout.
    .PARAMETER LabelWindows
        Nonblank Windows NTFS label, at most 32 characters.
    .PARAMETER LabelRecovery
        Nonblank recovery NTFS label, at most 32 characters.
    .PARAMETER SizeSystemGpt
        GPT system partition size in bytes.
    .PARAMETER SizeSystemMbr
        MBR system partition size in bytes.
    .PARAMETER SizeMSR
        GPT MSR partition size in bytes.
    .PARAMETER SizeRecovery
        Recovery partition size in bytes.
    .PARAMETER SizeWindows
        Optional fixed Windows partition size in bytes, at least 32GB.
    .PARAMETER NoRecoveryPartition
        Excludes recovery from the capacity calculation.
    .EXAMPLE
        Test-OSDCloudDiskLayout -DiskSize 256GB -SizeWindows 100GB
    .OUTPUTS
        None.
    .NOTES
        Does not access or modify disks. Returns no output on success.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateRange(1, [System.UInt64]::MaxValue)]
        [System.UInt64]$DiskSize,

        [ValidateSet('GPT', 'MBR')]
        [System.String]$PartitionStyle = 'GPT',

        [ValidateLength(1, 32)]
        [ValidatePattern('^(?!\s*$)[^\x00-\x1f\\/:*?"<>|+,;=\[\]]+$')]
        [System.String]$LabelWindows = 'OS',

        [ValidateLength(1, 32)]
        [ValidatePattern('^(?!\s*$)[^\x00-\x1f\\/:*?"<>|+,;=\[\]]+$')]
        [System.String]$LabelRecovery = 'Recovery',

        [ValidateRange(100MB, 3000MB)]
        [System.UInt64]$SizeSystemGpt = 500MB,

        [ValidateRange(100MB, 3000MB)]
        [System.UInt64]$SizeSystemMbr = 500MB,

        [ValidateRange(16MB, 128MB)]
        [System.UInt64]$SizeMSR = 16MB,

        [ValidateRange(350MB, 80000MB)]
        [System.UInt64]$SizeRecovery = 2000MB,

        [ValidateRange(32GB, [System.UInt64]::MaxValue)]
        [System.UInt64]$SizeWindows,

        [System.Management.Automation.SwitchParameter]$NoRecoveryPartition
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Validating $PartitionStyle layout against $DiskSize bytes."

    $systemSize = if ($PartitionStyle -eq 'GPT') { $SizeSystemGpt } else { $SizeSystemMbr }
    $msrSize = if ($PartitionStyle -eq 'GPT') { $SizeMSR } else { 0 }
    $recoverySize = if ($NoRecoveryPartition) { 0 } else { $SizeRecovery }
    $windowsSize = if ($PSBoundParameters.ContainsKey('SizeWindows')) { $SizeWindows } else { 1MB }
    # Decimal arithmetic avoids overflow. Allow for per-partition MiB alignment and disk metadata.
    $requiredSize = [decimal]$systemSize + $msrSize + $recoverySize + $windowsSize + 5MB
    if ($requiredSize -gt $DiskSize) {
        throw "The requested $PartitionStyle partition layout requires $requiredSize bytes including alignment; target disk capacity is $DiskSize bytes. No disk should be cleared."
    }
}
