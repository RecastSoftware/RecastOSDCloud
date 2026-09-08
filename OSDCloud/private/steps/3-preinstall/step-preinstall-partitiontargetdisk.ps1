function step-preinstall-partitiontargetdisk {
    [CmdletBinding()]
    param (
        [System.String]
        $RecoveryPartitionForce = $global:OSDCloudWorkflowInvoke.RecoveryPartition.Force,

        [System.String]
        $RecoveryPartitionSkip = $global:OSDCloudWorkflowInvoke.RecoveryPartition.Skip,

        [Int32]
        $DiskNumber = $global:OSDCloudWorkflowInvoke.DiskPartition.DiskNumber
    )
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DiskNumber: $DiskNumber"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] RecoveryPartitionForce: $RecoveryPartitionForce; RecoveryPartitionSkip: $RecoveryPartitionSkip; IsVM: $IsVM"

    # Mental Math
    $RecoveryPartition = $true
    if ($IsVM -eq $true) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Virtual machine detected; recovery partition disabled unless forced."
        $RecoveryPartition = $false
    }
    if ($RecoveryPartitionSkip) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] RecoveryPartitionSkip requested; recovery partition disabled."
        $RecoveryPartition = $false
    }
    if ($RecoveryPartitionForce) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] RecoveryPartitionForce requested; recovery partition enabled."
        $RecoveryPartition = $true
    }

    if ($RecoveryPartition -eq $false) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating GPT disk without recovery partition."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Recovery Partition will not be created. OK."
        New-OSDCloudDisk -PartitionStyle GPT -NoRecoveryPartition -Force -ErrorAction Stop
        Write-Host "=========================================================================" -ForegroundColor DarkCyan
        Write-Host "| SYSTEM | MSR |                    WINDOWS                             |" -ForegroundColor DarkCyan
        Write-Host "=========================================================================" -ForegroundColor DarkCyan
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating GPT disk with 2000MB recovery partition."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] 2GB Recovery Partition will be created. OK."
        if ($DiskNumber) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] New-OSDCloudDisk target DiskNumber: $DiskNumber"
            New-OSDCloudDisk -PartitionStyle GPT -DiskNumber $DiskNumber -SizeRecovery 2000MB -Force -ErrorAction Stop
        }
        else {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] New-OSDCloudDisk will use its default target disk selection."
            New-OSDCloudDisk -PartitionStyle GPT -SizeRecovery 2000MB -Force -ErrorAction Stop
        }
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
