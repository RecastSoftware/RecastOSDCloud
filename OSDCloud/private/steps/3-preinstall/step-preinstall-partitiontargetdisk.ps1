function step-preinstall-partitiontargetdisk {
    [CmdletBinding()]
    param (
        [System.Boolean]
        $RecoveryPartitionForce = $global:OSDCloudWorkflowInvoke.RecoveryPartition.Force,

        [System.Boolean]
        $RecoveryPartitionSkip = $global:OSDCloudWorkflowInvoke.RecoveryPartition.Skip,

        [System.Nullable[System.Int32]]
        $DiskNumber = $global:OSDCloudWorkflowInvoke.DeploymentDiskNumber
    )
    #=================================================
    $Error.Clear()
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DiskNumber: $DiskNumber"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] RecoveryPartitionForce: $RecoveryPartitionForce; RecoveryPartitionSkip: $RecoveryPartitionSkip; IsVM: $IsVM"

    $diskParameters = Get-OSDCloudDiskParameters -Settings $global:OSDCloudWorkflowInvoke `
        -RecoveryPartitionForce $RecoveryPartitionForce -RecoveryPartitionSkip $RecoveryPartitionSkip
    if ($null -ne $DiskNumber) {
        $diskParameters.DiskNumber = $DiskNumber
    }
    $diskParameters.Force = $true
    $diskParameters.ErrorAction = 'Stop'

    if ($diskParameters.NoRecoveryPartition) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating GPT disk without recovery partition."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Recovery Partition will not be created. OK."
        New-OSDCloudDisk @diskParameters
        Write-Host "=========================================================================" -ForegroundColor DarkCyan
        Write-Host "| SYSTEM | MSR |                    WINDOWS                             |" -ForegroundColor DarkCyan
        Write-Host "=========================================================================" -ForegroundColor DarkCyan
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating GPT disk with $($diskParameters.SizeRecovery) byte recovery partition."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($diskParameters.SizeRecovery / 1MB)MB Recovery Partition will be created. OK."
        New-OSDCloudDisk @diskParameters
        Write-Host "=========================================================================" -ForegroundColor DarkCyan
        Write-Host "| SYSTEM | MSR |                    WINDOWS                  | RECOVERY |" -ForegroundColor DarkCyan
        Write-Host "=========================================================================" -ForegroundColor DarkCyan
    }
    Start-Sleep -Seconds 5

    # Make sure that there is a PSDrive
    if (!(Get-PSDrive -Name 'C')) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] PSDrive C was not created after partitioning."
        Write-Warning "[$(Get-Date -format s)] Failed to create a PSDrive FileSystem at C:\."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Press Ctrl+C to exit OSDCloud"
        Start-Sleep -Seconds 86400
        exit
    }
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] PSDrive C is available after partitioning."
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
