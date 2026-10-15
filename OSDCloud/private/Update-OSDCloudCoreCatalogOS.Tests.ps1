BeforeAll {
    $fixtureRoot = Join-Path $TestDrive 'module'
    $null = New-Item -Path $fixtureRoot -ItemType Directory
    $modulePath = Join-Path $fixtureRoot 'CatalogRefreshFixture.psm1'
    @"
. '$PSScriptRoot\Update-OSDCloudCoreCatalogOS.ps1'
. '$PSScriptRoot\core-license\Get-OSDCoreLicense.ps1'
"@ | Set-Content -LiteralPath $modulePath
    $fixtureModule = Import-Module $modulePath -Force -PassThru
    $fixtureModule.SessionState.PSVariable.Set('fixtureRoot', $fixtureRoot)
    $expandScript = Join-Path $fixtureRoot 'expand.ps1'
    'Copy-Item -LiteralPath "$PSScriptRoot\products.xml" -Destination $args[1] -WhatIf:$false; $global:LASTEXITCODE = 0' |
        Set-Content -LiteralPath $expandScript
}

AfterAll {
    Remove-Module $fixtureModule
}

Describe 'Licensed OS catalog refresh and USB publication' {
    BeforeEach {
        $catalogRoot = Join-Path $fixtureRoot 'core\operatingsystems'
        if (Test-Path $catalogRoot) { Remove-Item $catalogRoot -Recurse -Force }
        $null = New-Item $catalogRoot -ItemType Directory -Force
        $usbRoot = Join-Path $fixtureRoot 'usb'
        if (Test-Path $usbRoot) { Remove-Item $usbRoot -Recurse -Force }
        $fixtureModule.SessionState.PSVariable.Set('licenseResult', [pscustomobject]@{ IsValid = $true; IsRegistered = $false })
        $fixtureModule.SessionState.PSVariable.Set('volumes', @())
        $fixtureModule.SessionState.PSVariable.Set('downloadDirectory', $null)
        $fixtureModule.SessionState.PSVariable.Set('disk', [pscustomobject]@{ BusType = 'USB'; IsReadOnly = $false; IsOffline = $false })
        $fixtureModule.SessionState.PSVariable.Set('partition', [pscustomobject]@{ DiskNumber = 7; IsReadOnly = $false; IsOffline = $false })
        $identity = '26200.9999.261015-1200'
        $nodes = foreach ($architecture in 'x64', 'ARM64') {
            "<File><FileName>$identity.CLIENTBUSINESS_VOL.en-us.$architecture.esd</FileName><LanguageCode>en-us</LanguageCode><Edition>Enterprise</Edition><Architecture>$architecture</Architecture><Size>100</Size><Sha256>$('A' * 64)</Sha256><FilePath>https://example.invalid/$architecture.esd</FilePath></File>"
        }
        "<MCT><Catalogs><Catalog><PublishedMedia><Files>$($nodes -join '')</Files></PublishedMedia></Catalog></Catalogs></MCT>" |
            Set-Content (Join-Path $fixtureRoot 'products.xml')
        Mock Get-OSDCoreLicense -ModuleName CatalogRefreshFixture {
            & (Get-Module CatalogRefreshFixture) { $script:licenseResult }
        }
        Mock Write-Host -ModuleName CatalogRefreshFixture {}
        Mock Invoke-RestMethod -ModuleName CatalogRefreshFixture {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { $digest = [Convert]::ToBase64String($sha.ComputeHash([byte[]]@(1, 2, 3))) }
            finally { $sha.Dispose() }
            [pscustomobject]@{ FileLocations = @([pscustomobject]@{
                FileName = 'products.cab'; Url = 'https://example.invalid/products.cab'; Size = 3; Digest = $digest
            }) }
        }
        Mock Invoke-WebRequest -ModuleName CatalogRefreshFixture {
            & (Get-Module CatalogRefreshFixture) { param ($Path) $script:downloadDirectory = Split-Path $Path } $OutFile
            [System.IO.File]::WriteAllBytes($OutFile, [byte[]]@(1, 2, 3))
        }
        Mock Get-Volume -ModuleName CatalogRefreshFixture { & (Get-Module CatalogRefreshFixture) { $script:volumes } }
        Mock Get-Partition -ModuleName CatalogRefreshFixture { & (Get-Module CatalogRefreshFixture) { $script:partition } }
        Mock Get-Disk -ModuleName CatalogRefreshFixture { & (Get-Module CatalogRefreshFixture) { $script:disk } }
        Mock Join-Path -ModuleName CatalogRefreshFixture -ParameterFilter { $ChildPath -eq 'System32\expand.exe' } {
            Microsoft.PowerShell.Management\Join-Path $fixtureRoot 'expand.ps1'
        }
        Mock Join-Path -ModuleName CatalogRefreshFixture -ParameterFilter { $Path -match '^[F-H]:\\$' } {
            Microsoft.PowerShell.Management\Join-Path "$fixtureRoot\usb\$($Path.Substring(0, 1))" $ChildPath
        }
    }

    AfterEach {
        $downloadDirectory = $fixtureModule.SessionState.PSVariable.GetValue('downloadDirectory')
        if ($downloadDirectory) {
            Test-Path -LiteralPath $downloadDirectory | Should -BeFalse
        }
        @(Get-ChildItem $catalogRoot -Filter '*.tmp' -Force).Count | Should -Be 0
        if (Test-Path $usbRoot) {
            @(Get-ChildItem $usbRoot -Filter '*.tmp' -Recurse -Force).Count | Should -Be 0
        }
    }

    It 'quietly skips <Case> before any update discovery or side effects' -TestCases @(
        @{ Case = 'missing license'; License = $null }
        @{ Case = 'invalid registered license'; License = [pscustomobject]@{ IsValid = $false; IsRegistered = $true } }
        @{ Case = 'registration only'; License = [pscustomobject]@{ IsRegistered = $true } }
    ) {
        param ($License)
        $fixtureModule.SessionState.PSVariable.Set('licenseResult', $License)
        Mock Test-Path -ModuleName CatalogRefreshFixture { throw 'Unexpected discovery' }
        Mock New-Item -ModuleName CatalogRefreshFixture { throw 'Unexpected write' }
        $result = @(Update-OSDCloudCoreCatalogOS -WarningVariable warnings -ErrorVariable errors)
        $result.Count | Should -Be 0
        @($warnings).Count | Should -Be 0
        @($errors).Count | Should -Be 0
        Should -Invoke Test-Path -ModuleName CatalogRefreshFixture -Times 0 -Exactly
        Should -Invoke New-Item -ModuleName CatalogRefreshFixture -Times 0 -Exactly
        Should -Invoke Invoke-RestMethod -ModuleName CatalogRefreshFixture -Times 0 -Exactly
        Should -Invoke Invoke-WebRequest -ModuleName CatalogRefreshFixture -Times 0 -Exactly
        Should -Invoke Get-Volume -ModuleName CatalogRefreshFixture -Times 0 -Exactly
        Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 0 -Exactly
    }

    It 'fails closed with only a generic verbose diagnostic on lookup failure' {
        Mock Get-OSDCoreLicense -ModuleName CatalogRefreshFixture { throw 'Sensitive synthetic lookup detail' }
        $output = @(Update-OSDCloudCoreCatalogOS -Verbose -WarningVariable warnings 4>&1)
        "$output" | Should -Match 'License lookup failed'
        "$output" | Should -Not -Match 'Sensitive synthetic'
        @($warnings).Count | Should -Be 0
        Should -Invoke Invoke-RestMethod -ModuleName CatalogRefreshFixture -Times 0 -Exactly
        Should -Invoke Get-Volume -ModuleName CatalogRefreshFixture -Times 0 -Exactly
        Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 0 -Exactly
    }

    It 'suppresses license-reader warnings when skipping an update' {
        Mock Get-OSDCoreLicense -ModuleName CatalogRefreshFixture {
            Write-Warning 'Synthetic license-reader warning' -WarningAction $WarningAction
            $null
        }
        $result = @(Update-OSDCloudCoreCatalogOS 3>&1)
        $result.Count | Should -Be 0
        Should -Invoke Get-OSDCoreLicense -ModuleName CatalogRefreshFixture -Times 1 -Exactly -ParameterFilter {
            $ErrorAction -eq 'Stop' -and $WarningAction -eq 'SilentlyContinue' -and $Verbose -eq $false
        }
        Should -Invoke Invoke-RestMethod -ModuleName CatalogRefreshFixture -Times 0 -Exactly
    }

    It 'publishes validated content independently of registration and preserves older catalogs' {
        Set-Content (Join-Path $catalogRoot '26100.1.260101-1200.xml') 'older'
        $result = Update-OSDCloudCoreCatalogOS -MinimumItemCount 2 -Confirm:$false
        $result.Published | Should -BeTrue
        $result.Build | Should -Be '26200.9999'
        $result.ItemCount | Should -Be 2
        $result.Sha256 | Should -Be (Get-FileHash (Join-Path $fixtureRoot 'products.xml')).Hash
        $result.ModuleCatalogPath | Should -Be (Join-Path $catalogRoot "$identity.xml")
        Test-Path $result.ModuleCatalogPath | Should -BeTrue
        Test-Path (Join-Path $catalogRoot '26100.1.260101-1200.xml') | Should -BeTrue
        Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 1 -Exactly -ParameterFilter {
            $Object -like '*Saving OS catalog to module:*' -and $Object.EndsWith($result.ModuleCatalogPath)
        }
        Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 1 -Exactly -ParameterFilter {
            $ForegroundColor -eq 'DarkGreen' -and $Object -like '*Recast: OSDCloud is updating the OS catalog.*'
        }
    }

    It 'copies only the updated catalog to multiple named USBs even if module content is unchanged' {
        Copy-Item (Join-Path $fixtureRoot 'products.xml') (Join-Path $catalogRoot "$identity.xml")
        Set-Content (Join-Path $catalogRoot '26100.1.260101-1200.xml') 'older'
        $fixtureModule.SessionState.PSVariable.Set('volumes', @(
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'F' }
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'G' }
            [pscustomobject]@{ FileSystemLabel = 'Other'; DriveLetter = 'H' }
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = $null }
        ))
        $result = Update-OSDCloudCoreCatalogOS -MinimumItemCount 2 -Confirm:$false
        $result.Published | Should -BeFalse
        $result.DriveCatalogPaths.Count | Should -Be 2
        foreach ($letter in 'F', 'G') {
            $files = @(Get-ChildItem "$usbRoot\$letter\OSDCloud\catalogs\operatingsystems" -File)
            $files.Count | Should -Be 1
            $files[0].Name | Should -Be "$identity.xml"
            $savedPath = $files[0].FullName
            Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 1 -Exactly -ParameterFilter {
                $Object -like '*Saving OS catalog to USB:*' -and $Object.EndsWith($savedPath)
            }
        }
        Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 0 -Exactly -ParameterFilter {
            $Object -like '*Saving OS catalog to module:*'
        }
        Test-Path "$usbRoot\H" | Should -BeFalse
        Should -Invoke Get-Partition -ModuleName CatalogRefreshFixture -Times 2 -Exactly
    }

    It 'excludes <Case> from synchronization' -TestCases @(
        @{ Case = 'non-USB'; Target = 'disk'; Property = 'BusType'; Value = 'NVMe' }
        @{ Case = 'read-only disk'; Target = 'disk'; Property = 'IsReadOnly'; Value = $true }
        @{ Case = 'offline disk'; Target = 'disk'; Property = 'IsOffline'; Value = $true }
        @{ Case = 'read-only partition'; Target = 'partition'; Property = 'IsReadOnly'; Value = $true }
        @{ Case = 'offline partition'; Target = 'partition'; Property = 'IsOffline'; Value = $true }
    ) {
        param ($Target, $Property, $Value)
        $fixtureModule.SessionState.PSVariable.GetValue($Target).$Property = $Value
        $fixtureModule.SessionState.PSVariable.Set('volumes', @([pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'F' }))
        $result = Update-OSDCloudCoreCatalogOS -MinimumItemCount 2 -Confirm:$false -WarningAction SilentlyContinue
        $result.Published | Should -BeTrue
        $result.DriveCatalogPaths.Count | Should -Be 0
        Test-Path $usbRoot | Should -BeFalse
    }

    It 'retains module publication when USB discovery fails' {
        Mock Get-Volume -ModuleName CatalogRefreshFixture { throw 'Synthetic discovery failure' }
        $result = Update-OSDCloudCoreCatalogOS -MinimumItemCount 2 -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
        $result.Published | Should -BeTrue
        "$warnings" | Should -Match 'Unable to discover'
    }

    It 'does not copy to a non-USB drive even when it already has an OSDCloud folder' {
        $existingFolder = New-Item "$usbRoot\F\OSDCloud" -ItemType Directory -Force
        Set-Content (Join-Path $existingFolder.FullName 'existing.txt') 'preserve'
        $fixtureModule.SessionState.PSVariable.GetValue('disk').BusType = 'NVMe'
        $fixtureModule.SessionState.PSVariable.Set('volumes', @([pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'F' }))
        $result = Update-OSDCloudCoreCatalogOS -MinimumItemCount 2 -Confirm:$false
        $result.DriveCatalogPaths.Count | Should -Be 0
        Test-Path "$usbRoot\F\OSDCloud\catalogs" | Should -BeFalse
        Get-Content (Join-Path $existingFolder.FullName 'existing.txt') | Should -Be 'preserve'
    }

    It 'warns on module publication failure and removes the staged catalog' {
        $null = New-Item (Join-Path $catalogRoot "$identity.xml") -ItemType Directory
        $result = Update-OSDCloudCoreCatalogOS -MinimumItemCount 2 -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$warnings" | Should -Match 'Catalog update was not successful'
        Should -Invoke Get-Volume -ModuleName CatalogRefreshFixture -Times 0 -Exactly
        Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 0 -Exactly -ParameterFilter {
            $Object -like '*OS catalog saved to*'
        }
    }

    It 'continues after a USB <Failure> failure' -TestCases @(
        @{ Failure = 'inspection' }
        @{ Failure = 'write' }
    ) {
        param ($Failure)
        $fixtureModule.SessionState.PSVariable.Set('volumes', @(
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'F' }
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'G' }
        ))
        if ($Failure -eq 'inspection') {
            Mock Get-Partition -ModuleName CatalogRefreshFixture -ParameterFilter { $DriveLetter -eq 'F' } { throw 'Synthetic inspection failure' }
        }
        else {
            Mock New-Item -ModuleName CatalogRefreshFixture -ParameterFilter { $Path -like '*\usb\F\*' } { throw 'Synthetic denied write' }
        }
        $result = Update-OSDCloudCoreCatalogOS -MinimumItemCount 2 -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
        $result.Published | Should -BeTrue
        $result.DriveCatalogPaths.Count | Should -Be 1
        $result.DriveCatalogPaths[0] | Should -BeLike '*\usb\G\*'
        @($warnings).Count | Should -Be 1
        Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 1 -Exactly -ParameterFilter {
            $Object -like '*Saving OS catalog to USB:*' -and $Object.EndsWith($result.DriveCatalogPaths[0])
        }
        Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 0 -Exactly -ParameterFilter {
            $Object -like '*Saving OS catalog to USB:*\usb\F\*'
        }
    }

    It 'rejects <Case> without changing persistent catalogs' -TestCases @(
        @{ Case = 'conflicting content' }
        @{ Case = 'newer catalog' }
        @{ Case = 'insufficient records' }
        @{ Case = 'download failure' }
        @{ Case = 'digest mismatch' }
        @{ Case = 'size mismatch' }
    ) {
        param ($Case)
        switch ($Case) {
            'conflicting content' { Set-Content (Join-Path $catalogRoot "$identity.xml") 'existing' }
            'newer catalog' { Set-Content (Join-Path $catalogRoot '26200.10000.261015-1200.xml') 'newer' }
            'download failure' { Mock Invoke-WebRequest -ModuleName CatalogRefreshFixture { throw 'Synthetic network failure' } }
            'digest mismatch' { Mock Invoke-WebRequest -ModuleName CatalogRefreshFixture { [System.IO.File]::WriteAllBytes($OutFile, [byte[]]@(3, 2, 1)) } }
            'size mismatch' { Mock Invoke-WebRequest -ModuleName CatalogRefreshFixture { [System.IO.File]::WriteAllBytes($OutFile, [byte[]]@(1, 2)) } }
        }
        $before = @(Get-ChildItem $catalogRoot -File | Get-FileHash)
        $minimum = if ($Case -eq 'insufficient records') { 50 } else { 2 }
        $result = Update-OSDCloudCoreCatalogOS -MinimumItemCount $minimum -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        @($warnings).Count | Should -Be 1
        $after = @(Get-ChildItem $catalogRoot -File | Get-FileHash)
        ($after.Hash -join ',') | Should -Be ($before.Hash -join ',')
        @(Get-ChildItem $catalogRoot -Filter '*.tmp').Count | Should -Be 0
        Should -Invoke Get-Volume -ModuleName CatalogRefreshFixture -Times 0 -Exactly
    }

    It 'validates under WhatIf without publishing or creating USB folders' {
        $fixtureModule.SessionState.PSVariable.Set('volumes', @([pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'F' }))
        $result = Update-OSDCloudCoreCatalogOS -MinimumItemCount 2 -WhatIf
        $result.Published | Should -BeFalse
        $result.ItemCount | Should -Be 2
        @(Get-ChildItem $catalogRoot -File).Count | Should -Be 0
        Test-Path $usbRoot | Should -BeFalse
        Should -Invoke Invoke-WebRequest -ModuleName CatalogRefreshFixture -Times 1 -Exactly
        Should -Invoke Write-Host -ModuleName CatalogRefreshFixture -Times 0 -Exactly -ParameterFilter {
            $Object -like '*OS catalog saved to*'
        }
    }
}
