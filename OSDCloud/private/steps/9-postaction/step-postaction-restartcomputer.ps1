function step-postaction-restartcomputer {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    #region Main
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] WinpeRestart: $($global:OSDCloudWorkflowInvoke.WinpeRestart)"
    if ($global:OSDCloudWorkflowInvoke.WinpeRestart) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Restart requested; waiting 30 seconds before Restart-Computer."
        Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] Device will restart in 30 seconds"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Press CTRL + C to cancel"
        #TODO EJECT ISO
        # (New-Object -ComObject 'Shell.Application').Namespace(17).Items() | Where-Object { $_.Type -eq 'CD Drive' } | ForEach-Object { $_.InvokeVerb('Eject') }
        Start-Sleep -Seconds 30
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Calling Restart-Computer."
        Restart-Computer
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Restart was not requested."
    }
    #endregion
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
