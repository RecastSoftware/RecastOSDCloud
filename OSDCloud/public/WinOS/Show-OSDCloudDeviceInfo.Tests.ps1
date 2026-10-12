BeforeAll {
    . "$PSScriptRoot\Show-OSDCloudDeviceInfo.ps1"
    . "$PSScriptRoot\Get-OSDCloudModuleVersion.ps1"
    . "$PSScriptRoot\..\..\private\core-device\Initialize-OSDCoreDevice.ps1"
    $originalDevice = $global:OSDCoreDevice
    $originalTitle = $host.UI.RawUI.WindowTitle
}

AfterAll {
    $global:OSDCoreDevice = $originalDevice
    $host.UI.RawUI.WindowTitle = $originalTitle
}

Describe 'Show-OSDCloudDeviceInfo snapshot display' {
    BeforeEach {
        $script:inventory = [ordered]@{
            OSVersion = '10.0.26100'
            NativeOSArchitecture = '64-bit'
            OSArchitecture = 'overridden'
            ComputerName = 'MININT-TEST'
            OSDManufacturer = 'Test Manufacturer'
            OSDProduct = 'Test Product'
            OSDModel = 'Test Model'
            BiosVersion = '1.2.3'
            BiosReleaseDate = '2026-10-01'
            TotalPhysicalMemory = 8GB
            TotalPhysicalMemoryGB = 8
            PhysicalMemory = @(
                [pscustomobject]@{ ConfiguredClockSpeed = 4800; Speed = 5600 }
                [pscustomobject]@{ ConfiguredClockSpeed = 4800; Speed = 5600 }
            )
            Processors = @(
                [pscustomobject]@{ Name = 'CPU One'; NumberOfLogicalProcessors = 8 }
                [pscustomobject]@{ Name = 'CPU Two'; NumberOfLogicalProcessors = 16 }
            )
            DiskDrives = @(
                [pscustomobject]@{ Model = 'Disk One'; DeviceID = '\\.\PHYSICALDRIVE0'; Size = [uint64]8000000000000 }
                [pscustomobject]@{ Model = 'Disk Two'; DeviceID = '\\.\PHYSICALDRIVE1'; Size = [uint64]512110190592 }
            )
            NetworkAdapters = @(
                [pscustomobject]@{ Name = 'Ethernet'; GUID = 'adapter-guid'; MACAddress = 'AA-BB-CC-DD-EE-FF' }
                [pscustomobject]@{ Name = 'Hidden'; GUID = $null; MACAddress = $null }
            )
            SerialNumber = 'private-serial'
            UUID = 'private-uuid'
        }
        $global:OSDCoreDevice = $null
        $script:lines = [System.Collections.Generic.List[string]]::new()
        $script:warnings = [System.Collections.Generic.List[string]]::new()
        Mock Initialize-OSDCoreDevice { $global:OSDCoreDevice = $script:inventory }
        Mock Get-OSDCloudModuleVersion { [version]'26.10.10.0' }
        Mock Write-Host { $script:lines.Add([string]$Object) }
        Mock Write-Warning { $script:warnings.Add($Message) }
        Mock Get-CimInstance { throw 'Display must not query hardware.' }
        Mock New-Item { throw 'Display must not create log directories.' }
        Mock Out-File { throw 'Display must not export diagnostics.' }
    }

    It 'renders the complete snapshot in order without querying or exporting hardware' {
        $output = @(Show-OSDCloudDeviceInfo)
        $output.Count | Should -Be 0
        $script:lines[0] | Should -Match 'OSDCloud PowerShell Module 26.10.10.0$'
        ($script:lines | Select-Object -Skip 1) | Should -Be @(
            'Host: MININT-TEST | 10.0.26100 64-bit'
            'Device: Test Manufacturer | Test Product | Test Model'
            'BIOS: 1.2.3 | 2026-10-01'
            'Processor: CPU One | 8 Logical'
            'Processor: CPU Two | 16 Logical'
            'Memory: 8 GB Total | 2 DIMMs at 4800 MHz'
            'Disk:  \\.\PHYSICALDRIVE0 | 8000GB Disk One'
            'Disk:  \\.\PHYSICALDRIVE1 | 512GB Disk Two'
            'NetAdapter AA-BB-CC-DD-EE-FF: Ethernet'
        )
        ($script:lines -join "`n") | Should -Not -Match 'private-serial|private-uuid|overridden|Hidden'
        $script:warnings.Count | Should -Be 0
        Should -Invoke Initialize-OSDCoreDevice -Times 1 -Exactly
        Should -Invoke Get-CimInstance -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke Out-File -Times 0 -Exactly
    }

    It 'preserves display memory rounding and warnings for <MemoryGB> GB' -ForEach @(
        @{ MemoryGB = 5; DisplayGB = 5; Warn = $true }
        @{ MemoryGB = 5.49; DisplayGB = 5; Warn = $true }
        @{ MemoryGB = 5.5; DisplayGB = 6; Warn = $false }
        @{ MemoryGB = 6; DisplayGB = 6; Warn = $false }
        @{ MemoryGB = 6.5; DisplayGB = 6; Warn = $false }
        @{ MemoryGB = 7; DisplayGB = 7; Warn = $false }
    ) {
        $script:inventory.TotalPhysicalMemory = $MemoryGB * 1GB
        $script:inventory.TotalPhysicalMemoryGB = 99
        Show-OSDCloudDeviceInfo
        $script:lines | Should -Contain "Memory: $DisplayGB GB Total | 2 DIMMs at 4800 MHz"
        @($script:warnings | Where-Object { $_ -like '*requires at least 6 GB*' }).Count |
            Should -Be ([int]$Warn)
    }

    It 'appends one or multiple IPv4 addresses after the matching MAC address' {
        $script:inventory.NetworkAdapters = @(
            [pscustomobject]@{ Name = 'Ethernet'; GUID = 'wired'; MACAddress = 'AA-BB'; IPv4Addresses = @('10.0.0.10', '10.0.0.11') }
            [pscustomobject]@{ Name = 'Wi-Fi'; GUID = 'wireless'; MACAddress = 'CC-DD'; IPv4Addresses = @('192.168.1.20') }
            [pscustomobject]@{ Name = 'Disconnected'; GUID = 'offline'; MACAddress = 'EE-FF'; IPv4Addresses = @() }
        )
        Show-OSDCloudDeviceInfo
        $script:lines | Should -Contain 'NetAdapter AA-BB: Ethernet [10.0.0.10, 10.0.0.11]'
        $script:lines | Should -Contain 'NetAdapter CC-DD: Wi-Fi [192.168.1.20]'
        $script:lines | Should -Contain 'NetAdapter EE-FF: Disconnected'
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }

    It 'warns instead of reporting zero when physical memory is missing' {
        $script:inventory.TotalPhysicalMemory = $null
        Show-OSDCloudDeviceInfo
        @($script:lines | Where-Object { $_ -like 'Memory:*' }).Count | Should -Be 0
        ($script:warnings -join "`n") | Should -Match 'Physical memory information is unavailable'
    }

    It 'falls back to reported speed and lists distinct module speeds' {
        $script:inventory.PhysicalMemory = @(
            [pscustomobject]@{ ConfiguredClockSpeed = 0; Speed = 3200 }
            [pscustomobject]@{ ConfiguredClockSpeed = 4800; Speed = 5600 }
        )
        Show-OSDCloudDeviceInfo
        $script:lines | Should -Contain 'Memory: 8 GB Total | 2 DIMMs at 3200, 4800 MHz'
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }

    It 'reports unavailable speed rather than zero while retaining the module count' {
        $script:inventory.PhysicalMemory = @([pscustomobject]@{ ConfiguredClockSpeed = 0; Speed = $null })
        Show-OSDCloudDeviceInfo
        $script:lines | Should -Contain 'Memory: 8 GB Total | 1 DIMM at Speed unavailable'
    }

    It 'retains total memory when module inventory is unavailable' {
        $script:inventory.PhysicalMemory = @()
        Show-OSDCloudDeviceInfo
        $script:lines | Should -Contain 'Memory: 8 GB Total | DIMM count unavailable at Speed unavailable'
    }

    It 'handles <Count> element inventory collections' -ForEach @(
        @{ Count = 0 }
        @{ Count = 1 }
    ) {
        $script:inventory.Processors = @($script:inventory.Processors | Select-Object -First $Count)
        $script:inventory.DiskDrives = @($script:inventory.DiskDrives | Select-Object -First $Count)
        $script:inventory.NetworkAdapters = @($script:inventory.NetworkAdapters | Select-Object -First $Count)
        Show-OSDCloudDeviceInfo
        @($script:lines | Where-Object { $_ -like 'Processor:*' }).Count | Should -Be $Count
        @($script:lines | Where-Object { $_ -like 'Disk:*' }).Count | Should -Be $Count
        @($script:lines | Where-Object { $_ -like 'NetAdapter *' }).Count | Should -Be $Count
    }

    It 'warns on failed initialization without displaying stale global inventory' {
        $global:OSDCoreDevice = $script:inventory
        Mock Initialize-OSDCoreDevice { throw 'Inventory collection failed.' }
        Show-OSDCloudDeviceInfo
        $script:lines | Should -Contain 'Host: Unavailable | Unavailable Unavailable'
        @($script:lines | Where-Object { $_ -match '^(Device|Processor|Disk):|^NetAdapter ' }).Count |
            Should -Be 0
        ($script:warnings -join "`n") | Should -Match 'Unable to initialize.*Inventory collection failed'
        Should -Invoke Get-CimInstance -Times 0 -Exactly
        Should -Invoke Out-File -Times 0 -Exactly
    }

    It 'warns when initialization does not publish an inventory' {
        Mock Initialize-OSDCoreDevice {}
        Show-OSDCloudDeviceInfo
        $script:lines | Should -Contain 'Host: Unavailable | Unavailable Unavailable'
        ($script:warnings -join "`n") | Should -Match 'did not produce a device inventory'
    }

    It 'still displays inventory when module version discovery fails' {
        Mock Get-OSDCloudModuleVersion { throw 'Version unavailable.' }
        Show-OSDCloudDeviceInfo
        $script:lines[0] | Should -Match 'OSDCloud PowerShell Module Unavailable$'
        $script:lines | Should -Contain 'Disk:  \\.\PHYSICALDRIVE0 | 8000GB Disk One'
        ($script:warnings -join "`n") | Should -Match 'Unable to retrieve.*Version unavailable'
    }

    It 'reports unavailable disk size without inventing a zero capacity' {
        $script:inventory.DiskDrives[0].Size = $null
        Show-OSDCloudDeviceInfo
        $script:lines | Should -Contain 'Disk:  \\.\PHYSICALDRIVE0 | Size unavailable Disk One'
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }
}
