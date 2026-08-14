function Update-OSDCoreDriverPackCatalogPanasonic {
    <#
    .SYNOPSIS
        Updates the Panasonic driver pack catalog bundled with the module.

    .DESCRIPTION
        Downloads Panasonic's driver pack catalog JSON, validates the JSON, and replaces
        the local module Panasonic catalog file.

    .PARAMETER LocalDriverPackCatalog
        Path to the local Panasonic catalog JSON file to update.

    .PARAMETER OemDriverPackCatalog
        URL to the online Panasonic driver pack catalog JSON file.

    .PARAMETER PassThru
        Returns parsed Panasonic driver pack catalog objects after updating the local catalog.

    .EXAMPLE
        Update-OSDCoreDriverPackCatalogPanasonic

        Updates the Panasonic driver pack catalog bundled with the module.

    .OUTPUTS
        None by default. PSCustomObject[] when PassThru is specified.

    .NOTES
        Catalog is downloaded from https://pna-b2b-storage-mkt.s3.amazonaws.com/computer/software/apps/Panasonic.json.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\panasonic.json'),

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OemDriverPackCatalog = 'https://pna-b2b-storage-mkt.s3.amazonaws.com/computer/software/apps/Panasonic.json',

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"

    $tempCatalogPath = Join-Path -Path $env:TEMP -ChildPath 'osdcloud-driverpack-panasonic.json'
    if (Test-Path -LiteralPath $tempCatalogPath) {
        Remove-Item -LiteralPath $tempCatalogPath -Force -ErrorAction SilentlyContinue
    }

    try {
        Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] Recast OSDCloud is updating the Panasonic DriverPack catalog."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Downloading $OemDriverPackCatalog"
        $null = Invoke-WebRequest -Uri $OemDriverPackCatalog -OutFile $tempCatalogPath -UseBasicParsing -ErrorAction Stop

        $jsonCatalogContent = Get-Content -Path $tempCatalogPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if (-not $jsonCatalogContent.Models) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Downloaded Panasonic DriverPack catalog JSON is invalid'),
                'CatalogValidationFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $tempCatalogPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if ($PSCmdlet.ShouldProcess($LocalDriverPackCatalog, 'Update Panasonic driver pack catalog')) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Updating $LocalDriverPackCatalog"
            Copy-Item -Path $tempCatalogPath -Destination $LocalDriverPackCatalog -Force
        }

        if ($PassThru.IsPresent) {
            Get-OSDCoreDriverPackCatalogPanasonic -LocalDriverPackCatalog $LocalDriverPackCatalog
        }
    }
    finally {
        if (Test-Path $tempCatalogPath) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Removing temporary catalog file"
            Remove-Item -Path $tempCatalogPath -Force -ErrorAction SilentlyContinue
        }
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
}
