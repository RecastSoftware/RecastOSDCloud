<#
.SYNOPSIS
Starts transcript logging for an OSDCloud workflow task.

.DESCRIPTION
Creates the OSDCloud workflow log directory under the current temporary path and
starts a PowerShell transcript with a timestamped file name. This step is normally
run near the beginning of an OSDCloud workflow task after the workflow task banner
has been displayed.

The transcript is written to $env:TEMP\osdcloud-logs, which resolves to the WinPE
temporary path when running from WinPE and to the current Windows temporary path
when the step is allowed to run in a full OS test context.

.EXAMPLE
step-initialize-osdcloudlogs

Creates the workflow log directory and starts transcript logging.

.NOTES
Internal workflow step used by OSDCloud deployment tasks.

.OUTPUTS
None. This function does not return objects.
#>
function step-initialize-osdcloudlogs {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $LogsPath = "$env:TEMP\osdcloud-logs"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] LogsPath: $LogsPath"

    $null = New-Item -Path $LogsPath -ItemType Directory -Force -ErrorAction SilentlyContinue

    $TranscriptFullName = Join-Path $LogsPath "transcript-$((Get-Date).ToString('yyyy-MM-dd-HHmmss')).log"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Starting transcript: $TranscriptFullName"
    if (-not (Start-Transcript -Path $TranscriptFullName -ErrorAction SilentlyContinue)) {
        Write-Warning "[$(Get-Date -format s)] Failed to start transcript at $TranscriptFullName"
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
