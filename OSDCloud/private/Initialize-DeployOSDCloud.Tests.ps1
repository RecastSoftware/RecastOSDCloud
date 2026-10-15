BeforeAll {
    . "$PSScriptRoot\Initialize-DeployOSDCloud.ps1"
    . "$PSScriptRoot\..\public\WinOS\Deploy-OSDCloud.ps1"
    . "$PSScriptRoot\core-license\Initialize-OSDCoreLicense.ps1"
    . "$PSScriptRoot\core-device\Initialize-OSDCoreDevice.ps1"
    . "$PSScriptRoot\workflow\Invoke-OSDCloudWorkflowTask.ps1"
    . "$PSScriptRoot\workflow\Invoke-OSDCloudWorkflowUI.ps1"
    function Get-OSDCloudWorkflowRuntimeParameter {
        [CmdletBinding()]
        param ($ModuleBase, $WorkflowName, $ProcessorArchitecture)
        return [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    }
    . "$PSScriptRoot\disk\Get-OSDCloudDiskParameters.ps1"
    . "$PSScriptRoot\disk\Test-OSDCloudDiskLayout.ps1"
    . "$PSScriptRoot\core-cache\Initialize-OSDCoreCache.ps1"
    . "$PSScriptRoot\core-driverpack\Initialize-ModuleCoreDriverPacks.ps1"
    . "$PSScriptRoot\core-driverpack\Get-OSDCoreModelDriversCacheObject.ps1"
    . "$PSScriptRoot\core-driverpack\Get-OSDCoreDriverPackCacheObject.ps1"
    . "$PSScriptRoot\core-driverpack\Test-OSDCoreDriverPackCloudObject.ps1"
    . "$PSScriptRoot\core-operatingsystem\Get-OSDCoreOperatingSystems.ps1"
    . "$PSScriptRoot\core-operatingsystem\Get-OSDCoreOperatingSystemCacheObject.ps1"
    . "$PSScriptRoot\core-operatingsystem\Test-OperatingSystemCloudObject.ps1"
    . "$PSScriptRoot\workflow\Initialize-OSDCloudWorkflowSettingsOS.ps1"
    . "$PSScriptRoot\workflow\Resolve-OSDCloudWorkflowOSActivation.ps1"
    . "$PSScriptRoot\workflow\Initialize-OSDCloudWorkflowTasks.ps1"
    $stateNames = @(
        'OSDCoreDevice', 'OSDCloudDeploy', 'OSDCloudEnv', 'OSDCoreDriverPacks',
        'ModuleCoreDriverPacks', 'OSDCoreOperatingSystems', 'OSDCloudWorkflowSettingsOS',
        'OSDCloudWorkflowTasks', 'OSDCoreLicense'
    )
    $originalState = @{}
    foreach ($name in $stateNames) {
        $originalState[$name] = Get-Variable -Name $name -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    }
}

AfterAll {
    foreach ($name in $stateNames) {
        Set-Variable -Name $name -Value $originalState[$name] -Scope Global
    }
}

Describe 'Initialize-DeployOSDCloud ModelDrivers defaults' {
    BeforeEach {
        $entry = [pscustomobject]@{ Type = 'ModelDrivers'; FullName = 'E:\OSDCloud\modeldrivers-amd64\HP_8CD1_Any model_28000.1' }
        $global:OSDCoreDevice = [pscustomobject]@{
            OSDManufacturer = 'HP'
            OSDProduct = '8CD1'
            OSDModel = 'A different device model'
            ProcessorArchitecture = 'amd64'
            LocalDisk = @([pscustomobject]@{ Number = 0; FriendlyName = 'Test disk'; Size = 100GB })
        }
        $global:OSDCloudEnv = $null
        $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $true }
        $global:ModuleCoreDriverPacks = @([pscustomobject]@{
            Name = 'OEM pack'; SystemId = '8CD1'; OSArchitecture = 'amd64'; FileName = 'pack.cab'
            Url = 'https://example.invalid/pack.cab'; HashMD5 = 'not-used-for-modeldrivers'
        })
        $global:OSDCloudWorkflowSettingsOS = [pscustomobject]@{
            OperatingSystem = [pscustomobject]@{ default = 'Windows 11 25H2'; values = @('Windows 11 25H2') }
            OSActivation = [pscustomobject]@{ default = 'Retail'; values = @('Retail') }
            OSEdition = [pscustomobject]@{ default = 'Pro'; values = @([pscustomobject]@{ Edition = 'Pro'; EditionId = 'Professional' }) }
            OSLanguageCode = [pscustomobject]@{ default = 'en-us'; values = @('en-us') }
        }
        $global:OSDCloudWorkflowTasks = @([pscustomobject]@{ name = 'OSDCloud'; steps = @() })
        Mock Initialize-OSDCoreCache {}
        Mock Initialize-OSDCoreLicense { $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $true } }
        Mock Initialize-OSDCoreDevice {}
        Mock Invoke-OSDCloudWorkflowTask {}
        Mock Invoke-OSDCloudWorkflowUI {}
        Mock Initialize-ModuleCoreDriverPacks {}
        Mock Get-OSDCoreModelDriversCacheObject { $entry }
        Mock Test-OSDCoreDriverPackCloudObject { $true }
        Mock Get-OSDCoreDriverPackCacheObject {}
        Mock Get-OSDCoreOperatingSystems {
            [pscustomobject]@{
                OperatingSystem = 'Windows 11 25H2'; OSActivation = 'Retail'; OSLanguageCode = 'en-us'
                OSArchitecture = $global:OSDCoreDevice.ProcessorArchitecture; OSBuild = '26200'; OSBuildVersion = '26200.9457'
            }
        }
        Mock Initialize-OSDCloudWorkflowSettingsOS {}
        Mock Resolve-OSDCloudWorkflowOSActivation { $OSActivation }
        Mock Test-OperatingSystemCloudObject { $true }
        Mock Get-OSDCoreOperatingSystemCacheObject {}
        Mock Initialize-OSDCloudWorkflowTasks {}
        Mock Export-Clixml {}
        Mock Out-File {}
        Mock Out-Host {}
        Mock Remove-Item {}
        Mock Get-FileHash { throw 'Unexpected archive hashing' }
        Mock Write-Host {}
    }

    It 'defaults to ModelDrivers and retains OEM fallback without testing its URL or archive' {
        Initialize-DeployOSDCloud
        $global:OSDCloudDeploy.DriverPackName | Should -Be 'ModelDrivers'
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -Be $entry
        $global:OSDCloudDeploy.DriverPackCloudObject.Name | Should -Be 'OEM pack'
        $global:OSDCloudDeploy.OSBuildVersion | Should -Be '26200.9457'
        Should -Invoke Test-OSDCoreDriverPackCloudObject -Times 0 -Exactly
        Should -Invoke Get-OSDCoreDriverPackCacheObject -Times 0 -Exactly
        Should -Invoke Get-FileHash -Times 0 -Exactly
    }

    It 'preserves the default disk layout and automatic Windows sizing' {
        Initialize-DeployOSDCloud
        $global:OSDCloudDeploy.DiskLabelOS | Should -Be 'OS'
        $global:OSDCloudDeploy.DiskLabelRecovery | Should -Be 'Recovery'
        $global:OSDCloudDeploy.DiskSizeSystem | Should -Be 500MB
        $global:OSDCloudDeploy.DiskSizeRecovery | Should -Be 2000MB
        $global:OSDCloudDeploy.DiskSizeOS | Should -BeNullOrEmpty
    }

    It 'retains all disk overrides without losing disk number zero' {
        Initialize-DeployOSDCloud -DiskNumber 0 -DiskLabelOS Windows -DiskLabelRecovery WinRE `
            -DiskSizeSystem 1GB -DiskSizeOS 32GB -DiskSizeRecovery 3GB -WarningVariable warnings
        $global:OSDCloudDeploy.DeploymentDiskNumber | Should -Be 0
        $global:OSDCloudDeploy.DiskLabelOS | Should -Be 'Windows'
        $global:OSDCloudDeploy.DiskLabelRecovery | Should -Be 'WinRE'
        $global:OSDCloudDeploy.DiskSizeSystem | Should -Be 1GB
        $global:OSDCloudDeploy.DiskSizeOS | Should -Be 32GB
        $global:OSDCloudDeploy.DiskSizeRecovery | Should -Be 3GB
        @($warnings).Count | Should -Be 0
        Should -Invoke Initialize-OSDCoreLicense -Times 0 -Exactly
    }

    It 'rejects an oversized OS partition during initialization' {
        { Initialize-DeployOSDCloud -DiskSizeOS 100GB } | Should -Throw '*target disk capacity*'
        Should -Invoke Initialize-OSDCloudWorkflowTasks -Times 0 -Exactly
    }

    It 'falls back for all unregistered overrides with exactly one warning' {
        $global:OSDCoreLicense.IsRegistered = $false
        Initialize-DeployOSDCloud -DiskNumber 0 -DiskLabelOS Windows -DiskLabelRecovery WinRE `
            -DiskSizeSystem 1GB -DiskSizeOS 100GB -DiskSizeRecovery 3GB `
            -WarningVariable warnings -WarningAction SilentlyContinue
        $global:OSDCloudDeploy.DiskLabelOS | Should -Be 'OS'
        $global:OSDCloudDeploy.DiskLabelRecovery | Should -Be 'Recovery'
        $global:OSDCloudDeploy.DiskSizeSystem | Should -Be 500MB
        $global:OSDCloudDeploy.DiskSizeRecovery | Should -Be 2000MB
        $global:OSDCloudDeploy.DiskSizeOS | Should -BeNullOrEmpty
        $global:OSDCloudDeploy.DeploymentDiskNumber | Should -Be 0
        $diskParameters = Get-OSDCloudDiskParameters -Settings $global:OSDCloudDeploy
        $diskParameters.ContainsKey('SizeWindows') | Should -BeFalse
        @($warnings).Count | Should -Be 1
        "$warnings" | Should -Match 'registration.*default partition labels and sizes'
        Should -Invoke Initialize-OSDCoreLicense -Times 0 -Exactly
    }

    It 'warns once for each explicitly supplied unregistered customization: <Name>' -TestCases @(
        @{ Name = 'DiskLabelOS'; Value = 'Windows' }
        @{ Name = 'DiskLabelRecovery'; Value = 'WinRE' }
        @{ Name = 'DiskSizeSystem'; Value = 1GB }
        @{ Name = 'DiskSizeOS'; Value = 100GB }
        @{ Name = 'DiskSizeRecovery'; Value = 3GB }
        @{ Name = 'DiskLabelOS'; Value = 'OS' }
        @{ Name = 'DiskSizeSystem'; Value = 500MB }
    ) {
        param ($Name, $Value)
        $global:OSDCoreLicense.IsRegistered = $false
        $parameters = @{ $Name = $Value }
        Initialize-DeployOSDCloud @parameters -WarningVariable warnings -WarningAction SilentlyContinue
        @($warnings).Count | Should -Be 1
        "$warnings" | Should -Match $Name
        $global:OSDCloudDeploy.DiskLabelOS | Should -Be 'OS'
        $global:OSDCloudDeploy.DiskLabelRecovery | Should -Be 'Recovery'
        $global:OSDCloudDeploy.DiskSizeSystem | Should -Be 500MB
        $global:OSDCloudDeploy.DiskSizeRecovery | Should -Be 2000MB
        $global:OSDCloudDeploy.DiskSizeOS | Should -BeNullOrEmpty
    }

    It 'does not warn or gate DiskNumber without customization parameters' {
        $global:OSDCoreLicense.IsRegistered = $false
        $global:OSDCoreDevice.LocalDisk += [pscustomobject]@{ Number = 1; FriendlyName = 'Second disk'; Size = 100GB }
        Initialize-DeployOSDCloud -DiskNumber 1 -WarningVariable warnings
        @($warnings).Count | Should -Be 0
        $global:OSDCloudDeploy.DeploymentDiskNumber | Should -Be 1
        Should -Invoke Initialize-OSDCoreLicense -Times 0 -Exactly
    }

    It 'initializes missing license state and uses its registration result: registered=<Registered>' -TestCases @(
        @{ Registered = $true }
        @{ Registered = $false }
    ) {
        param ($Registered)
        $global:OSDCoreLicense = $null
        Mock Initialize-OSDCoreLicense { $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $Registered } }
        Initialize-DeployOSDCloud -DiskSizeOS 32GB -WarningVariable warnings -WarningAction SilentlyContinue
        Should -Invoke Initialize-OSDCoreLicense -Times 1 -Exactly
        if ($Registered) {
            $global:OSDCloudDeploy.DiskSizeOS | Should -Be 32GB
            @($warnings).Count | Should -Be 0
        }
        else {
            $global:OSDCloudDeploy.DiskSizeOS | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
        }
    }

    It 'does not grant customization for a license object missing registration' {
        $global:OSDCoreLicense = [pscustomobject]@{}
        Initialize-DeployOSDCloud -DiskSizeOS 100GB -WarningVariable warnings -WarningAction SilentlyContinue
        $global:OSDCloudDeploy.DiskSizeOS | Should -BeNullOrEmpty
        @($warnings).Count | Should -Be 1
    }

    It 'surfaces license initialization failure without proceeding' {
        $global:OSDCoreLicense = $null
        Mock Initialize-OSDCoreLicense { throw 'License initialization failed' }
        { Initialize-DeployOSDCloud -DiskSizeOS 32GB } | Should -Throw '*License initialization failed*'
        Should -Invoke Initialize-OSDCoreCache -Times 0 -Exactly
    }

    It 'preserves binding validation for unregistered invalid input' {
        $global:OSDCoreLicense.IsRegistered = $false
        { Initialize-DeployOSDCloud -DiskSizeOS 0 } | Should -Throw
        { Initialize-DeployOSDCloud -DiskLabelOS "bad`nlabel" } | Should -Throw
        Should -Invoke Initialize-OSDCoreCache -Times 0 -Exactly
    }

    It 'uses the real shared gate for public deployment: CLI=<CLI>, registered=<Registered>' -TestCases @(
        @{ CLI = $true; Registered = $true }
        @{ CLI = $false; Registered = $true }
        @{ CLI = $true; Registered = $false }
        @{ CLI = $false; Registered = $false }
    ) {
        param ($CLI, $Registered)
        Mock Initialize-OSDCoreLicense { $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $Registered } }
        Deploy-OSDCloud -CLI:$CLI -DiskNumber 0 -DiskLabelOS Windows -DiskLabelRecovery WinRE `
            -DiskSizeSystem 1GB -DiskSizeOS 32GB -DiskSizeRecovery 3GB `
            -WarningVariable warnings -WarningAction SilentlyContinue
        Should -Invoke Initialize-OSDCoreLicense -Times 1 -Exactly
        $global:OSDCloudDeploy.DeploymentDiskNumber | Should -Be 0
        if ($Registered) {
            $global:OSDCloudDeploy.DiskLabelOS | Should -Be 'Windows'
            $global:OSDCloudDeploy.DiskLabelRecovery | Should -Be 'WinRE'
            $global:OSDCloudDeploy.DiskSizeSystem | Should -Be 1GB
            $global:OSDCloudDeploy.DiskSizeOS | Should -Be 32GB
            $global:OSDCloudDeploy.DiskSizeRecovery | Should -Be 3GB
            @($warnings).Count | Should -Be 0
        }
        else {
            $global:OSDCloudDeploy.DiskLabelOS | Should -Be 'OS'
            $global:OSDCloudDeploy.DiskLabelRecovery | Should -Be 'Recovery'
            $global:OSDCloudDeploy.DiskSizeSystem | Should -Be 500MB
            $global:OSDCloudDeploy.DiskSizeOS | Should -BeNullOrEmpty
            $global:OSDCloudDeploy.DiskSizeRecovery | Should -Be 2000MB
            @($warnings).Count | Should -Be 1
        }
    }

    It 'applies unregistered disk fallback when Incognito overrides a registered license: CLI=<CLI>' -TestCases @(
        @{ CLI = $true }
        @{ CLI = $false }
    ) {
        param ($CLI)
        Deploy-OSDCloud -CLI:$CLI -Incognito -DiskNumber 0 -DiskLabelOS Windows -DiskLabelRecovery WinRE `
            -DiskSizeSystem 1GB -DiskSizeOS 100GB -DiskSizeRecovery 3GB `
            -WarningVariable warnings -WarningAction SilentlyContinue
        $global:OSDCoreLicense.IsRegistered | Should -BeFalse
        $global:OSDCloudDeploy.DiskLabelOS | Should -Be 'OS'
        $global:OSDCloudDeploy.DiskLabelRecovery | Should -Be 'Recovery'
        $global:OSDCloudDeploy.DiskSizeSystem | Should -Be 500MB
        $global:OSDCloudDeploy.DiskSizeOS | Should -BeNullOrEmpty
        $global:OSDCloudDeploy.DiskSizeRecovery | Should -Be 2000MB
        $global:OSDCloudDeploy.DeploymentDiskNumber | Should -Be 0
        @($warnings).Count | Should -Be 1
        Should -Invoke Initialize-OSDCoreLicense -Times 1 -Exactly
    }

    It 'defaults to ModelDrivers when the device has no OEM catalog entry' {
        $global:ModuleCoreDriverPacks = @()
        Initialize-DeployOSDCloud
        $global:OSDCloudDeploy.DriverPackName | Should -Be 'ModelDrivers'
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -Be $entry
        $global:OSDCloudDeploy.DriverPackCloudObject | Should -BeNullOrEmpty
    }

    It 'selects ModelDrivers after device overrides and with the effective architecture' {
        Initialize-DeployOSDCloud -OSDManufacturer Microsoft -OSDProduct Surface_Product -OSDModel 'Ignored override' -ProcessorArchitecture arm64
        Should -Invoke Get-OSDCoreModelDriversCacheObject -Times 1 -Exactly -ParameterFilter {
            $OSArchitecture -eq 'arm64' -and $global:OSDCoreDevice.OSDManufacturer -eq 'Microsoft' -and
            $global:OSDCoreDevice.OSDProduct -eq 'Surface_Product'
        }
        $global:OSDCloudDeploy.OSArchitecture | Should -Be 'arm64'
    }

    It 'retains the original OEM validation behavior when no safe ModelDrivers match' {
        Mock Get-OSDCoreModelDriversCacheObject {}
        Initialize-DeployOSDCloud
        $global:OSDCloudDeploy.DriverPackName | Should -Be 'OEM pack'
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -BeNullOrEmpty
        Should -Invoke Test-OSDCoreDriverPackCloudObject -Times 1 -Exactly
        Should -Invoke Get-OSDCoreDriverPackCacheObject -Times 1 -Exactly
    }
}
