function Get-OSDCloudBootMenuKeyboardLayout {
    <#
    .SYNOPSIS
        Lists the keyboard layouts available to the standalone OSDCloud BootMenu.

    .DESCRIPTION
        Reads keyboard layouts from
        HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts and returns
        one object per eight-digit hexadecimal layout ID (KLID) with a
        Layout Text value. Input method editor layouts (IDs beginning with E)
        are excluded because they cannot be set with wpeutil SetKeyboardLayout.
        Results are sorted by name.

        The InputLocale property uses the LANGID:KLID form accepted by
        wpeutil SetKeyboardLayout, where LANGID is the last four digits of
        the layout ID. IsCurrent identifies the layout reported by
        Win32_Keyboard, when available.

    .PARAMETER Path
        Registry path that contains keyboard layout keys. Defaults to the
        system keyboard layout registry key.

    .EXAMPLE
        Get-OSDCloudBootMenuKeyboardLayout

        Lists the keyboard layouts available in the current WinPE session.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Used by Show-OSDCloudBootMenuProfileWindow.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts'
    )

    $currentLayout = $null
    try {
        $currentLayout = [string](Get-CimInstance -ClassName Win32_Keyboard -ErrorAction Stop |
                Select-Object -ExpandProperty Layout -First 1)
    }
    catch {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to detect the current keyboard layout: $($_.Exception.Message)"
    }

    $layoutKeys = @(Get-ChildItem -LiteralPath $Path -ErrorAction Stop)
    $layouts = foreach ($layoutKey in $layoutKeys) {
        $layoutId = $layoutKey.PSChildName
        if ($layoutId -notmatch '^[0-9A-Fa-f]{8}$' -or $layoutId -match '^[Ee]') {
            continue
        }

        $layoutText = [string]$layoutKey.GetValue('Layout Text')
        if ([string]::IsNullOrWhiteSpace($layoutText)) {
            continue
        }

        $normalizedId = $layoutId.ToUpperInvariant()
        [pscustomobject]@{
            Name        = $layoutText
            Id          = $normalizedId
            InputLocale = '{0}:{1}' -f $normalizedId.Substring(4), $normalizedId
            IsCurrent   = (-not [string]::IsNullOrWhiteSpace($currentLayout)) -and
            ($normalizedId -eq $currentLayout.Trim().ToUpperInvariant())
        }
    }

    $layouts | Sort-Object -Property Name, Id
}
