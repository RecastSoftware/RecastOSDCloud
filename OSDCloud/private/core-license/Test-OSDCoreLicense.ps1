#requires -Version 5.1

function Test-OSDCoreLicense {
    <#
    .SYNOPSIS
        Tests whether a valid Recast license is available for licensed features.

    .DESCRIPTION
        Uses the selected Get-OSDCoreLicense result's IsValid property, not
        registration or cached global license state. Missing, invalid, or failed
        lookups return false without warnings, errors, or registration guidance.
        Lookup failures produce only a generic verbose diagnostic.

    .EXAMPLE
        Test-OSDCoreLicense

        Returns whether licensed feature work may proceed.

    .OUTPUTS
        System.Boolean

    .NOTES
        Has no parameters or bypass. Preserves the reader's existing license
        selection, expiration, and signature policies.
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
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] License lookup failed; licensed feature disabled."
        return $false
    }
}
