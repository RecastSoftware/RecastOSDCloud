function Resolve-OSDCoreModelDriversPath {
    <#
    .SYNOPSIS
        Resolves a safe ModelDrivers source by volume identity.
    .DESCRIPTION
        Finds the cached volume's current drive letter and validates its model directory.
        Excludes every non-boot local disk eligible for Clear-DeviceLocalDisk, not only
        the selected deployment disk. Missing or ambiguous sources produce a warning.
    .PARAMETER CacheObject
        ModelDrivers inventory entry containing Name, OSArchitecture, and VolumeUniqueId.
    .EXAMPLE
        Resolve-OSDCoreModelDriversPath -CacheObject $global:OSDCloudDeploy.ModelDriversCacheObject
        Returns the current safe source path, including after USB drive-letter changes.
    .OUTPUTS
        System.String. The safe source path, or no output when it cannot be resolved.
    .NOTES
        Storage metadata must be available. Unknown source safety is not accepted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [psobject]$CacheObject
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    if ($CacheObject.Type -ne 'ModelDrivers' -or $CacheObject.OSArchitecture -notin 'amd64', 'arm64' -or
        [string]::IsNullOrWhiteSpace($CacheObject.VolumeUniqueId) -or
        [string]::IsNullOrWhiteSpace($CacheObject.Name) -or $CacheObject.Name -match '[\\/]') {
        Write-Warning "[$(Get-Date -format s)] ModelDrivers source metadata is invalid: $($CacheObject.FullName)"
        return
    }

    try {
        $volumes = @(Get-Volume -UniqueId $CacheObject.VolumeUniqueId -ErrorAction Stop |
            Where-Object { $_.DriveLetter -match '^[A-Z]$' })
        if ($volumes.Count -ne 1) {
            Write-Warning "[$(Get-Date -format s)] ModelDrivers volume is missing or ambiguous: $($CacheObject.FullName)"
            return
        }

        $partitions = @(Get-Partition -DriveLetter $volumes[0].DriveLetter -ErrorAction Stop)
        if ($partitions.Count -ne 1 -or $null -eq $partitions[0].DiskNumber) {
            Write-Warning "[$(Get-Date -format s)] Cannot determine ModelDrivers source disk: $($CacheObject.FullName)"
            return
        }
        $localDisks = @(Get-DeviceLocalDisk -ErrorAction Stop)
        if (@($localDisks | Where-Object { $null -eq $_.Number -or $null -eq $_.IsBoot }).Count -gt 0) {
            Write-Warning "[$(Get-Date -format s)] Cannot determine which local disks will be cleared. Excluding ModelDrivers source: $($CacheObject.FullName)"
            return
        }
        $clearDisks = @($localDisks | Where-Object { $_.IsBoot -eq $false })
        if ($partitions[0].DiskNumber -in $clearDisks.Number) {
            Write-Warning "[$(Get-Date -format s)] Excluding ModelDrivers on disk $($partitions[0].DiskNumber), which will be cleared: $($CacheObject.FullName)"
            return
        }

        $driveRoot = "$($volumes[0].DriveLetter):\"
        $relativePath = "OSDCloud\modeldrivers-$($CacheObject.OSArchitecture)\$($CacheObject.Name)"
        $sourcePath = Join-Path -Path $driveRoot -ChildPath $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Container) -or
            @(Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Filter '*.inf' -ErrorAction Stop).Count -eq 0) {
            Write-Warning "[$(Get-Date -format s)] ModelDrivers source is missing or contains no INF files: $sourcePath"
            return
        }
        $sourcePath
    }
    catch {
        Write-Warning "[$(Get-Date -format s)] Cannot resolve a safe ModelDrivers source for $($CacheObject.FullName): $($_.Exception.Message)"
    }
}
