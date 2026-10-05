BeforeAll {
    . "$PSScriptRoot\Get-OSDCoreCacheContent.ps1"
    $originalTemp = $env:TEMP
    $env:TEMP = Join-Path $TestDrive 'temp'
    New-Item -Path $env:TEMP -ItemType Directory | Out-Null
    $fixtureRoot = Join-Path $TestDrive 'drives'
    $fixtures = @(
        'D\OSDCloud\modeldrivers-amd64\HP_8CD1_HP ZBook Firefly 16 inch G11 Mobile Workstation PC_26200.9457\nested\driver.inf',
        'D\OSDCloud\modeldrivers-amd64\HP_895E_HP Z2 Mini G9 Workstation Desktop PC_26200.9457\driver.inf',
        'D\OSDCloud\modeldrivers-amd64\Microsoft_Surface_Product_Model_with_underscores_28000.100\driver.inf',
        'D\OSDCloud\modeldrivers-amd64\HP_8CD1_InvalidBuild_not-a-build\driver.inf',
        'D\OSDCloud\modeldrivers-amd64\HP_8CD1_Overflow_99999999999999.1\driver.inf',
        'D\OSDCloud\modeldrivers-amd64\HP_8CD1_Empty_26200.9000\readme.txt',
        'E\OSDCloud\modeldrivers-arm64\HP_8CD1_Different model description_28000.100\driver.inf',
        'D\OSDCloud\OS\nested\windows.esd',
        'D\OSDCloud\ISO\windows.iso',
        'D\OSDCloud\DriverPacks\pack.cab',
        'D\OSDCloud\DriverPacks\pack.exe',
        'D\OSDCloud\DriverPacks\pack.msi',
        'D\OSDCloud\DriverPacks\pack.zip',
        'D\OSDCloud\DriverPacks\ignore.txt',
        'D\OSDCloud\Drivers\Custom\nested\driver.inf',
        'D\OSDCloud\Profiles\BranchOffice\profile.json',
        'D\OSDCloud\WIM\windows.wim'
    )
    $fixtures += @($fixtures | Where-Object { $_ -like '*\modeldrivers-*' } |
        ForEach-Object { $_ -replace '\\modeldrivers-', '\winpedrivers-' })
    foreach ($fixture in $fixtures) {
        $path = Join-Path $fixtureRoot $fixture
        New-Item -Path (Split-Path $path -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath $path -Value 'fixture' -Encoding Ascii
    }
    $sizedFolder = Join-Path $fixtureRoot 'D\OSDCloud\modeldrivers-amd64\HP_8CD1_HP ZBook Firefly 16 inch G11 Mobile Workstation PC_26200.9457'
    [System.IO.File]::WriteAllBytes((Join-Path $sizedFolder 'driver.sys'), [byte[]]::new(1MB))
    [System.IO.File]::WriteAllBytes((Join-Path ($sizedFolder -replace '\\modeldrivers-', '\winpedrivers-') 'driver.sys'), [byte[]]::new(1MB))
}

AfterAll {
    $env:TEMP = $originalTemp
}

Describe 'Get-OSDCoreCacheContent <DriverType>' -ForEach @(
    @{ DriverType = 'ModelDrivers' }
    @{ DriverType = 'WinPEDrivers' }
) {
    BeforeEach {
        Mock Get-PSDrive {
            [pscustomobject]@{ Root = 'D:\' }
            [pscustomobject]@{ Root = 'E:\' }
        }
        Mock Join-Path {
            if ($Path -match '^[DE]:\\$') {
                return [System.IO.Path]::Combine($fixtureRoot, $Path.Substring(0, 1), $ChildPath)
            }
            [System.IO.Path]::Combine($Path, $ChildPath)
        }
        Mock Get-Volume {
            [pscustomobject]@{ FileSystemLabel = "Cache-$DriveLetter"; UniqueId = "volume-$DriveLetter" }
        }
        Mock Get-Disk {}
        Mock Get-Partition {}
    }

    It 'discovers both architectures, immediate folders, and nested INF files' {
        $items = @(Get-OSDCoreCacheContent -Type $DriverType -WarningAction SilentlyContinue)
        $items.Count | Should -Be 4
        @($items | Where-Object OSArchitecture -eq amd64).Count | Should -Be 3
        @($items | Where-Object OSArchitecture -eq arm64).Count | Should -Be 1
        @($items | Where-Object Name -like '*Empty*').Count | Should -Be 0
        @($items | Where-Object Name -eq nested).Count | Should -Be 0
        $items.Name | Should -Contain 'HP_895E_HP Z2 Mini G9 Workstation Desktop PC_26200.9457'
        @($items | Where-Object Type -ne $DriverType).Count | Should -Be 0
    }

    It 'preserves the folder identity, numeric build string, size and common metadata' {
        $item = Get-OSDCoreCacheContent -Type $DriverType -Include D -WarningAction SilentlyContinue |
            Where-Object Name -like 'HP_8CD1_HP ZBook*'
        $item.ModelIdentity | Should -Be 'HP_8CD1_HP ZBook Firefly 16 inch G11 Mobile Workstation PC'
        $item.OSBuildVersion | Should -Be '26200.9457'
        $item.SizeMB | Should -Be 1
        $item.Type | Should -Be $DriverType
        $item.DriveRoot | Should -Be 'D:\'
        $item.VolumeLabel | Should -Be 'Cache-D'
        $item.VolumeUniqueId | Should -Be 'volume-D'
        $item.USB | Should -BeFalse
        Test-Path -LiteralPath $item.FullName | Should -BeTrue
        $item.PSObject.Properties.Name | Should -Contain 'FullName'
    }

    It 'retains underscores in product and descriptive model text' {
        $item = Get-OSDCoreCacheContent -Type $DriverType -WarningAction SilentlyContinue |
            Where-Object Name -like 'Microsoft*'
        $item.ModelIdentity | Should -Be 'Microsoft_Surface_Product_Model_with_underscores'
    }

    It 'warns about malformed names and overflowing versions instead of returning them' {
        $items = @(Get-OSDCoreCacheContent -Type $DriverType -WarningVariable messages -WarningAction SilentlyContinue)
        $messages.Count | Should -Be 2
        $messages[0].ToString() | Should -Match "Invalid $DriverType folder name:"
        @($items | Where-Object Name -match 'InvalidBuild|Overflow').Count | Should -Be 0
    }

    It 'includes ModelDrivers, WinPEDrivers and all existing types by default' {
        $items = @(Get-OSDCoreCacheContent -WarningAction SilentlyContinue)
        $items.Count | Should -Be 17
        @($items.Type | Sort-Object -Unique).Count | Should -Be 8
        @($items | Where-Object Type -eq $DriverType).Count | Should -Be 4
    }

    It 'includes the same inventory for wildcard selection' {
        $all = @(Get-OSDCoreCacheContent -WarningAction SilentlyContinue)
        $wildcard = @(Get-OSDCoreCacheContent -Type '*' -WarningAction SilentlyContinue)
        ($wildcard.FullName -join '|') | Should -Be ($all.FullName -join '|')
    }

    It 'supports mixed selectors and de-duplicates repeated types' {
        $items = @(Get-OSDCoreCacheContent -Type $DriverType,ESD,$DriverType -WarningAction SilentlyContinue)
        $items.Count | Should -Be 5
        @($items | Where-Object Type -eq ESD).Count | Should -Be 1
    }

    It 'continues to select existing content types independently' {
        $items = @(Get-OSDCoreCacheContent -Type DriverPacks,Drivers)
        $items.Count | Should -Be 5
        $items.Type | Should -Not -Contain 'ModelDrivers'
        $items.Type | Should -Not -Contain 'WinPEDrivers'
    }

    It 'honors include and exclude filters, with exclude taking precedence' {
        $items = @(Get-OSDCoreCacheContent -Type $DriverType -Include D,E -Exclude D)
        $items.Count | Should -Be 1
        $items[0].DriveRoot | Should -Be 'E:\'
    }

    It 'exports driver metadata in the cache XML' {
        $items = @(Get-OSDCoreCacheContent -Type $DriverType -WarningAction SilentlyContinue)
        $exported = @(Import-Clixml -LiteralPath (Join-Path $env:TEMP 'OSDCoreCache.xml'))
        $exported.Count | Should -Be $items.Count
        ($exported.ModelIdentity -join '|') | Should -Be ($items.ModelIdentity -join '|')
        ($exported.OSArchitecture -join '|') | Should -Be ($items.OSArchitecture -join '|')
        ($exported.OSBuildVersion -join '|') | Should -Be ($items.OSBuildVersion -join '|')
        ($exported.Type -join '|') | Should -Be ($items.Type -join '|')
    }

    It 'reports driver directory enumeration errors' {
        Mock Get-ChildItem { throw 'Cannot enumerate source' } -ParameterFilter { $LiteralPath -like "*$($DriverType.ToLowerInvariant())-amd64" }
        { Get-OSDCoreCacheContent -Type $DriverType } | Should -Throw '*Cannot enumerate source*'
    }

    It 'returns a canonical type for case-insensitive selectors' {
        $items = @(Get-OSDCoreCacheContent -Type $DriverType.ToLowerInvariant() -WarningAction SilentlyContinue)
        $items.Count | Should -Be 4
        @($items | Where-Object { $_.Type -cne $DriverType }).Count | Should -Be 0
    }

    It 'discovers both driver types together without conflating identical folder names' {
        $items = @(Get-OSDCoreCacheContent -Type ModelDrivers,WinPEDrivers -WarningAction SilentlyContinue)
        $items.Count | Should -Be 8
        @($items | Where-Object Type -eq ModelDrivers).Count | Should -Be 4
        @($items | Where-Object Type -eq WinPEDrivers).Count | Should -Be 4
    }
}
