BeforeAll {
    . "$PSScriptRoot\Get-OSDCoreLicense.ps1"
    . "$PSScriptRoot\Initialize-OSDCoreLicense.ps1"
    $originalLicense = $global:OSDCoreLicense
    $licenseDirectory = Join-Path $TestDrive 'licenses'
    $null = New-Item $licenseDirectory -ItemType Directory
    $licensePath = Join-Path $licenseDirectory 'synthetic.license2'
    @{
        Data = @{
            LicenseGuid = '11111111-1111-4111-8111-111111111111'
            Email = 'synthetic@example.invalid'
            AuthorizedPluginCommands = @('synthetic')
        }
        Signature = 'synthetic-not-a-real-signature'
    } | ConvertTo-Json -Depth 4 | Set-Content $licensePath
    $originalHash = (Get-FileHash $licensePath).Hash
}

AfterAll {
    $global:OSDCoreLicense = $originalLicense
}

Describe 'Incognito license discovery simulation' {
    BeforeEach {
        $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $false; IsIncognito = $true }
    }

    It 'returns no license before discovery even with an explicit license path' {
        Mock Test-Path { throw 'Unexpected path discovery' }
        Mock Get-ChildItem { throw 'Unexpected file discovery' }
        Mock Get-Content { throw 'Unexpected license read' }
        Mock New-Item { throw 'Unexpected filesystem change' }
        Get-OSDCoreLicense -Path $licenseDirectory | Should -BeNullOrEmpty
        Should -Invoke Test-Path -Times 0 -Exactly
        Should -Invoke Get-ChildItem -Times 0 -Exactly
        Should -Invoke Get-Content -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
    }

    It 'restores the same saved valid license when simulation is disabled' {
        Get-OSDCoreLicense -Path $licenseDirectory | Should -BeNullOrEmpty
        $global:OSDCoreLicense.IsIncognito = $false
        $license = Get-OSDCoreLicense -Path $licenseDirectory
        $license.IsValid | Should -BeTrue
        $license.Email | Should -Be 'synthetic@example.invalid'
        (Get-FileHash $licensePath).Hash | Should -Be $originalHash
    }

    It 'does not treat unregistered state alone as license denial' {
        $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $false }
        (Get-OSDCoreLicense -Path $licenseDirectory).IsValid | Should -BeTrue
    }

    It 'clears simulation before initializing the next normal license state' {
        Mock Get-OSDCoreLicense {
            $global:OSDCoreLicense.IsIncognito | Should -BeFalse
            [pscustomobject]@{ Email = 'synthetic@example.invalid'; IsValid = $true }
        }
        Mock Get-CimInstance { [pscustomobject]@{ UUID = '' } }
        Initialize-OSDCoreLicense
        $global:OSDCoreLicense.IsIncognito | Should -BeFalse
        $global:OSDCoreLicense.IsRegistered | Should -BeTrue
        $global:OSDCoreLicense.License.IsValid | Should -BeTrue
    }
}
