BeforeAll {
    $tokens = $null
    $parseErrors = $null
    $initializerAst = [System.Management.Automation.Language.Parser]::ParseFile(
        "$PSScriptRoot\Initialize-OSDCoreDevice.ps1", [ref]$tokens, [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw ($parseErrors -join "`n")
    }
    $snapshotAssignment = $initializerAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$global:OSDCoreDevice' -and
        $node.Right.Extent.Text -like '[[]ordered]*'
    }, $true)
    $snapshotMap = $snapshotAssignment.Find({
        param($node)
        $node -is [System.Management.Automation.Language.HashtableAst]
    }, $true)
    # Evaluate only the actual snapshot mappings, not the initializer's hardware
    # queries, clock synchronization, disk discovery, or diagnostic writes.
    $inventoryKeys = @('DiskDrives', 'NetworkAdapters', 'Processors', 'PhysicalMemory', 'NativeOSArchitecture', 'TotalPhysicalMemory')
    $inventoryMappings = @($snapshotMap.KeyValuePairs | Where-Object {
        $_.Item1.Value -in $inventoryKeys
    })
    $mappingScript = [scriptblock]::Create(
        "[ordered]@{`n" + (($inventoryMappings | ForEach-Object {
            $_.Item1.Extent.Text + ' = ' + $_.Item2.Extent.Text
        }) -join "`n") + "`n}"
    )
    $initializerFunction = $initializerAst.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    $statements = $initializerFunction.Body.EndBlock.Statements
    for ($i = 0; $i -lt $statements.Count; $i++) {
        if ($statements[$i] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $statements[$i].Left.Extent.Text -eq '$classWin32PhysicalMemory') {
            $physicalMemoryCollection = [scriptblock]::Create(
                ($statements[$i..($i + 2)] | ForEach-Object { $_.Extent.Text }) -join "`n"
            )
            break
        }
    }
}

Describe 'Initialize-OSDCoreDevice physical memory collection' {
    BeforeEach {
        $LogsPath = $TestDrive
        Mock Out-File {}
    }

    It 'queries modules once and exports the complete diagnostic inventory' {
        Mock Get-CimInstance {
            [pscustomobject]@{ DeviceLocator = 'DIMM1'; Speed = 5600; ConfiguredClockSpeed = 4800 }
            [pscustomobject]@{ DeviceLocator = 'DIMM2'; Speed = 5600; ConfiguredClockSpeed = 4800 }
        }
        . $physicalMemoryCollection
        $classWin32PhysicalMemory.Count | Should -Be 2
        $classWin32PhysicalMemory[0].DeviceLocator | Should -Be 'DIMM1'
        Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'Win32_PhysicalMemory' -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Out-File -Times 2 -Exactly -ParameterFilter {
            $FilePath -eq (Join-Path $LogsPath 'Win32_PhysicalMemory.txt')
        }
    }

    It 'warns and leaves an empty inventory if module collection fails' {
        Mock Get-CimInstance { throw 'Memory provider unavailable.' }
        Mock Write-Warning {}
        . $physicalMemoryCollection
        $classWin32PhysicalMemory.Count | Should -Be 0
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter {
            $Message -like '*Unable to query Win32_PhysicalMemory:*Memory provider unavailable*'
        }
    }
}

Describe 'Initialize-OSDCoreDevice display inventory mappings' {
    BeforeEach {
        $classWin32NetworkAdapterConfiguration = @()
        $classWin32PhysicalMemory = @()
    }

    It 'matches IPv4 addresses by adapter index and excludes IPv6 and unassigned addresses' {
        $classWin32NetworkAdapter = @(
            [pscustomobject]@{ Name = 'Ethernet'; Index = 1 }
            [pscustomobject]@{ Name = 'Wi-Fi'; Index = 2 }
            [pscustomobject]@{ Name = 'Disconnected'; Index = 3 }
            [pscustomobject]@{ Name = 'IPv6 only'; Index = 4 }
        )
        $classWin32NetworkAdapterConfiguration = @(
            [pscustomobject]@{ Index = 2; IPAddress = @('192.168.1.20') }
            [pscustomobject]@{ Index = 1; IPAddress = @('fe80::1', '10.0.0.10', '10.0.0.11') }
            [pscustomobject]@{ Index = 4; IPAddress = @('fe80::4') }
        )
        $snapshot = & $mappingScript
        $snapshot.NetworkAdapters[0].IPv4Addresses | Should -Be @('10.0.0.10', '10.0.0.11')
        $snapshot.NetworkAdapters[1].IPv4Addresses | Should -Be @('192.168.1.20')
        $snapshot.NetworkAdapters[2].IPv4Addresses.Count | Should -Be 0
        $snapshot.NetworkAdapters[3].IPv4Addresses.Count | Should -Be 0
        $jsonSnapshot = $snapshot | ConvertTo-Json -Depth 10 -WarningVariable serializationWarnings | ConvertFrom-Json
        @($serializationWarnings).Count | Should -Be 0
        $jsonSnapshot.NetworkAdapters[0].IPv4Addresses | Should -Be @('10.0.0.10', '10.0.0.11')
    }

    It 'exposes all six fields from the existing collection variables' {
        $inventoryMappings.Count | Should -Be 6
        $classWin32DiskDrive = [pscustomobject]@{ Model = 'Disk'; ExtraDiskField = 'retained' }
        $classWin32NetworkAdapter = [pscustomobject]@{ Name = 'Ethernet'; ExtraNetworkField = 'retained' }
        $classWin32Processor = [pscustomobject]@{ Name = 'CPU'; ExtraProcessorField = 'retained' }
        $classWin32PhysicalMemory = [pscustomobject]@{ ConfiguredClockSpeed = 4800; Speed = 5600; Capacity = 8GB }
        $classWin32OperatingSystem = [pscustomobject]@{ OSArchitecture = '64-bit' }
        $classWin32ComputerSystem = [pscustomobject]@{ TotalPhysicalMemory = 6.5GB }
        $OSArchitecture = 'override'
        $snapshot = & $mappingScript
        $snapshot.NativeOSArchitecture | Should -Be '64-bit'
        $snapshot.TotalPhysicalMemory | Should -Be 6.5GB
        $snapshot.DiskDrives[0].Model | Should -Be 'Disk'
        $snapshot.NetworkAdapters[0].Name | Should -Be 'Ethernet'
        $snapshot.Processors[0].Name | Should -Be 'CPU'

        $jsonSnapshot = $snapshot | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $xmlPath = Join-Path $TestDrive 'inventory.xml'
        $snapshot | Export-Clixml -Path $xmlPath
        $xmlSnapshot = Import-Clixml -Path $xmlPath
        foreach ($roundTrip in @($jsonSnapshot, $xmlSnapshot)) {
            $roundTrip.DiskDrives[0].ExtraDiskField | Should -Be 'retained'
            $roundTrip.NetworkAdapters[0].ExtraNetworkField | Should -Be 'retained'
            $roundTrip.Processors[0].ExtraProcessorField | Should -Be 'retained'
            $roundTrip.PhysicalMemory[0].ConfiguredClockSpeed | Should -Be 4800
            $roundTrip.PhysicalMemory[0].Speed | Should -Be 5600
            $roundTrip.PhysicalMemory[0].Capacity | Should -Be 8GB
            $roundTrip.TotalPhysicalMemory | Should -Be 6.5GB
            $roundTrip.NativeOSArchitecture | Should -Be '64-bit'
        }
    }

    It 'excludes deep CIM metadata without truncating JSON or losing hardware properties' {
        $metadata = [pscustomobject]@{ ClassName = 'TestClass' }
        $metadata | Add-Member -NotePropertyName Parent -NotePropertyValue $metadata
        $classWin32DiskDrive = [pscustomobject]@{
            Model = 'Disk'
            DeviceID = 'disk0'
            Size = [uint64]1TB
            Capabilities = [uint16[]]@(3, 4)
            CimClass = $metadata
            CimInstanceProperties = $metadata
            CimSystemProperties = $metadata
        }
        $classWin32NetworkAdapter = $classWin32DiskDrive
        $classWin32Processor = $classWin32DiskDrive
        $classWin32PhysicalMemory = $classWin32DiskDrive
        $classWin32OperatingSystem = $null
        $classWin32ComputerSystem = $null
        $snapshot = & $mappingScript
        $json = $snapshot | ConvertTo-Json -Depth 10 -WarningVariable serializationWarnings
        @($serializationWarnings).Count | Should -Be 0
        $roundTrip = $json | ConvertFrom-Json
        foreach ($key in @('DiskDrives', 'NetworkAdapters', 'Processors', 'PhysicalMemory')) {
            $snapshot[$key][0].PSObject.Properties.Name | Should -Not -Contain 'CimClass'
            $snapshot[$key][0].PSObject.Properties.Name | Should -Not -Contain 'CimInstanceProperties'
            $snapshot[$key][0].PSObject.Properties.Name | Should -Not -Contain 'CimSystemProperties'
            $roundTrip.$key[0].Model | Should -Be 'Disk'
            $roundTrip.$key[0].Size | Should -Be 1TB
            $roundTrip.$key[0].Capabilities | Should -Be @(3, 4)
        }
        $classWin32DiskDrive.CimClass | Should -Not -BeNullOrEmpty
    }

    It 'normalizes <Count> collected objects to arrays without null placeholders' -ForEach @(
        @{ Count = 0 }
        @{ Count = 1 }
        @{ Count = 2 }
    ) {
        $objects = @(
            [pscustomobject]@{ Name = 'One' }
            [pscustomobject]@{ Name = 'Two' }
        )
        $classWin32DiskDrive = $objects | Select-Object -First $Count
        $classWin32NetworkAdapter = $objects | Select-Object -First $Count
        $classWin32Processor = $objects | Select-Object -First $Count
        $classWin32PhysicalMemory = $objects | Select-Object -First $Count
        $classWin32OperatingSystem = $null
        $classWin32ComputerSystem = $null
        $snapshot = & $mappingScript
        foreach ($key in @('DiskDrives', 'NetworkAdapters', 'Processors', 'PhysicalMemory')) {
            ($snapshot[$key] -is [array]) | Should -BeTrue
            $snapshot[$key].Count | Should -Be $Count
        }
        $snapshot.TotalPhysicalMemory | Should -BeNullOrEmpty
        $snapshot.NativeOSArchitecture | Should -BeNullOrEmpty
    }
}
