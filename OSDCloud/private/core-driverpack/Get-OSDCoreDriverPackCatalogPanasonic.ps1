function Get-OSDCoreDriverPackCatalogPanasonic {
    <#
    .SYNOPSIS
        Gets the Panasonic driver pack catalog bundled with the module.

    .DESCRIPTION
        Reads the Panasonic driver pack catalog JSON from the module and returns Windows 11
        driver pack objects. This function does not download or update catalog content.
        Use Update-OSDCoreDriverPackCatalogPanasonic to refresh the module catalog.

    .PARAMETER LocalDriverPackCatalog
        Path to the local Panasonic catalog JSON file bundled with the module.

    .EXAMPLE
        Get-OSDCoreDriverPackCatalogPanasonic

        Gets the Panasonic driver pack catalog from the module.

    .OUTPUTS
        PSCustomObject[]
        Returns custom objects with driver pack information including Name, Model,
        SystemId, URL, ReleaseDate, and other metadata.

    .NOTES
        The module catalog is stored in core\driverpacks\panasonic.json.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\panasonic.json')
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Indexing $LocalDriverPackCatalog"

    $jsonCatalogContent = Get-Content -Path $LocalDriverPackCatalog -Raw -ErrorAction Stop | ConvertFrom-Json
    if (-not $jsonCatalogContent.Models) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Failed to load Panasonic driver pack catalog content'),
            'CatalogLoadFailed',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $LocalDriverPackCatalog
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Building driver pack catalog"
    $catalogVersion = Get-Date $jsonCatalogContent.LastDateModified -Format 'yy.MM.dd'
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Catalog version: $catalogVersion"

    $results = foreach ($model in $jsonCatalogContent.Models) {
        $modelName = $model.Alias
        $systemId = $model.Product

        foreach ($item in $model.DriverPacks) {
            if ($item.OSVer -eq 'Win10') { continue }

            $downloadUrl = $item.URL
            $releaseDate = Get-Date $item.ReleaseDate -Format 'yy.MM.dd'

            $objectProperties = [Ordered]@{
                CatalogVersion  = $catalogVersion
                ReleaseDate     = $releaseDate
                Name            = "Panasonic $modelName [$releaseDate]"
                Manufacturer    = 'Panasonic'
                Model           = $modelName
                SystemId        = $systemId
                FileName        = $downloadUrl | Split-Path -Leaf
                Url             = $downloadUrl
                OperatingSystem = 'Windows 11'
                OSArchitecture  = 'amd64'
                OSVersion       = $item.OSRelease
                HashMD5         = $item.Hash
            }
            New-Object -TypeName PSObject -Property $objectProperties
        }
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Filtering to latest driver packs per model"
    $results = $results | Sort-Object Model, OSVersion -Descending | Group-Object Model | ForEach-Object { $_.Group | Select-Object -First 1 }
    $results = $results | Sort-Object Model, OSVersion -Descending | Group-Object HashMD5 | ForEach-Object { $_.Group | Select-Object -First 1 }
    $results = $results | Sort-Object Model
    if ($VerbosePreference -eq 'Continue' -or $DebugPreference -eq 'Continue') {
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath "$env:Temp\osdcloud-driverpack-panasonic.json" -Encoding utf8
    }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Found $($results.Count) Windows 11 driver packs"
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    $results
}
