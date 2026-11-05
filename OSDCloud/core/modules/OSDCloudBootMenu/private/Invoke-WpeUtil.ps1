#requires -Version 5.1

function Invoke-WpeUtil {
    <#
    .SYNOPSIS
        Wrapper around wpeutil.exe for WinPE utility commands

    .DESCRIPTION
        Calls wpeutil.exe with the specified command. This wrapper exists
        so that Pester tests can mock the external executable.

    .PARAMETER Command
        The wpeutil command to execute (e.g. DisableFirewall, UpdateBootInfo).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $null = & wpeutil.exe $Command 2>&1
}
