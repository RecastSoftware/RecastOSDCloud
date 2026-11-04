#requires -Version 5.1

function Invoke-Robocopy {
    <#
    .SYNOPSIS
        Wrapper around robocopy.exe for content copying in WinPE

    .DESCRIPTION
        Calls robocopy.exe with flags that mirror Source into Destination,
        preserving extra files at the destination. This wrapper exists so
        that Pester tests can mock the external executable call.

    .PARAMETER Source
        The source directory to copy from.

    .PARAMETER Destination
        The destination directory to copy into.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $null = & robocopy.exe $Source $Destination /E /XX /COPY:DAT /DCOPY:DAT /R:0 /NFL /NDL 2>&1
}
