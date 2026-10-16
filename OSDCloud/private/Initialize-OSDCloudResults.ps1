function Initialize-OSDCloudResults {
    <#
    .SYNOPSIS
        Creates a fresh deployment results summary.
    .DESCRIPTION
        Resets the global OSDCloudResults object for one Deploy-OSDCloud invocation.
        Timing remains null until deployment starts.
    .PARAMETER ModuleVersion
        Version of the module running the deployment.
    .PARAMETER WorkflowName
        Selected workflow name.
    .PARAMETER LaunchMethod
        CLI or GUI launch method.
    .EXAMPLE
        Initialize-OSDCloudResults -ModuleVersion '26.10.15.1' -WorkflowName default -LaunchMethod CLI
    .NOTES
        Populates global OSDCloudResults. Does not collect or transmit device data.
    #>
    [CmdletBinding()]
    param (
        [string]$ModuleVersion,
        [string]$WorkflowName,
        [ValidateSet('CLI', 'GUI')]
        [string]$LaunchMethod
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Initializing deployment results"

    $global:OSDCloudResults = [pscustomobject][ordered]@{
        SchemaVersion         = 1
        DeploymentId          = [guid]::NewGuid().ToString()
        DistinctId            = $null
        IsComplete            = $false
        Status                = 'NotStarted'
        StartTimeUtc          = $null
        EndTimeUtc            = $null
        totalDuration         = $null
        totalDurationRAW      = $null
        totalSizeMB           = $null
        totalMBps             = $null
        sizeOS                = $null
        sizeDriverPack        = $null
        totalSizeDownloadMB   = $null
        totalSizeCacheMB      = $null
        totalSizeCopyMB       = $null
        ContentInternet       = $null
        ContentLocal          = $null
        timeCloud             = $null
        timeDownload          = $null
        timeCache             = $null
        timeCopy              = $null
        timeExpand            = $null
        timeOther             = $null
        stepClearDisk         = $null
        stepOSDownload        = $null
        stepOSCache           = $null
        stepOSCopy            = $null
        stepOSExpand          = $null
        stepDriverPackDownload = $null
        stepDriverPackCache   = $null
        stepDriverPackCopy    = $null
        stepDriverPackExpand  = $null
        rateOSDownload        = $null
        rateOSCache           = $null
        rateOSCopy            = $null
        rateOSExpand          = $null
        rateDriverPackDownload = $null
        rateDriverPackCache   = $null
        rateDriverPackCopy    = $null
        rateDriverPackExpand  = $null
        Network               = $null
        ContentSource         = $null
        ModuleVersion         = $ModuleVersion
        WorkflowName          = $WorkflowName
        WorkflowTaskName      = $null
        LaunchMethod          = $LaunchMethod
        DeploymentPhase       = if ($env:SystemDrive -eq 'X:') { 'WinPE' } else { 'Windows' }
        OSDManufacturer       = $null
        OSDModel              = $null
        OSDProduct            = $null
        ProcessorArchitecture = $null
        TotalPhysicalMemoryGB = $null
        OSName                = $null
        OSVersion             = $null
        OSBuild               = $null
        OSBuildVersion        = $null
        OSEditionId           = $null
        OSActivation          = $null
        OSLanguageCode        = $null
        OSFileName            = $null
        DriverPackName        = $null
        DriverPackFileName    = $null
    }
}
