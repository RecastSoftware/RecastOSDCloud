<#
.SYNOPSIS
Applies offline drivers from a local driver folder to the Windows image.

.DESCRIPTION
Validates the configured driver folder paths and, when present, uses Add-WindowsDriver
to inject all drivers recursively into the offline Windows installation at C:. If no
driver folders are configured or no paths exist, the step exits without error. When
selected removable media changes drive letters, the step re-resolves each saved
driver folder by scanning current file system drives for the same relative path.

.PARAMETER DriverFolderPath
Path(s) to folders that contain driver INF files and subfolders. Absolute paths are
re-resolved by their OSDCloud\Drivers relative suffix when the original drive letter
is no longer valid.

.EXAMPLE
step-Add-WindowsDriver-DriverFolder -DriverFolderPath 'D:\DriverPack'

Injects drivers from D:\DriverPack into the offline Windows image.

.NOTES
Internal workflow step used by OSDCloud deployment tasks.
#>
function step-Add-WindowsDriver-DriverFolder {
    [CmdletBinding()]
    param (
        [System.String[]]
        $DriverFolderPath
    )
    #=================================================
    $startMessage = "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    Write-Debug -Message $startMessage; Write-Verbose -Message $startMessage
    #=================================================
    $Error.Clear()
    $logPath = 'C:\Windows\Temp\osdcloud-logs'
    $offlinePath = 'C:\'
    $dismLogPath = Join-Path -Path $logPath -ChildPath 'dism-add-windowsdriver-driverfolder.log'
    $volumeMetadataCache = @{}
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverFolderPath count: $(@($DriverFolderPath).Count); LogPath: $logPath; OfflinePath: $offlinePath"

    function Get-DriveRootFromPath {
        param(
            [Parameter()]
            [string]$Path
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $null
        }

        $driveRootMatch = [System.Text.RegularExpressions.Regex]::Match($Path, '^[A-Z]:\\')
        if ($driveRootMatch.Success) {
            return $driveRootMatch.Value
        }

        return $null
    }

    function Get-DriverFolderRelativePath {
        param(
            [Parameter()]
            [string]$Path
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $null
        }

        $relativePathMatch = [System.Text.RegularExpressions.Regex]::Match($Path, '(?i)(OSDCloud\\Drivers(?:\\.*)?)$')
        if ($relativePathMatch.Success) {
            return $relativePathMatch.Groups[1].Value
        }

        return $null
    }

    function Get-DriveVolumeMetadata {
        param(
            [Parameter()]
            [string]$Path
        )

        $driveRoot = Get-DriveRootFromPath -Path $Path
        if ([string]::IsNullOrWhiteSpace($driveRoot)) {
            return [PSCustomObject]@{
                DriveRoot      = $null
                VolumeLabel    = $null
                VolumeUniqueId = $null
            }
        }

        if ($volumeMetadataCache.ContainsKey($driveRoot)) {
            return $volumeMetadataCache[$driveRoot]
        }

        $volume = $null
        try {
            $volume = Get-Volume -DriveLetter $driveRoot.Substring(0, 1) -ErrorAction Stop
        }
        catch {
            $volume = $null
        }

        $volumeMetadata = [PSCustomObject]@{
            DriveRoot      = $driveRoot
            VolumeLabel    = if ($volume) { [string]$volume.FileSystemLabel } else { $null }
            VolumeUniqueId = if ($volume) { [string]$volume.UniqueId } else { $null }
        }

        $volumeMetadataCache[$driveRoot] = $volumeMetadata
        return $volumeMetadata
    }

    function Resolve-DriverFolderPath {
        param(
            [Parameter()]
            $Selection,

            [Parameter()]
            [string]$FallbackPath
        )

        $originalPath = $FallbackPath
        if ($Selection -and -not [string]::IsNullOrWhiteSpace([string]$Selection.Path)) {
            $originalPath = [string]$Selection.Path
        }

        if (-not [string]::IsNullOrWhiteSpace($originalPath) -and (Test-Path -LiteralPath $originalPath -PathType Container)) {
            return $originalPath
        }

        $relativePath = $null
        if ($Selection -and -not [string]::IsNullOrWhiteSpace([string]$Selection.RelativePath)) {
            $relativePath = [string]$Selection.RelativePath
        }
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            $relativePath = Get-DriverFolderRelativePath -Path $originalPath
        }

        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            Write-Warning "[$(Get-Date -format s)] Unable to determine a relative driver folder path for $originalPath"
            return $null
        }

        $candidatePaths = @(
            Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' } | ForEach-Object {
                $candidatePath = Join-Path -Path $_.Root -ChildPath $relativePath
                if (Test-Path -LiteralPath $candidatePath -PathType Container) {
                    $candidatePath
                }
            } | Sort-Object -Unique
        )

        if (-not $candidatePaths -or $candidatePaths.Count -eq 0) {
            Write-Verbose "[$(Get-Date -format s)] No current drives contain relative driver folder path $relativePath"
            Write-Warning "[$(Get-Date -format s)] DriverFolderPath was not found: $originalPath"
            return $null
        }

        if ($candidatePaths.Count -eq 1) {
            Write-Verbose "[$(Get-Date -format s)] Resolved driver folder candidate: $($candidatePaths[0])"
            return $candidatePaths[0]
        }

        $preferredPaths = @()
        $storedVolumeUniqueId = if ($Selection) { [string]$Selection.VolumeUniqueId } else { $null }
        $storedVolumeLabel = if ($Selection) { [string]$Selection.VolumeLabel } else { $null }

        if (-not [string]::IsNullOrWhiteSpace($storedVolumeUniqueId)) {
            $preferredPaths = @($candidatePaths | Where-Object {
                    [string](Get-DriveVolumeMetadata -Path $_).VolumeUniqueId -eq $storedVolumeUniqueId
                })
        }

        if ($preferredPaths.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($storedVolumeLabel)) {
            $preferredPaths = @($candidatePaths | Where-Object {
                    [string](Get-DriveVolumeMetadata -Path $_).VolumeLabel -eq $storedVolumeLabel
                })
        }

        if ($preferredPaths.Count -eq 1) {
            return $preferredPaths[0]
        }

        Write-Warning "[$(Get-Date -format s)] Multiple matching driver folders were found for $originalPath. Skipping this folder to avoid selecting the wrong drive."
        return $null
    }

    $validDriverFolderPaths = @($DriverFolderPath | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        } | Select-Object -Unique)

    if (-not $validDriverFolderPaths -or $validDriverFolderPaths.Count -eq 0) {
        Write-Verbose "[$(Get-Date -format s)] DriverFolderPath is not set. Skipping driver injection."
        return
    }

    $selectionLookup = @{}

    $driverFolderSelections = @($validDriverFolderPaths | ForEach-Object {
            $driverPath = [string]$_
            if ($selectionLookup.ContainsKey($driverPath)) {
                $selectionLookup[$driverPath]
            }
            else {
                [PSCustomObject]@{
                    Path           = $driverPath
                    RelativePath   = Get-DriverFolderRelativePath -Path $driverPath
                    DriveRoot      = Get-DriveRootFromPath -Path $driverPath
                    VolumeLabel    = $null
                    VolumeUniqueId = $null
                }
            }
        })

    $resolvedDriverFolderPaths = @()
    foreach ($selection in $driverFolderSelections) {
        $originalPath = [string]$selection.Path
        $resolvedPath = Resolve-DriverFolderPath -Selection $selection -FallbackPath $originalPath
        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            continue
        }

        if ($resolvedDriverFolderPaths -notcontains $resolvedPath) {
            if ($resolvedPath -ne $originalPath) {
                Write-Verbose "[$(Get-Date -format s)] Resolved driver folder path from $originalPath to $resolvedPath"
            }
            $resolvedDriverFolderPaths += $resolvedPath
        }
    }

    if (-not $resolvedDriverFolderPaths -or $resolvedDriverFolderPaths.Count -eq 0) {
        Write-Verbose "[$(Get-Date -format s)] No valid driver folders were resolved. Skipping driver injection."
        return
    }

    if (-not (Test-Path -LiteralPath $logPath)) {
        Write-Verbose "[$(Get-Date -format s)] Creating driver folder DISM log path: $logPath"
        New-Item -ItemType Directory -Path $logPath -Force | Out-Null
    }

    foreach ($driverPath in $resolvedDriverFolderPaths) {
        Write-Verbose "[$(Get-Date -format s)] Applying drivers from $driverPath"
        try {
            Add-WindowsDriver -Path $offlinePath -Driver $driverPath -Recurse -ForceUnsigned `
                -LogPath $dismLogPath `
                -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Warning "[$(Get-Date -format s)] Add-WindowsDriver failed for $driverPath. $($_.Exception.Message)"
        }
    }
    #=================================================
    $endMessage = "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    Write-Verbose -Message $endMessage; Write-Debug -Message $endMessage
    #=================================================
}
