function step-finalize-stoposdcloudworkflow {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Finalizing OSDCloud workflow timing'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $global:OSDCloudWorkflowInvoke.TimeEnd = Get-Date
        if ($global:OSDCloudWorkflowInvoke.TimeStart) {
            $global:OSDCloudWorkflowInvoke.TimeSpan = New-TimeSpan -Start $global:OSDCloudWorkflowInvoke.TimeStart -End $global:OSDCloudWorkflowInvoke.TimeEnd
            $ElapsedTime = $global:OSDCloudWorkflowInvoke.TimeSpan.ToString("mm' minutes 'ss' seconds'")
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] OSDCloud workflow elapsed time: $ElapsedTime."
        }
        else {
            $ElapsedTime = 'Unavailable (workflow start time was not recorded)'
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Workflow start time was not recorded; elapsed time is unavailable."
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] TimeStart: $($global:OSDCloudWorkflowInvoke.TimeStart); TimeEnd: $($global:OSDCloudWorkflowInvoke.TimeEnd); TimeSpan: $($global:OSDCloudWorkflowInvoke.TimeSpan)"

        $WorkflowSnapshotPath = 'C:\Windows\Temp\osdcloud-logs\OSDCloudWorkflowInvoke.json'
        $ProgressPhase = 'Saving the workflow invocation snapshot'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Saving workflow invocation details to:"
        Write-Host -ForegroundColor DarkGray "  $WorkflowSnapshotPath"
        try {
            $global:OSDCloudWorkflowInvoke |
                ConvertTo-Json -ErrorAction Stop |
                Out-File -FilePath $WorkflowSnapshotPath -Encoding utf8 -Width 2000 -Force -ErrorAction Stop
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Workflow invocation snapshot saved."
        }
        catch {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Could not save workflow invocation snapshot: $($_.Exception.Message)"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Workflow finalization will continue without the snapshot."
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional workflow finalization failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] OSDCloud deployment has completed; workflow finalization errors will not stop the deployment."
    }
    #=================================================
}
