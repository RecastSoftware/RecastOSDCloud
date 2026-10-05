#requires -Version 5.1

function Invoke-CmdScript {
    <#
    .SYNOPSIS
        Wrapper around cmd.exe for executing CMD scripts in WinPE

    .DESCRIPTION
        Calls cmd.exe /c call with the specified script path. This wrapper
        exists so that Pester tests can mock the external executable call.

    .PARAMETER ScriptPath
        The full path to the .cmd script file to execute.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    & cmd.exe /c call "$ScriptPath" 2>&1
}
