function Update-OSDCoreDriverPackCatalogHP {
    <#
    .SYNOPSIS
        Updates the HP driver pack catalog bundled with the module.

    .DESCRIPTION
        Downloads HPClientDriverPackCatalog.cab, validates and extracts the XML catalog,
        validates the extracted XML, and replaces the local module HP catalog file.

    .PARAMETER LocalDriverPackCatalog
        Path to the local HP catalog XML file to update.

    .PARAMETER OemDriverPackCatalog
        URL to the online HP Client Driver Pack Catalog CAB file.

    .PARAMETER PassThru
        Returns parsed HP driver pack catalog objects after updating the local catalog.

    .EXAMPLE
        Update-OSDCoreDriverPackCatalogHP

        Updates the HP driver pack catalog bundled with the module.

    .EXAMPLE
        Update-OSDCoreDriverPackCatalogHP -PassThru

        Updates the HP catalog and returns parsed Windows 11 driver pack objects.

    .OUTPUTS
        None by default. PSCustomObject[] when PassThru is specified.

    .NOTES
        Catalog is downloaded from https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HPClientDriverPackCatalog.cab.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\hp.xml'),

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OemDriverPackCatalog = 'https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HPClientDriverPackCatalog.cab',

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"

    $tempCatalogPackagePath = Join-Path -Path $env:TEMP -ChildPath 'HPClientDriverPackCatalog.cab'
    $tempCatalogPath = Join-Path -Path $env:TEMP -ChildPath 'osdcloud-driverpack-hp.xml'

    foreach ($tempPath in @($tempCatalogPackagePath, $tempCatalogPath)) {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] Recast: OSDCloud is updating the HP DriverPack catalog."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Downloading $OemDriverPackCatalog"
        $null = Invoke-WebRequest -Uri $OemDriverPackCatalog -OutFile $tempCatalogPackagePath -ErrorAction Stop

        if (-not (Test-Path $tempCatalogPackagePath)) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Failed to download HP DriverPack catalog CAB'),
                'CatalogDownloadFailed',
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                $OemDriverPackCatalog
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Validating $tempCatalogPackagePath"
        $cabTest = try { & expand.exe -D $tempCatalogPackagePath 2>&1 } catch { $null }
        if ($LASTEXITCODE -ne 0) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("HP DriverPack catalog CAB validation failed: $cabTest"),
                'CatalogPackageValidationFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $tempCatalogPackagePath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Extracting $tempCatalogPath"
        $expandResult = & expand.exe $tempCatalogPackagePath $tempCatalogPath 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tempCatalogPath)) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Failed to extract HP DriverPack catalog: $expandResult"),
                'CatalogExtractFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $tempCatalogPackagePath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        [xml]$xmlCatalogContent = Get-Content -Path $tempCatalogPath -Raw -ErrorAction Stop
        if (-not $xmlCatalogContent.NewDataSet.HPClientDriverPackCatalog) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Extracted HP DriverPack catalog XML is invalid'),
                'CatalogValidationFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $tempCatalogPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if ($PSCmdlet.ShouldProcess($LocalDriverPackCatalog, 'Update HP driver pack catalog')) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Updating $LocalDriverPackCatalog"
            Copy-Item -Path $tempCatalogPath -Destination $LocalDriverPackCatalog -Force
        }

        if ($PassThru.IsPresent) {
            Get-OSDCoreDriverPackCatalogHP -LocalDriverPackCatalog $LocalDriverPackCatalog
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
