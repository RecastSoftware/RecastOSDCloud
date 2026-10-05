function Get-OSDCoreModelDriversCacheObject {
    <#
    .SYNOPSIS
        Gets the newest safe ModelDrivers cache entry for a device and architecture.
    .DESCRIPTION
        Matches the literal manufacturer/product prefix with its trailing underscore,
        case-insensitively. Model text and the deployed OS build do not affect selection.
        Orders folder builds numerically, excluding sources that cannot survive disk clearing.
    .PARAMETER OSDManufacturer
        Device manufacturer. Defaults to the current OSDCore device.
    .PARAMETER OSDProduct
        Device product identifier. Defaults to the current OSDCore device.
    .PARAMETER OSArchitecture
        Deployment architecture, amd64 or arm64.
    .PARAMETER CacheContent
        Inventory to search. Defaults to the shared OSDCore cache.
    .EXAMPLE
        Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD1 -OSArchitecture amd64
        Returns the newest safe HP_8CD1 model directory containing drivers.
    .OUTPUTS
        System.Management.Automation.PSObject. A matching cache entry, or no output.
    .NOTES
        Equal builds use the full path as a deterministic tie-break.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param (
        [Parameter()]
        [string]$OSDManufacturer = $global:OSDCoreDevice.OSDManufacturer,

        [Parameter()]
        [string]$OSDProduct = $global:OSDCoreDevice.OSDProduct,

        [Parameter()]
        [ValidateSet('amd64', 'arm64')]
        [string]$OSArchitecture = $global:OSDCloudDeploy.OSArchitecture,

        [Parameter()]
        [psobject[]]$CacheContent = $global:OSDCoreCache
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    if ([string]::IsNullOrWhiteSpace($OSDManufacturer) -or [string]::IsNullOrWhiteSpace($OSDProduct)) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Device manufacturer/product is not set."
        return
    }

    $prefix = "${OSDManufacturer}_${OSDProduct}_"
    $candidates = foreach ($item in $CacheContent) {
        if ($item.Type -ne 'ModelDrivers' -or $item.OSArchitecture -ne $OSArchitecture -or
            -not ([string]$item.ModelIdentity).StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $buildVersion = $null
        if (-not [version]::TryParse([string]$item.OSBuildVersion, [ref]$buildVersion)) {
            Write-Warning "[$(Get-Date -format s)] Invalid ModelDrivers build version: $($item.FullName)"
            continue
        }
        [pscustomobject]@{ CacheObject = $item; BuildVersion = $buildVersion }
    }
    foreach ($match in ($candidates | Sort-Object -Property @{ Expression = { $_.BuildVersion }; Descending = $true }, @{ Expression = { $_.CacheObject.FullName } })) {
        if (Resolve-OSDCoreModelDriversPath -CacheObject $match.CacheObject) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Selected $($match.CacheObject.FullName)"
            return $match.CacheObject
        }
    }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No eligible ModelDrivers source found."
}
