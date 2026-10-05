#requires -Version 5.1

function Invoke-DrvLoad {
    <#
    .SYNOPSIS
        Wrapper around drvload.exe for driver loading in WinPE

    .DESCRIPTION
        Calls drvload.exe with the specified .inf file path. This wrapper
        exists so that Pester tests can mock the external executable call.

    .PARAMETER InfPath
        The full path to the .inf driver file to load.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$InfPath
    )

    & drvload.exe $InfPath 2>&1
}
