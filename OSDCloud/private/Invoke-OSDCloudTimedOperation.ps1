function Invoke-OSDCloudTimedOperation {
    <#
    .SYNOPSIS
        Measures a deployment operation without changing its output.
    .DESCRIPTION
        Accumulates unrounded seconds in the current workflow snapshot, including
        time spent in failed attempts. Results aggregation rounds each phase once.
    .PARAMETER Name
        Results duration property corresponding to the operation.
    .PARAMETER Action
        Operation to execute. Output and terminating errors propagate to the caller.
        Native exit codes must be checked inside this script block.
    .PARAMETER CachedFilePath
        Expected destination of a download helper that reuses existing files.
        An existing file classifies that operation as cache reuse, not download.
    .EXAMPLE
        Invoke-OSDCloudTimedOperation -Name stepOSCopy -Action { Copy-Item $source $destination }
    .NOTES
        Updates global OSDCloudWorkflowInvoke.Durations and CompletedTransfers.
        Successful acquisition operations identify copy/download sources independently
        of rounded timing. Reporting failures warn and never replace an operation error.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('stepOSCopy', 'stepOSDownload', 'stepOSCache', 'stepDriverPackCopy',
            'stepDriverPackDownload', 'stepDriverPackCache', 'stepOSExpand', 'stepDriverPackExpand', 'stepClearDisk')]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Action,
        [string]$CachedFilePath
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Measuring $Name"
    if ($CachedFilePath -and $Name -in @('stepOSDownload', 'stepDriverPackDownload', 'stepOSCache', 'stepDriverPackCache')) {
        if (Test-Path -LiteralPath $CachedFilePath -PathType Leaf) {
            $Name = $Name -replace '(Download|Cache)$', 'Copy'
        }
    }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Action
        $timer.Stop()
        if ($Name -in @('stepOSCopy', 'stepOSDownload', 'stepOSCache', 'stepDriverPackCopy', 'stepDriverPackDownload', 'stepDriverPackCache')) {
            try {
                if ($null -eq $global:OSDCloudWorkflowInvoke.CompletedTransfers) {
                    $global:OSDCloudWorkflowInvoke.CompletedTransfers = @{}
                }
                if (-not $CachedFilePath -or (Test-Path -LiteralPath $CachedFilePath -PathType Leaf -ErrorAction Stop)) {
                    $global:OSDCloudWorkflowInvoke.CompletedTransfers[$Name] = $true
                }
            }
            catch {
                Write-Warning "Could not record completed ${Name}: $($_.Exception.Message)"
            }
        }
    }
    finally {
        $timer.Stop()
        try {
            if ($null -eq $global:OSDCloudWorkflowInvoke.Durations) {
                $global:OSDCloudWorkflowInvoke.Durations = @{}
            }
            $global:OSDCloudWorkflowInvoke.Durations[$Name] += $timer.Elapsed.TotalSeconds
        }
        catch {
            Write-Warning "Could not record ${Name}: $($_.Exception.Message)"
        }
    }
}
