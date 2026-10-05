BeforeAll {
    . "$PSScriptRoot\Get-OSDCoreModelDriversCacheObject.ps1"
    . "$PSScriptRoot\Resolve-OSDCoreModelDriversPath.ps1"
}

Describe 'Get-OSDCoreModelDriversCacheObject matching and ordering' {
    BeforeEach {
        Mock Resolve-OSDCoreModelDriversPath { $CacheObject.FullName }
        $content = @(
            [pscustomobject]@{ Type = 'ModelDrivers'; OSArchitecture = 'amd64'; ModelIdentity = 'HP_8CD1_Old model'; OSBuildVersion = '26200.99'; FullName = 'E:\old' },
            [pscustomobject]@{ Type = 'ModelDrivers'; OSArchitecture = 'amd64'; ModelIdentity = 'HP_8CD1_Renamed model'; OSBuildVersion = '26200.100'; FullName = 'E:\new' },
            [pscustomobject]@{ Type = 'ModelDrivers'; OSArchitecture = 'arm64'; ModelIdentity = 'HP_8CD1_ARM model'; OSBuildVersion = '28000.100'; FullName = 'E:\arm' },
            [pscustomobject]@{ Type = 'ModelDrivers'; OSArchitecture = 'amd64'; ModelIdentity = 'HP_8CD10_Wrong product'; OSBuildVersion = '28000.100'; FullName = 'E:\wrong-product' },
            [pscustomobject]@{ Type = 'ModelDrivers'; OSArchitecture = 'amd64'; ModelIdentity = 'Dell_8CD1_Wrong manufacturer'; OSBuildVersion = '28000.100'; FullName = 'E:\wrong-manufacturer' },
            [pscustomobject]@{ Type = 'Drivers'; OSArchitecture = 'amd64'; ModelIdentity = 'HP_8CD1_Wrong type'; OSBuildVersion = '28000.100'; FullName = 'E:\wrong-type' }
        )
    }

    It 'matches manufacturer/product only, ignoring different model text and sorting numerically' {
        $item = Get-OSDCoreModelDriversCacheObject -OSDManufacturer hp -OSDProduct 8cd1 -OSArchitecture amd64 -CacheContent $content
        $item.FullName | Should -Be 'E:\new'
        Should -Invoke Resolve-OSDCoreModelDriversPath -Times 1 -Exactly
    }

    It 'selects only the matching architecture' {
        $item = Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD1 -OSArchitecture arm64 -CacheContent $content
        $item.FullName | Should -Be 'E:\arm'
    }

    It 'never selects WinPEDrivers for deployment even with a higher matching build' {
        $winPEContent = @([pscustomobject]@{
            Type = 'WinPEDrivers'
            OSArchitecture = 'amd64'
            ModelIdentity = 'HP_8CD1_WinPE model'
            OSBuildVersion = '28000.100'
            FullName = 'E:\OSDCloud\winpedrivers-amd64\HP_8CD1_WinPE model_28000.100'
        })
        $item = Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD1 -OSArchitecture amd64 -CacheContent ($content + $winPEContent)
        $item.FullName | Should -Be 'E:\new'
        Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD1 -OSArchitecture amd64 -CacheContent $winPEContent | Should -BeNullOrEmpty
        Should -Invoke Resolve-OSDCoreModelDriversPath -Times 0 -Exactly -ParameterFilter { $CacheObject.Type -eq 'WinPEDrivers' }
    }

    It 'selects a higher major build regardless of the deployed OS build' {
        $content += [pscustomobject]@{ Type = 'ModelDrivers'; OSArchitecture = 'amd64'; ModelIdentity = 'HP_8CD1_Another description'; OSBuildVersion = '28000.1'; FullName = 'E:\new-major' }
        $item = Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD1 -OSArchitecture amd64 -CacheContent $content
        $item.FullName | Should -Be 'E:\new-major'
    }

    It 'uses deterministic path order for equal versions' {
        $content += [pscustomobject]@{ Type = 'ModelDrivers'; OSArchitecture = 'amd64'; ModelIdentity = 'HP_8CD1_Alternate description'; OSBuildVersion = '26200.100'; FullName = 'D:\duplicate' }
        $item = Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD1 -OSArchitecture amd64 -CacheContent $content
        $item.FullName | Should -Be 'D:\duplicate'
    }

    It 'falls back to the next safe folder when the newest source is excluded' {
        Mock Resolve-OSDCoreModelDriversPath {} -ParameterFilter { $CacheObject.FullName -eq 'E:\new' }
        $item = Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD1 -OSArchitecture amd64 -CacheContent $content
        $item.FullName | Should -Be 'E:\old'
    }

    It 'matches product underscores and regex characters literally' {
        $content = @([pscustomobject]@{ Type = 'ModelDrivers'; OSArchitecture = 'arm64'; ModelIdentity = 'Microsoft_Surface_Product[1]_Any model'; OSBuildVersion = '28000.100'; FullName = 'E:\surface' })
        $item = Get-OSDCoreModelDriversCacheObject -OSDManufacturer Microsoft -OSDProduct 'Surface_Product[1]' -OSArchitecture arm64 -CacheContent $content
        $item.FullName | Should -Be 'E:\surface'
    }

    It 'does not match a product prefix without the underscore boundary' {
        Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD -OSArchitecture amd64 -CacheContent $content | Should -BeNullOrEmpty
        Should -Invoke Resolve-OSDCoreModelDriversPath -Times 0 -Exactly
    }

    It 'warns and excludes an invalid numeric version' {
        $content[1].OSBuildVersion = 'invalid'
        $item = Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD1 -OSArchitecture amd64 -CacheContent $content -WarningVariable messages -WarningAction SilentlyContinue
        $item.FullName | Should -Be 'E:\old'
        $messages.Count | Should -Be 1
    }

    It 'returns no source for missing device identity or an empty inventory' {
        Get-OSDCoreModelDriversCacheObject -OSDManufacturer '' -OSDProduct 8CD1 -OSArchitecture amd64 -CacheContent $content | Should -BeNullOrEmpty
        Get-OSDCoreModelDriversCacheObject -OSDManufacturer HP -OSDProduct 8CD1 -OSArchitecture amd64 -CacheContent @() | Should -BeNullOrEmpty
        Should -Invoke Resolve-OSDCoreModelDriversPath -Times 0 -Exactly
    }
}
