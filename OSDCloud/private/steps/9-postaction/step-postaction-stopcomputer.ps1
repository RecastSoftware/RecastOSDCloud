function step-postaction-stopcomputer {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Checking whether shutdown was requested'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $CurrentStep = $global:OSDCloudCurrentStep
        $ShutdownRequested = [bool]$global:OSDCloudWorkflowInvoke.WinpeShutdown
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Step: $($CurrentStep.name); WinpeShutdown: $ShutdownRequested"

        if (-not $ShutdownRequested) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] No shutdown was requested. The computer will remain running."
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
            return
        }

        $DelaySeconds = 30
        Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] [PROGRESS] OSDCloud has completed. The computer will shut down in $DelaySeconds seconds."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Press CTRL+C to cancel the shutdown."
        $ProgressPhase = "Waiting $DelaySeconds seconds before shutdown"
        Start-Sleep -Seconds $DelaySeconds -ErrorAction Stop

        $ProgressPhase = 'Shutting down the computer'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Shutting down the computer now."
        Stop-Computer -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Post-action shutdown failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] OSDCloud has completed; the shutdown failure will not stop the workflow."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
