function Test-OSDCloudBootMenu {
    <#
    .SYNOPSIS
        Shows the standalone OSDCloud BootMenu window in Windows for testing

    .DESCRIPTION
        Opens the BootMenu profile window that Invoke-OSDCloudBootMenu shows in
        WinPE, so its layout and shortcuts can be tested in full Windows. The
        window opens in test mode and nothing is deployed or changed:

        - Start returns the selected profile object; the profile is not run.
        - Keyboard Layout lists the installed layouts, but selecting one only
          reports the wpeutil SetKeyboardLayout command it would run.
        - OSDCloud Explorer opens Start-OSDCloudExplorer in a separate window.

        By default, profiles are discovered the same way as in WinPE, from
        OSDCloud\core\bootmenu-profiles\<id>\osdcloudbootmenu.json on drives C:
        through Z:. Unlike Invoke-OSDCloudBootMenu, the window is shown even
        when only one profile is found. When no profiles are found, or discovery
        fails, sample profiles are shown instead and a warning explains why.
        Import the standalone OSDCloudWinPE manifest before calling this
        command. OSDCloud is needed only if the Explorer action is selected.

    .PARAMETER SampleProfiles
        Shows built-in sample profiles without searching drives for profiles.

    .EXAMPLE
        PS> Test-OSDCloudBootMenu

        Shows the discovered BootMenu profiles, or sample profiles when none are
        found, and returns the profile selected with Start.

    .EXAMPLE
        PS> Test-OSDCloudBootMenu -SampleProfiles

        Shows the window with sample profiles only.

    .INPUTS
        None. You cannot pipe objects to Test-OSDCloudBootMenu.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        The selected profile with Index, Id, Profile, Path, and AssetPath
        properties. Nothing is returned when the window is cancelled or closed.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
        Requires Windows with WPF and a single-threaded apartment (STA)
        PowerShell session, which is the default for Windows PowerShell 5.1 and
        PowerShell 7 on Windows.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [switch]$SampleProfiles
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.InvalidOperationException]::new('Test-OSDCloudBootMenu requires a single-threaded apartment (STA) PowerShell session. Start PowerShell with -STA.'),
                'OSDCloudBootMenuRequiresSTA',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null
            )
        )
    }

    $profiles = @()
    if (-not $SampleProfiles) {
        try {
            $profiles = @(Get-OSDCloudBootMenuProfileCandidates -ErrorAction Stop)
            if ($profiles.Count -eq 0) {
                Write-Warning 'Test-OSDCloudBootMenu: No BootMenu profiles were found. Showing sample profiles.'
            }
        }
        catch {
            Write-Warning "Test-OSDCloudBootMenu: Profile discovery failed, showing sample profiles: $($_.Exception.Message)"
            $profiles = @()
        }
    }

    if ($profiles.Count -eq 0) {
        $profiles = @(
            foreach ($sample in @(
                    @{ Id = '6a4f1b2c-0d3e-4f5a-8b6c-7d8e9f0a1b2c'; Name = 'Sample: Default'; Folder = 'sample-default' },
                    @{ Id = '7b5a2c3d-1e4f-4a6b-9c7d-8e9f0a1b2c3d'; Name = 'Sample: Autopilot'; Folder = 'sample-autopilot' },
                    @{ Id = '8c6b3d4e-2f5a-4b7c-8d8e-9f0a1b2c3d4e'; Name = 'Sample: Kiosk'; Folder = 'sample-kiosk' }
                )) {
                $assetPath = "X:\OSDCloud\core\bootmenu-profiles\$($sample.Folder)"
                [pscustomobject]@{
                    Index     = 0
                    Id        = $sample.Id
                    Profile   = $sample.Name
                    Path      = "$assetPath\osdcloudbootmenu.json"
                    AssetPath = $assetPath
                }
            }
        )
    }

    $orderedProfiles = @($profiles | Sort-Object RootIndex, OrderIndex, Profile, Path)
    for ($i = 0; $i -lt $orderedProfiles.Count; $i++) {
        $orderedProfiles[$i].Index = $i + 1
    }

    $selectedProfile = Show-OSDCloudBootMenuProfileWindow -Profiles $orderedProfiles -TestMode -ErrorAction Stop
    if ($selectedProfile) {
        Write-Verbose "Test-OSDCloudBootMenu: Selected profile '$($selectedProfile.Profile)' at '$($selectedProfile.Path)'. The profile was not run."
        $selectedProfile
    }
    else {
        Write-Warning 'Test-OSDCloudBootMenu: Profile selection cancelled.'
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
}
