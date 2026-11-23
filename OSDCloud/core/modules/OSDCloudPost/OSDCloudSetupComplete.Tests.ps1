Import-Module (Join-Path $PSScriptRoot 'OSDCloudPost.psd1') -Force

Describe 'Standalone OSDCloudPost contract' {
    It 'imports inertly and exports only the entry points with rendered help' {
        @(Get-Command -Module OSDCloudPost -CommandType Function).Name | Sort-Object |
            Should -Be @('Invoke-OSDCloudPreOOBE', 'Invoke-OSDCloudSetupComplete')
        @(Get-Command -Module OSDCloudPost -CommandType Alias).Name | Should -Be @('OSDCloudPreOOBE')
        (Get-Help Invoke-OSDCloudSetupComplete -Full).Examples.Example.Count | Should -Be 2
    }
}

InModuleScope OSDCloudPost {
    Describe 'SetupComplete runtime' {
        BeforeAll {
            '{"Warmup":"Load Windows PowerShell JSON assemblies before changing SystemRoot"}' | ConvertFrom-Json | Out-Null
            $script:realSystemRoot = $env:SystemRoot
            $script:testPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $script:startProcessCmdlet = Get-Command Start-Process -CommandType Cmdlet
            $script:exampleRoot = Join-Path $PSScriptRoot 'files\SetupComplete'
            function New-TestPackage {
                [CmdletBinding()]
                param (
                    [string]$Name = 'Package With Spaces',
                    [hashtable]$Manifest = @{ Version = 1; Script = 'Run.ps1' },
                    [string]$Body = "'success'"
                )
                $folder = Join-Path $TestDrive $Name
                [void][IO.Directory]::CreateDirectory($folder)
                [IO.File]::WriteAllText((Join-Path $folder 'OSDCloudSetupComplete.json'), ($Manifest | ConvertTo-Json -Depth 8))
                [IO.File]::WriteAllText((Join-Path $folder 'Run.ps1'), $Body)
                return $folder
            }
        }

        BeforeEach {
            $env:SystemRoot = Join-Path $TestDrive ("Windows-" + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($env:SystemRoot)
        }

        AfterEach { $env:SystemRoot = $script:realSystemRoot }

        Describe 'Configuration validation and device conditions' {
            It 'rejects WinPE before executing any packages' {
                $drive = $env:SystemDrive
                try {
                    $env:SystemDrive = 'X:'
                    { Assert-OSDCloudSetupCompleteContext } | Should -Throw '*full Windows*'
                }
                finally { $env:SystemDrive = $drive }
            }

            It 'rejects invalid configurations: <Label>' -TestCases @(
                @{ Label = 'version'; Data = @{ Version = 2; Script = 'Run.ps1' } }
                @{ Label = 'version type'; Data = @{ Version = '1'; Script = 'Run.ps1' } }
                @{ Label = 'script missing'; Data = @{ Version = 1 } }
                @{ Label = 'unknown field'; Data = @{ Version = 1; Script = 'Run.ps1'; DefaultSelected = $true } }
                @{ Label = 'enabled type'; Data = @{ Version = 1; Script = 'Run.ps1'; Enabled = 'false' } }
                @{ Label = 'copy type'; Data = @{ Version = 1; Script = 'Run.ps1'; CopyToLocal = 1 } }
                @{ Label = 'arguments type'; Data = @{ Version = 1; Script = 'Run.ps1'; Arguments = @() } }
                @{ Label = 'unknown condition'; Data = @{ Version = 1; Script = 'Run.ps1'; Conditions = @{ Model = '*' } } }
                @{ Label = 'empty patterns'; Data = @{ Version = 1; Script = 'Run.ps1'; Conditions = @{ ComputerModel = @() } } }
                @{ Label = 'unsupported architecture'; Data = @{ Version = 1; Script = 'Run.ps1'; Conditions = @{ OSArchitecture = 'x64' } } }
                @{ Label = 'script traversal'; Data = @{ Version = 1; Script = '..\Run.ps1' } }
                @{ Label = 'nested script'; Data = @{ Version = 1; Script = 'Sub\Run.ps1' } }
                @{ Label = 'rooted script'; Data = @{ Version = 1; Script = 'C:\Run.ps1' } }
                @{ Label = 'alternate stream'; Data = @{ Version = 1; Script = 'Run.ps1:other.ps1' } }
                @{ Label = 'missing script'; Data = @{ Version = 1; Script = 'Missing.ps1' } }
            ) {
                param ($Label, $Data)
                $folder = New-TestPackage -Manifest $Data
                { Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{} } | Should -Throw
            }

            It 'rejects malformed or non-object JSON without logging the original contents' {
                $folder = New-TestPackage
                foreach ($json in @('', '[{}]', '{"Arguments":"sensitive-value",')) {
                    [IO.File]::WriteAllText((Join-Path $folder 'OSDCloudSetupComplete.json'), $json)
                    try {
                        Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{}
                        throw 'Configuration unexpectedly accepted.'
                    }
                    catch { $_.Exception.Message | Should -Not -Match 'sensitive-value|unexpectedly accepted' }
                }
            }

            It 'uses AND across fields, OR across patterns, and native OS architecture' {
                Mock Get-CimInstance { [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'Latitude 7450' } }
                Mock Get-ItemPropertyValue { 'ARM64' }
                $folder = New-TestPackage -Manifest @{
                    Version = 1; Script = 'Run.ps1'; Conditions = @{
                        ComputerManufacturer = 'dell*'; ComputerModel = @('Precision*','Latitude 7*'); OSArchitecture = @('amd64','arm64')
                    }
                }
                $context = @{}
                (Read-OSDCloudSetupCompleteManifest -Folder $folder -Context $context).Path | Should -Be (Join-Path $folder 'Run.ps1')
                Read-OSDCloudSetupCompleteManifest -Folder $folder -Context $context | Should -Not -BeNullOrEmpty
                Should -Invoke Get-CimInstance -Times 1 -Exactly
                Should -Invoke Get-ItemPropertyValue -Times 1 -Exactly
                $context.ComputerSystem.Model = 'Other device'
                Read-OSDCloudSetupCompleteManifest -Folder $folder -Context $context | Should -BeNullOrEmpty
            }

            It 'skips disabled packages without querying device facts' {
                Mock Get-CimInstance { throw 'Must not query' }
                $folder = New-TestPackage -Manifest @{
                    Version = 1; Script = 'Run.ps1'; Enabled = $false; Conditions = @{ ComputerManufacturer = 'Dell*' }
                }
                Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{} | Should -BeNullOrEmpty
                Should -Invoke Get-CimInstance -Times 0
            }

            It 'fails explicitly when required facts are unavailable but accepts unconditional packages' {
                Mock Get-CimInstance { throw 'CIM unavailable' }
                $folder = New-TestPackage -Manifest @{ Version = 1; Script = 'Run.ps1'; Conditions = @{ ComputerModel = '*' } }
                { Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{} } | Should -Throw '*CIM unavailable*'
                $folder = New-TestPackage -Name 'Unconditional'
                Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{} | Should -Not -BeNullOrEmpty
            }

            It 'validates all five supplied examples with representative device facts' {
                $examples = @(Get-ChildItem -LiteralPath $script:exampleRoot -Filter 'Example-0*.json')
                $examples.Count | Should -Be 5
                foreach ($example in $examples) {
                    $folder = New-TestPackage -Name $example.BaseName
                    Copy-Item -LiteralPath $example.FullName -Destination (Join-Path $folder 'OSDCloudSetupComplete.json') -Force
                    Copy-Item -LiteralPath (Join-Path $script:exampleRoot 'Example-SetupComplete.ps1') -Destination $folder
                    $context = @{
                        ComputerSystem = [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'Latitude 7450' }
                        OSArchitecture = if ($example.Name -match 'Arm64') { 'ARM64' } else { 'AMD64' }
                    }
                    Read-OSDCloudSetupCompleteManifest -Folder $folder -Context $context | Should -Not -BeNullOrEmpty
                }
            }

            It 'rejects a package reached through a junction' {
                $folder = New-TestPackage -Name 'JunctionTarget'
                $link = Join-Path $TestDrive 'PackageLink'
                [void](New-Item -Path $link -ItemType Junction -Target $folder -ErrorAction Stop)
                try {
                    { Read-OSDCloudSetupCompleteManifest -Folder $link -Context @{} } | Should -Throw '*reparse point*'
                }
                finally { [IO.Directory]::Delete($link) }
            }
        }

        Describe 'Harmless real Windows PowerShell child processes' {
            BeforeEach {
                Mock Start-Process {
                    param ($FilePath, $ArgumentList, $WorkingDirectory, $NoNewWindow, $Wait, $PassThru,
                        $RedirectStandardOutput, $RedirectStandardError)
                    $testRoot = $env:SystemRoot
                    try {
                        $env:SystemRoot = $script:realSystemRoot
                        & $script:startProcessCmdlet -FilePath $script:testPowerShell -ArgumentList $ArgumentList `
                            -WorkingDirectory $WorkingDirectory -NoNewWindow -Wait -PassThru `
                            -RedirectStandardOutput $RedirectStandardOutput -RedirectStandardError $RedirectStandardError -ErrorAction Stop
                    }
                    finally { $env:SystemRoot = $testRoot }
                }
            }

            It 'preserves ScriptRoot, working directory, literal quoted arguments and relative content' {
                $body = @'
param([string]$Message)
$ErrorActionPreference = 'Stop'
"Root=$PSScriptRoot"
"Working=$((Get-Location).Path)"
"Content=$(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payload.txt') -Raw)"
"Message=$Message"
'@
                $folder = New-TestPackage -Body $body -Manifest @{
                    Version = 1; Script = 'Run.ps1'; Arguments = '-Message "two words; $(not evaluated) & literal"'
                }
                [IO.File]::WriteAllText((Join-Path $folder 'payload.txt'), 'supporting content')
                $package = Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{}
                Invoke-OSDCloudSetupCompletePackage -Package $package | Should -Be 0
                $output = Get-Content -LiteralPath (Get-ChildItem "$env:SystemRoot\Temp\osdcloud-logs\*.stdout.log").FullName -Raw
                $output | Should -Match ([regex]::Escape("Root=$folder"))
                $output | Should -Match ([regex]::Escape("Working=$folder"))
                $output | Should -Match 'Content=supporting content'
                $output | Should -Match ([regex]::Escape('Message=two words; $(not evaluated) & literal'))
                Get-Content "$env:SystemRoot\Temp\osdcloud-logs\OSDCloudSetupComplete.log" -Raw |
                    Should -Not -Match 'two words'
            }

            It 'captures stdout/stderr and preserves explicit exits without exiting the caller: <Code>' -TestCases @(
                @{ Code = 0 }, @{ Code = 7 }, @{ Code = 3010 }
            ) {
                param ($Code)
                $folder = New-TestPackage -Body "'output'; [Console]::Error.WriteLine('diagnostic'); exit $Code"
                $package = Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{}
                Invoke-OSDCloudSetupCompletePackage -Package $package | Should -Be $Code
                Get-Content (Get-ChildItem "$env:SystemRoot\Temp\osdcloud-logs\*.stdout.log").FullName -Raw | Should -Match 'output'
                Get-Content (Get-ChildItem "$env:SystemRoot\Temp\osdcloud-logs\*.stderr.log").FullName -Raw | Should -Match 'diagnostic'
                if ($Code -eq 3010) {
                    Get-Content "$env:SystemRoot\Temp\osdcloud-logs\OSDCloudSetupComplete.log" -Raw | Should -Match 'reboot required'
                }
            }

            It 'reports terminating script errors and rejects prompts noninteractively' {
                foreach ($body in @("throw 'fixture error'", "`$ErrorActionPreference = 'Stop'; Read-Host 'No prompt allowed'")) {
                    $folder = New-TestPackage -Body $body
                    $package = Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{}
                    Invoke-OSDCloudSetupCompletePackage -Package $package | Should -Not -Be 0
                }
            }

            It 'runs the supplied ARM64 local-copy example with its supporting JSON' {
                $folder = New-TestPackage -Name 'Arm64Example'
                foreach ($name in 'Example-SetupComplete.ps1','Example-Content.json') {
                    Copy-Item -LiteralPath (Join-Path $script:exampleRoot $name) -Destination $folder
                }
                Copy-Item -LiteralPath (Join-Path $script:exampleRoot 'Example-04-Arm64-Copy-Local.json') `
                    -Destination (Join-Path $folder 'OSDCloudSetupComplete.json') -Force
                $package = Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{ OSArchitecture = 'ARM64' }
                Invoke-OSDCloudSetupCompletePackage -Package $package | Should -Be 0
                $output = Get-Content (Get-ChildItem "$env:SystemRoot\Temp\osdcloud-logs\*.stdout.log").FullName -Raw
                $output | Should -Match 'Local ARM64 package: Supporting content was read'
                $output | Should -Match ([regex]::Escape("ScriptRoot=$env:SystemRoot\Temp\OSDCloudSetupComplete\Arm64Example"))
            }

            It 'does not substitute success after a child launch failure' {
                Mock Start-Process { throw 'Child launch failed fixture' }
                $folder = New-TestPackage
                $package = Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{}
                { Invoke-OSDCloudSetupCompletePackage -Package $package } | Should -Throw '*Child launch failed*'
            }

            It 'copies all content, clears only copied read-only flags, and retains unique copies across reruns' {
                $folder = New-TestPackage -Manifest @{ Version = 1; Script = 'Run.ps1'; CopyToLocal = $true } -Body @'
$ErrorActionPreference = 'Stop'
"Root=$PSScriptRoot"
Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Sub\payload.txt')
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'new.txt') -Value 'created'
'@
                [void][IO.Directory]::CreateDirectory((Join-Path $folder 'Sub'))
                $payload = Join-Path $folder 'Sub\payload.txt'
                [IO.File]::WriteAllText($payload, 'copied content')
                (Get-Item -LiteralPath $payload).IsReadOnly = $true
                try {
                    $package = Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{}
                    Invoke-OSDCloudSetupCompletePackage -Package $package | Should -Be 0
                    Invoke-OSDCloudSetupCompletePackage -Package $package | Should -Be 0
                    foreach ($name in @('Package With Spaces', 'Package With Spaces-2')) {
                        $copy = Join-Path $env:SystemRoot "Temp\OSDCloudSetupComplete\$name"
                        Get-Content -LiteralPath (Join-Path $copy 'Sub\payload.txt') | Should -Be 'copied content'
                        (Get-Item -LiteralPath (Join-Path $copy 'Sub\payload.txt')).IsReadOnly | Should -BeFalse
                        Test-Path -LiteralPath (Join-Path $copy 'new.txt') | Should -BeTrue
                    }
                    (Get-Item -LiteralPath $payload).IsReadOnly | Should -BeTrue
                    Test-Path -LiteralPath (Join-Path $folder 'new.txt') | Should -BeFalse
                    @(Get-ChildItem "$env:SystemRoot\Temp\osdcloud-logs\*.stdout.log").Count | Should -Be 2
                }
                finally { (Get-Item -LiteralPath $payload).IsReadOnly = $false }
            }

            It 'rejects reparse points in copied supporting content without launching' {
                $folder = New-TestPackage -Manifest @{ Version = 1; Script = 'Run.ps1'; CopyToLocal = $true }
                $target = Join-Path $TestDrive 'ContentTarget'
                [void][IO.Directory]::CreateDirectory($target)
                $link = Join-Path $folder 'LinkedContent'
                [void](New-Item -Path $link -ItemType Junction -Target $target -ErrorAction Stop)
                try {
                    $package = Read-OSDCloudSetupCompleteManifest -Folder $folder -Context @{}
                    { Invoke-OSDCloudSetupCompletePackage -Package $package } | Should -Throw '*reparse point*'
                    Should -Invoke Start-Process -Times 0
                }
                finally { [IO.Directory]::Delete($link) }
            }
        }

        Describe 'Entry point scheduling and aggregate status' {
            BeforeEach { Mock Assert-OSDCloudSetupCompleteContext {} }

            It 'lists local discovery first and A through Z after it' {
                $roots = @(Get-OSDCloudSetupCompleteRoot)
                $roots[0] | Should -Be (Join-Path $env:SystemRoot 'Setup\SetupComplete')
                $roots[1..26] | Should -Be @(65..90 | ForEach-Object { "$([char]$_):\OSDCloud\post\SetupComplete" })
            }

            It 'sorts within each root, continues failures, returns only a status, and reruns every time' {
                $firstRoot = Join-Path $TestDrive 'Local'
                $secondRoot = Join-Path $TestDrive 'External'
                [void](New-TestPackage -Name 'Local\020-Fails')
                [void](New-TestPackage -Name 'Local\025-Throws')
                [void](New-TestPackage -Name 'Local\010-First')
                [void](New-TestPackage -Name 'Local\030-Last')
                [void](New-TestPackage -Name 'External\000-External')
                [void](New-TestPackage -Name 'Local\005-Invalid' -Manifest @{ Version = 9; Script = 'Run.ps1' })
                [void](New-TestPackage -Name 'Local\001-Disabled' -Manifest @{ Version = 1; Script = 'Run.ps1'; Enabled = $false })
                Mock Get-OSDCloudSetupCompleteRoot { $firstRoot; $secondRoot }
                $script:executionOrder = @()
                Mock Invoke-OSDCloudSetupCompletePackage {
                    param ($Package)
                    $script:executionOrder += $Package.Name
                    if ($Package.Name -eq '020-Fails') { return 12 }
                    if ($Package.Name -eq '025-Throws') { throw 'Child launch failed fixture' }
                    return 0
                }
                @(Invoke-OSDCloudSetupComplete -WarningAction SilentlyContinue) | Should -Be @(1)
                $script:executionOrder | Should -Be @('010-First','020-Fails','025-Throws','030-Last','000-External')
                Invoke-OSDCloudSetupComplete -WarningAction SilentlyContinue | Should -Be 1
                $script:executionOrder.Count | Should -Be 10
            }

            It 'returns success for no eligible packages and for reboot-required success' {
                Mock Get-OSDCloudSetupCompleteRoot { Join-Path $TestDrive 'NoPackages' }
                Invoke-OSDCloudSetupComplete | Should -Be 0
                $folder = New-TestPackage -Name 'Eligible\One'
                Mock Get-OSDCloudSetupCompleteRoot { Split-Path -Path $folder -Parent }
                Mock Invoke-OSDCloudSetupCompletePackage { 3010 }
                Invoke-OSDCloudSetupComplete | Should -Be 0
            }

            It 'continues a later root after a root discovery failure' {
                $folder = New-TestPackage -Name 'GoodRoot\Package'
                $badRoot = Join-Path $TestDrive 'Unreadable'
                [void][IO.Directory]::CreateDirectory($badRoot)
                Mock Get-OSDCloudSetupCompleteRoot { $badRoot; Split-Path -Path $folder -Parent }
                Mock Get-ChildItem { throw 'Access denied fixture' } -ParameterFilter { $LiteralPath -eq $badRoot }
                Mock Invoke-OSDCloudSetupCompletePackage { 0 }
                Invoke-OSDCloudSetupComplete -WarningAction SilentlyContinue | Should -Be 1
                Should -Invoke Invoke-OSDCloudSetupCompletePackage -Times 1
            }

            It 'refuses a concurrent invocation while another process owns the execution mutex' {
                $ready = Join-Path $TestDrive 'MutexReady.txt'
                $child = @'
$mutex = [Threading.Mutex]::new($false, 'Global\RecastOSDCloud.SetupComplete')
try {
    if (-not $mutex.WaitOne(0)) { exit 2 }
    try {
        [IO.File]::WriteAllText('READY_PATH', 'ready')
        Start-Sleep -Seconds 3
    }
    finally { $mutex.ReleaseMutex() }
}
finally { $mutex.Dispose() }
'@
                $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
                        $child.Replace('READY_PATH', $ready.Replace("'", "''"))))
                $testRoot = $env:SystemRoot
                try {
                    $env:SystemRoot = $script:realSystemRoot
                    $process = & $script:startProcessCmdlet -FilePath $script:testPowerShell `
                        -ArgumentList "-NoProfile -NonInteractive -EncodedCommand $encoded" -NoNewWindow -PassThru
                }
                finally { $env:SystemRoot = $testRoot }
                try {
                    $deadline = [DateTime]::UtcNow.AddSeconds(10)
                    while (-not (Test-Path -LiteralPath $ready) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
                        Start-Sleep -Milliseconds 25
                    }
                    Test-Path -LiteralPath $ready | Should -BeTrue
                    Mock Get-OSDCloudSetupCompleteRoot { throw 'Must not discover packages' }
                    Invoke-OSDCloudSetupComplete 2>$null | Should -Be 1
                    Should -Invoke Get-OSDCloudSetupCompleteRoot -Times 0
                }
                finally { $process.WaitForExit(); $process.Dispose() }
            }

            It 'surfaces context and logging failures as nonzero status' {
                Mock Assert-OSDCloudSetupCompleteContext { throw 'Unsupported fixture context' }
                Invoke-OSDCloudSetupComplete 2>$null | Should -Be 1
                Mock Assert-OSDCloudSetupCompleteContext {}
                Mock Write-OSDCloudSetupCompleteLog { throw 'Log disk unavailable' }
                Invoke-OSDCloudSetupComplete 2>$null | Should -Be 1
            }
        }
    }
}
