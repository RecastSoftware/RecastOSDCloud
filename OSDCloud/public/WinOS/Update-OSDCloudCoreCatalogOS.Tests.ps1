#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\OSDCloud.psd1'
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module OSDCloud -Force -ErrorAction SilentlyContinue
}

Describe 'Update-OSDCloudCoreCatalogOS' {
    It 'is exported with ShouldProcess support' {
        $command = Get-Command Update-OSDCloudCoreCatalogOS -Module OSDCloud

        $command | Should -Not -BeNullOrEmpty
        $command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $command.Parameters.ContainsKey('Confirm') | Should -BeTrue
    }

    It 'validates MinimumItemCount before execution' {
        { Update-OSDCloudCoreCatalogOS -MinimumItemCount 0 -WhatIf } | Should -Throw
        { Update-OSDCloudCoreCatalogOS -MinimumItemCount 100001 -WhatIf } | Should -Throw
    }

    It 'reports metadata service failures without terminating' {
        Mock -CommandName Invoke-RestMethod -ModuleName OSDCloud -MockWith {
            throw 'Metadata service unavailable'
        }

        $warnings = @()
        $result = Update-OSDCloudCoreCatalogOS -WhatIf -WarningVariable warnings

        $result | Should -BeNullOrEmpty
        $warnings | Should -HaveCount 1
        $warnings[0].Message | Should -Match 'Metadata service unavailable'
    }

    It 'rejects metadata without exactly one products.cab record' {
        Mock -CommandName Invoke-RestMethod -ModuleName OSDCloud -MockWith {
            [pscustomobject]@{
                FileLocations = @()
            }
        }
        Mock -CommandName Invoke-WebRequest -ModuleName OSDCloud -MockWith {
            throw 'Invoke-WebRequest should not be called'
        }

        $warnings = @()
        $result = Update-OSDCloudCoreCatalogOS -WhatIf -WarningVariable warnings

        $result | Should -BeNullOrEmpty
        $warnings | Should -HaveCount 1
        $warnings[0].Message | Should -Match 'returned 0 products.cab records; expected one'
        Should -Invoke Invoke-WebRequest -ModuleName OSDCloud -Times 0 -Exactly
    }
}
