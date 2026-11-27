#requires -Version 5.1

function Test-WinpeStartupAssetLicense {
    <#
    .SYNOPSIS
        Quietly tests Recast license validity for WinpeStartup asset imports.

    .DESCRIPTION
        Delegates to Test-OSDCoreLicense for the reader's IsValid result, independently
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
    return (Test-OSDCoreLicense)
}
