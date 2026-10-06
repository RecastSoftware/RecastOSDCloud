BeforeAll {
    . "$PSScriptRoot\Get-WinpeStartupProfileCandidates.ps1"
}

Describe 'Get-WinpeStartupProfileCandidates' {
    It 'discovers folder profiles and legacy root-level JSON files' {
        Mock Test-Path {
            if ($LiteralPath -eq 'C:\WinpeStartup\profiles') {
                return $true
            }
            if ($LiteralPath -eq (Join-Path (Join-Path 'C:\WinpeStartup\profiles' 'BranchOffice') 'winpestartup.json')) {
                return $true
            }
            return $false
        }

        Mock Get-ChildItem {
            if ($File) {
                return @(
                    [pscustomobject]@{
                        BaseName = 'Legacy'
                        FullName = (Join-Path 'C:\WinpeStartup\profiles' 'Legacy.json')
                    }
                )
            }
            if ($Directory) {
                return @(
                    [pscustomobject]@{
                        Name     = 'BranchOffice'
                        FullName = (Join-Path 'C:\WinpeStartup\profiles' 'BranchOffice')
                    }
                    [pscustomobject]@{
                        Name     = 'Empty'
                        FullName = (Join-Path 'C:\WinpeStartup\profiles' 'Empty')
                    }
                )
            }
        } -ParameterFilter { $LiteralPath -eq 'C:\WinpeStartup\profiles' }

        $profiles = @(Get-WinpeStartupProfileCandidates)

        $profiles.Count | Should -Be 2
        $profiles.Profile | Should -Contain 'BranchOffice'
        $profiles.Profile | Should -Contain 'Legacy'
        ($profiles | Where-Object Profile -eq 'BranchOffice').Path |
            Should -Be (Join-Path (Join-Path 'C:\WinpeStartup\profiles' 'BranchOffice') 'winpestartup.json')
        ($profiles | Where-Object Profile -eq 'Legacy').Path |
            Should -Be (Join-Path 'C:\WinpeStartup\profiles' 'Legacy.json')
        Should -Invoke Get-ChildItem -Times 2 -Exactly -ParameterFilter { $LiteralPath -eq 'C:\WinpeStartup\profiles' }
    }
}
