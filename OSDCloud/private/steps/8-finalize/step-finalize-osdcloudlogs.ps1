function step-finalize-osdcloudlogs {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Preparing the OSDCloud log directory'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $Step = $global:OSDCloudCurrentStep
        $LogsPath = 'C:\Windows\Temp\osdcloud-logs'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Preparing OSDCloud deployment logs."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Log collection destination:"
        Write-Host -ForegroundColor DarkGray "  $LogsPath"

        if (-not (Test-Path -LiteralPath $LogsPath -PathType Container -ErrorAction Stop)) {
            $ProgressPhase = 'Creating the OSDCloud log directory'
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Creating log directory:"
            Write-Host -ForegroundColor DarkGray "  $LogsPath"
            New-Item -Path $LogsPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $DismLogSource = Join-Path $env:SystemRoot 'logs\dism\dism.log'
        $DismLogDestination = Join-Path $LogsPath 'dism.log'
        $ProgressPhase = 'Collecting the DISM log'
        if (Test-Path -LiteralPath $DismLogSource -PathType Leaf -ErrorAction Stop) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Copying DISM log from:"
            Write-Host -ForegroundColor DarkGray "  $DismLogSource"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Copying DISM log to:"
            Write-Host -ForegroundColor DarkGray "  $DismLogDestination"
            Copy-Item -LiteralPath $DismLogSource -Destination $DismLogDestination -Force -ErrorAction Stop
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] DISM log copied successfully."
        }
        else {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] DISM log was not found at:"
            Write-Host -ForegroundColor DarkGray "  $DismLogSource"
        }

        $ProgressPhase = 'Stopping the PowerShell transcript'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Stopping the PowerShell transcript, if one is active."
        try {
            $null = Stop-Transcript -ErrorAction Stop
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] PowerShell transcript stopped."
        }
        catch {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] No active transcript was stopped: $($_.Exception.Message)"
        }

        if ($env:SystemDrive -eq 'X:') {
            $WinPELogsPath = 'X:\Windows\Temp\osdcloud-logs'
            $ProgressPhase = 'Copying WinPE logs to the target Windows volume'
            if (Test-Path -LiteralPath $WinPELogsPath -PathType Container -ErrorAction Stop) {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Copying WinPE logs from:"
                Write-Host -ForegroundColor DarkGray "  $WinPELogsPath"
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Copying WinPE logs to:"
                Write-Host -ForegroundColor DarkGray "  $LogsPath"
                & robocopy.exe $WinPELogsPath $LogsPath '*.*' /e /ndl /nfl /njh /njs /r:0 /w:0
                $RobocopyExitCode = $LASTEXITCODE
                if ($RobocopyExitCode -ge 8) {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] WinPE log copy returned robocopy exit code $RobocopyExitCode."
                }
                else {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] WinPE log copy completed (robocopy exit code $RobocopyExitCode)."
                }
            }
            else {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] WinPE log directory was not found:"
                Write-Host -ForegroundColor DarkGray "  $WinPELogsPath"
            }
        }
        else {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] SystemDrive is $env:SystemDrive; skipping WinPE log copy."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] SystemDrive is $env:SystemDrive. WinPE log copy is not required."
        }

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] OSDCloud log collection completed."
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional log collection failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing OSDCloud without completing all log collection tasks."
    }
    #=================================================
}
