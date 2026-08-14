function step-postaction-stopcomputer {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $currentStep = $global:OSDCloudCurrentStep
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Step: $($currentStep.name)"
    if ($global:OSDCloudWorkflowInvoke.WinpeShutdown) {
        Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] Device will shut down in 30 seconds"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Press CTRL + C to cancel"
        #TODO EJECT ISO
        # (New-Object -ComObject 'Shell.Application').Namespace(17).Items() | Where-Object { $_.Type -eq 'CD Drive' } | ForEach-Object { $_.InvokeVerb('Eject') }
        Start-Sleep -Seconds 30
        Stop-Computer
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
