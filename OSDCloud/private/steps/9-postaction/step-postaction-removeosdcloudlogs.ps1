function step-postaction-removeosdcloudlogs {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    # Stop Transcript at this point as this file is locked and will cause issues with cleanup
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Stopping transcript before log cleanup."
    $null = Stop-Transcript -ErrorAction SilentlyContinue

    $LogsPath = "C:\Windows\Temp\osdcloud-logs"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] LogsPath: $LogsPath"

    $Params = @{
        ErrorAction = 'SilentlyContinue'
        Force       = $true
        Path        = $LogsPath
        Recurse     = $true
    }

    if (Test-Path $LogsPath) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Removing OSDCloud logs path: $LogsPath"
        Remove-Item @Params | Out-Null
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] LogsPath was not found. Nothing to remove."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
