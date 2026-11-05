function New-OSDCloudBootMenuChildCommand {
    <#
    .SYNOPSIS
        Creates a module-aware child PowerShell command
    .DESCRIPTION
        Prioritizes the child PowerShell installation's built-in modules over
        inherited module paths, then imports this BootMenu manifest before running
        commands. Private utility commands execute in the imported module scope.
        Terminating failures exit the child with status 1, including when NoExit
        is requested.
    .PARAMETER Command
        PowerShell text to execute after importing BootMenu.
    .PARAMETER Private
        Runs the command in BootMenu's private module scope.
    .EXAMPLE
        PS> New-OSDCloudBootMenuChildCommand -Command 'Show-WinpeStartupIpconfig' -Private

        Returns child script text without executing it.
    .INPUTS
        None. This function does not accept pipeline input.
    .OUTPUTS
        System.String. Child PowerShell script text.
    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$Command,
        [switch]$Private
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating child command"
    $manifestPath = $script:OSDCloudBootMenuModulePath.Replace("'", "''")
    $body = if ($Private) { "& `$bootMenuModule {`r`n$Command`r`n}" } else { $Command }
    return @"
try {
`$env:PSModulePath = [IO.Path]::Combine(`$PSHOME, 'Modules') + [IO.Path]::PathSeparator + `$env:PSModulePath
`$bootMenuModule = Import-Module -Name '$manifestPath' -PassThru -ErrorAction Stop
$body
}
catch {
Write-Error -ErrorRecord `$_
exit 1
}
"@
}
