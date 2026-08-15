<#
.SYNOPSIS
Displays the startup banner for an OSDCloud workflow task.

.DESCRIPTION
Writes the selected workflow task name to the host, gives the user five seconds
to cancel with Ctrl+C, and then allows the workflow executor to continue to the
next step. Task JSON files pass the root task name through the WorkflowTaskName
parameter so the banner matches the selected workflow task.

.PARAMETER WorkflowTaskName
Display name of the workflow task being started. The value should match the name
field at the root of the workflow task JSON file.

.EXAMPLE
step-initialize-osdcloudworkflowtask -WorkflowTaskName 'OSDCloud'

Displays the OSDCloud task startup message and waits five seconds before the
workflow continues.

.NOTES
Internal workflow step used by OSDCloud deployment tasks.

.OUTPUTS
None. This function does not return objects.
#>
function step-initialize-osdcloudworkflowtask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$WorkflowTaskName = "OSDCloud Workflow"
    )
    #=================================================
    $Error.Clear()
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] WorkflowTaskName: $WorkflowTaskName"

    # Display delay message to user
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Starting $WorkflowTaskName in 5 seconds..."
    Write-Host -ForegroundColor DarkGray "Press Ctrl+C to exit OSDCloud"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Waiting 5 seconds before workflow continues."
    Start-Sleep -Seconds 5
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
