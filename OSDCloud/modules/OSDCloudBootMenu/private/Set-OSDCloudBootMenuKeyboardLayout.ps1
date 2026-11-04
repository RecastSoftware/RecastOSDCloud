function Set-OSDCloudBootMenuKeyboardLayout {
    <#
    .SYNOPSIS
        Sets the keyboard layout for the current WinPE session.

    .DESCRIPTION
        Runs wpeutil SetKeyboardLayout with the specified LANGID:KLID input
        locale, such as 0409:00000409. The change applies to the current WinPE
        session only. A terminating error is returned when wpeutil cannot be
        started or exits with a non-zero code.

    .PARAMETER InputLocale
        Input locale in the LANGID:KLID form, for example 040C:0000040C.

    .EXAMPLE
        Set-OSDCloudBootMenuKeyboardLayout -InputLocale '0409:00020409'

        Sets the United States-International keyboard layout for the session.

    .OUTPUTS
        System.Void

    .NOTES
        Used by Show-OSDCloudBootMenuProfileWindow. Requires WinPE (wpeutil.exe).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}$')]
        [string]$InputLocale
    )

    if (-not $PSCmdlet.ShouldProcess($InputLocale, 'Set WinPE keyboard layout')) {
        return
    }

    try {
        $process = Start-Process -FilePath 'wpeutil.exe' -ArgumentList @('SetKeyboardLayout', $InputLocale) `
            -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
    }
    catch {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new("Unable to start wpeutil SetKeyboardLayout: $($_.Exception.Message)", $_.Exception),
                'KeyboardLayoutStartFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $InputLocale))
    }

    if ($process.ExitCode -ne 0) {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new("wpeutil SetKeyboardLayout $InputLocale exited with code $($process.ExitCode)."),
                'KeyboardLayoutSetFailed',
                [System.Management.Automation.ErrorCategory]::InvalidResult,
                $InputLocale))
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Set keyboard layout to $InputLocale"
}
