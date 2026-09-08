function Get-OSDCoreDriverPackCatalogDell {
    <#
    .SYNOPSIS
        Gets the Dell driver pack catalog bundled with the module.

    .DESCRIPTION
        Reads the Dell driver pack catalog XML from the module and returns Windows 11
        driver pack objects. This function does not download or update catalog content.
        Use Update-OSDCoreDriverPackCatalogDell to refresh the module catalog.

    .PARAMETER LocalDriverPackCatalog
        Path to the local Dell catalog XML file bundled with the module.

    .EXAMPLE
        Get-OSDCoreDriverPackCatalogDell

        Gets the Dell driver pack catalog from the module.

    .EXAMPLE
        Get-OSDCoreDriverPackCatalogDell -LocalDriverPackCatalog 'C:\Catalogs\dell.xml'

        Gets Dell driver pack catalog values from a custom XML file.

    .OUTPUTS
        PSCustomObject[]
        Returns custom objects with driver pack information including Name, Model,
        SystemId, URL, ReleaseDate, and other metadata.

    .NOTES
        The module catalog is stored in core\driverpacks\dell.xml.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\dell.xml')
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Indexing $LocalDriverPackCatalog"

    [xml]$xmlCatalogContent = Get-Content -Path $LocalDriverPackCatalog -Raw -ErrorAction Stop

    if (-not $xmlCatalogContent) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Failed to load Dell driver pack catalog content'),
            'CatalogLoadFailed',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $LocalDriverPackCatalog
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Building driver pack catalog"
    $onlineBaseUri = 'https://downloads.dell.com/'

    $rawCatalogVersion = $xmlCatalogContent.DriverPackManifest.version -replace '.00', '.01'
    $catalogVersion = (Get-Date $rawCatalogVersion).ToString('yy.MM.dd')
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Catalog version: $catalogVersion"

    $dellDriverPackXml = $xmlCatalogContent.DriverPackManifest.DriverPackage
    $dellDriverPackXml = $dellDriverPackXml | Where-Object {
        $osCode = $_.SupportedOperatingSystems.OperatingSystem.osCode
        $osCode -and ($osCode.Trim() | Select-Object -Unique) -notmatch 'winpe'
    }

    $results = foreach ($item in $dellDriverPackXml) {
        $osCode = $item.SupportedOperatingSystems.OperatingSystem.osCode.Trim() | Select-Object -Unique
        if ($osCode -match 'Windows11') {
            $operatingSystem = 'Windows 11'
        }
        else {
            continue
        }

        $name = "Dell $($item.SupportedSystems.Brand.Model.name | Select-Object -Unique)"
        $name = $name -replace '  ', ' '
        $name = $name -replace 'Dell Dell', 'Dell'
        $model = ($item.SupportedSystems.Brand.Model.name | Select-Object -Unique)

        $driverPackVersion = $item.dellVersion
        if ($driverPackVersion -eq '*') {
            $driverPackVersion = $null
        }

        $releaseDate = Get-Date $item.dateTime -Format 'yy.MM.dd'

        $objectProperties = [Ordered]@{
            CatalogVersion  = $catalogVersion
            ReleaseDate     = $releaseDate
            Name            = "$name $driverPackVersion [$releaseDate]"
            Manufacturer    = 'Dell'
            Model           = $model
            SystemId        = [string[]]@($item.SupportedSystems.Brand.Model.systemID | Select-Object -Unique)
            FileName        = (Split-Path -Leaf $item.path)
            Url             = -join ($onlineBaseUri, $item.path)
            OperatingSystem = $operatingSystem
            OSArchitecture  = 'amd64'
            HashMD5         = $item.HashMD5
        }
        New-Object -TypeName PSObject -Property $objectProperties
    }

    $results = $results | Sort-Object -Property Name
    if ($VerbosePreference -eq 'Continue' -or $DebugPreference -eq 'Continue') {
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath "$env:Temp\osdcloud-driverpack-dell.json" -Encoding utf8
    }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Found $($results.Count) Windows 11 driver packs"
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    $results
}
