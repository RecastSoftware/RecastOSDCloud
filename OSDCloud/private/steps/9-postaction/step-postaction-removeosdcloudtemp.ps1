function step-postaction-removeosdcloudtemp {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Checking for the OSDCloud temporary directory'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $Step = $global:OSDCloudCurrentStep
        $Path = 'C:\Windows\Temp\osdcloud'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Checking for temporary OSDCloud files at:"
        Write-Host -ForegroundColor DarkGray "  $Path"

        if (Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop) {
            $FileCount = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue).Count
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Found $FileCount temporary file(s). Removing the OSDCloud temporary directory."
            $ProgressPhase = 'Removing the OSDCloud temporary directory'
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] OSDCloud temporary directory removed."
        }
        else {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] OSDCloud temporary directory was not found. No cleanup is needed."
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional temporary-file cleanup failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing without removing all OSDCloud temporary files."
    }
    #=================================================
}
