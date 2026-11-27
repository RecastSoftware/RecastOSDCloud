BeforeAll {
    . "$PSScriptRoot\Test-OSDCloudBootMenu.ps1"
    function Get-OSDCloudBootMenuProfileCandidates { }
    function Show-OSDCloudBootMenuProfileWindow { param ($Profiles, [switch]$TestMode) }
}

Describe 'Test-OSDCloudBootMenu' {
    It 'shows a single discovered profile in test mode and returns the selection' {
        $candidate = [pscustomobject]@{ Index = 0; Id = '11111111-1111-1111-1111-111111111111'; Profile = 'Menu'; Path = 'C:\OSDCloud\core\bootmenu-profiles\menu\osdcloudbootmenu.json'; AssetPath = 'C:\OSDCloud\core\bootmenu-profiles\menu' }
        Mock Get-OSDCloudBootMenuProfileCandidates { $candidate }
        Mock Show-OSDCloudBootMenuProfileWindow { $Profiles[0] }

        $result = Test-OSDCloudBootMenu

        $result.Profile | Should -Be 'Menu'
        $result.Index | Should -Be 1
        Should -Invoke Show-OSDCloudBootMenuProfileWindow -Times 1 -Exactly -ParameterFilter { $TestMode -and @($Profiles).Count -eq 1 }
    }

    It 'shows sample profiles without discovery when requested' {
        Mock Get-OSDCloudBootMenuProfileCandidates { throw 'should not be called' }
        Mock Show-OSDCloudBootMenuProfileWindow { }

        Test-OSDCloudBootMenu -SampleProfiles -WarningAction SilentlyContinue -ErrorVariable errors

        $errors | Should -BeNullOrEmpty
        Should -Invoke Get-OSDCloudBootMenuProfileCandidates -Times 0 -Exactly
        Should -Invoke Show-OSDCloudBootMenuProfileWindow -Times 1 -Exactly -ParameterFilter {
            $TestMode -and @($Profiles).Count -eq 3 -and @($Profiles | Where-Object { $_.Profile -notlike 'Sample:*' }).Count -eq 0 -and
            (@($Profiles.Index) -join ',') -eq '1,2,3' -and
            @($Profiles | Where-Object { $_.Path -notlike 'X:\OSDCloud\core\bootmenu-profiles\sample-*\osdcloudbootmenu.json' }).Count -eq 0
        }
    }

    It 'falls back to sample profiles with a warning when discovery fails' {
        Mock Get-OSDCloudBootMenuProfileCandidates { throw 'Invalid profile' }
        Mock Show-OSDCloudBootMenuProfileWindow { }

        Test-OSDCloudBootMenu -WarningVariable warnings -WarningAction SilentlyContinue

        ($warnings -join ' ') | Should -BeLike '*Profile discovery failed*Invalid profile*'
        Should -Invoke Show-OSDCloudBootMenuProfileWindow -Times 1 -Exactly -ParameterFilter { @($Profiles).Count -eq 3 }
    }

    It 'falls back to sample profiles when none are found' {
        Mock Get-OSDCloudBootMenuProfileCandidates { }
        Mock Show-OSDCloudBootMenuProfileWindow { }

        Test-OSDCloudBootMenu -WarningVariable warnings -WarningAction SilentlyContinue

        ($warnings -join ' ') | Should -BeLike '*No BootMenu profiles were found*'
        Should -Invoke Show-OSDCloudBootMenuProfileWindow -Times 1 -Exactly -ParameterFilter { @($Profiles).Count -eq 3 }
    }

    It 'returns nothing and warns when the window is cancelled' {
        Mock Get-OSDCloudBootMenuProfileCandidates { }
        Mock Show-OSDCloudBootMenuProfileWindow { }

        $result = Test-OSDCloudBootMenu -SampleProfiles -WarningVariable warnings -WarningAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        ($warnings -join ' ') | Should -BeLike '*cancelled*'
    }
}
