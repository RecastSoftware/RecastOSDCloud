BeforeAll {
    . "$PSScriptRoot\Get-OSDCoreLicense.ps1"
    . "$PSScriptRoot\Test-OSDCoreLicense.ps1"
    $savedLicenseState = Get-Variable -Name OSDCoreLicense -Scope Global -ErrorAction SilentlyContinue
}

AfterAll {
    if ($savedLicenseState) {
        $global:OSDCoreLicense = $savedLicenseState.Value
    }
    else {
        Remove-Variable -Name OSDCoreLicense -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'Test-OSDCoreLicense shared validity decision' {
    It 'returns one Boolean for <Case> independently of registration' -TestCases @(
        @{ Case = 'valid unregistered license'; License = [pscustomobject]@{ IsValid = $true }; Registered = $false; Expected = $true }
        @{ Case = 'invalid registered license'; License = [pscustomobject]@{ IsValid = $false }; Registered = $true; Expected = $false }
        @{ Case = 'registration only'; License = [pscustomobject]@{ IsRegistered = $true }; Registered = $true; Expected = $false }
        @{ Case = 'email only'; License = [pscustomobject]@{ Email = 'synthetic@example.invalid' }; Registered = $true; Expected = $false }
        @{ Case = 'missing license'; License = $null; Registered = $true; Expected = $false }
        @{ Case = 'valid expired candidate under existing policy'; License = [pscustomobject]@{ IsValid = $true; Expiration = [datetime]'2000-01-01' }; Registered = $false; Expected = $true }
    ) {
        param ($License, $Registered, $Expected)
        $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $Registered }
        Mock Get-OSDCoreLicense { $License }
        $result = @(Test-OSDCoreLicense -WarningVariable warnings -ErrorVariable lookupErrors)

        $result.Count | Should -Be 1
        $result[0] | Should -BeOfType ([bool])
        $result[0] | Should -Be $Expected
        @($warnings).Count | Should -Be 0
        @($lookupErrors).Count | Should -Be 0
        Should -Invoke Get-OSDCoreLicense -Times 1 -Exactly -ParameterFilter {
            $ErrorAction -eq 'Stop' -and $WarningAction -eq 'SilentlyContinue' -and $Verbose -eq $false
        }
    }

    It 'can check validity before global license initialization' {
        $global:OSDCoreLicense = $null
        Mock Get-OSDCoreLicense { [pscustomobject]@{ IsValid = $true } }
        Test-OSDCoreLicense | Should -BeTrue
        $global:OSDCoreLicense | Should -BeNullOrEmpty
    }

    It 'fails closed for a <Failure> lookup with no private diagnostics' -TestCases @(
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
        $output = @(Test-OSDCoreLicense -ErrorAction Stop -WarningAction Continue -Verbose 2>&1 3>&1 4>&1)
        @($output | Where-Object { $_ -is [bool] }).Count | Should -Be 1
        ($output | Where-Object { $_ -is [bool] }) | Should -BeFalse
        @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
        @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
        ($output | Out-String) | Should -Not -Match 'synthetic-private-license-data'
        if ($Failure -ne 'warning then missing') {
            ($output | Out-String) | Should -Match 'License lookup failed'
        }
    }

    It 'honors real reader Incognito behavior without discovering saved licenses' {
        $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $true; IsIncognito = $true }
        Mock Get-ChildItem { throw 'Unexpected license discovery' }
        Mock Test-Path { throw 'Unexpected license path lookup' }
        Mock New-Item { throw 'Unexpected license directory creation' }
        Test-OSDCoreLicense | Should -BeFalse
        Should -Invoke Get-ChildItem -Times 0 -Exactly
        Should -Invoke Test-Path -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
    }
}
