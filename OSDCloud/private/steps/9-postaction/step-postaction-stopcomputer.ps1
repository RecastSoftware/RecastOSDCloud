function step-postaction-stopcomputer {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $currentStep = $global:OSDCloudCurrentStep
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Step: $($currentStep.name)"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] WinpeShutdown: $($global:OSDCloudWorkflowInvoke.WinpeShutdown)"
    if ($global:OSDCloudWorkflowInvoke.WinpeShutdown) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Shutdown requested; waiting 30 seconds before Stop-Computer."
        Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] Device will shut down in 30 seconds"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Press CTRL + C to cancel"
        #TODO EJECT ISO
        # (New-Object -ComObject 'Shell.Application').Namespace(17).Items() | Where-Object { $_.Type -eq 'CD Drive' } | ForEach-Object { $_.InvokeVerb('Eject') }
        Start-Sleep -Seconds 30
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Calling Stop-Computer."
        Stop-Computer
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Shutdown was not requested."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
