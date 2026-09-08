function step-finalize-osdcloudlogs {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    #region Main
    $LogsPath = "C:\Windows\Temp\osdcloud-logs"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] LogsPath: $LogsPath"

    $Params = @{
        Path        = $LogsPath
        ItemType    = 'Directory'
        Force       = $true
        ErrorAction = 'SilentlyContinue'
    }

    if (-not (Test-Path $Params.Path)) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating logs path: $($Params.Path)"
        New-Item @Params | Out-Null
    }

    # Copy the DISM log to C:\Windows\Temp\osdcloud-logs
    if (Test-Path "$env:SystemRoot\logs\dism\dism.log") {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Copying DISM log from $env:SystemRoot\logs\dism\dism.log."
        Copy-Item -Path "$env:SystemRoot\logs\dism\dism.log" -Destination 'C:\Windows\Temp\osdcloud-logs\dism.log' -Force | Out-Null
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DISM log was not found at $env:SystemRoot\logs\dism\dism.log."
    }

    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Stopping transcript."
    $null = Stop-Transcript -ErrorAction SilentlyContinue

    # Copy existing WinPE Logs to C:\Windows\Temp\osdcloud-logs
    if ($env:SystemDrive -eq 'X:') {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Copying WinPE logs from X:\Windows\Temp\osdcloud-logs to C:\Windows\Temp\osdcloud-logs."
        $null = robocopy "X:\Windows\Temp\osdcloud-logs" "C:\Windows\Temp\osdcloud-logs" *.* /e /ndl /r:0 /w:0
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] SystemDrive is $env:SystemDrive; skipping WinPE log copy."
    }
    #endregion
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
