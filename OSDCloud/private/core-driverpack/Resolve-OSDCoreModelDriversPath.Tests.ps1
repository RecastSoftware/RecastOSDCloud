BeforeAll {
    . "$PSScriptRoot\Resolve-OSDCoreModelDriversPath.ps1"
    function Get-DeviceLocalDisk { [CmdletBinding()] param () }
}

Describe 'Resolve-OSDCoreModelDriversPath source safety' {
    BeforeEach {
        $entry = [pscustomobject]@{
            Type = 'ModelDrivers'
            Name = 'HP_8CD1_Model [description]_26200.100'
            OSArchitecture = 'amd64'
            FullName = 'E:\OSDCloud\modeldrivers-amd64\HP_8CD1_Model [description]_26200.100'
            VolumeUniqueId = 'usb-volume'
        }
        Mock Get-Volume { [pscustomobject]@{ DriveLetter = 'F'; UniqueId = 'usb-volume' } }
        Mock Get-Partition { [pscustomobject]@{ DiskNumber = 3 } }
        Mock Get-DeviceLocalDisk { [pscustomobject]@{ Number = 0; IsBoot = $false } }
        Mock Test-Path { $true }
        Mock Get-ChildItem { [pscustomobject]@{ Name = 'driver.inf' } }
    }

    It 'uses the volume identity after drive letters change' {
        Resolve-OSDCoreModelDriversPath -CacheObject $entry |
            Should -Be 'F:\OSDCloud\modeldrivers-amd64\HP_8CD1_Model [description]_26200.100'
        Should -Invoke Get-Volume -Times 1 -Exactly -ParameterFilter { $UniqueId -eq 'usb-volume' }
        Should -Invoke Test-Path -Times 1 -Exactly -ParameterFilter { $LiteralPath -like 'F:\OSDCloud\*' -and $PathType -eq 'Container' }
    }

    It 'excludes a source on any disk that will be erased, including a non-target disk' {
        Mock Get-DeviceLocalDisk {
            [pscustomobject]@{ Number = 0; IsBoot = $false }
            [pscustomobject]@{ Number = 3; IsBoot = $false }
        }
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningVariable messages -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$messages" | Should -Match 'disk 3.*will be cleared'
        Should -Invoke Get-ChildItem -Times 0 -Exactly
    }

    It 'does not exclude a boot disk that the clear helper will skip' {
        Mock Get-DeviceLocalDisk { [pscustomobject]@{ Number = 3; IsBoot = $true } }
        Resolve-OSDCoreModelDriversPath -CacheObject $entry | Should -Not -BeNullOrEmpty
    }

    It 'warns and excludes unknown volume metadata' {
        $entry.VolumeUniqueId = ''
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningVariable messages -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$messages" | Should -Match 'metadata is invalid'
        Should -Invoke Get-Volume -Times 0 -Exactly
    }

    It 'warns and excludes an absent volume' {
        Mock Get-Volume {}
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningVariable messages -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$messages" | Should -Match 'missing or ambiguous'
    }

    It 'warns and excludes an ambiguous volume' {
        Mock Get-Volume {
            [pscustomobject]@{ DriveLetter = 'F' }
            [pscustomobject]@{ DriveLetter = 'G' }
        }
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningVariable messages -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$messages" | Should -Match 'missing or ambiguous'
    }

    It 'warns and excludes missing partition information' {
        Mock Get-Partition {}
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningVariable messages -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$messages" | Should -Match 'Cannot determine.*source disk'
    }

    It 'reports failed disk enumeration instead of assuming safety' {
        Mock Get-DeviceLocalDisk { throw 'Storage unavailable' }
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningVariable messages -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$messages" | Should -Match 'Storage unavailable'
    }

    It 'excludes sources when local disk metadata is incomplete' {
        Mock Get-DeviceLocalDisk { [pscustomobject]@{ IsBoot = $false } }
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningVariable messages -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$messages" | Should -Match 'Cannot determine which local disks will be cleared'
        Should -Invoke Get-ChildItem -Times 0 -Exactly
    }

    It 'warns if the selected folder disappears' {
        Mock Test-Path { $false }
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningVariable messages -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$messages" | Should -Match 'source is missing'
    }

    It 'warns if the selected folder no longer contains INF files' {
        Mock Get-ChildItem {}
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningVariable messages -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        "$messages" | Should -Match 'contains no INF files'
    }

    It 'does not use the old drive letter when the selected volume is unmounted' {
        Mock Get-Volume { [pscustomobject]@{ DriveLetter = $null } }
        Resolve-OSDCoreModelDriversPath -CacheObject $entry -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        Should -Invoke Test-Path -Times 0 -Exactly
    }
}
