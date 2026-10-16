function Send-OSDCloudResults {
    <#
    .SYNOPSIS
        Sends reduced terminal deployment analytics.
    .DESCRIPTION
        Sends an OSDCloudResults PostHog event with an explicit property allowlist
        and a two-second timeout. Failures warn without stopping deployment.
    .EXAMPLE
        Send-OSDCloudResults
    .NOTES
        Reads global OSDCloudResults. The caller must finalize a started deployment
        before invoking this function. The existing workflow start event is separate.
    #>
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Sending deployment results"

    try {
        $results = $global:OSDCloudResults
        if ($null -eq $results.StartTimeUtc -or $results.Status -notin @('Completed', 'Failed')) {
            throw 'Only finalized, started deployment results can be sent.'
        }
        if ([string]::IsNullOrWhiteSpace($results.DistinctId)) {
            throw 'Deployment results have no analytics identity.'
        }
        $properties = @{}
        foreach ($name in @(
            'SchemaVersion', 'DeploymentId', 'IsComplete', 'Status',
            'totalDuration', 'totalDurationRAW',
            'timeDownload', 'timeCache', 'timeCopy', 'timeExpand', 'timeOther', 'timeCloud',
            'totalSizeDownloadMB', 'totalSizeCopyMB', 'totalSizeCacheMB', 'totalSizeMB', 'totalMBps',
            'ContentSource',
            'sizeOS',
            'sizeDriverPack',
            'stepClearDisk',
            'stepOSDownload',
            'stepOSCache',
            'stepOSCopy',
            'stepOSExpand',
            'stepDriverPackDownload',
            'stepDriverPackCache',
            'stepDriverPackCopy',
            'stepDriverPackExpand',
            'rateOSDownload', 'rateOSCache', 'rateOSCopy', 'rateOSExpand',
            'rateDriverPackDownload', 'rateDriverPackCache', 'rateDriverPackCopy', 'rateDriverPackExpand', 'Network',
            'ModuleVersion', 'WorkflowName', 'WorkflowTaskName', 'LaunchMethod', 'DeploymentPhase',
            'OSDManufacturer', 'OSDModel', 'OSDProduct', 'ProcessorArchitecture', 'TotalPhysicalMemoryGB',
            'OSName', 'OSVersion', 'OSBuild', 'OSBuildVersion', 'OSEditionId',
            'OSActivation', 'OSLanguageCode', 'OSFileName', 'DriverPackName', 'DriverPackFileName'
        )) {
            $properties[$name] = $results.$name
        }
        foreach ($name in 'StartTimeUtc', 'EndTimeUtc') {
            $properties[$name] = $results.$name.ToUniversalTime().ToString('o')
        }
        $properties['distinct_id'] = $results.DistinctId
        $payload = @{
            api_key    = 'phc_2h7nQJCo41Hc5C64B2SkcEBZOvJ6mHr5xAHZyjPl3ZK'
            event      = 'OSDCloudResults'
            properties = $properties
            timestamp  = [datetime]::UtcNow.ToString('o')
        }
        Invoke-RestMethod -Method Post -Uri 'https://us.i.posthog.com/capture/' `
            -Body ($payload | ConvertTo-Json -Depth 4 -Compress) -ContentType 'application/json' `
            -TimeoutSec 2 -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "Could not send OSDCloudResults analytics: $($_.Exception.Message)"
    }
}
