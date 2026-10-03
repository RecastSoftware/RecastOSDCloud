function step-postaction-removeosdcloudlogs {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Preparing to remove OSDCloud logs'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $Step = $global:OSDCloudCurrentStep
        $LogsPath = 'C:\Windows\Temp\osdcloud-logs'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Preparing to remove temporary OSDCloud logs."

        $ProgressPhase = 'Stopping the PowerShell transcript'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Stopping the PowerShell transcript before log cleanup."
        try {
            $null = Stop-Transcript -ErrorAction Stop
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] PowerShell transcript stopped."
        }
        catch {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] No active transcript was stopped: $($_.Exception.Message)"
        }

        $ProgressPhase = 'Checking for the OSDCloud log directory'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Checking for OSDCloud logs at:"
        Write-Host -ForegroundColor DarkGray "  $LogsPath"
        if (Test-Path -LiteralPath $LogsPath -PathType Container -ErrorAction Stop) {
            $LogFileCount = @(Get-ChildItem -LiteralPath $LogsPath -File -Recurse -Force -ErrorAction SilentlyContinue).Count
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Found $LogFileCount log file(s). Removing the log directory."
            $ProgressPhase = 'Removing the OSDCloud log directory'
            Remove-Item -LiteralPath $LogsPath -Recurse -Force -ErrorAction Stop
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] OSDCloud log directory removed."
        }
        else {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] OSDCloud log directory was not found. No log cleanup is needed."
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional log cleanup failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing without removing all OSDCloud logs."
    }
    #=================================================
}
