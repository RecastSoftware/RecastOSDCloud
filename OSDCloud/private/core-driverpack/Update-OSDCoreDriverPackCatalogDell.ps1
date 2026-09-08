function Update-OSDCoreDriverPackCatalogDell {
    <#
    .SYNOPSIS
        Updates the Dell driver pack catalog bundled with the module.

    .DESCRIPTION
        Downloads Dell DriverPackCatalog.cab, extracts DriverPackCatalog.xml, validates
        the extracted XML, and replaces the local module Dell catalog file.

    .PARAMETER LocalDriverPackCatalog
        Path to the local Dell catalog XML file to update.

    .PARAMETER OemDriverPackCatalog
        URL to the online Dell DriverPack catalog CAB file.

    .PARAMETER PassThru
        Returns parsed Dell driver pack catalog objects after updating the local catalog.

    .EXAMPLE
        Update-OSDCoreDriverPackCatalogDell

        Updates the Dell driver pack catalog bundled with the module.

    .EXAMPLE
        Update-OSDCoreDriverPackCatalogDell -PassThru

        Updates the Dell catalog and returns parsed Windows 11 driver pack objects.

    .OUTPUTS
        None by default. PSCustomObject[] when PassThru is specified.

    .NOTES
        Catalog is downloaded from https://downloads.dell.com/catalog/DriverPackCatalog.cab.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\dell.xml'),

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]$OemDriverPackCatalog = 'https://downloads.dell.com/catalog/DriverPackCatalog.cab',

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"

    $tempCatalogPackagePath = Join-Path -Path $env:TEMP -ChildPath 'DriverPackCatalog.cab'
    $tempCatalogPath = Join-Path -Path $env:TEMP -ChildPath 'osdcloud-driverpack-dell.xml'

    foreach ($tempPath in @($tempCatalogPackagePath, $tempCatalogPath)) {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] Recast: OSDCloud is updating the Dell DriverPack catalog."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Downloading $OemDriverPackCatalog"
        $null = Invoke-WebRequest -Uri $OemDriverPackCatalog -OutFile $tempCatalogPackagePath -ErrorAction Stop

        if (-not (Test-Path $tempCatalogPackagePath)) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Failed to download Dell DriverPack catalog CAB'),
                'CatalogDownloadFailed',
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                $OemDriverPackCatalog
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Extracting $tempCatalogPath"
        $expandResult = & expand.exe $tempCatalogPackagePath $tempCatalogPath 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tempCatalogPath)) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Failed to extract Dell DriverPack catalog: $expandResult"),
                'CatalogExtractFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $tempCatalogPackagePath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        [xml]$xmlCatalogContent = Get-Content -Path $tempCatalogPath -Raw -ErrorAction Stop
        if (-not $xmlCatalogContent.DriverPackManifest.DriverPackage) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Extracted Dell DriverPack catalog XML is invalid'),
                'CatalogValidationFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $tempCatalogPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if ($PSCmdlet.ShouldProcess($LocalDriverPackCatalog, 'Update Dell driver pack catalog')) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Updating $LocalDriverPackCatalog"
            Copy-Item -Path $tempCatalogPath -Destination $LocalDriverPackCatalog -Force
        }

        if ($PassThru.IsPresent) {
            Get-OSDCoreDriverPackCatalogDell -LocalDriverPackCatalog $LocalDriverPackCatalog
        }
    }
    finally {
        if (Test-Path $tempCatalogPackagePath) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Removing temporary CAB file"
            Remove-Item -Path $tempCatalogPackagePath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $tempCatalogPath) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Removing temporary catalog file"
            Remove-Item -Path $tempCatalogPath -Force -ErrorAction SilentlyContinue
        }
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
}
