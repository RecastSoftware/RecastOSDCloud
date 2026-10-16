function Update-OSDCloudResults {
    <#
    .SYNOPSIS
        Updates reduced deployment results metadata.
    .DESCRIPTION
        Copies selected scalar device and deployment properties to OSDCloudResults.
        Resolves a pseudonymous analytics identity once per results object.
    .EXAMPLE
        Update-OSDCloudResults
    .NOTES
        Reads global OSDCoreDevice and OSDCloudDeploy; updates global OSDCloudResults.
        Does not include raw UUIDs, license identifiers, URLs, or exception text.
    #>
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Updating deployment results metadata"

    try {
        foreach ($name in 'OSDManufacturer', 'OSDModel', 'OSDProduct', 'ProcessorArchitecture', 'TotalPhysicalMemoryGB') {
            $global:OSDCloudResults.$name = $global:OSDCoreDevice.$name
        }
        $workflow = $global:OSDCloudWorkflowInvoke
        $downloadBytes = 0L
        $copyBytes = 0L
        $cacheBytes = 0L
        $hasAcquisition = $false
        $hasCloudSource = $false
        $hasCacheSource = $false
        $hasUnknownSource = $false
        $global:OSDCloudResults.ContentSource = $null
        foreach ($content in 'OS', 'DriverPack') {
            $acquisition = $workflow."${content}Acquisition"
            if ($null -ne $acquisition) {
                $global:OSDCloudResults."size${content}" = [long][math]::Round($acquisition.Bytes / 1MB, 0, [MidpointRounding]::AwayFromZero)
                if ($acquisition.Downloaded) { $downloadBytes += $acquisition.Bytes }
                if ($acquisition.Copied) { $copyBytes += $acquisition.Bytes }
                if ($acquisition.Cached) { $cacheBytes += $acquisition.Bytes }
                if ($acquisition.Downloaded -or $acquisition.Cached) {
                    $hasCloudSource = $true
                }
                elseif ($acquisition.Copied) {
                    $hasCacheSource = $true
                }
                else {
                    $hasUnknownSource = $true
                }
                $hasAcquisition = $true
            }
        }
        if (-not $hasUnknownSource) {
            if ($hasCloudSource -and $hasCacheSource) { $global:OSDCloudResults.ContentSource = 'Mixed' }
            elseif ($hasCloudSource) { $global:OSDCloudResults.ContentSource = 'Cloud' }
            elseif ($hasCacheSource) { $global:OSDCloudResults.ContentSource = 'Cache' }
        }
        if ($hasAcquisition) {
            $global:OSDCloudResults.totalSizeDownloadMB = [long][math]::Round($downloadBytes / 1MB, 0, [MidpointRounding]::AwayFromZero)
            $global:OSDCloudResults.totalSizeCopyMB = [long][math]::Round($copyBytes / 1MB, 0, [MidpointRounding]::AwayFromZero)
            $global:OSDCloudResults.totalSizeCacheMB = [long][math]::Round($cacheBytes / 1MB, 0, [MidpointRounding]::AwayFromZero)
            $global:OSDCloudResults.totalSizeMB = [long](
                [long]$global:OSDCloudResults.sizeOS + [long]$global:OSDCloudResults.sizeDriverPack)
        }
        foreach ($name in 'stepOSCopy', 'stepOSDownload', 'stepOSCache', 'stepOSExpand',
            'stepDriverPackCopy', 'stepDriverPackDownload', 'stepDriverPackCache', 'stepDriverPackExpand', 'stepClearDisk') {
            if ($null -ne $workflow.Durations -and $null -ne $workflow.Durations[$name]) {
                $global:OSDCloudResults.$name = [long][math]::Round($workflow.Durations[$name], 0, [MidpointRounding]::AwayFromZero)
            }
        }
        if ($null -ne $global:OSDCloudResults.totalDurationRAW) {
            $stepTotal = 0L
            foreach ($operation in 'Download', 'Cache', 'Copy', 'Expand') {
                $operationTotal = 0L
                foreach ($content in 'OS', 'DriverPack') {
                    $duration = $global:OSDCloudResults."step${content}${operation}"
                    if ($null -ne $duration) {
                        $operationTotal += [long]$duration
                    }
                }
                $global:OSDCloudResults."time${operation}" = $operationTotal
                $stepTotal += $operationTotal
            }
            if ($null -ne $global:OSDCloudResults.stepClearDisk) {
                $stepTotal += [long]$global:OSDCloudResults.stepClearDisk
            }
            $global:OSDCloudResults.timeCloud = [long](
                $global:OSDCloudResults.timeDownload + $global:OSDCloudResults.timeCache)
            $global:OSDCloudResults.timeOther = [long][math]::Max(
                0, $global:OSDCloudResults.totalDurationRAW - $stepTotal)
        }
        foreach ($content in 'OS', 'DriverPack') {
            foreach ($operation in 'Download', 'Cache', 'Copy', 'Expand') {
                $size = $global:OSDCloudResults."size${content}"
                $seconds = $global:OSDCloudResults."step${content}${operation}"
                $global:OSDCloudResults."rate${content}${operation}" = $null
                if ($null -ne $size -and $size -ge 0 -and $null -ne $seconds -and $seconds -gt 0) {
                    $global:OSDCloudResults."rate${content}${operation}" = [long][math]::Round(
                        $size / [double]$seconds, 0, [MidpointRounding]::AwayFromZero)
                }
            }
        }
        if ($null -ne $global:OSDCloudResults.totalDurationRAW) {
            $global:OSDCloudResults.totalDuration = [long][math]::Max(0,
                $global:OSDCloudResults.totalDurationRAW - [long]$global:OSDCloudResults.stepClearDisk)
        }
        $global:OSDCloudResults.totalMBps = $null
        if ($null -ne $global:OSDCloudResults.totalSizeMB -and
            $null -ne $global:OSDCloudResults.totalDuration -and
            $global:OSDCloudResults.totalDuration -gt 0) {
            $global:OSDCloudResults.totalMBps = [long][math]::Round(
                $global:OSDCloudResults.totalSizeMB / [double]$global:OSDCloudResults.totalDuration,
                0, [MidpointRounding]::AwayFromZero)
        }
        foreach ($name in 'WorkflowTaskName', 'OSEditionId', 'DriverPackName') {
            $global:OSDCloudResults.$name = $global:OSDCloudDeploy.$name
            if ($null -ne $workflow.$name) {
                $global:OSDCloudResults.$name = $workflow.$name
            }
        }
        $operatingSystem = $global:OSDCloudDeploy.OperatingSystemCloudObject
        if ($null -ne $workflow.OperatingSystemCloudObject) {
            $operatingSystem = $workflow.OperatingSystemCloudObject
        }
        foreach ($name in 'OSName', 'OSVersion', 'OSBuild', 'OSBuildVersion', 'OSActivation', 'OSLanguageCode') {
            $global:OSDCloudResults.$name = $operatingSystem.$name
        }
        $global:OSDCloudResults.OSFileName = $operatingSystem.FileName
        $driverPack = $global:OSDCloudDeploy.DriverPackCloudObject
        if ($null -ne $workflow.DriverPackCloudObject) {
            $driverPack = $workflow.DriverPackCloudObject
        }
        $global:OSDCloudResults.DriverPackFileName = $driverPack.FileName

        if ([string]::IsNullOrWhiteSpace($global:OSDCloudResults.DistinctId)) {
            $distinctId = [string]$global:OSDCoreDevice.EndpointSHA
            if ([string]::IsNullOrWhiteSpace($distinctId) -and -not [string]::IsNullOrWhiteSpace($global:OSDCoreDevice.UUID)) {
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                try {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$global:OSDCoreDevice.UUID)
                    $distinctId = [System.BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '')
                }
                finally {
                    $sha256.Dispose()
                }
            }
            if ([string]::IsNullOrWhiteSpace($distinctId)) {
                $distinctId = [guid]::NewGuid().ToString()
            }
            $global:OSDCloudResults.DistinctId = $distinctId
        }
    }
    catch {
        Write-Warning "Could not update OSDCloudResults metadata: $($_.Exception.Message)"
    }

    $global:OSDCloudResults.Network = $null
    try {
        $configurations = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction Stop |
            Where-Object { @($_.DefaultIPGateway | Where-Object { $_ -and $_ -notin @('0.0.0.0', '::') }).Count -gt 0 })
        if ($configurations.Count -gt 0) {
            $adapters = @(Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop |
                Where-Object { $_.Index -in $configurations.Index -and $_.NetConnectionStatus -eq 2 })
            $types = @($adapters | ForEach-Object {
                if ($_.AdapterTypeID -eq 9 -or $_.Name -match 'WiFi|Wi-Fi|Wireless|WLAN|802\.11') { 'Wireless' }
                elseif ($_.AdapterTypeID -eq 0 -and $_.PhysicalAdapter -eq $true) { 'Wired' }
                else { 'Unknown' }
            } | Select-Object -Unique)
            if ($types.Count -eq 1 -and $types[0] -in @('Wired', 'Wireless')) {
                $global:OSDCloudResults.Network = $types[0]
            }
        }
        if ($null -eq $global:OSDCloudResults.Network) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Network type is unavailable or ambiguous"
        }
    }
    catch {
        Write-Warning "Could not determine OSDCloudResults network type: $($_.Exception.Message)"
    }
}
