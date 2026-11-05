#requires -Version 5.1

function Invoke-WpeInit {
    <#
    .SYNOPSIS
        Wrapper around wpeinit.exe for WinPE initialization

    .DESCRIPTION
        Calls wpeinit.exe to perform WinPE hardware initialization. This
        wrapper exists so that Pester tests can mock the external executable.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    $null = & wpeinit.exe 2>&1
}
