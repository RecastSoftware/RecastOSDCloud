<#
.SYNOPSIS
Synchronizes canonical operating-system files from RecastOSDCloud to OSD.

.DESCRIPTION
Reads the adjacent synchronization manifest and compares canonical RecastOSDCloud
operating-system functions and catalog files with an OSD repository checkout. In
check mode, reports drift and exits with an error without changing files. Otherwise,
copies missing or changed files and removes extra managed catalog files.

.PARAMETER DestinationRepositoryPath
Specifies the root of the OSD repository to validate or update.

.PARAMETER Check
Validates synchronization without changing the destination repository.

.EXAMPLE
.\Sync-OSDOperatingSystemParity.ps1 -DestinationRepositoryPath ..\..\OSD -Check

Checks an adjacent OSD repository for operating-system parity drift.

.EXAMPLE
.\Sync-OSDOperatingSystemParity.ps1 -DestinationRepositoryPath ..\..\OSD

Synchronizes the mapped operating-system files into an adjacent OSD repository.

.LINK
https://github.com/OSDeploy/OSD/tree/master/docs

.NOTES
Author: David Segura - Recast Software
2026-09-30 - Initial operating-system parity synchronization script
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DestinationRepositoryPath,

    [Parameter()]
    [switch]$Check
)

$Error.Clear()
$ErrorActionPreference = 'Stop'
$sourceRepositoryPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$destinationRepositoryPath = [System.IO.Path]::GetFullPath($DestinationRepositoryPath)
$manifestPath = Join-Path $PSScriptRoot 'osd-operating-system-sync.json'

if (-not (Test-Path -LiteralPath $destinationRepositoryPath -PathType Container)) {
    throw "Destination OSD repository was not found at '$destinationRepositoryPath'."
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Operating-system synchronization manifest was not found at '$manifestPath'."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$results = @()

foreach ($mapping in $manifest.Files) {
    $sourcePath = Join-Path $sourceRepositoryPath $mapping.Source
    $destinationPath = Join-Path $destinationRepositoryPath $mapping.Destination
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Canonical operating-system file was not found at '$sourcePath'."
    }

    $state = if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
        'Missing'
    }
    elseif ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash) {
        'Different'
    }
    else {
        'InSync'
    }

    if (-not $Check -and $state -ne 'InSync' -and $PSCmdlet.ShouldProcess($destinationPath, 'Synchronize canonical operating-system file')) {
        $null = New-Item -Path (Split-Path -Path $destinationPath -Parent) -ItemType Directory -Force
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        $state = 'Synchronized'
    }

    $results += [pscustomobject]@{
        Source      = $mapping.Source
        Destination = $mapping.Destination
        State       = $state
    }
}

foreach ($directoryMapping in $manifest.Directories) {
    $sourceDirectory = Join-Path $sourceRepositoryPath $directoryMapping.Source
    $destinationDirectory = Join-Path $destinationRepositoryPath $directoryMapping.Destination
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Canonical operating-system directory was not found at '$sourceDirectory'."
    }
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container) -and -not $Check) {
        $null = New-Item -Path $destinationDirectory -ItemType Directory -Force
    }

    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceDirectory -Filter $directoryMapping.Pattern -File)
    foreach ($sourceFile in $sourceFiles) {
        $relativeDestination = Join-Path $directoryMapping.Destination $sourceFile.Name
        $destinationPath = Join-Path $destinationRepositoryPath $relativeDestination
        $state = if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            'Missing'
        }
        elseif ((Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash) {
            'Different'
        }
        else {
            'InSync'
        }

        if (-not $Check -and $state -ne 'InSync' -and $PSCmdlet.ShouldProcess($destinationPath, 'Synchronize canonical operating-system catalog')) {
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath -Force
            $state = 'Synchronized'
        }

        $results += [pscustomobject]@{
            Source      = Join-Path $directoryMapping.Source $sourceFile.Name
            Destination = $relativeDestination
            State       = $state
        }
    }

    if ($directoryMapping.RemoveExtra -and (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        $sourceNames = @($sourceFiles.Name)
        foreach ($destinationFile in Get-ChildItem -LiteralPath $destinationDirectory -Filter $directoryMapping.Pattern -File) {
            if ($destinationFile.Name -in $sourceNames) {
                continue
            }

            $relativeDestination = Join-Path $directoryMapping.Destination $destinationFile.Name
            $state = 'Extra'
            if (-not $Check -and $PSCmdlet.ShouldProcess($destinationFile.FullName, 'Remove unmanaged operating-system catalog')) {
                Remove-Item -LiteralPath $destinationFile.FullName -Force
                $state = 'Removed'
            }

            $results += [pscustomobject]@{
                Source      = $null
                Destination = $relativeDestination
                State       = $state
            }
        }
    }
}

$results
if ($Check) {
    $drift = @($results | Where-Object State -NE 'InSync')
    if ($drift.Count -gt 0) {
        throw "Operating-system parity check found $($drift.Count) drifted file(s)."
    }
}
