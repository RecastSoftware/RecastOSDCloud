BeforeAll {
    . "$PSScriptRoot\Initialize-OSDCloudResults.ps1"
    . "$PSScriptRoot\Update-OSDCloudResults.ps1"
    . "$PSScriptRoot\Export-OSDCloudResults.ps1"
    . "$PSScriptRoot\Send-OSDCloudResults.ps1"
    . "$PSScriptRoot\Set-OSDCloudAcquisitionResult.ps1"
    $stateNames = @('OSDCloudResults', 'OSDCloudDeploy', 'OSDCoreDevice', 'OSDCloudWorkflowInvoke')
    $originalState = @{}
    foreach ($name in $stateNames) {
        $originalState[$name] = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
    }
    $originalTemp = $env:TEMP
}

AfterAll {
    $env:TEMP = $originalTemp
    foreach ($name in $stateNames) {
        if ($originalState[$name]) { Set-Variable -Name $name -Value $originalState[$name].Value -Scope Global }
        else { Remove-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue }
    }
}

Describe 'Deployment results helpers' {
    BeforeEach {
        Mock Get-CimInstance { @() }
        $env:TEMP = Join-Path $TestDrive 'current'
        $targetRoot = Join-Path $TestDrive 'target'
        $global:OSDCoreDevice = [pscustomobject]@{
            OSDManufacturer = 'Test OEM'; OSDModel = 'Model'; OSDProduct = 'Product'
            ProcessorArchitecture = 'arm64'; TotalPhysicalMemoryGB = 16
            EndpointSHA = 'hashed-device'; UUID = 'raw-private-uuid'
            SerialNumber = 'private-serial'; idRegisteredLicense = 'private-license'
        }
        $global:OSDCloudDeploy = [pscustomobject]@{
            WorkflowTaskName = 'OSDCloud'; OSEditionId = 'Professional'; DriverPackName = 'Test pack'
            DriverPackCloudObject = [pscustomobject]@{ FileName = 'drivers.cab' }
            OperatingSystemCloudObject = [pscustomobject]@{
                OSName = 'Windows 11'; OSVersion = '26H2'; OSBuild = '26300'
                OSBuildVersion = '26300.9711'; OSActivation = 'Retail'; OSLanguageCode = 'en-us'
                FileName = 'install.esd'; FilePath = 'https://private.invalid/image.esd'
            }
        }
        $global:OSDCloudWorkflowInvoke = @{ ParamsExpandWindowsImage = @{ ApplyPath = $targetRoot } }
        $global:OSDCloudWorkflowInvoke.CompletedTransfers = @{
            stepOSDownload = $true
            stepDriverPackDownload = $true
        }
        Initialize-OSDCloudResults -ModuleVersion '26.10.15.1' -WorkflowName default -LaunchMethod CLI
        Update-OSDCloudResults
        Mock Invoke-RestMethod {}
    }

    It 'creates a reduced fresh schema with nullable timing and no raw identifiers' {
        $id = $global:OSDCloudResults.DeploymentId
        $global:OSDCloudResults.SchemaVersion | Should -Be 1
        $global:OSDCloudResults.Status | Should -Be 'NotStarted'
        $global:OSDCloudResults.IsComplete | Should -BeFalse
        $global:OSDCloudResults.StartTimeUtc | Should -BeNullOrEmpty
        $global:OSDCloudResults.totalDurationRAW | Should -BeNullOrEmpty
        $global:OSDCloudResults.ContentSource | Should -BeNullOrEmpty
        $propertyNames = @($global:OSDCloudResults.PSObject.Properties.Name)
        foreach ($name in 'sizeOS', 'sizeDriverPack', 'totalDurationRAW', 'totalDuration',
            'timeDownload', 'timeCache', 'timeCopy', 'timeExpand', 'timeOther', 'timeCloud',
            'totalSizeDownloadMB', 'totalSizeCopyMB', 'totalSizeMB', 'totalMBps',
            'OSFileName', 'DriverPackFileName') {
            $propertyNames -ccontains $name | Should -BeTrue
        }
        @($propertyNames | Where-Object { $_ -cmatch '^step' }).Count | Should -Be 9
        @($propertyNames | Where-Object { $_ -match '^Duration' }).Count | Should -Be 0
        foreach ($name in 'stepOSCopy', 'stepOSDownload', 'stepOSExpand',
            'stepDriverPackCopy', 'stepDriverPackDownload', 'stepDriverPackExpand', 'stepClearDisk',
            'totalDurationRAW', 'totalDuration') {
            $propertyNames | Should -Contain $name
        }
        $global:OSDCloudResults.ProcessorArchitecture | Should -Be 'arm64'
        $global:OSDCloudResults.TotalPhysicalMemoryGB | Should -Be 16
        $global:OSDCloudResults.OSBuildVersion | Should -Be '26300.9711'
        $global:OSDCloudResults.OSFileName | Should -BeExactly 'install.esd'
        $global:OSDCloudResults.DriverPackFileName | Should -BeExactly 'drivers.cab'
        $json = $global:OSDCloudResults | ConvertTo-Json
        $json | Should -Not -Match 'raw-private-uuid|private-serial|private-license|private.invalid'
        Initialize-OSDCloudResults -ModuleVersion '26.10.15.1' -WorkflowName default -LaunchMethod GUI
        $global:OSDCloudResults.DeploymentId | Should -Not -Be $id
        $global:OSDCloudResults.LaunchMethod | Should -Be 'GUI'
    }

    It 'hashes the UUID when needed and keeps the resolved identity for the run' {
        $global:OSDCoreDevice.EndpointSHA = $null
        $global:OSDCloudResults.DistinctId = $null
        Update-OSDCloudResults
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $expected = [BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes('raw-private-uuid'))).Replace('-', '')
        }
        finally { $sha256.Dispose() }
        $global:OSDCloudResults.DistinctId | Should -Be $expected
        $global:OSDCoreDevice.UUID = 'different'
        Update-OSDCloudResults
        $global:OSDCloudResults.DistinctId | Should -Be $expected
    }

    It 'calculates all rates from reported MB and seconds and clears unavailable rates' {
        foreach ($content in 'OS', 'DriverPack') {
            $global:OSDCloudResults."size${content}" = 5L
            foreach ($operation in 'Download', 'Cache', 'Copy', 'Expand') {
                $global:OSDCloudResults."step${content}${operation}" = 2L
            }
        }
        Update-OSDCloudResults
        foreach ($content in 'OS', 'DriverPack') {
            foreach ($operation in 'Download', 'Cache', 'Copy', 'Expand') {
                $global:OSDCloudResults."rate${content}${operation}" | Should -Be 3
                $global:OSDCloudResults."rate${content}${operation}" | Should -BeOfType ([long])
                $global:OSDCloudResults."step${content}${operation}" = 0L
            }
        }
        Update-OSDCloudResults
        foreach ($content in 'OS', 'DriverPack') {
            foreach ($operation in 'Download', 'Cache', 'Copy', 'Expand') {
                $global:OSDCloudResults."rate${content}${operation}" | Should -BeNullOrEmpty
                $global:OSDCloudResults."step${content}${operation}" = 2L
            }
            $global:OSDCloudResults."size${content}" = $null
        }
        Update-OSDCloudResults
        foreach ($content in 'OS', 'DriverPack') {
            foreach ($operation in 'Download', 'Cache', 'Copy', 'Expand') {
                $global:OSDCloudResults."rate${content}${operation}" | Should -BeNullOrEmpty
            }
        }
    }

    It 'calculates total size and throughput from reported content and deployment duration' {
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 5MB
        Set-OSDCloudAcquisitionResult -Content DriverPack -Bytes 5MB
        $global:OSDCloudResults.totalDurationRAW = 2L
        Update-OSDCloudResults
        $global:OSDCloudResults.totalSizeMB | Should -Be 10
        $global:OSDCloudResults.totalSizeMB | Should -BeOfType ([long])
        $global:OSDCloudResults.totalMBps | Should -Be 5
        $global:OSDCloudResults.totalMBps | Should -BeOfType ([long])

        $global:OSDCloudResults.totalDurationRAW = 0L
        Update-OSDCloudResults
        $global:OSDCloudResults.totalMBps | Should -BeNullOrEmpty
    }

    It 'classifies gateway adapters as <Expected>' -TestCases @(
        @{ AdapterType = 0; AdapterName = 'Ethernet'; Expected = 'Wired' }
        @{ AdapterType = 9; AdapterName = 'Radio'; Expected = 'Wireless' }
        @{ AdapterType = 0; AdapterName = 'Wi-Fi'; Expected = 'Wireless' }
    ) {
        param ($AdapterType, $AdapterName, $Expected)
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_NetworkAdapterConfiguration') {
                [pscustomobject]@{ Index = 4; DefaultIPGateway = @('192.0.2.1') }
            }
            else {
                [pscustomobject]@{ Index = 4; AdapterTypeID = $AdapterType; Name = $AdapterName; PhysicalAdapter = $true; NetConnectionStatus = 2 }
            }
        }
        Update-OSDCloudResults
        $global:OSDCloudResults.Network | Should -BeExactly $Expected
    }

    It 'keeps network null when wired and wireless gateways are both active' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_NetworkAdapterConfiguration') {
                [pscustomobject]@{ Index = 4; DefaultIPGateway = @('192.0.2.1') }
                [pscustomobject]@{ Index = 5; DefaultIPGateway = @('192.0.2.2') }
            }
            else {
                [pscustomobject]@{ Index = 4; AdapterTypeID = 0; Name = 'Ethernet'; PhysicalAdapter = $true; NetConnectionStatus = 2 }
                [pscustomobject]@{ Index = 5; AdapterTypeID = 9; Name = 'Radio'; PhysicalAdapter = $true; NetConnectionStatus = 2 }
            }
        }
        Update-OSDCloudResults
        $global:OSDCloudResults.Network | Should -BeNullOrEmpty
    }

    It 'keeps network null when no gateway is available or discovery fails' {
        Update-OSDCloudResults
        $global:OSDCloudResults.Network | Should -BeNullOrEmpty
        Mock Get-CimInstance { throw 'Synthetic network discovery failure' }
        Update-OSDCloudResults -WarningVariable warnings
        $global:OSDCloudResults.Network | Should -BeNullOrEmpty
        "$warnings" | Should -Match 'Synthetic network discovery failure'
        $global:OSDCloudResults.DistinctId | Should -Not -BeNullOrEmpty
    }

    It 'separates USB-cache downloads from direct downloads and rounds cache bytes once' {
        $global:OSDCloudWorkflowInvoke.CompletedTransfers = @{
            stepOSCache = $true; stepDriverPackCache = $true
            stepOSCopy = $true; stepDriverPackCopy = $true
        }
        $global:OSDCloudWorkflowInvoke.Durations = @{ stepOSCache = 2; stepDriverPackCache = 2 }
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 1.49MB
        Set-OSDCloudAcquisitionResult -Content DriverPack -Bytes 1.49MB
        Update-OSDCloudResults
        $global:OSDCloudResults.totalSizeCacheMB | Should -Be 3
        $global:OSDCloudResults.totalSizeDownloadMB | Should -Be 0
        $global:OSDCloudResults.totalSizeCopyMB | Should -Be 3
        $global:OSDCloudResults.rateOSCache | Should -Be 1
        $global:OSDCloudResults.rateDriverPackCache | Should -Be 1
        $global:OSDCloudResults.rateOSDownload | Should -BeNullOrEmpty
        $global:OSDCloudResults.rateDriverPackDownload | Should -BeNullOrEmpty
        Export-OSDCloudResults
        $loaded = Import-Clixml -LiteralPath (Join-Path $env:TEMP 'OSDCloudResults.clixml')
        $loaded.totalSizeCacheMB | Should -Be 3
        $loaded.stepOSCache | Should -Be 2
        $loaded.rateDriverPackCache | Should -Be 1
        $global:OSDCloudResults.StartTimeUtc = [datetime]::UtcNow
        $global:OSDCloudResults.EndTimeUtc = [datetime]::UtcNow
        $global:OSDCloudResults.Status = 'Completed'
        Mock Invoke-RestMethod { $script:capturedBody = $Body }
        Send-OSDCloudResults
        $payload = $script:capturedBody | ConvertFrom-Json
        $payload.properties.totalSizeCacheMB | Should -Be 3
        $payload.properties.totalSizeDownloadMB | Should -Be 0
        $payload.properties.stepOSCache | Should -Be 2
        $payload.properties.rateDriverPackCache | Should -Be 1
    }

    It 'classifies acquired content as <Expected> for OS=<OS> and DriverPack=<DriverPack>' -TestCases @(
        @{ OS = 'Download'; DriverPack = 'Download'; Expected = 'Cloud' }
        @{ OS = 'Cache'; DriverPack = 'Cache'; Expected = 'Cloud' }
        @{ OS = 'Cache'; DriverPack = 'Download'; Expected = 'Cloud' }
        @{ OS = 'Copy'; DriverPack = 'Copy'; Expected = 'Cache' }
        @{ OS = 'Copy'; DriverPack = 'Download'; Expected = 'Mixed' }
        @{ OS = 'Cache'; DriverPack = 'Copy'; Expected = 'Mixed' }
        @{ OS = 'Download'; DriverPack = ''; Expected = 'Cloud' }
        @{ OS = ''; DriverPack = 'Copy'; Expected = 'Cache' }
        @{ OS = ''; DriverPack = ''; Expected = $null }
    ) {
        param ($OS, $DriverPack, $Expected)
        $global:OSDCloudWorkflowInvoke.CompletedTransfers = @{}
        foreach ($content in 'OS', 'DriverPack') {
            $operation = Get-Variable -Name $content -ValueOnly
            if ($operation) {
                $global:OSDCloudWorkflowInvoke.CompletedTransfers["step${content}${operation}"] = $true
                if ($operation -eq 'Cache') {
                    $global:OSDCloudWorkflowInvoke.CompletedTransfers["step${content}Copy"] = $true
                }
                Set-OSDCloudAcquisitionResult -Content $content -Bytes 1
            }
        }
        Update-OSDCloudResults
        $global:OSDCloudResults.ContentSource | Should -BeExactly $Expected
    }

    It 'clears a previous classification when acquisition source is unknown' {
        $global:OSDCloudResults.ContentSource = 'Cloud'
        $global:OSDCloudWorkflowInvoke.CompletedTransfers = @{}
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 1MB
        Update-OSDCloudResults
        $global:OSDCloudResults.ContentSource | Should -BeNullOrEmpty
    }

    It 'generates one fallback GUID when device identity is unavailable' {
        $global:OSDCloudResults.DistinctId = $null
        $global:OSDCoreDevice.EndpointSHA = $null
        $global:OSDCoreDevice.UUID = $null
        Update-OSDCloudResults
        $id = $global:OSDCloudResults.DistinctId
        { [guid]::Parse($id) } | Should -Not -Throw
        Update-OSDCloudResults
        $global:OSDCloudResults.DistinctId | Should -Be $id
    }

    It 'refreshes metadata from the workflow execution snapshot when available' {
        $global:OSDCloudWorkflowInvoke.DriverPackName = 'Resolved pack'
        $global:OSDCloudWorkflowInvoke.DriverPackCloudObject = [pscustomobject]@{ FileName = 'resolved-drivers.cab' }
        $global:OSDCloudWorkflowInvoke.OSEditionId = 'Enterprise'
        $global:OSDCloudWorkflowInvoke.OperatingSystemCloudObject = [pscustomobject]@{
            OSBuildVersion = '26300.9999'
            FileName = 'resolved-install.esd'
        }
        Update-OSDCloudResults
        $global:OSDCloudResults.DriverPackName | Should -Be 'Resolved pack'
        $global:OSDCloudResults.DriverPackFileName | Should -BeExactly 'resolved-drivers.cab'
        $global:OSDCloudResults.OSEditionId | Should -Be 'Enterprise'
        $global:OSDCloudResults.OSBuildVersion | Should -Be '26300.9999'
        $global:OSDCloudResults.OSFileName | Should -BeExactly 'resolved-install.esd'
    }

    It 'round trips typed results in current TEMP and the actual target Windows TEMP' {
        $null = New-Item -Path (Join-Path $targetRoot 'Windows') -ItemType Directory -Force
        $global:OSDCloudResults.StartTimeUtc = [datetime]::UtcNow
        $global:OSDCloudResults.EndTimeUtc = [datetime]::UtcNow
        $global:OSDCloudResults.totalDurationRAW = 126L
        $global:OSDCloudWorkflowInvoke.CompletedTransfers.stepOSCopy = $true
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 5.5MB
        $global:OSDCloudWorkflowInvoke.Durations = @{ stepOSCopy = 2.5; stepClearDisk = 10.5 }
        Update-OSDCloudResults
        $global:OSDCloudResults.IsComplete = $true
        $global:OSDCloudResults.Status = 'Completed'
        Export-OSDCloudResults -IncludeTarget
        foreach ($directory in @($env:TEMP, (Join-Path $targetRoot 'Windows\Temp'))) {
            $loaded = Import-Clixml -LiteralPath (Join-Path $directory 'OSDCloudResults.clixml')
            $loaded.DeploymentId | Should -Be $global:OSDCloudResults.DeploymentId
            $loaded.IsComplete | Should -BeOfType ([bool])
            $loaded.StartTimeUtc | Should -BeOfType ([datetime])
            $loaded.totalDurationRAW | Should -BeOfType ([long])
            $loaded.totalDurationRAW | Should -Be 126
            $loaded.sizeOS | Should -BeOfType ([long])
            $loaded.sizeOS | Should -Be 6
            $loaded.totalSizeCopyMB | Should -Be 6
            $loaded.totalSizeDownloadMB | Should -Be 6
            foreach ($name in 'sizeOS', 'sizeDriverPack', 'totalDurationRAW', 'totalDuration',
                'totalSizeDownloadMB', 'totalSizeCopyMB', 'totalSizeMB', 'totalMBps') {
                $loaded.PSObject.Properties.Name -ccontains $name | Should -BeTrue
            }
            $loaded.stepOSCopy | Should -Be 3
            $loaded.rateOSCopy | Should -Be 2
            $loaded.ContentSource | Should -BeExactly 'Cloud'
            $loaded.Network | Should -BeNullOrEmpty
            $loaded.totalDuration | Should -Be 115
            $loaded.stepClearDisk | Should -Be 11
            $loaded.PSObject.Properties.Name | Should -Not -Contain 'DurationSeconds'
            $loaded.PSObject.Properties.Name | Should -Not -Contain 'OSDurationSeconds'
        }
    }

    It 'overwrites the running snapshot with terminal results' {
        $global:OSDCloudResults.Status = 'Running'
        Export-OSDCloudResults
        (Import-Clixml -LiteralPath (Join-Path $env:TEMP 'OSDCloudResults.clixml')).Status | Should -Be 'Running'
        $global:OSDCloudResults.Status = 'Failed'
        Export-OSDCloudResults
        (Import-Clixml -LiteralPath (Join-Path $env:TEMP 'OSDCloudResults.clixml')).Status | Should -Be 'Failed'
    }

    It 'warns about unavailable target context but still saves current TEMP: <Case>' -TestCases @(
        @{ Case = 'no context' }
        @{ Case = 'no Windows directory' }
    ) {
        param ($Case)
        if ($Case -eq 'no context') { $global:OSDCloudWorkflowInvoke = $null }
        Mock Test-Path { $false }
        Export-OSDCloudResults -IncludeTarget -WarningVariable warnings
        "$warnings" | Should -Match 'Could not resolve'
        Import-Clixml -LiteralPath (Join-Path $env:TEMP 'OSDCloudResults.clixml') | Should -Not -BeNullOrEmpty
    }

    It 'attempts target export independently when current TEMP cannot be written' {
        $null = New-Item -Path (Join-Path $targetRoot 'Windows') -ItemType Directory -Force
        Mock Export-Clixml { throw 'Synthetic write failure' } -ParameterFilter { $LiteralPath -like '*\current\*' }
        Export-OSDCloudResults -IncludeTarget -WarningVariable warnings
        "$warnings" | Should -Match 'Synthetic write failure'
        Import-Clixml -LiteralPath (Join-Path $targetRoot 'Windows\Temp\OSDCloudResults.clixml') | Should -Not -BeNullOrEmpty
    }

    It 'warns on directory creation failure without throwing' {
        Mock New-Item { throw 'Synthetic directory failure' }
        { Export-OSDCloudResults -WarningAction SilentlyContinue } | Should -Not -Throw
        Export-OSDCloudResults -WarningVariable warnings
        "$warnings" | Should -Match 'Synthetic directory failure'
    }

    It 'exports once when current TEMP is the target Windows TEMP' {
        $env:TEMP = Join-Path $targetRoot 'Windows\Temp'
        $null = New-Item -Path (Join-Path $targetRoot 'Windows') -ItemType Directory -Force
        Mock Export-Clixml {}
        Export-OSDCloudResults -IncludeTarget
        Should -Invoke Export-Clixml -Times 1 -Exactly
    }

    It 'uses a non-C image application root without touching the real volume' {
        $global:OSDCloudWorkflowInvoke.ParamsExpandWindowsImage.ApplyPath = 'D:\'
        Mock Test-Path { $true }
        Mock New-Item {}
        Mock Export-Clixml {}
        Mock Join-Path { "$Path\$ChildPath".Replace('\\', '\') }
        Export-OSDCloudResults -IncludeTarget
        Should -Invoke Test-Path -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq 'D:\Windows' }
        Should -Invoke Export-Clixml -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq 'D:\Windows\Temp\OSDCloudResults.clixml' }
        Should -Invoke Export-Clixml -Times 0 -Exactly -ParameterFilter { $LiteralPath -like 'C:\Windows\Temp\*' }
    }

    It 'sends exactly the allowlisted terminal properties as typed JSON with a bounded timeout' {
        $global:OSDCloudResults.Status = 'Completed'
        $global:OSDCloudResults.IsComplete = $true
        $global:OSDCloudResults.StartTimeUtc = [datetime]::UtcNow.AddSeconds(-125)
        $global:OSDCloudResults.EndTimeUtc = [datetime]::UtcNow
        $global:OSDCloudResults.totalDurationRAW = 126L
        $global:OSDCloudWorkflowInvoke.CompletedTransfers.stepOSCopy = $true
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 2.5MB
        Set-OSDCloudAcquisitionResult -Content DriverPack -Bytes 1.25MB
        $global:OSDCloudWorkflowInvoke.Durations = @{
            stepOSCopy = 4.5; stepOSDownload = 10.4; stepOSExpand = 11.5
            stepDriverPackCopy = 0.4; stepDriverPackDownload = 12.5
            stepDriverPackExpand = 13.4; stepClearDisk = 14.5
        }
        Update-OSDCloudResults
        $global:OSDCloudResults | Add-Member -NotePropertyName Secret -NotePropertyValue 'private-secret'
        Mock Invoke-RestMethod { $script:capturedBody = $Body }
        Send-OSDCloudResults
        $payload = $script:capturedBody | ConvertFrom-Json
        $payload.event | Should -Be 'OSDCloudResultsBeta'
        $payload.properties.IsComplete | Should -BeOfType ([bool])
        $payload.properties.totalDurationRAW | Should -Be 126
        $payload.properties.sizeOS | Should -Be 3
        $payload.properties.stepOSCopy | Should -Be 5
        $payload.properties.sizeDriverPack | Should -Be 1
        $payload.properties.stepDriverPackCopy | Should -Be 0
        $payload.properties.stepOSDownload | Should -Be 10
        $payload.properties.stepOSExpand | Should -Be 12
        $payload.properties.stepDriverPackDownload | Should -Be 13
        $payload.properties.stepDriverPackExpand | Should -Be 13
        $payload.properties.stepClearDisk | Should -Be 15
        $payload.properties.totalDuration | Should -Be 111
        $payload.properties.timeDownload | Should -Be 23
        $payload.properties.timeCache | Should -Be 0
        $payload.properties.timeCopy | Should -Be 5
        $payload.properties.timeExpand | Should -Be 25
        $payload.properties.timeOther | Should -Be 58
        $payload.properties.timeCloud | Should -Be 23
        $payload.properties.OSFileName | Should -BeExactly 'install.esd'
        $payload.properties.DriverPackFileName | Should -BeExactly 'drivers.cab'
        $payload.properties.totalSizeDownloadMB | Should -Be 4
        $payload.properties.totalSizeCopyMB | Should -Be 3
        $payload.properties.totalSizeMB | Should -Be 4
        $payload.properties.totalMBps | Should -Be 0
        $payload.properties.ContentSource | Should -BeExactly 'Cloud'
        $payload.properties.rateOSCopy | Should -Be 1
        $payload.properties.rateDriverPackCopy | Should -BeNullOrEmpty
        $payload.properties.Network | Should -BeNullOrEmpty
        $payload.properties.distinct_id | Should -Be 'hashed-device'
        $payload.properties.DeploymentId | Should -Be $global:OSDCloudResults.DeploymentId
        $script:capturedBody | Should -Match '"StartTimeUtc"\s*:\s*"[^"]+Z"'
        $script:capturedBody | Should -Match '"EndTimeUtc"\s*:\s*"[^"]+Z"'
        $expectedNames = @(
            'SchemaVersion', 'DeploymentId', 'IsComplete', 'Status', 'StartTimeUtc', 'EndTimeUtc',
            'totalDurationRAW', 'ModuleVersion', 'WorkflowName', 'WorkflowTaskName', 'LaunchMethod',
            'timeDownload', 'timeCache', 'timeCopy', 'timeExpand', 'timeOther', 'timeCloud',
            'totalDuration', 'stepOSDownload', 'stepOSExpand', 'stepDriverPackDownload',
            'stepOSCache', 'stepDriverPackCache', 'rateOSCache', 'rateDriverPackCache', 'totalSizeCacheMB',
            'totalSizeMB', 'totalMBps',
            'ContentSource',
            'rateOSDownload', 'rateOSCopy', 'rateOSExpand',
            'rateDriverPackDownload', 'rateDriverPackCopy', 'rateDriverPackExpand', 'Network',
            'stepDriverPackExpand', 'stepClearDisk', 'totalSizeCopyMB',
            'sizeOS', 'stepOSCopy', 'sizeDriverPack', 'stepDriverPackCopy', 'totalSizeDownloadMB',
            'DeploymentPhase', 'OSDManufacturer', 'OSDModel', 'OSDProduct', 'ProcessorArchitecture',
            'TotalPhysicalMemoryGB', 'OSName', 'OSVersion', 'OSBuild', 'OSBuildVersion', 'OSEditionId',
            'OSActivation', 'OSLanguageCode', 'OSFileName', 'DriverPackName', 'DriverPackFileName',
            'distinct_id'
        )
        @($payload.properties.PSObject.Properties.Name).Count | Should -Be $expectedNames.Count
        foreach ($name in $expectedNames) {
            $payload.properties.PSObject.Properties.Name -ccontains $name | Should -BeTrue
        }
        $script:capturedBody | Should -Not -Match 'private-secret|raw-private-uuid|private-serial|private-license|private.invalid'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and $Uri -eq 'https://us.i.posthog.com/capture/' -and
            $TimeoutSec -eq 2 -and $ContentType -eq 'application/json' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'warns on telemetry failure without throwing' {
        $global:OSDCloudResults.Status = 'Failed'
        $global:OSDCloudResults.StartTimeUtc = [datetime]::UtcNow
        $global:OSDCloudResults.EndTimeUtc = [datetime]::UtcNow
        Mock Invoke-RestMethod { throw 'Synthetic network failure' }
        Send-OSDCloudResults -WarningVariable warnings
        "$warnings" | Should -Match 'Synthetic network failure'
    }

    It 'does not send unstarted or unfinalized results' {
        Send-OSDCloudResults -WarningVariable warnings
        "$warnings" | Should -Match 'Only finalized'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'rounds combined original bytes, not the sum of rounded MB sizes' {
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 1.49MB
        Set-OSDCloudAcquisitionResult -Content DriverPack -Bytes 1.49MB
        $global:OSDCloudWorkflowInvoke.Durations = @{ stepOSCopy = 4.49; stepDriverPackCopy = 4.5 }
        Update-OSDCloudResults
        $global:OSDCloudResults.sizeOS | Should -Be 1
        $global:OSDCloudResults.sizeDriverPack | Should -Be 1
        $global:OSDCloudResults.totalSizeDownloadMB | Should -Be 3
        $global:OSDCloudResults.totalSizeMB | Should -Be 2
        $global:OSDCloudResults.stepOSCopy | Should -Be 4
        $global:OSDCloudResults.stepDriverPackCopy | Should -Be 5
    }

    It 'leaves missing content unknown and totals only acquired bytes without double counting' {
        $global:OSDCloudResults.totalSizeDownloadMB | Should -BeNullOrEmpty
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 2.5MB
        Update-OSDCloudResults
        Update-OSDCloudResults
        $global:OSDCloudResults.sizeDriverPack | Should -BeNullOrEmpty
        $global:OSDCloudResults.stepDriverPackCopy | Should -BeNullOrEmpty
        $global:OSDCloudResults.totalSizeDownloadMB | Should -Be 3
        $global:OSDCloudResults.totalSizeMB | Should -Be 3
    }

    It 'uses full total duration for ZTI when no confirmation wait occurred' {
        $global:OSDCloudResults.totalDurationRAW = 126L
        Update-OSDCloudResults
        $global:OSDCloudResults.totalDuration | Should -Be 126
        $global:OSDCloudResults.timeDownload | Should -Be 0
        $global:OSDCloudResults.timeCache | Should -Be 0
        $global:OSDCloudResults.timeCopy | Should -Be 0
        $global:OSDCloudResults.timeExpand | Should -Be 0
        $global:OSDCloudResults.timeOther | Should -Be 126
        $global:OSDCloudResults.timeCloud | Should -Be 0
        $global:OSDCloudResults.stepClearDisk | Should -BeNullOrEmpty
    }

    It 'does not produce a negative ZTI duration' {
        $global:OSDCloudResults.totalDurationRAW = 1L
        $global:OSDCloudWorkflowInvoke.Durations = @{ stepClearDisk = 1.5 }
        Update-OSDCloudResults
        $global:OSDCloudResults.totalDuration | Should -Be 0
    }

    It 'separates downloaded and copied content and rounds original bytes once' {
        $global:OSDCloudWorkflowInvoke.CompletedTransfers = @{
            stepOSDownload = $true; stepOSCopy = $true; stepDriverPackCopy = $true
        }
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 1.49MB
        Set-OSDCloudAcquisitionResult -Content DriverPack -Bytes 1.49MB
        Update-OSDCloudResults
        $global:OSDCloudResults.sizeOS | Should -Be 1
        $global:OSDCloudResults.sizeDriverPack | Should -Be 1
        $global:OSDCloudResults.totalSizeDownloadMB | Should -Be 1
        $global:OSDCloudResults.totalSizeCopyMB | Should -Be 3
        Update-OSDCloudResults
        $global:OSDCloudResults.totalSizeCopyMB | Should -Be 3
    }

    It 'reports zero download size for cache-only content' {
        $global:OSDCloudWorkflowInvoke.CompletedTransfers = @{ stepOSCopy = $true }
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 2.5MB
        Update-OSDCloudResults
        $global:OSDCloudResults.totalSizeDownloadMB | Should -Be 0
        $global:OSDCloudResults.totalSizeCopyMB | Should -Be 3
    }
}
