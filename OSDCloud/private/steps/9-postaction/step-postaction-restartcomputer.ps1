function step-postaction-restartcomputer {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Checking whether a restart was requested'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $Step = $global:OSDCloudCurrentStep
        $RestartRequested = [bool]$global:OSDCloudWorkflowInvoke.WinpeRestart
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] WinpeRestart: $RestartRequested"

        if (-not $RestartRequested) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] No restart was requested. The computer will remain running."
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
            return
        }

        $DelaySeconds = 30
        Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] [PROGRESS] OSDCloud has completed. The computer will restart in $DelaySeconds seconds."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Press CTRL+C to cancel the restart."
        $ProgressPhase = "Waiting $DelaySeconds seconds before restart"
        Start-Sleep -Seconds $DelaySeconds -ErrorAction Stop

        $ProgressPhase = 'Restarting the computer'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Restarting the computer now."
        Restart-Computer -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Post-action restart failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] OSDCloud has completed; the restart failure will not stop the workflow."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
