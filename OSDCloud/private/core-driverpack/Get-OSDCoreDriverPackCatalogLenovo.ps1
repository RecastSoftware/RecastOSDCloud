function Get-OSDCoreDriverPackCatalogLenovo {
    <#
    .SYNOPSIS
        Gets the Lenovo driver pack catalog bundled with the module.

    .DESCRIPTION
        Reads the Lenovo driver pack catalog XML from the module and returns Windows 11
        driver pack objects. This function does not download or update catalog content.
        Use Update-OSDCoreDriverPackCatalogLenovo to refresh the module catalog.

    .PARAMETER LocalDriverPackCatalog
        Path to the local Lenovo catalog XML file bundled with the module.

    .EXAMPLE
        Get-OSDCoreDriverPackCatalogLenovo

        Gets the Lenovo driver pack catalog from the module.

    .EXAMPLE
        Get-OSDCoreDriverPackCatalogLenovo -LocalDriverPackCatalog 'C:\Catalogs\lenovo.xml'

        Gets Lenovo driver pack catalog values from a custom XML file.

    .OUTPUTS
        PSCustomObject[]
        Returns custom objects with driver pack information including Name, Model,
        SystemId, URL, ReleaseDate, and other metadata.

    .NOTES
        The module catalog is stored in core\driverpacks\lenovo.xml.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\lenovo.xml')
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Indexing $LocalDriverPackCatalog"

    [xml]$xmlCatalogContent = Get-Content -Path $LocalDriverPackCatalog -Raw -ErrorAction Stop
    if (-not $xmlCatalogContent.ModelList.Model) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Failed to load Lenovo driver pack catalog content'),
            'CatalogLoadFailed',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $LocalDriverPackCatalog
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Building driver pack catalog"
    $catalogVersion = Get-Date -Format yy.MM.dd
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Catalog version: $catalogVersion"

    $modelList = $xmlCatalogContent.ModelList.Model
    $results = foreach ($model in $modelList) {
        foreach ($item in $model.SCCM) {
            $downloadUrl = $item.'#text'
            $releaseDate = Get-Date $item.date -Format 'yy.MM.dd'
            $osVersion = $item.version
            if ($osVersion -eq '*') {
                $osVersion = $null
            }

            if ($item.os -eq 'win11') {
                $operatingSystem = 'Windows 11'
            }
            else {
                continue
            }

            $objectProperties = [Ordered]@{
                CatalogVersion  = $catalogVersion
                ReleaseDate     = $releaseDate
                Name            = "Lenovo $($model.name) [$releaseDate]"
                Manufacturer    = 'Lenovo'
                Model           = $model.name
                SystemId        = $model.Types.Type.split(',').ForEach({ $_.Trim() })
                FileName        = $downloadUrl | Split-Path -Leaf
                Url             = $downloadUrl
                OperatingSystem = $operatingSystem
                OSArchitecture  = 'amd64'
                OSVersion       = $osVersion
                HashMD5         = $item.crc
            }
            New-Object -TypeName PSObject -Property $objectProperties
        }
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Filtering to latest driver packs per model"
    $results = $results | Sort-Object Model, OSVersion -Descending | Group-Object Model | ForEach-Object { $_.Group | Select-Object -First 1 }
    $results = $results | Sort-Object Model, OSVersion -Descending
    if ($VerbosePreference -eq 'Continue' -or $DebugPreference -eq 'Continue') {
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath "$env:Temp\osdcloud-driverpack-lenovo.json" -Encoding utf8
    }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Found $($results.Count) Windows 11 driver packs"
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    $results
}
