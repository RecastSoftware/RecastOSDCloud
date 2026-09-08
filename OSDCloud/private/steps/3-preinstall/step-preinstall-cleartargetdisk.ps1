function step-preinstall-cleartargetdisk {
    [CmdletBinding()]
    param (
        # We should always confirm to Clear-Disk as this is destructive
        [System.Boolean]
        $Confirm = $true
    )
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Initial Confirm: $Confirm"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Force: $($global:OSDCloudWorkflowInvoke.Force)"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] LocalDisk count: $(@($global:OSDCoreDevice.LocalDisk).Count)"

    if ($global:OSDCloudWorkflowInvoke.Force -eq $true) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Force is enabled; Clear-Disk confirmation will be disabled."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Force was specified. Clear-Disk confirmation prompts are disabled"
        $Confirm = $false
    }

    # If Confirm is set to false, we need to check if there are multiple disks
    if (($Confirm -eq $false) -and ($global:OSDCloudWorkflowInvoke.Force -ne $true) -and (@($global:OSDCoreDevice.LocalDisk).Count -ge 2)) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Multiple fixed disks detected without Force; re-enabling confirmation."
        Write-Warning "[$(Get-Date -format s)] OSDCloud has detected more than 1 Fixed Disk is installed. Clear-Disk with Confirm is required"
        $Confirm = $true
    }

    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Calling Clear-DeviceLocalDisk with Confirm=$Confirm."
    Clear-DeviceLocalDisk -Force -NoResults -Confirm:$Confirm -ErrorAction Stop
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
