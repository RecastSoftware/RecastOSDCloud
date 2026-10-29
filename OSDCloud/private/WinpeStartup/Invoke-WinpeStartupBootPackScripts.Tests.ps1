BeforeAll {
    . "$PSScriptRoot\Assert-OSDCloudBootPackManifest.ps1"
    . "$PSScriptRoot\Invoke-WinpeStartupBootPackScripts.ps1"
    function Test-WinpeStartupAssetLicense { $true }

    function New-TestImportPack {
        param ($Root, $Name, $Type = 'Import', [switch]$CorruptManifest)
        $id = [guid]::NewGuid().ToString()
        $source = Join-Path $TestDrive "src-$Name"
        $null = New-Item -ItemType Directory -Path (Join-Path $source 'scripts'), (Join-Path $source 'winpe-reg') -Force
        Set-Content -LiteralPath (Join-Path $source 'scripts\run.ps1') -Value "Set-Content -LiteralPath (Join-Path `$PWD 'ran-$Name.txt') -Value 'ps1'"
        Set-Content -LiteralPath (Join-Path $source 'scripts\run.cmd') -Value "@echo cmd> ran-cmd-$Name.txt"
        Set-Content -LiteralPath (Join-Path $source 'scripts\copy.ps1') -Value "Set-Content -LiteralPath (Join-Path `$PWD 'copied-$Name.txt') -Value 'no'"
        Set-Content -LiteralPath (Join-Path $source 'winpe-reg\proxy.reg') -Value 'Windows Registry Editor Version 5.00'
        $manifest = [ordered]@{
            schemaVersion = 1
            info          = [ordered]@{ id = $id; name = $Name; author = ''; description = ''; created = '2026-10-29T00:00:00'; modified = '2026-10-29T00:00:00' }
            type          = $Type
            architecture  = 'any'
            items         = @(
                [ordered]@{ source = 'winpe-reg/proxy.reg'; kind = 'Registry' }
                [ordered]@{ source = 'scripts/run.ps1'; kind = 'Script'; action = 'Execute' }
                [ordered]@{ source = 'scripts/run.cmd'; kind = 'Script'; action = 'Execute' }
                [ordered]@{ source = 'scripts/copy.ps1'; kind = 'Script'; action = 'Copy' }
            )
        }
        $manifestJson = $manifest | ConvertTo-Json -Depth 5
        Set-Content -LiteralPath (Join-Path $source 'bootpack.json') -Value $(if ($CorruptManifest) { ($manifestJson -replace $id, ([guid]::NewGuid().ToString())) } else { $manifestJson })
        $packPath = Join-Path $Root $id
        $null = New-Item -ItemType Directory -Path $packPath -Force
        $ddf = @(
            '.OPTION EXPLICIT', '.Set CabinetNameTemplate=bootpack.cab', ".Set DiskDirectoryTemplate=`"$packPath`"",
            '.Set Cabinet=on', '.Set Compress=on', '.Set MaxDiskSize=0', '.Set InfFileName=nul', '.Set RptFileName=nul', '.Set DestinationDir='
            "`"$(Join-Path $source 'bootpack.json')`" `"bootpack.json`""
            '.Set DestinationDir=winpe-reg', "`"$(Join-Path $source 'winpe-reg\proxy.reg')`" `"proxy.reg`""
            '.Set DestinationDir=scripts'
            "`"$(Join-Path $source 'scripts\run.ps1')`" `"run.ps1`"", "`"$(Join-Path $source 'scripts\run.cmd')`" `"run.cmd`"", "`"$(Join-Path $source 'scripts\copy.ps1')`" `"copy.ps1`""
        )
        $ddfPath = Join-Path $TestDrive "$Name.ddf"
        [IO.File]::WriteAllLines($ddfPath, $ddf, [Text.Encoding]::ASCII)
        $null = & makecab.exe /F $ddfPath
        $manifestJson | Set-Content -LiteralPath (Join-Path $packPath 'bootpack.json')
        [pscustomobject]@{ Id = $id; Path = $packPath }
    }
}

Describe 'Expand-WinpeStartupBootPack' -Skip:(-not (Get-Command makecab.exe -ErrorAction SilentlyContinue)) {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:destination = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $root -Force
        Mock Write-Warning { }
    }

    It 'expands valid Import Packs with a prefix and returns their paths' {
        $pack = New-TestImportPack -Root $root -Name 'Valid'
        $paths = @(Expand-WinpeStartupBootPack -Path $root -Destination $destination -Prefix 'bootpack-' -SystemDrive 'X:')
        $paths | Should -Be @(Join-Path $destination "bootpack-$($pack.Id)")
        Test-Path -LiteralPath (Join-Path $paths[0] 'winpe-reg\proxy.reg') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $paths[0] 'scripts\run.cmd') | Should -BeTrue
    }

    It 'does nothing outside WinPE or without a valid license' {
        $null = New-TestImportPack -Root $root -Name 'Gated'
        @(Expand-WinpeStartupBootPack -Path $root -Destination $destination -SystemDrive 'C:').Count | Should -Be 0
        Mock Test-WinpeStartupAssetLicense { $false }
        @(Expand-WinpeStartupBootPack -Path $root -Destination $destination -SystemDrive 'X:').Count | Should -Be 0
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'skips Build Packs and Packs whose embedded manifest does not match' {
        $null = New-TestImportPack -Root $root -Name 'BuildType' -Type Build
        $null = New-TestImportPack -Root $root -Name 'Mismatch' -CorruptManifest
        @(Expand-WinpeStartupBootPack -Path $root -Destination $destination -SystemDrive 'X:').Count | Should -Be 0
        Should -Invoke Write-Warning -Times 2 -Exactly
        @(Get-ChildItem -LiteralPath $destination -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'runs only Execute scripts from the expanded Pack folder' {
        $null = New-TestImportPack -Root $root -Name 'Run'
        $paths = @(Expand-WinpeStartupBootPack -Path $root -Destination $destination -SystemDrive 'X:')
        Invoke-WinpeStartupBootPackScripts -Path $paths
        Get-Content -LiteralPath (Join-Path $paths[0] 'scripts\ran-Run.txt') | Should -Be 'ps1'
        (Get-Content -LiteralPath (Join-Path $paths[0] 'scripts\ran-cmd-Run.txt')).Trim() | Should -Be 'cmd'
        Test-Path -LiteralPath (Join-Path $paths[0] 'scripts\copied-Run.txt') | Should -BeFalse
        Should -Invoke Write-Warning -Times 0 -Exactly
    }

    It 'accepts an empty path collection' {
        { Invoke-WinpeStartupBootPackScripts -Path @() } | Should -Not -Throw
    }
}
