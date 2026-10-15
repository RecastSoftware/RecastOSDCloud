BeforeAll {
    . "$PSScriptRoot\Update-RecastOSDCloudUSBCache.ps1"
    . "$PSScriptRoot\..\core-license\Get-OSDCoreLicense.ps1"
    . "$PSScriptRoot\..\core-license\Test-OSDCoreLicense.ps1"
    . "$PSScriptRoot\..\core-license\Show-OSDCoreLicenseHelp.ps1"
    . "$PSScriptRoot\..\core-license\Initialize-OSDCoreLicense.ps1"
    . "$PSScriptRoot\..\core-device\Initialize-OSDCoreDevice.ps1"
    . "$PSScriptRoot\..\core\Convert-KeyboardLayoutToLanguageCode.ps1"
    . "$PSScriptRoot\Get-OSDCoreCacheUSBPath.ps1"
    $originalDevice = $global:OSDCoreDevice
    $originalLicense = $global:OSDCoreLicense
}

AfterAll {
    $global:OSDCoreDevice = $originalDevice
    $global:OSDCoreLicense = $originalLicense
}

Describe 'USB cache language inference license boundary' {
    BeforeEach {
        $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $false }
        $global:OSDCoreDevice = [pscustomobject]@{ KeyboardLayout = '0000040C' }
        Mock Get-OSDCoreLicense { [pscustomobject]@{ IsValid = $true } }
        Mock Show-OSDCoreLicenseHelp {}
        Mock Initialize-OSDCoreLicense {}
        Mock Initialize-OSDCoreDevice {}
        Mock Get-OSDCoreCacheUSBPath { 'E:\OSDCloud' }
        Mock Write-Host {}
        Mock Convert-KeyboardLayoutToLanguageCode { throw 'Synthetic selection boundary reached' }
    }

    It 'allows a valid unregistered license to reach keyboard conversion' {
        { Update-RecastOSDCloudUSBCache -OSArchitecture amd64 } | Should -Throw '*Synthetic selection boundary reached*'
        Should -Invoke Convert-KeyboardLayoutToLanguageCode -Times 1 -Exactly -ParameterFilter {
            $KeyboardLayout -eq '0000040C' -and $FallbackLanguageCode -eq 'en-US'
        }
        Should -Invoke Show-OSDCoreLicenseHelp -Times 0 -Exactly
    }

    It 'denies <Case> before USB discovery or keyboard conversion' -TestCases @(
        @{ Case = 'missing' }
        @{ Case = 'invalid registered' }
        @{ Case = 'registration only' }
        @{ Case = 'failed lookup' }
    ) {
        param ($Case)
        $global:OSDCoreLicense.IsRegistered = $true
        Mock Get-OSDCoreLicense {
            switch ($Case) {
                'missing' { $null }
                'invalid registered' { [pscustomobject]@{ IsValid = $false } }
                'registration only' { [pscustomobject]@{ IsRegistered = $true } }
                'failed lookup' { throw 'synthetic-private-license-data' }
            }
        }
        $output = @(Update-RecastOSDCloudUSBCache -OSArchitecture amd64 -Verbose 4>&1 3>&1 2>&1)
        "$output" | Should -Not -Match 'synthetic-private-license-data'
        Should -Invoke Show-OSDCoreLicenseHelp -Times 1 -Exactly
        Should -Invoke Get-OSDCoreCacheUSBPath -Times 0 -Exactly
        Should -Invoke Convert-KeyboardLayoutToLanguageCode -Times 0 -Exactly
    }
}
