function Get-OSDCoreDriverPackCatalogHP {
    <#
    .SYNOPSIS
        Gets the HP driver pack catalog bundled with the module.

    .DESCRIPTION
        Reads the HP driver pack catalog XML from the module and returns Windows 11
        driver pack objects. This function does not download or update catalog content.
        Use Update-OSDCoreDriverPackCatalogHP to refresh the module catalog.

    .PARAMETER LocalDriverPackCatalog
        Path to the local HP catalog XML file bundled with the module.

    .EXAMPLE
        Get-OSDCoreDriverPackCatalogHP

        Gets the HP driver pack catalog from the module.

    .EXAMPLE
        Get-OSDCoreDriverPackCatalogHP -LocalDriverPackCatalog 'C:\Catalogs\hp.xml'

        Gets HP driver pack catalog values from a custom XML file.

    .OUTPUTS
        PSCustomObject[]
        Returns custom objects with driver pack information including Name, Model,
        SystemId, URL, ReleaseDate, and other metadata.

    .NOTES
        The module catalog is stored in core\driverpacks\hp.xml.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\hp.xml')
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Indexing $LocalDriverPackCatalog"

    [xml]$xmlCatalogContent = Get-Content -Path $LocalDriverPackCatalog -Raw -ErrorAction Stop
    if (-not $xmlCatalogContent.NewDataSet.HPClientDriverPackCatalog) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Failed to load HP driver pack catalog content'),
            'CatalogLoadFailed',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $LocalDriverPackCatalog
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Building driver pack catalog"
    $hpCatalogRoot = $xmlCatalogContent.NewDataSet.HPClientDriverPackCatalog
    if ($hpCatalogRoot -and $hpCatalogRoot.DateReleased) {
        $dtDateReleased = [datetime]::ParseExact($hpCatalogRoot.DateReleased, 'yyyy-MM-dd', $null)
        $catalogVersion = $dtDateReleased.ToString('yy.MM.dd')
    }
    else {
        $catalogVersion = Get-Date -Format yy.MM.dd
    }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Catalog version: $catalogVersion"

    $hpSoftPaqList = $xmlCatalogContent.NewDataSet.HPClientDriverPackCatalog.SoftPaqList.SoftPaq
    $hpModelList = $xmlCatalogContent.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
    $hpModelList = $hpModelList | Where-Object { $_.OSId -ge '4317' }

    $results = foreach ($item in $hpModelList) {
        $hpSoftPaq = $hpSoftPaqList | Where-Object { $_.Id -eq $item.SoftPaqId }
        if ($null -eq $hpSoftPaq) {
            continue
        }

        $osVersion = $item.OSName
        $osVersion = $osVersion.Substring($osVersion.Length - 4)

        $template = 'M/d/yyyy hh:mm:ss tt'
        $dtReleaseDate = [datetime]::ParseExact($hpSoftPaq.DateReleased, $template, $null)
        $releaseDate = $dtReleaseDate.ToString('yy.MM.dd')

        $systemIds = if ($item.SystemId) {
            $item.SystemId.split(',').ForEach({ $_.Trim() })
        }
        else {
            @()
        }

        $objectProperties = [Ordered]@{
            CatalogVersion  = $catalogVersion
            ReleaseDate     = $releaseDate
            Name            = "$($item.SystemName) $($item.SoftPaqId) [$releaseDate]"
            Manufacturer    = 'HP'
            Model           = $item.SystemName
            SystemId        = [string[]]$systemIds
            FileName        = $hpSoftPaq.Url | Split-Path -Leaf
            Url             = $hpSoftPaq.Url
            OperatingSystem = 'Windows 11'
            OSArchitecture  = 'amd64'
            OSVersion       = $osVersion
            HashMD5         = $hpSoftPaq.MD5
        }
        New-Object -TypeName PSObject -Property $objectProperties
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Filtering to latest driver packs per model"
    $results = $results | Sort-Object Model, OSVersion -Descending | Group-Object Model | ForEach-Object { $_.Group | Select-Object -First 1 }
    $results = $results | Sort-Object -Property Name
    if ($VerbosePreference -eq 'Continue' -or $DebugPreference -eq 'Continue') {
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath "$env:Temp\osdcloud-driverpack-hp.json" -Encoding utf8
    }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Found $($results.Count) Windows 11 driver packs"
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    $results
}
