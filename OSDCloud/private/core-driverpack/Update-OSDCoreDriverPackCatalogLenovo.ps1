function Update-OSDCoreDriverPackCatalogLenovo {
    <#
    .SYNOPSIS
        Updates the Lenovo driver pack catalog bundled with the module.

    .DESCRIPTION
        Downloads Lenovo's SCCM driver pack catalog XML, validates the XML, and replaces
        the local module Lenovo catalog file.

    .PARAMETER LocalDriverPackCatalog
        Path to the local Lenovo catalog XML file to update.

    .PARAMETER OemDriverPackCatalog
        URL to the online Lenovo driver pack catalog XML file.

    .PARAMETER PassThru
        Returns parsed Lenovo driver pack catalog objects after updating the local catalog.

    .EXAMPLE
        Update-OSDCoreDriverPackCatalogLenovo

        Updates the Lenovo driver pack catalog bundled with the module.

    .OUTPUTS
        None by default. PSCustomObject[] when PassThru is specified.

    .NOTES
        Catalog is downloaded from https://download.lenovo.com/cdrt/td/catalogv2.xml.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\lenovo.xml'),

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OemDriverPackCatalog = 'https://download.lenovo.com/cdrt/td/catalogv2.xml',

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"

    $tempCatalogPath = Join-Path -Path $env:TEMP -ChildPath 'osdcloud-driverpack-lenovo.xml'
    Remove-Item -Path $tempCatalogPath -Force -ErrorAction SilentlyContinue

    try {
        Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] Updating Lenovo DriverPack catalog."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Downloading $OemDriverPackCatalog"
        $null = Invoke-WebRequest -Uri $OemDriverPackCatalog -OutFile $tempCatalogPath -UseBasicParsing -ErrorAction Stop

        [xml]$xmlCatalogContent = Get-Content -Path $tempCatalogPath -Raw -ErrorAction Stop
        if (-not $xmlCatalogContent.ModelList.Model) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Downloaded Lenovo DriverPack catalog XML is invalid'),
                'CatalogValidationFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $tempCatalogPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if ($PSCmdlet.ShouldProcess($LocalDriverPackCatalog, 'Update Lenovo driver pack catalog')) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Updating $LocalDriverPackCatalog"
            Copy-Item -Path $tempCatalogPath -Destination $LocalDriverPackCatalog -Force
        }

        if ($PassThru.IsPresent) {
            Get-OSDCoreDriverPackCatalogLenovo -LocalDriverPackCatalog $LocalDriverPackCatalog
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
