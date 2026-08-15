function Update-OSDCoreDriverPackCloudObjectSurface {
    <#
    .SYNOPSIS
    Gets the latest Microsoft Surface driver pack object for a device product.

    .DESCRIPTION
    Updates the bundled Microsoft Surface driver pack catalog entry matching the
    specified OSDProduct, then returns the refreshed driver pack catalog object.
    SystemId values are compared using an exact, case-insensitive match.

    .PARAMETER OSDProduct
    Surface System SKU or SystemId used to select the driver pack catalog entry.

    .EXAMPLE
    Update-OSDCoreDriverPackCloudObjectSurface -OSDProduct 'Surface_Pro_9_2038'

    Updates and returns the matching Surface driver pack catalog object.

    .OUTPUTS
    PSCustomObject. The refreshed Surface driver pack catalog object when a match
    is found. Otherwise, no object is returned.

    .NOTES
    Internal helper for refreshing selected Surface driver pack metadata.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSDProduct
    )
    #=================================================
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Updating Surface DriverPackCloudObject for OSDProduct '$OSDProduct'."
    $surfaceDriverPacks = Update-OSDCoreDriverPackCatalogSurface -OSDProduct $OSDProduct -PassThru -Confirm:$false

    $driverPackCloudObject = $surfaceDriverPacks | Where-Object {
        $systemIdMatch = $false
        foreach ($systemId in @($_.SystemId)) {
            if ([System.String]::Equals([System.String]$systemId, $OSDProduct, [System.StringComparison]::OrdinalIgnoreCase)) {
                $systemIdMatch = $true
                break
            }
        }
        $systemIdMatch
    } | Select-Object -First 1

    if ($driverPackCloudObject) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Refreshed Surface DriverPackCloudObject: $($driverPackCloudObject.Name)"
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
        return $driverPackCloudObject
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No Surface DriverPackCloudObject matched OSDProduct '$OSDProduct'."
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
}
