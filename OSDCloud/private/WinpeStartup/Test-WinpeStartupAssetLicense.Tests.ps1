BeforeAll {
    . "$PSScriptRoot\..\core-license\Get-OSDCoreLicense.ps1"
    . "$PSScriptRoot\Test-WinpeStartupAssetLicense.ps1"
}

Describe 'Test-WinpeStartupAssetLicense' {
    It 'uses validity rather than registration for <Label>' -TestCases @(
        @{ Label = 'valid unregistered license'; License = [pscustomobject]@{ IsValid = $true }; Registered = $false; Expected = $true }
        @{ Label = 'invalid registered license'; License = [pscustomobject]@{ IsValid = $false }; Registered = $true; Expected = $false }
        @{ Label = 'missing registered license'; License = $null; Registered = $true; Expected = $false }
        @{ Label = 'license without validity'; License = [pscustomobject]@{ Email = 'synthetic@example.invalid' }; Registered = $true; Expected = $false }
        @{ Label = 'valid expired candidate under existing policy'; License = [pscustomobject]@{ IsValid = $true; Expiration = [datetime]'2000-01-01' }; Registered = $false; Expected = $true }
    ) {
        param ($License, $Registered, $Expected)
        $savedLicense = Get-Variable -Name OSDCoreLicense -Scope Global -ErrorAction SilentlyContinue
        try {
            $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $Registered }
            Mock Get-OSDCoreLicense { $License }
            $warnings = @()
            $lookupErrors = @()

            $result = @(Test-WinpeStartupAssetLicense -WarningVariable warnings -ErrorVariable lookupErrors)

            $result.Count | Should -Be 1
            $result[0] | Should -BeOfType ([bool])
            $result[0] | Should -Be $Expected
            $warnings.Count | Should -Be 0
            $lookupErrors.Count | Should -Be 0
            Should -Invoke Get-OSDCoreLicense -Times 1 -Exactly -ParameterFilter {
                $ErrorAction -eq 'Stop' -and $WarningAction -eq 'SilentlyContinue' -and -not $Verbose
            }
        }
        finally {
            if ($savedLicense) {
                $global:OSDCoreLicense = $savedLicense.Value
            }
            else {
                Remove-Variable -Name OSDCoreLicense -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }

    It 'quietly denies a <Failure> lookup without logging exception details' -TestCases @(
        @{ Failure = 'terminating' }
        @{ Failure = 'nonterminating' }
        @{ Failure = 'warning then missing' }
    ) {
        param ($Failure)
        Mock Get-OSDCoreLicense {
            switch ($Failure) {
                'terminating' { throw 'synthetic-private-license-data' }
                'nonterminating' { Write-Error 'synthetic-private-license-data' }
                'warning then missing' { Write-Warning 'synthetic-private-license-data' }
            }
        }
        $output = @(Test-WinpeStartupAssetLicense -ErrorAction Stop `
            -WarningAction Continue -Verbose 2>&1 3>&1 4>&1)

        @($output | Where-Object { $_ -is [bool] }).Count | Should -Be 1
        ($output | Where-Object { $_ -is [bool] }) | Should -Be $false
        @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
        @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
        ($output | Out-String) | Should -Not -Match 'synthetic-private-license-data'
    }
}
