function Invoke-PEStartupCommand {
    <#
    .SYNOPSIS
        Launches a BootMenu utility in a child Windows PowerShell process

    .DESCRIPTION
        Imports the current BootMenu manifest and executes the command in its private
        module scope without rerunning wpeinit. Preserves window style and NoExit.
        Synchronous launches with Wait report a nonzero child exit code as an error.

    .PARAMETER Command
        PowerShell text to execute in BootMenu's private module scope.

    .PARAMETER WindowStyle
        Child window style. Defaults to Normal.

    .PARAMETER Run
        Synchronous permits Wait to wait for the child. Asynchronous always returns
        after launch, even when Wait is specified. Defaults to Synchronous.

    .PARAMETER NoExit
        Keeps the child PowerShell window open after successful command completion.

    .PARAMETER Wait
        Waits for a synchronous child to exit. With NoExit, the user must close it.

    .EXAMPLE
        PS> Invoke-PEStartupCommand -Command 'Show-WinpeStartupIpconfig' -WindowStyle Minimized -NoExit

        Opens a minimized IP configuration window without waiting for it to close.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.String]
        $Command,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Normal', 'Minimized', 'Maximized', 'Hidden')]
        [System.String]
        $WindowStyle = 'Normal',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Asynchronous', 'Synchronous')]
        [System.String]
        $Run = 'Synchronous',

		[switch]
		$NoExit,

		[switch]
		$Wait
	)
    #=================================================
    $Error.Clear()
    #=================================================
    $childCommand = New-OSDCloudBootMenuChildCommand -Command $Command -Private
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
    $arguments = @('-NoLogo', '-NoProfile')
    if ($NoExit) { $arguments += '-NoExit' }
    $arguments += @('-EncodedCommand', $encodedCommand)
    $waitForExit = $Wait -and $Run -eq 'Synchronous'
    $processParameters = @{
        FilePath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        ArgumentList = $arguments
        WindowStyle = $WindowStyle
        Wait = [bool]$waitForExit
        PassThru = [bool]$waitForExit
        ErrorAction = 'Stop'
    }
    $process = Start-Process @processParameters
    if ($waitForExit -and $process.ExitCode -ne 0) {
        throw "BootMenu utility '$Command' exited with code $($process.ExitCode)."
    }
    #=================================================
}
