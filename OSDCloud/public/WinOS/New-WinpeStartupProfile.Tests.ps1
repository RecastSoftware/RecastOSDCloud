BeforeAll {
    . "$PSScriptRoot\New-WinpeStartupProfile.ps1"
    . "$PSScriptRoot\..\WinPE\Invoke-WinpeStartup.ps1"
    $script:bootAssetsPath = 'C:\ProgramData\OSDeployCore\boot-assets\winpestartup-profiles'
    if (-not ('WinpeStartupProfileTests.DecliningHost' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;

namespace WinpeStartupProfileTests {
    public sealed class DecliningHost : PSHost {
        private readonly PSHost inner;
        private readonly DecliningUI ui;
        public DecliningHost(PSHost inner) { this.inner = inner; ui = new DecliningUI(inner.UI); }
        public int PromptCount { get { return ui.PromptCount; } }
        public override Guid InstanceId { get { return inner.InstanceId; } }
        public override string Name { get { return "DecliningProfileTestHost"; } }
        public override Version Version { get { return inner.Version; } }
        public override CultureInfo CurrentCulture { get { return inner.CurrentCulture; } }
        public override CultureInfo CurrentUICulture { get { return inner.CurrentUICulture; } }
        public override PSHostUserInterface UI { get { return ui; } }
        public override void SetShouldExit(int code) { throw new NotSupportedException(); }
        public override void EnterNestedPrompt() { throw new NotSupportedException(); }
        public override void ExitNestedPrompt() { throw new NotSupportedException(); }
        public override void NotifyBeginApplication() { inner.NotifyBeginApplication(); }
        public override void NotifyEndApplication() { inner.NotifyEndApplication(); }
    }
    public sealed class DecliningUI : PSHostUserInterface {
        private readonly PSHostUserInterface inner;
        public DecliningUI(PSHostUserInterface inner) { this.inner = inner; }
        public int PromptCount { get; private set; }
        public override PSHostRawUserInterface RawUI { get { return inner.RawUI; } }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
            PromptCount++;
            for (int i = 0; i < choices.Count; i++) {
                if (choices[i].Label.Replace("&", "") == "No") { return i; }
            }
            throw new InvalidOperationException("Expected a No confirmation choice.");
        }
        public override string ReadLine() { throw new NotSupportedException(); }
        public override SecureString ReadLineAsSecureString() { throw new NotSupportedException(); }
        public override System.Collections.Generic.Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> fields) { throw new NotSupportedException(); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName) { throw new NotSupportedException(); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes types, PSCredentialUIOptions options) { throw new NotSupportedException(); }
        public override void Write(string value) { inner.Write(value); }
        public override void Write(ConsoleColor foreground, ConsoleColor background, string value) { inner.Write(foreground, background, value); }
        public override void WriteLine(string value) { inner.WriteLine(value); }
        public override void WriteErrorLine(string value) { inner.WriteErrorLine(value); }
        public override void WriteDebugLine(string value) { inner.WriteDebugLine(value); }
        public override void WriteVerboseLine(string value) { inner.WriteVerboseLine(value); }
        public override void WriteWarningLine(string value) { inner.WriteWarningLine(value); }
        public override void WriteProgress(long sourceId, ProgressRecord record) { inner.WriteProgress(sourceId, record); }
    }
}
'@
    }
}

Describe 'New-WinpeStartupProfile' {
    BeforeEach {
        $script:bootExists = $false
        $script:elevated = $true
        $script:testRoot = [System.IO.Path]::Combine($TestDrive, [guid]::NewGuid().ToString('N'))
        $script:bootRoot = [System.IO.Path]::Combine($script:testRoot, 'BootAssets')
        $script:volumes = @([pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'F' })
        $script:disk = [pscustomobject]@{ BusType = 'USB'; IsReadOnly = $false; IsOffline = $false }
        $script:partition = [pscustomobject]@{ DiskNumber = 7; IsReadOnly = $false; IsOffline = $false }
        Mock Test-Path { $script:bootExists } -ParameterFilter { $LiteralPath -eq $script:bootAssetsPath }
        Mock Join-Path {
            [System.IO.Path]::Combine($script:bootRoot, $ChildPath)
        } -ParameterFilter { $Path -eq $script:bootAssetsPath }
        Mock Join-Path {
            [System.IO.Path]::Combine($script:testRoot, "USB-$($Path.Substring(0, 1))", $ChildPath)
        } -ParameterFilter { $Path -match '^[A-Z]:\\$' }
        Mock Get-Volume { $script:volumes }
        Mock Get-Partition { $script:partition }
        Mock Get-Disk { $script:disk }
        Mock Start-Process {}
        Mock New-Object {
            $principal = [pscustomobject]@{}
            $principal | Add-Member -MemberType ScriptMethod -Name IsInRole -Value { $script:elevated }
            $principal
        } -ParameterFilter { $TypeName -eq 'System.Security.Principal.WindowsPrincipal' }
    }

    It 'exposes every runtime setting with the same type and error-action validation' {
        $runtime = Get-Command Invoke-WinpeStartup
        $author = Get-Command New-WinpeStartupProfile
        $common = [System.Management.Automation.PSCmdlet]::CommonParameters
        $settings = @($runtime.Parameters.Keys | Where-Object { $_ -notin $common })
        $settings.Count | Should -Be 16
        foreach ($name in $settings) {
            $author.Parameters[$name].ParameterType | Should -Be $runtime.Parameters[$name].ParameterType
            if ($name -like '*EA') {
                ($author.Parameters[$name].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues |
                    Should -Be @('Continue', 'Stop')
            }
        }
    }

    It 'writes all 16 settings using exact names and native JSON types without authoring or common parameters' {
        $settings = @{
            ProfileName = 'AllSettings'
            SkipOnScreenKeyboard = $true
            ShowPnpDevices = $false
            ShowPnpErrors = $true
            SkipWiFi = $false
            SkipIPConfig = $true
            SkipUpdateOSDCloud = $false
            InstallModule = @('ModuleOne', 'ModuleTwo')
            InvokeStartupCommand = @('Write-Output preparation', 'https://example.invalid/start.ps1')
            InvokeStartupCommandNoExit = $true
            InvokeStartupCommandEA = 'Stop'
            InvokeMainCommand = @('Write-Output main')
            InvokeMainCommandNoExit = $false
            InvokeMainCommandEA = 'Continue'
            InvokeShutdownCommand = @()
            InvokeShutdownCommandNoExit = $true
            InvokeShutdownCommandEA = 'Stop'
            PassThru = $true
            Force = $true
            Confirm = $false
            Verbose = $false
            ErrorAction = 'Stop'
        }
        $file = New-WinpeStartupProfile @settings
        $file | Should -BeOfType ([System.IO.FileInfo])
        $file.FullName | Should -Be ([System.IO.Path]::Combine($script:testRoot, 'USB-F', 'WinpeStartup', 'Profiles', 'AllSettings', 'winpestartup.json'))
        $savedSettings = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        @($savedSettings.PSObject.Properties).Count | Should -Be 17
        foreach ($name in @('SkipOnScreenKeyboard', 'ShowPnpDevices', 'ShowPnpErrors', 'SkipWiFi', 'SkipIPConfig', 'SkipUpdateOSDCloud',
            'InvokeStartupCommandNoExit', 'InvokeMainCommandNoExit', 'InvokeShutdownCommandNoExit')) {
            $savedSettings."Invoke-WinpeStartup:$name" | Should -BeOfType ([bool])
            $savedSettings."Invoke-WinpeStartup:$name" | Should -Be $settings[$name]
        }
        foreach ($name in @('InstallModule', 'InvokeStartupCommand', 'InvokeMainCommand', 'InvokeShutdownCommand')) {
            $savedSettings."Invoke-WinpeStartup:$name".GetType().IsArray | Should -BeTrue
            $savedSettings."Invoke-WinpeStartup:$name" | Should -Be $settings[$name]
        }
        foreach ($name in @('InvokeStartupCommandEA', 'InvokeMainCommandEA', 'InvokeShutdownCommandEA')) {
            $savedSettings."Invoke-WinpeStartup:$name" | Should -Be $settings[$name]
        }
    }

    It 'includes unspecified defaults and preserves explicit false' {
        $file = New-WinpeStartupProfile -ProfileName 'ExplicitFalse' -InvokeMainCommandNoExit:$false -PassThru
        $savedSettings = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        @($savedSettings.PSObject.Properties).Count | Should -Be 17
        $savedSettings.'Invoke-WinpeStartup:InvokeMainCommandNoExit' | Should -BeFalse
    }

    It 'preserves non-ASCII commands through the runtime Get-Content path' {
        $command = "Write-Output 'caf$([char]0x00e9)'"
        $file = New-WinpeStartupProfile -ProfileName 'Unicode' -InvokeMainCommand $command -PassThru
        $savedSettings = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $savedSettings.'Invoke-WinpeStartup:InvokeMainCommand'[0] | Should -BeExactly $command
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        @($bytes[0..2]) | Should -Be @(239, 187, 191)
    }

    It 'creates a complete profile matching bundled OSDCloud defaults with no success-stream output' {
        @(New-WinpeStartupProfile -ProfileName 'Empty').Count | Should -Be 0
        $path = [System.IO.Path]::Combine($script:testRoot, 'USB-F', 'WinpeStartup', 'Profiles', 'Empty', 'winpestartup.json')
        $savedSettings = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $defaults = Get-Content -LiteralPath "$PSScriptRoot\..\..\core\PSDefaultParameterValues.json" -Raw | ConvertFrom-Json
        $bundled = Get-Content -LiteralPath "$PSScriptRoot\..\..\core\winpestartup-profiles\OSDCloud\winpestartup.json" -Raw | ConvertFrom-Json
        @($savedSettings.PSObject.Properties).Count | Should -Be 17
        foreach ($property in $defaults.PSObject.Properties) {
            $expected = $property.Value
            if ($bundled.PSObject.Properties[$property.Name]) {
                $expected = $bundled.($property.Name)
            }
            $savedSettings.($property.Name) | Should -Be $expected
        }
        $savedSettings.Environment.WINPESTARTUP_AUTHOR | Should -BeExactly ([System.Environment]::UserName)
        $savedSettings.Environment.WINPESTARTUP_PROFILE | Should -BeExactly 'Empty'
        $savedSettings.PSObject.Properties.Name | Should -Be @(
            'Environment'
            'Invoke-WinpeStartup:ShowPnpDevices'
            'Invoke-WinpeStartup:ShowPnpErrors'
            'Invoke-WinpeStartup:SkipOnScreenKeyboard'
            'Invoke-WinpeStartup:SkipWiFi'
            'Invoke-WinpeStartup:SkipIPConfig'
            'Invoke-WinpeStartup:SkipUpdateOSDCloud'
            'Invoke-WinpeStartup:InstallModule'
            'Invoke-WinpeStartup:InvokeStartupCommand'
            'Invoke-WinpeStartup:InvokeStartupCommandEA'
            'Invoke-WinpeStartup:InvokeStartupCommandNoExit'
            'Invoke-WinpeStartup:InvokeMainCommand'
            'Invoke-WinpeStartup:InvokeMainCommandEA'
            'Invoke-WinpeStartup:InvokeMainCommandNoExit'
            'Invoke-WinpeStartup:InvokeShutdownCommand'
            'Invoke-WinpeStartup:InvokeShutdownCommandEA'
            'Invoke-WinpeStartup:InvokeShutdownCommandNoExit'
        )
        $savedSettings.Environment.PSObject.Properties.Name | Should -Be @('WINPESTARTUP_AUTHOR', 'WINPESTARTUP_PROFILE')
        $script:expectedEditorPath = $path
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'notepad.exe' -and $ArgumentList -eq "`"$script:expectedEditorPath`""
        }
    }

    It 'normalizes error-action values to canonical runtime values' {
        $file = New-WinpeStartupProfile -ProfileName 'Canonical' -InvokeMainCommandEA stop -InvokeShutdownCommandEA continue -PassThru
        $savedSettings = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $savedSettings.'Invoke-WinpeStartup:InvokeMainCommandEA' | Should -BeExactly 'Stop'
        $savedSettings.'Invoke-WinpeStartup:InvokeShutdownCommandEA' | Should -BeExactly 'Continue'
    }

    It 'stores scalar environment values without changing the author environment' {
        $original = [System.Environment]::GetEnvironmentVariable('OSDCLOUD_PROFILE_AUTHOR_TEST', 'Process')
        $file = New-WinpeStartupProfile -ProfileName 'Environment' -Environment @{
            OSDCLOUD_PROFILE_AUTHOR_TEST = 'site'
            Ring = 2
            Interactive = $true
            Fraction = [decimal]1.25
            Empty = ''
        } -PassThru
        $savedSettings = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        @($savedSettings.PSObject.Properties).Count | Should -Be 17
        $savedSettings.Environment.OSDCLOUD_PROFILE_AUTHOR_TEST | Should -Be 'site'
        $savedSettings.Environment.Ring | Should -Be 2
        $savedSettings.Environment.Interactive | Should -BeOfType ([bool])
        $savedSettings.Environment.Fraction | Should -Be 1.25
        $savedSettings.Environment.Empty | Should -BeExactly ''
        [System.Environment]::GetEnvironmentVariable('OSDCLOUD_PROFILE_AUTHOR_TEST', 'Process') | Should -Be $original
    }

    It 'retains generated metadata when Environment is explicitly empty' {
        $file = New-WinpeStartupProfile -ProfileName 'EmptyEnvironment' -Environment @{} -PassThru
        $savedSettings = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $savedSettings.PSObject.Properties.Name | Should -Contain 'Environment'
        $savedSettings.Environment | Should -BeOfType ([pscustomobject])
        @($savedSettings.Environment.PSObject.Properties).Count | Should -Be 2
        $savedSettings.Environment.WINPESTARTUP_AUTHOR | Should -BeExactly ([System.Environment]::UserName)
        $savedSettings.Environment.WINPESTARTUP_PROFILE | Should -BeExactly 'EmptyEnvironment'
    }

    It 'overrides supplied metadata without modifying the caller hashtable' {
        $environmentValues = @{
            WINPESTARTUP_AUTHOR = 'OtherUser'
            WINPESTARTUP_PROFILE = 'OtherProfile'
            Site = 'BranchOffice'
        }
        $file = New-WinpeStartupProfile -ProfileName 'ActualProfile' -Environment $environmentValues -PassThru
        $savedSettings = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $savedSettings.Environment.WINPESTARTUP_AUTHOR | Should -BeExactly ([System.Environment]::UserName)
        $savedSettings.Environment.WINPESTARTUP_PROFILE | Should -BeExactly 'ActualProfile'
        $savedSettings.Environment.Site | Should -BeExactly 'BranchOffice'
        $environmentValues.WINPESTARTUP_AUTHOR | Should -BeExactly 'OtherUser'
        $environmentValues.WINPESTARTUP_PROFILE | Should -BeExactly 'OtherProfile'
    }

    It 'rejects invalid folder name <Name> before discovery or writes' -ForEach @(
        @{ Name = '.' }, @{ Name = '..' }, @{ Name = 'C:\Profile' },
        @{ Name = 'Parent\Child' }, @{ Name = 'Parent/Child' }, @{ Name = ' ' },
        @{ Name = 'Trailing.' }, @{ Name = 'Trailing ' }, @{ Name = 'CON' },
        @{ Name = 'nul.json' }, @{ Name = 'COM1' }, @{ Name = 'LPT9.txt' },
        @{ Name = 'CONIN$' }, @{ Name = 'CONOUT$' }, @{ Name = ('a' * 256) },
        @{ Name = 'Wild*Card' }, @{ Name = 'Wild?Card' }, @{ Name = 'Control' + [char]1 }
    ) {
        { New-WinpeStartupProfile -ProfileName $Name } | Should -Throw '*single valid Windows folder name*'
        Should -Invoke Get-Volume -Times 0 -Exactly
    }

    It 'rejects invalid array setting <Setting>' -ForEach @(
        @{ Setting = 'InstallModule'; Value = $null },
        @{ Setting = 'InvokeStartupCommand'; Value = @('') },
        @{ Setting = 'InvokeMainCommand'; Value = @('valid', ' ') },
        @{ Setting = 'InvokeShutdownCommand'; Value = @($null) }
    ) {
        $arguments = @{ ProfileName = 'Invalid'; $Setting = $Value }
        { New-WinpeStartupProfile @arguments } | Should -Throw '*array of non-empty strings*'
        Should -Invoke Get-Volume -Times 0 -Exactly
    }

    It 'rejects unsupported error-action settings before discovery' {
        { New-WinpeStartupProfile -ProfileName 'InvalidEA' -InvokeMainCommandEA Ignore } | Should -Throw
        Should -Invoke Get-Volume -Times 0 -Exactly
    }

    It 'rejects invalid environment entry <Case> before discovery' -ForEach @(
        @{ Case = 'null'; Value = @{ Site = $null } },
        @{ Case = 'array'; Value = @{ Site = @('one') } },
        @{ Case = 'object'; Value = @{ Site = @{ Nested = 'one' } } },
        @{ Case = 'date'; Value = @{ Site = [datetime]'2026-01-01' } },
        @{ Case = 'NaN'; Value = @{ Site = [double]::NaN } },
        @{ Case = 'infinity'; Value = @{ Site = [single]::PositiveInfinity } },
        @{ Case = 'enum'; Value = @{ Site = [System.DayOfWeek]::Monday } },
        @{ Case = 'equals in name'; Value = @{ 'Bad=Name' = 'site' } },
        @{ Case = 'empty name'; Value = @{ '' = 'site' } },
        @{ Case = 'non-string name'; Value = @{ 42 = 'site' } },
        @{ Case = 'null character in name'; Value = @{ ("Bad" + [char]0) = 'site' } }
    ) {
        { New-WinpeStartupProfile -ProfileName 'InvalidEnvironment' -Environment $Value } | Should -Throw '*Environment variable*'
        Should -Invoke Get-Volume -Times 0 -Exactly
    }

    It 'saves identical content to Boot-Assets and multiple actual USB drive letters' {
        $script:bootExists = $true
        $script:volumes = @(
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'H' }
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'Q' }
        )
        $files = @(New-WinpeStartupProfile -ProfileName 'Multiple' -InvokeMainCommand 'Write-Output ready' -PassThru)
        $files.Count | Should -Be 3
        $files[0].FullName | Should -Be ([System.IO.Path]::Combine($script:bootRoot, 'Multiple', 'winpestartup.json'))
        $files[1].FullName | Should -Match '\\USB-H\\'
        $files[2].FullName | Should -Match '\\USB-Q\\'
        (Get-Content -LiteralPath $files[0].FullName -Raw) | Should -BeExactly (Get-Content -LiteralPath $files[1].FullName -Raw)
        (Get-Content -LiteralPath $files[0].FullName -Raw) | Should -BeExactly (Get-Content -LiteralPath $files[2].FullName -Raw)
        Should -Invoke Start-Process -Times 3 -Exactly -ParameterFilter { $FilePath -eq 'notepad.exe' }
    }

    It 'does not create a missing Boot-Assets root or require elevation for USB' {
        $script:elevated = $false
        New-WinpeStartupProfile -ProfileName 'USBOnly'
        Test-Path -LiteralPath $script:bootRoot | Should -BeFalse
        Should -Invoke New-Object -Times 0 -Exactly -ParameterFilter { $TypeName -eq 'System.Security.Principal.WindowsPrincipal' }
    }

    It 'reports insufficient elevation for Boot-Assets but still saves to USB' {
        $script:bootExists = $true
        $script:elevated = $false
        $files = @(New-WinpeStartupProfile -ProfileName 'NonAdmin' -PassThru -ErrorAction SilentlyContinue -ErrorVariable saveErrors)
        $files.Count | Should -Be 1
        $files[0].FullName | Should -Match '\\USB-F\\'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -like '*USB-F*' }
        @($saveErrors | Where-Object { $_.FullyQualifiedErrorId -like 'WinpeStartupProfileSaveFailed*' }).Count | Should -Be 1
        $saveErrors.Exception.Message | Should -Contain "Administrator rights are required to save '$([System.IO.Path]::Combine($script:bootRoot, 'NonAdmin', 'winpestartup.json'))'. Run PowerShell as administrator."
        Test-Path -LiteralPath $script:bootRoot | Should -BeFalse
    }

    It 'stops at the first save failure when ErrorAction Stop is requested' {
        $script:bootExists = $true
        $script:elevated = $false
        { New-WinpeStartupProfile -ProfileName 'StopOnFailure' -ErrorAction Stop } | Should -Throw '*Administrator rights*'
        Test-Path -LiteralPath ([System.IO.Path]::Combine($script:testRoot, 'USB-F')) | Should -BeFalse
    }

    It 'ignores partial labels and volumes without a drive letter' {
        $script:volumes = @(
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud-Data'; DriveLetter = 'F' }
            [pscustomobject]@{ FileSystemLabel = 'NotOSDCloud'; DriveLetter = 'H' }
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = $null }
        )
        { New-WinpeStartupProfile -ProfileName 'NoMatch' } | Should -Throw '*No usable destinations*'
        Should -Invoke Get-Partition -Times 0 -Exactly
    }

    It 'excludes non-USB volumes' {
        $script:disk.BusType = 'NVMe'
        { New-WinpeStartupProfile -ProfileName 'LocalDisk' } | Should -Throw '*No usable destinations*'
        Test-Path -LiteralPath ([System.IO.Path]::Combine($script:testRoot, 'USB-F')) | Should -BeFalse
    }

    It 'excludes unavailable media: <Case>' -ForEach @(
        @{ Case = 'read-only disk'; ObjectName = 'disk'; Property = 'IsReadOnly' },
        @{ Case = 'offline disk'; ObjectName = 'disk'; Property = 'IsOffline' },
        @{ Case = 'read-only partition'; ObjectName = 'partition'; Property = 'IsReadOnly' },
        @{ Case = 'offline partition'; ObjectName = 'partition'; Property = 'IsOffline' }
    ) {
        (Get-Variable -Name $ObjectName -Scope Script -ValueOnly).$Property = $true
        Mock Write-Warning {}
        { New-WinpeStartupProfile -ProfileName 'Unavailable' } | Should -Throw '*No usable destinations*'
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'read-only OSDCloud USB volume' }
        Test-Path -LiteralPath ([System.IO.Path]::Combine($script:testRoot, 'USB-F')) | Should -BeFalse
    }

    It 'reports volume discovery failure but saves to Boot-Assets when available' {
        $script:bootExists = $true
        Mock Get-Volume { throw 'Storage discovery failed' }
        $file = New-WinpeStartupProfile -ProfileName 'DiscoveryFailure' -PassThru -ErrorAction SilentlyContinue -ErrorVariable discoveryErrors
        $file.FullName | Should -Be ([System.IO.Path]::Combine($script:bootRoot, 'DiscoveryFailure', 'winpestartup.json'))
        $discoveryErrors.Exception.Message | Should -Contain 'Storage discovery failed'
    }

    It 'reports Boot-Assets discovery failure but still saves to USB' {
        Mock Test-Path { throw 'Boot-Assets discovery denied' } -ParameterFilter { $LiteralPath -eq $script:bootAssetsPath }
        $file = New-WinpeStartupProfile -ProfileName 'BootDiscoveryFailure' -PassThru -ErrorAction SilentlyContinue -ErrorVariable discoveryErrors
        $file.FullName | Should -Match '\\USB-F\\'
        $discoveryErrors.Exception.Message | Should -Contain 'Boot-Assets discovery denied'
    }

    It 'reports per-volume discovery failure and still processes the next volume' {
        $script:volumes = @(
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'F' }
            [pscustomobject]@{ FileSystemLabel = 'OSDCloud'; DriveLetter = 'H' }
        )
        Mock Get-Partition { throw 'Partition discovery failed' } -ParameterFilter { $DriveLetter -eq 'F' }
        $file = New-WinpeStartupProfile -ProfileName 'PartitionFailure' -PassThru -ErrorAction SilentlyContinue -ErrorVariable discoveryErrors
        $file.FullName | Should -Match '\\USB-H\\'
        $discoveryErrors.Exception.Message | Should -Contain 'Partition discovery failed'
    }

    It 'reports actual filesystem failure and still saves to another destination' {
        $script:bootExists = $true
        $null = New-Item -Path $script:bootRoot -ItemType Directory -Force
        $null = New-Item -Path ([System.IO.Path]::Combine($script:bootRoot, 'Blocked')) -ItemType File
        $file = New-WinpeStartupProfile -ProfileName 'Blocked' -PassThru -ErrorAction SilentlyContinue -ErrorVariable saveErrors
        $file.FullName | Should -Match '\\USB-F\\'
        @($saveErrors | Where-Object { $_.FullyQualifiedErrorId -like 'WinpeStartupProfileSaveFailed*' }).Count | Should -Be 1
    }

    It 'refuses overwrite and leaves existing content unchanged' {
        $file = New-WinpeStartupProfile -ProfileName 'Existing' -SkipWiFi -PassThru
        $original = Get-Content -LiteralPath $file.FullName -Raw
        { New-WinpeStartupProfile -ProfileName 'Existing' -SkipIPConfig -ErrorAction Stop } | Should -Throw '*Use -Force*'
        (Get-Content -LiteralPath $file.FullName -Raw) | Should -BeExactly $original
        @(Get-ChildItem -LiteralPath $file.DirectoryName -Filter '*.tmp').Count | Should -Be 0
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It 'replaces existing content with Force and removes temporary files' {
        $file = New-WinpeStartupProfile -ProfileName 'Replace' -SkipWiFi -PassThru
        New-WinpeStartupProfile -ProfileName 'Replace' -SkipIPConfig -Force
        $savedSettings = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        @($savedSettings.PSObject.Properties).Count | Should -Be 17
        $savedSettings.'Invoke-WinpeStartup:SkipIPConfig' | Should -BeTrue
        $savedSettings.'Invoke-WinpeStartup:SkipWiFi' | Should -BeFalse
        @(Get-ChildItem -LiteralPath $file.DirectoryName -Filter '*.tmp').Count | Should -Be 0
    }

    It 'preserves the old file and cleans temporary files after a failed replacement' {
        $file = New-WinpeStartupProfile -ProfileName 'Locked' -SkipWiFi -PassThru
        $original = Get-Content -LiteralPath $file.FullName -Raw
        $lock = [System.IO.File]::Open($file.FullName, 'Open', 'Read', 'None')
        try {
            { New-WinpeStartupProfile -ProfileName 'Locked' -SkipIPConfig -Force -ErrorAction Stop } | Should -Throw
        }
        finally {
            $lock.Dispose()
        }
        (Get-Content -LiteralPath $file.FullName -Raw) | Should -BeExactly $original
        @(Get-ChildItem -LiteralPath $file.DirectoryName -Filter '*.tmp').Count | Should -Be 0
    }

    It 'errors when no save succeeds and cleans temporary files after publication fails' {
        $directory = [System.IO.Path]::Combine($script:testRoot, 'USB-F', 'WinpeStartup', 'Profiles', 'BlockedTarget')
        $null = New-Item -Path ([System.IO.Path]::Combine($directory, 'winpestartup.json')) -ItemType Directory -Force
        { New-WinpeStartupProfile -ProfileName 'BlockedTarget' -Force -ErrorAction SilentlyContinue } | Should -Throw '*No profile was saved*'
        Test-Path -LiteralPath ([System.IO.Path]::Combine($directory, 'winpestartup.json')) -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $directory -Filter '*.tmp').Count | Should -Be 0
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'reports Notepad launch failure separately without losing the saved profile' {
        Mock Start-Process { throw 'Notepad unavailable' }
        $file = New-WinpeStartupProfile -ProfileName 'EditorFailure' -PassThru -ErrorAction SilentlyContinue -ErrorVariable editorErrors
        $file.Exists | Should -BeTrue
        @($editorErrors | Where-Object { $_.FullyQualifiedErrorId -like 'WinpeStartupProfileEditorFailed*' }).Count | Should -Be 1
        $editorErrors.Exception.Message | Should -Contain 'Notepad unavailable'
        (Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json).'Invoke-WinpeStartup:InvokeMainCommand' |
            Should -Be @('Show-OSDCloudDeviceInfo', 'Deploy-OSDCloud')
    }

    It 'does not write or open an editor if bundled defaults cannot be read' {
        Mock Get-Content { throw 'Bundled profile unavailable' } -ParameterFilter { $LiteralPath -like '*winpestartup-profiles\OSDCloud\winpestartup.json' }
        { New-WinpeStartupProfile -ProfileName 'MissingDefaults' } | Should -Throw '*Bundled profile unavailable*'
        Should -Invoke Get-Volume -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'does not mutate any destination with WhatIf, even with Force and missing elevation' {
        $script:bootExists = $true
        $script:elevated = $false
        @(New-WinpeStartupProfile -ProfileName 'Preview' -SkipWiFi -Force -PassThru -WhatIf).Count | Should -Be 0
        Test-Path -LiteralPath $script:bootRoot | Should -BeFalse
        Test-Path -LiteralPath ([System.IO.Path]::Combine($script:testRoot, 'USB-F')) | Should -BeFalse
        Should -Invoke New-Object -Times 0 -Exactly -ParameterFilter { $TypeName -eq 'System.Security.Principal.WindowsPrincipal' }
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'does not replace an existing profile under WhatIf' {
        $file = New-WinpeStartupProfile -ProfileName 'PreviewExisting' -SkipWiFi -PassThru
        $original = Get-Content -LiteralPath $file.FullName -Raw
        New-WinpeStartupProfile -ProfileName 'PreviewExisting' -SkipIPConfig -Force -WhatIf
        (Get-Content -LiteralPath $file.FullName -Raw) | Should -BeExactly $original
        @(Get-ChildItem -LiteralPath $file.DirectoryName -Filter '*.tmp').Count | Should -Be 0
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It 'does not create files when confirmation is declined, even with Force' {
        $decliningHost = [WinpeStartupProfileTests.DecliningHost]::new($Host)
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($decliningHost)
        $runspace.Open()
        $session = [powershell]::Create()
        $session.Runspace = $runspace
        try {
            $null = $session.AddScript({
                param($FunctionPath, $DestinationRoot)
                . $FunctionPath
                $script:destinationRoot = $DestinationRoot
                function Test-Path {
                    [CmdletBinding()]
                    param($LiteralPath, $PathType)
                    $true
                }
                function Get-Volume {
                    [CmdletBinding()]
                    param()
                    @()
                }
                function Join-Path {
                    param($Path, $ChildPath)
                    if ($Path -eq 'C:\ProgramData\OSDeployCore\boot-assets\winpestartup-profiles') {
                        $Path = $script:destinationRoot
                    }
                    [System.IO.Path]::Combine($Path, $ChildPath)
                }
                New-WinpeStartupProfile -ProfileName 'Declined' -Force -PassThru -Confirm
            }).AddArgument("$PSScriptRoot\New-WinpeStartupProfile.ps1").AddArgument($script:bootRoot)
            $result = @($session.Invoke())
            $session.HadErrors | Should -BeFalse -Because (($session.Streams.Error | Out-String).Trim())
            $decliningHost.PromptCount | Should -Be 1
            $result.Count | Should -Be 0
            [System.IO.Directory]::Exists($script:bootRoot) | Should -BeFalse
        }
        finally {
            $session.Dispose()
            $runspace.Dispose()
        }
    }

    It 'documents every declared authoring parameter' {
        $help = Get-Help New-WinpeStartupProfile -Full
        $common = @([System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
        foreach ($name in (Get-Command New-WinpeStartupProfile).Parameters.Keys | Where-Object { $_ -notin $common }) {
            $help.Parameters.Parameter.Name | Should -Contain $name
        }
        @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
    }

    It 'registers the export in the manifest and loads the file in both environments' {
        $moduleRoot = [System.IO.Path]::GetFullPath("$PSScriptRoot\..\..")
        $manifest = Import-PowerShellDataFile -LiteralPath "$moduleRoot\OSDCloud.psd1"
        $manifest.FunctionsToExport | Should -Contain 'New-WinpeStartupProfile'
        foreach ($systemDrive in @('C:', 'X:')) {
            $session = [powershell]::Create()
            try {
                $null = $session.AddScript({
                    param($ModuleRoot, $SystemDrive)
                    $originalSystemDrive = $env:SystemDrive
                    try {
                        $env:SystemDrive = $SystemDrive
                        Import-Module "$ModuleRoot\OSDCloud.psd1" -Force -ErrorAction Stop
                        Get-Command New-WinpeStartupProfile -Module OSDCloud -ErrorAction Stop | Select-Object -ExpandProperty Name
                    }
                    finally {
                        $env:SystemDrive = $originalSystemDrive
                    }
                }).AddArgument($moduleRoot).AddArgument($systemDrive)
                $result = $session.Invoke()
                $session.HadErrors | Should -BeFalse -Because (($session.Streams.Error | Out-String).Trim())
                $result | Should -Contain 'New-WinpeStartupProfile'
            }
            finally {
                $session.Dispose()
            }
        }
    }
}
