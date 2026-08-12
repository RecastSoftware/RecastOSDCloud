function step-finalize-stoposdcloudworkflow {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    #region Main
    $global:OSDCloudWorkflowInvoke.TimeEnd = Get-Date
    $global:OSDCloudWorkflowInvoke.TimeSpan = New-TimeSpan -Start $global:OSDCloudWorkflowInvoke.TimeStart -End $global:OSDCloudWorkflowInvoke.TimeEnd
    $global:OSDCloudWorkflowInvoke | ConvertTo-Json | Out-File -FilePath 'C:\Windows\Temp\osdcloud-logs\OSDCloudWorkflowInvoke.json' -Encoding utf8 -Width 2000 -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Completed in $($global:OSDCloudWorkflowInvoke.TimeSpan.ToString("mm' minutes 'ss' seconds'"))"
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
