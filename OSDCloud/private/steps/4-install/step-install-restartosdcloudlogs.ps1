function step-install-restartosdcloudlogs {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
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

    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Moving WinPE transcript logs into offline Windows log path."
    $null = robocopy "X:\Windows\Temp\osdcloud-logs" "$LogsPath" transcript.log /e /move /ndl /nfl /r:0 /w:0
    $TranscriptFullName = Join-Path $LogsPath "transcript-$((Get-Date).ToString('yyyy-MM-dd-HHmmss')).log"

    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Restarting transcript: $TranscriptFullName"
    $null = Start-Transcript -Path $TranscriptFullName -ErrorAction SilentlyContinue
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
