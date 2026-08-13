function Get-OSDCoreDriverPackCatalogSurface {
    <#
    .SYNOPSIS
        Gets the Microsoft Surface driver pack catalog bundled with the module.

    .DESCRIPTION
        Reads the Surface driver pack catalog JSON from the module and returns the catalog
        objects. This function does not perform live UpdatePage checks or update catalog
        content. Use Update-OSDCoreDriverPackCatalogSurface to refresh the module catalog.

    .PARAMETER LocalDriverPackCatalog
        Path to the local Surface catalog JSON file bundled with the module.

    .EXAMPLE
        Get-OSDCoreDriverPackCatalogSurface

        Gets the Surface driver pack catalog from the module.

    .OUTPUTS
        PSCustomObject[]
        Objects with CatalogVersion, ReleaseDate, Name, Manufacturer, Model, SystemId,
        FileName, Url, OperatingSystem, OSArchitecture, HashMD5, and UpdatePage properties.

    .NOTES
        The module catalog is stored in core\driverpacks\surface.json.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\surface.json')
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Indexing $LocalDriverPackCatalog"

    $jsonCatalogContent = Get-Content -Path $LocalDriverPackCatalog -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    if (-not $jsonCatalogContent) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('Failed to load Surface driver pack catalog content'),
            'CatalogLoadFailed',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $LocalDriverPackCatalog
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Found $(@($jsonCatalogContent).Count) Surface driver packs"
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    $jsonCatalogContent
}
