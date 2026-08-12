function step-install-restartosdcloudlogs {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $LogsPath = "C:\Windows\Temp\osdcloud-logs"

    $Params = @{
        Path        = $LogsPath
        ItemType    = 'Directory'
        Force       = $true
        ErrorAction = 'SilentlyContinue'
    }

    if (-not (Test-Path $Params.Path)) {
        New-Item @Params | Out-Null
    }

    $null = robocopy "X:\Windows\Temp\osdcloud-logs" "$LogsPath" transcript.log /e /move /ndl /nfl /r:0 /w:0
    $TranscriptFullName = Join-Path $LogsPath "transcript-$((Get-Date).ToString('yyyy-MM-dd-HHmmss')).log"

    $null = Start-Transcript -Path $TranscriptFullName -ErrorAction SilentlyContinue
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
