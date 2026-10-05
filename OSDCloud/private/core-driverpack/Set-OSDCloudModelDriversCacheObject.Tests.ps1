BeforeAll {
    . "$PSScriptRoot\Get-OSDCoreModelDriversCacheObject.ps1"
    . "$PSScriptRoot\Set-OSDCloudModelDriversCacheObject.ps1"
    . "$PSScriptRoot\..\workflow\Invoke-OSDCloudWorkflowTask.ps1"
    $originalDeploy = $global:OSDCloudDeploy
    $originalDevice = $global:OSDCoreDevice
    $originalInvoke = $global:OSDCloudWorkflowInvoke
    $originalSettings = $global:OSDCloudWorkflowSettingsUser
}

AfterAll {
    $global:OSDCloudDeploy = $originalDeploy
    $global:OSDCoreDevice = $originalDevice
    $global:OSDCloudWorkflowInvoke = $originalInvoke
    $global:OSDCloudWorkflowSettingsUser = $originalSettings
}

Describe 'ModelDrivers deployment precedence' {
    BeforeEach {
        $entry = [pscustomobject]@{ Type = 'ModelDrivers'; FullName = 'E:\modeldrivers' }
        $global:OSDCoreDevice = [pscustomobject]@{ OSDManufacturer = 'HP'; OSDProduct = '8CD1'; OSDModel = 'Ignored' }
        $global:OSDCloudDeploy = [pscustomobject]@{
            WorkflowName = 'default'
            OSArchitecture = 'amd64'
            DriverPackName = 'OEM pack'
            DriverPackCloudObject = [pscustomobject]@{ Name = 'OEM pack'; Url = 'https://example.invalid/pack.cab' }
            ModelDriversCacheObject = $null
            OperatingSystemCloudObject = [pscustomobject]@{ OSBuildVersion = '19045.1'; OSArchitecture = 'amd64' }
            WorkflowTaskObject = [pscustomobject]@{ steps = @() }
        }
        $global:OSDCloudWorkflowSettingsUser = [pscustomobject]@{ RecoveryPartition = $true; WinpeRestart = $false; WinpeShutdown = $false }
        Mock Get-OSDCoreModelDriversCacheObject { $entry }
        Mock Write-Host {}
        Mock Get-ComputerInfo { [pscustomobject]@{ OsName = 'Test Windows' } }
        Mock Invoke-RestMethod {}
    }

    It 'always selects ModelDrivers in CLI with driver choice <Choice>' -TestCases @(
        @{ Choice = 'None' }
        @{ Choice = 'Microsoft Update Catalog' }
        @{ Choice = 'OEM pack' }
        @{ Choice = 'ModelDrivers' }
        @{ Choice = $null }
    ) {
        param ($Choice)
        $global:OSDCloudDeploy.WorkflowName = 'cli'
        $global:OSDCloudDeploy.DriverPackName = $Choice
        Set-OSDCloudModelDriversCacheObject
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -Be $entry
        Should -Invoke Get-OSDCoreModelDriversCacheObject -Times 1 -Exactly -ParameterFilter { $OSArchitecture -eq 'amd64' }
    }

    It 'preserves GUI bypass choice <Choice> and clears an old ModelDrivers selection' -TestCases @(
        @{ Choice = 'None' }
        @{ Choice = 'Microsoft Update Catalog' }
    ) {
        param ($Choice)
        $global:OSDCloudDeploy.DriverPackName = $Choice
        $global:OSDCloudDeploy.ModelDriversCacheObject = $entry
        Set-OSDCloudModelDriversCacheObject
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -BeNullOrEmpty
        Should -Invoke Get-OSDCoreModelDriversCacheObject -Times 0 -Exactly
    }

    It 'prefers ModelDrivers in GUI without replacing OEM metadata' {
        $cloudObject = $global:OSDCloudDeploy.DriverPackCloudObject
        Set-OSDCloudModelDriversCacheObject
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -Be $entry
        $global:OSDCloudDeploy.DriverPackCloudObject | Should -Be $cloudObject
    }

    It 'uses ModelDrivers in CLI even when no OEM pack exists' {
        $global:OSDCloudDeploy.WorkflowName = 'cli'
        $global:OSDCloudDeploy.DriverPackName = $null
        $global:OSDCloudDeploy.DriverPackCloudObject = $null
        Set-OSDCloudModelDriversCacheObject
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -Be $entry
    }

    It 'restores the OEM fallback when a previously available model source is excluded' {
        $global:OSDCloudDeploy.DriverPackName = 'ModelDrivers'
        Mock Get-OSDCoreModelDriversCacheObject {}
        Set-OSDCloudModelDriversCacheObject -WarningVariable messages -WarningAction SilentlyContinue
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -BeNullOrEmpty
        $global:OSDCloudDeploy.DriverPackName | Should -Be 'OEM pack'
        "$messages" | Should -Match 'OEM fallback'
    }

    It 'retains an OEM selection when no ModelDrivers match' {
        Mock Get-OSDCoreModelDriversCacheObject {}
        Set-OSDCloudModelDriversCacheObject
        $global:OSDCloudDeploy.DriverPackName | Should -Be 'OEM pack'
        $global:OSDCloudDeploy.ModelDriversCacheObject | Should -BeNullOrEmpty
    }

    It 'refreshes CLI selection at the shared workflow boundary and snapshots it separately' {
        $global:OSDCloudDeploy.WorkflowName = 'cli'
        $global:OSDCloudDeploy.DriverPackName = 'None'
        Invoke-OSDCloudWorkflowTask -Test
        $global:OSDCloudWorkflowInvoke.ModelDriversCacheObject | Should -Be $entry
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged | Should -BeFalse
        $global:OSDCloudWorkflowInvoke.DriverPackName | Should -Be 'None'
        $global:OSDCloudWorkflowInvoke.DriverPackCloudObject | Should -Be $global:OSDCloudDeploy.DriverPackCloudObject
        Should -Invoke Get-OSDCoreModelDriversCacheObject -Times 1 -Exactly
    }

    It 'fails explicitly if deployment state is missing' {
        $global:OSDCloudDeploy = $null
        { Set-OSDCloudModelDriversCacheObject } | Should -Throw '*must be initialized*'
    }
}
