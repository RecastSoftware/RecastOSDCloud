function step-postaction-removeosdcloudlogs {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    #=================================================
    # Stop Transcript at this point as this file is locked and will cause issues with cleanup
    $null = Stop-Transcript -ErrorAction SilentlyContinue

    $LogsPath = "C:\Windows\Temp\osdcloud-logs"

    $Params = @{
        ErrorAction = 'SilentlyContinue'
        Force       = $true
        Path        = $LogsPath
        Recurse     = $true
    }

    if (Test-Path $LogsPath) {
        Remove-Item @Params | Out-Null
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
