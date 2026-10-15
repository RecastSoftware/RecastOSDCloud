#requires -Version 5.1

function Test-WinpeStartupAssetLicense {
    <#
    .SYNOPSIS
        Quietly tests Recast license validity for WinpeStartup asset imports.

    .DESCRIPTION
        Uses the existing Recast license reader's IsValid result, independently
        of registration state. Missing, invalid, or unreadable licenses disable
        asset imports without warnings, errors, or registration guidance.
        Lookup failures produce only a generic verbose diagnostic.

    .EXAMPLE
        Test-WinpeStartupAssetLicense

        Returns whether Core and selected-profile assets may be imported.

    .OUTPUTS
        System.Boolean

    .NOTES
        Does not change license validity or expiration policy.
        Has no parameters or license-gate bypass.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    $Error.Clear()
    try {
        $license = Get-OSDCoreLicense -ErrorAction Stop -WarningAction SilentlyContinue -Verbose:$false
        return ($null -ne $license -and $license.IsValid -eq $true)
    }
    catch {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] License lookup failed; asset imports disabled."
        return $false
    }
}
