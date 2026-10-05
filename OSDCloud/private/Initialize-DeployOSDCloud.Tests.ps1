BeforeAll {
    . "$PSScriptRoot\Initialize-DeployOSDCloud.ps1"
    . "$PSScriptRoot\core-cache\Initialize-OSDCoreCache.ps1"
    . "$PSScriptRoot\core-driverpack\Initialize-ModuleCoreDriverPacks.ps1"
    . "$PSScriptRoot\core-driverpack\Get-OSDCoreModelDriversCacheObject.ps1"
    . "$PSScriptRoot\core-driverpack\Get-OSDCoreDriverPackCacheObject.ps1"
    . "$PSScriptRoot\core-driverpack\Test-OSDCoreDriverPackCloudObject.ps1"
    . "$PSScriptRoot\core-operatingsystem\Get-OSDCoreOperatingSystems.ps1"
    . "$PSScriptRoot\core-operatingsystem\Get-OSDCoreOperatingSystemCacheObject.ps1"
    . "$PSScriptRoot\core-operatingsystem\Test-OperatingSystemCloudObject.ps1"
    . "$PSScriptRoot\workflow\Initialize-OSDCloudWorkflowSettingsOS.ps1"
    . "$PSScriptRoot\workflow\Resolve-OSDCloudWorkflowOSActivation.ps1"
    . "$PSScriptRoot\workflow\Initialize-OSDCloudWorkflowTasks.ps1"
    $stateNames = @(
        'OSDCoreDevice', 'OSDCloudDeploy', 'OSDCloudEnv', 'OSDCoreDriverPacks',
        'ModuleCoreDriverPacks', 'OSDCoreOperatingSystems', 'OSDCloudWorkflowSettingsOS',
        'OSDCloudWorkflowTasks'
    )
    $originalState = @{}
    foreach ($name in $stateNames) {
        $originalState[$name] = Get-Variable -Name $name -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    }
}

AfterAll {
    foreach ($name in $stateNames) {
        Set-Variable -Name $name -Value $originalState[$name] -Scope Global
    }
}

Describe 'Initialize-DeployOSDCloud ModelDrivers defaults' {
    BeforeEach {
        $entry = [pscustomobject]@{ Type = 'ModelDrivers'; FullName = 'E:\OSDCloud\modeldrivers-amd64\HP_8CD1_Any model_28000.1' }
        $global:OSDCoreDevice = [pscustomobject]@{
            OSDManufacturer = 'HP'
            OSDProduct = '8CD1'
            OSDModel = 'A different device model'
            ProcessorArchitecture = 'amd64'
            LocalDisk = @([pscustomobject]@{ Number = 0; FriendlyName = 'Test disk'; Size = 100GB })
        }
        $global:OSDCloudEnv = $null
        $global:ModuleCoreDriverPacks = @([pscustomobject]@{
            Name = 'OEM pack'; SystemId = '8CD1'; OSArchitecture = 'amd64'; FileName = 'pack.cab'
            Url = 'https://example.invalid/pack.cab'; HashMD5 = 'not-used-for-modeldrivers'
        })
        $global:OSDCloudWorkflowSettingsOS = [pscustomobject]@{
            OperatingSystem = [pscustomobject]@{ default = 'Windows 11 25H2'; values = @('Windows 11 25H2') }
            OSActivation = [pscustomobject]@{ default = 'Retail'; values = @('Retail') }
            OSEdition = [pscustomobject]@{ default = 'Pro'; values = @([pscustomobject]@{ Edition = 'Pro'; EditionId = 'Professional' }) }
            OSLanguageCode = [pscustomobject]@{ default = 'en-us'; values = @('en-us') }
        }
        $global:OSDCloudWorkflowTasks = @([pscustomobject]@{ name = 'OSDCloud'; steps = @() })
        Mock Initialize-OSDCoreCache {}
        Mock Initialize-ModuleCoreDriverPacks {}
        Mock Get-OSDCoreModelDriversCacheObject { $entry }
        Mock Test-OSDCoreDriverPackCloudObject { $true }
        Mock Get-OSDCoreDriverPackCacheObject {}
        Mock Get-OSDCoreOperatingSystems {
            [pscustomobject]@{
                OperatingSystem = 'Windows 11 25H2'; OSActivation = 'Retail'; OSLanguageCode = 'en-us'
                OSArchitecture = $global:OSDCoreDevice.ProcessorArchitecture; OSBuild = '26200'; OSBuildVersion = '26200.9457'
            }
        }
        Mock Initialize-OSDCloudWorkflowSettingsOS {}
        Mock Resolve-OSDCloudWorkflowOSActivation { $OSActivation }
        Mock Test-OperatingSystemCloudObject { $true }
        Mock Get-OSDCoreOperatingSystemCacheObject {}
        Mock Initialize-OSDCloudWorkflowTasks {}
        Mock Export-Clixml {}
        Mock Get-FileHash { throw 'Unexpected archive hashing' }
        Mock Write-Host {}
    }

    It 'defaults to ModelDrivers and retains OEM fallback without testing its URL or archive' {
        Initialize-DeployOSDCloud
        $global:OSDCloudDeploy.DriverPackName | Should -Be 'ModelDrivers'
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -Be $entry
        $global:OSDCloudDeploy.DriverPackCloudObject.Name | Should -Be 'OEM pack'
        $global:OSDCloudDeploy.OSBuildVersion | Should -Be '26200.9457'
        Should -Invoke Test-OSDCoreDriverPackCloudObject -Times 0 -Exactly
        Should -Invoke Get-OSDCoreDriverPackCacheObject -Times 0 -Exactly
        Should -Invoke Get-FileHash -Times 0 -Exactly
    }

    It 'defaults to ModelDrivers when the device has no OEM catalog entry' {
        $global:ModuleCoreDriverPacks = @()
        Initialize-DeployOSDCloud
        $global:OSDCloudDeploy.DriverPackName | Should -Be 'ModelDrivers'
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -Be $entry
        $global:OSDCloudDeploy.DriverPackCloudObject | Should -BeNullOrEmpty
    }

    It 'selects ModelDrivers after device overrides and with the effective architecture' {
        Initialize-DeployOSDCloud -OSDManufacturer Microsoft -OSDProduct Surface_Product -OSDModel 'Ignored override' -ProcessorArchitecture arm64
        Should -Invoke Get-OSDCoreModelDriversCacheObject -Times 1 -Exactly -ParameterFilter {
            $OSArchitecture -eq 'arm64' -and $global:OSDCoreDevice.OSDManufacturer -eq 'Microsoft' -and
            $global:OSDCoreDevice.OSDProduct -eq 'Surface_Product'
        }
        $global:OSDCloudDeploy.OSArchitecture | Should -Be 'arm64'
    }

    It 'retains the original OEM validation behavior when no safe ModelDrivers match' {
        Mock Get-OSDCoreModelDriversCacheObject {}
        Initialize-DeployOSDCloud
        $global:OSDCloudDeploy.DriverPackName | Should -Be 'OEM pack'
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -BeNullOrEmpty
        Should -Invoke Test-OSDCoreDriverPackCloudObject -Times 1 -Exactly
        Should -Invoke Get-OSDCoreDriverPackCacheObject -Times 1 -Exactly
    }
}
