BeforeAll {
    $fixtureRoot = Join-Path $TestDrive 'index-module'
    $null = New-Item $fixtureRoot -ItemType Directory
    $modulePath = Join-Path $fixtureRoot 'CatalogIndexFixture.psm1'
    @"
. '$PSScriptRoot\Initialize-ModuleCoreOperatingSystems.ps1'
. '$PSScriptRoot\..\core-license\Get-OSDCoreLicense.ps1'
"@ | Set-Content $modulePath
    $fixtureModule = Import-Module $modulePath -Force -PassThru
    $originalCatalogState = Get-Variable ModuleCoreOperatingSystems -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    $originalProgramData = $env:ProgramData
}

AfterAll {
    $global:ModuleCoreOperatingSystems = $originalCatalogState
    $env:ProgramData = $originalProgramData
    Remove-Module $fixtureModule
}

Describe 'External USB operating system catalog indexing' {
    BeforeEach {
        $catalogRoot = Join-Path $fixtureRoot 'core\operatingsystems'
        $env:ProgramData = Join-Path $fixtureRoot 'programdata'
        $cacheRoot = Join-Path $env:ProgramData 'OSDeployCore\OSDCloud\core\operatingsystems'
        $usbDriveRoot = Join-Path $fixtureRoot 'usb'
        $usbRoot = Join-Path $fixtureRoot 'usb\OSDCloud\core\operatingsystems'
        foreach ($directory in @($catalogRoot, $env:ProgramData, $usbDriveRoot)) {
            if (Test-Path $directory) { Remove-Item $directory -Recurse -Force }
            $null = New-Item $directory -ItemType Directory -Force
        }
        $null = New-Item $usbRoot, $cacheRoot -ItemType Directory -Force
        $moduleXml = '<MCT><Catalogs><Catalog><PublishedMedia><Files><File><FileName>module.esd</FileName><LanguageCode>en-us</LanguageCode><Architecture>x64</Architecture><FilePath>https://example.invalid/module.esd</FilePath><Sha256>module-hash</Sha256></File></Files></PublishedMedia></Catalog></Catalogs></MCT>'
        $externalXml = $moduleXml.Replace('module.esd', 'usb.esd').Replace('module-hash', 'usb-hash')
        Mock Get-PSDrive -ModuleName CatalogIndexFixture { [pscustomobject]@{ Root = 'F:\' } }
        Mock Join-Path -ModuleName CatalogIndexFixture -ParameterFilter { $Path -eq 'F:\' } {
            Microsoft.PowerShell.Management\Join-Path $usbDriveRoot $ChildPath
        }
        Mock Test-Path -ModuleName CatalogIndexFixture -ParameterFilter { $LiteralPath -notlike "$fixtureRoot\*" } { $false }
        Mock Export-Clixml -ModuleName CatalogIndexFixture {}
        Mock Get-OSDCoreLicense -ModuleName CatalogIndexFixture { throw 'Indexing must not require a license' }
        Mock Get-Disk -ModuleName CatalogIndexFixture { throw 'Indexing must not require writable media' }
    }

    It 'indexes the USB destination without a license or writable-source requirement' {
        Set-Content (Join-Path $catalogRoot '26100.1.260101-1200.xml') $moduleXml
        $usbCatalog = Join-Path $usbRoot '26200.9999.261015-1200.xml'
        Set-Content $usbCatalog $externalXml
        $file = Get-Item $usbCatalog
        $file.IsReadOnly = $true
        try {
            Initialize-ModuleCoreOperatingSystems
            @($global:ModuleCoreOperatingSystems).Count | Should -Be 2
            $usbEntry = $global:ModuleCoreOperatingSystems | Where-Object FileName -eq 'usb.esd'
            $usbEntry.OSBuildVersion | Should -Be '26200.9999'
            $usbEntry.Sha256 | Should -Be 'usb-hash'
            Should -Invoke Join-Path -ModuleName CatalogIndexFixture -Times 1 -Exactly -ParameterFilter {
                $Path -eq 'F:\' -and $ChildPath -eq 'OSDCloud\core\operatingsystems'
            }
            Should -Invoke Get-OSDCoreLicense -ModuleName CatalogIndexFixture -Times 0 -Exactly
            Should -Invoke Get-Disk -ModuleName CatalogIndexFixture -Times 0 -Exactly
        }
        finally {
            $file.IsReadOnly = $false
        }
    }

    It 'indexes catalogs from the new ProgramData core directory' {
        Set-Content (Join-Path $catalogRoot '26200.9000.261001-1200.xml') $moduleXml
        Set-Content (Join-Path $cacheRoot '26200.9999.261015-1200.xml') $externalXml
        Initialize-ModuleCoreOperatingSystems
        @($global:ModuleCoreOperatingSystems).Count | Should -Be 1
        $global:ModuleCoreOperatingSystems.OSBuildVersion | Should -Be '26200.9999'
    }

    It 'ignores old USB and ProgramData catalog directories without migrating or deleting them' {
        Set-Content (Join-Path $catalogRoot '26200.9000.261001-1200.xml') $moduleXml
        $oldRoots = @(
            (Join-Path $usbDriveRoot 'OSDCloud\catalogs\operatingsystems')
            (Join-Path $env:ProgramData 'OSDeployCore\OSDCloud\catalogs\operatingsystems')
        )
        foreach ($root in $oldRoots) {
            $null = New-Item $root -ItemType Directory -Force
            Set-Content (Join-Path $root '26200.9999.261015-1200.xml') $externalXml
        }
        Initialize-ModuleCoreOperatingSystems
        @($global:ModuleCoreOperatingSystems).Count | Should -Be 1
        $global:ModuleCoreOperatingSystems.FileName | Should -Be 'module.esd'
        foreach ($root in $oldRoots) {
            Get-Content (Join-Path $root '26200.9999.261015-1200.xml') | Should -Be $externalXml
        }
        @(Get-ChildItem $usbRoot, $cacheRoot -File).Count | Should -Be 0
    }

    It 'selects the latest revision across module and USB catalogs' {
        Set-Content (Join-Path $catalogRoot '26200.9000.261001-1200.xml') $moduleXml
        Set-Content (Join-Path $usbRoot '26200.9999.261015-1200.xml') $externalXml
        Initialize-ModuleCoreOperatingSystems
        @($global:ModuleCoreOperatingSystems).Count | Should -Be 1
        $global:ModuleCoreOperatingSystems.FileName | Should -Be 'usb.esd'
        $global:ModuleCoreOperatingSystems.OSBuildVersion | Should -Be '26200.9999'
    }

    It 'prefers bundled catalogs when the USB has the same revision' {
        Set-Content (Join-Path $catalogRoot '26200.9999.261015-1200.xml') $moduleXml
        Set-Content (Join-Path $usbRoot '26200.9999.261015-1200.xml') $externalXml
        Initialize-ModuleCoreOperatingSystems
        @($global:ModuleCoreOperatingSystems).Count | Should -Be 1
        $global:ModuleCoreOperatingSystems.FileName | Should -Be 'module.esd'
    }

    It 'warns and keeps module entries when the USB catalog is malformed' {
        Set-Content (Join-Path $catalogRoot '26200.9999.261015-1200.xml') $moduleXml
        Set-Content (Join-Path $usbRoot '26200.10000.261015-1200.xml') '<invalid'
        Initialize-ModuleCoreOperatingSystems -WarningVariable warnings -WarningAction SilentlyContinue
        $global:ModuleCoreOperatingSystems.FileName | Should -Be 'module.esd'
        @($warnings).Count | Should -Be 1
    }
}
