BeforeAll {
    . "$PSScriptRoot\Get-OSDCoreDriverPackCatalogLenovo.ps1"
}

Describe 'Get-OSDCoreDriverPackCatalogLenovo checksum mapping' {
    It 'uses the MD5 attribute rather than the CRC attribute' {
        $catalogPath = Join-Path $TestDrive 'lenovo.xml'
        @'
<ModelList>
    <Model name="Test Model">
        <Types>
            <Type>TEST</Type>
        </Types>
        <SCCM os="win11" version="24H2" date="2026-01-01" crc="different-checksum" md5="0123456789abcdef0123456789abcdef">https://download.lenovo.com/test.exe</SCCM>
    </Model>
</ModelList>
'@ | Set-Content -Path $catalogPath

        $catalog = @(Get-OSDCoreDriverPackCatalogLenovo -LocalDriverPackCatalog $catalogPath)

        $catalog.Count | Should -Be 1
        $catalog[0].HashMD5 | Should -Be '0123456789abcdef0123456789abcdef'
    }
}
