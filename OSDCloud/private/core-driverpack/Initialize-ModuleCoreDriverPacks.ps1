function Initialize-ModuleCoreDriverPacks {
    <#
    .SYNOPSIS
    Retrieves driver pack information for the specified manufacturer and operating system architecture.

    .DESCRIPTION
    Gets driver pack catalogs based on the device manufacturer and OS architecture. For AMD64 architecture,
    manufacturer-specific catalogs are loaded. For ARM64 and other architectures, the default catalog is returned.
    Supports Dell, HP, Lenovo, Microsoft (Surface), and generic devices.

    .PARAMETER OSDManufacturer
    The device manufacturer name. Defaults to the value from $global:OSDCoreDevice.OSDManufacturer.
    Supported values: Dell, HP, Lenovo, Microsoft, or any other value will use the Default catalog.

    .PARAMETER ProcessorArchitecture
    The operating system architecture. Defaults to the value from $global:OSDCoreDevice.ProcessorArchitecture.
    Typically 'amd64' or 'arm64'.

    .PARAMETER OSDProduct
    The device product value. Defaults to the value from $global:OSDCoreDevice.OSDProduct.
    Used to scope Microsoft Surface catalog updates to the current device.

    .OUTPUTS
    PSCustomObject
    Array of driver pack objects containing driver information for the specified manufacturer and architecture.

    .EXAMPLE
    PS> Initialize-ModuleCoreDriverPacks
    Returns driver packs for the current device's manufacturer and architecture.

    .EXAMPLE
    PS> Initialize-ModuleCoreDriverPacks -OSDManufacturer 'Dell' -ProcessorArchitecture 'amd64'
    Returns driver packs for Dell devices with AMD64 architecture.

    .NOTES
    Requires manufacturer-specific cmdlets (Get-OSDCoreDriverPackCatalogDell, Get-OSDCoreDriverPackCatalogHP, etc.) to be available.
    #>
    [CmdletBinding()]
    param (
        [System.String]$OSDManufacturer = $global:OSDCoreDevice.OSDManufacturer,

        [System.String]$ProcessorArchitecture = $global:OSDCoreDevice.ProcessorArchitecture,

        [System.String]$OSDProduct = $global:OSDCoreDevice.OSDProduct
    )
    #=================================================
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] [$($MyInvocation.MyCommand.Name)] $OSDManufacturer $ProcessorArchitecture"
    #=================================================
    [System.String]$GenericDriverPackJson = Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\generic.json'

    $shouldUpdateDriverPackCatalog = $false
    $osdRegisteredValue = $null
    if ($global:OSDCoreDevice) {
        if ($global:OSDCoreDevice -is [System.Collections.IDictionary] -and $global:OSDCoreDevice.Contains('OSDRegistered')) {
            $osdRegisteredValue = $global:OSDCoreDevice['OSDRegistered']
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSDRegistered dictionary key detected with value '$osdRegisteredValue'."
        }
        elseif ($global:OSDCoreDevice.PSObject.Properties.Match('OSDRegistered').Count -gt 0) {
            $osdRegisteredValue = $global:OSDCoreDevice.OSDRegistered
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSDRegistered object property detected with value '$osdRegisteredValue'."
        }
        else {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSDRegistered was not found on OSDCoreDevice."
        }

        $shouldUpdateDriverPackCatalog = $osdRegisteredValue -eq $true
    }
    else {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSDCoreDevice is not initialized."
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] shouldUpdateDriverPackCatalog is '$shouldUpdateDriverPackCatalog'."

    if ($shouldUpdateDriverPackCatalog) {
        $updateDriverPackCatalog = switch ($OSDManufacturer) {
            'Dell' { { Update-OSDCoreDriverPackCatalogDell -Confirm:$false } }
            'HP' { { Update-OSDCoreDriverPackCatalogHP -Confirm:$false } }
            'Lenovo' { { Update-OSDCoreDriverPackCatalogLenovo -Confirm:$false } }
            'Microsoft' { { Update-OSDCoreDriverPackCatalogSurface -OSDProduct $OSDProduct -Confirm:$false } }
            'Panasonic' { { Update-OSDCoreDriverPackCatalogPanasonic -Confirm:$false } }
            default { $null }
        }

        if ($updateDriverPackCatalog) {
            try {
                Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Updating driver pack catalog for $OSDManufacturer."
                & $updateDriverPackCatalog
            }
            catch {
                Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to update driver pack catalog for $OSDManufacturer. Using bundled catalog. $($_.Exception.Message)"
            }
        }
        else {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No driver pack catalog updater is available for $OSDManufacturer."
        }
    }
    else {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Driver pack catalog update skipped because OSDRegistered is not true."
    }

    # Load Generic driver pack catalog for fallback
    $GenericCatalog = Get-Content -Path $GenericDriverPackJson -Raw | ConvertFrom-Json

    if ($ProcessorArchitecture -eq 'amd64') {
        $DriverPackValues = switch ($OSDManufacturer) {
            'Dell' { Get-OSDCoreDriverPackCatalogDell }
            'HP' { Get-OSDCoreDriverPackCatalogHP }
            'Lenovo' { Get-OSDCoreDriverPackCatalogLenovo }
            'Microsoft' { Get-OSDCoreDriverPackCatalogSurface }
            'Panasonic' { Get-OSDCoreDriverPackCatalogPanasonic }
            default { $GenericCatalog }
        }
    }
    else {
        $DriverPackValues = switch ($OSDManufacturer) {
            'Microsoft' { Get-OSDCoreDriverPackCatalogSurface }
            default { $GenericCatalog }
        }
    }

    #$DriverPackValues | Where-Object { $_.OSArchitecture -eq $ProcessorArchitecture }
    # Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Ready: ModuleCoreDriverPacks"
    $global:ModuleCoreDriverPacks = $DriverPackValues | Where-Object { $_.OSArchitecture -eq $ProcessorArchitecture }
    $global:ModuleCoreDriverPacks | Export-Clixml -Path (Join-Path -Path $env:TEMP -ChildPath 'ModuleCoreDriverPacks.xml') -Force
}
