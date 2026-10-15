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
}

AfterAll {
    $global:ModuleCoreOperatingSystems = $originalCatalogState
    Remove-Module $fixtureModule
}

Describe 'External USB operating system catalog indexing' {
    BeforeEach {
        $catalogRoot = Join-Path $fixtureRoot 'core\operatingsystems'
        $usbRoot = Join-Path $fixtureRoot 'usb\OSDCloud\catalogs\operatingsystems'
        foreach ($directory in @($catalogRoot, $usbRoot)) {
            if (Test-Path $directory) { Remove-Item $directory -Recurse -Force }
            $null = New-Item $directory -ItemType Directory -Force
        }
        $moduleXml = '<MCT><Catalogs><Catalog><PublishedMedia><Files><File><FileName>module.esd</FileName><LanguageCode>en-us</LanguageCode><Architecture>x64</Architecture><FilePath>https://example.invalid/module.esd</FilePath><Sha256>module-hash</Sha256></File></Files></PublishedMedia></Catalog></Catalogs></MCT>'
        $externalXml = $moduleXml.Replace('module.esd', 'usb.esd').Replace('module-hash', 'usb-hash')
        Mock Get-PSDrive -ModuleName CatalogIndexFixture { [pscustomobject]@{ Root = 'F:\' } }
        Mock Join-Path -ModuleName CatalogIndexFixture -ParameterFilter { $Path -eq 'F:\' } { $usbRoot }
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
                $Path -eq 'F:\' -and $ChildPath -eq 'OSDCloud\catalogs\operatingsystems'
            }
            Should -Invoke Get-OSDCoreLicense -ModuleName CatalogIndexFixture -Times 0 -Exactly
            Should -Invoke Get-Disk -ModuleName CatalogIndexFixture -Times 0 -Exactly
        }
        finally {
            $file.IsReadOnly = $false
        }
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
