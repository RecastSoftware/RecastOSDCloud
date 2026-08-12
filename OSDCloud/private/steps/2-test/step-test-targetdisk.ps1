<#
.SYNOPSIS
Validates that OSDCloud detected a local deployment disk.

.DESCRIPTION
Checks $global:OSDCloudDeploy.DeploymentDisk before destructive preinstall steps run.
When a fixed local disk is detected, the step writes an informational success
message and allows the workflow to continue. When no fixed local disk is detected,
the step warns that WinPE may require additional storage, SCSI, or RAID drivers,
then waits so the user can cancel the deployment.

.EXAMPLE
step-test-targetdisk

Validates that a fixed local disk is available for the workflow.

.NOTES
Internal workflow step used by OSDCloud deployment tasks.

.OUTPUTS
None. This function does not return objects.
#>
function step-test-targetdisk {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    if ($global:OSDCloudDeploy.DeploymentDisk) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Fixed Disk is valid. OK."
    }
    else {
        Write-Warning "[$(Get-Date -format s)] Unable to detect a Fixed Disk."
        Write-Warning "[$(Get-Date -format s)] WinPE may need additional Disk, SCSI or Raid Drivers."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
