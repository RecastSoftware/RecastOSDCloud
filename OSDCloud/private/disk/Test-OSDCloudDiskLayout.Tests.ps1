BeforeAll {
    . "$PSScriptRoot\Test-OSDCloudDiskLayout.ps1"
    . "$PSScriptRoot\Get-OSDCloudDiskParameters.ps1"
    $originalDevice = $global:OSDCoreDevice
    $originalIsVM = Get-Variable IsVM -Scope Global -ErrorAction SilentlyContinue
}

AfterAll {
    $global:OSDCoreDevice = $originalDevice
    if ($originalIsVM) {
        $global:IsVM = $originalIsVM.Value
    }
    else {
        Remove-Variable IsVM -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'Deployment disk settings' {
    BeforeEach {
        $global:OSDCoreDevice = [pscustomobject]@{ IsVM = $false }
        $global:IsVM = $false
    }

    It 'retains defaults for older deployment objects' {
        $parameters = Get-OSDCloudDiskParameters -Settings ([pscustomobject]@{})
        $parameters.LabelWindows | Should -Be 'OS'
        $parameters.LabelRecovery | Should -Be 'Recovery'
        $parameters.SizeSystemGpt | Should -Be 500MB
        $parameters.SizeRecovery | Should -Be 2000MB
        $parameters.NoRecoveryPartition | Should -BeFalse
        $parameters.ContainsKey('SizeWindows') | Should -BeFalse
        { Test-OSDCloudDiskLayout -DiskSize 100GB @parameters } | Should -Not -Throw
    }

    It 'maps all overrides without altering recovery policy' {
        $settings = [pscustomobject]@{
            DiskLabelOS = 'Windows'; DiskLabelRecovery = 'WinRE'
            DiskSizeSystem = 1GB; DiskSizeOS = 32GB; DiskSizeRecovery = 3GB
            RecoveryPartition = [pscustomobject]@{ Skip = $true; Force = $false }
        }
        $parameters = Get-OSDCloudDiskParameters -Settings $settings
        $parameters.LabelWindows | Should -Be 'Windows'
        $parameters.LabelRecovery | Should -Be 'WinRE'
        $parameters.SizeSystemGpt | Should -Be 1GB
        $parameters.SizeWindows | Should -Be 32GB
        $parameters.SizeRecovery | Should -Be 3GB
        $parameters.NoRecoveryPartition | Should -BeTrue
    }

    It 'resolves recovery: VM=<VM> Skip=<Skip> Force=<Force>' -TestCases @(
        @{ VM = $false; Skip = $false; Force = $false; Disabled = $false }
        @{ VM = $true; Skip = $false; Force = $false; Disabled = $true }
        @{ VM = $false; Skip = $true; Force = $false; Disabled = $true }
        @{ VM = $true; Skip = $true; Force = $true; Disabled = $false }
        @{ VM = $false; Skip = $true; Force = $true; Disabled = $false }
    ) {
        param ($VM, $Skip, $Force, $Disabled)
        $global:OSDCoreDevice.IsVM = $VM
        $parameters = Get-OSDCloudDiskParameters -Settings ([pscustomobject]@{}) `
            -RecoveryPartitionSkip $Skip -RecoveryPartitionForce $Force
        $parameters.NoRecoveryPartition | Should -Be $Disabled
    }
}

Describe 'Disk layout validation' {
    It 'accepts valid size boundary <Name>=<Value>' -TestCases @(
        @{ Name = 'SizeSystemGpt'; Value = 100MB }
        @{ Name = 'SizeSystemGpt'; Value = 3000MB }
        @{ Name = 'SizeRecovery'; Value = 350MB }
        @{ Name = 'SizeRecovery'; Value = 80000MB }
        @{ Name = 'SizeWindows'; Value = 32GB }
    ) {
        param ($Name, $Value)
        $parameters = @{ $Name = $Value }
        { Test-OSDCloudDiskLayout -DiskSize 256GB @parameters } | Should -Not -Throw
    }

    It 'rejects invalid size <Name>=<Value>' -TestCases @(
        @{ Name = 'SizeSystemGpt'; Value = 100MB - 1 }
        @{ Name = 'SizeSystemGpt'; Value = 3000MB + 1 }
        @{ Name = 'SizeRecovery'; Value = 350MB - 1 }
        @{ Name = 'SizeRecovery'; Value = 80000MB + 1 }
        @{ Name = 'SizeWindows'; Value = 0 }
        @{ Name = 'SizeWindows'; Value = 32GB - 1 }
        @{ Name = 'SizeWindows'; Value = -1 }
    ) {
        param ($Name, $Value)
        $parameters = @{ $Name = $Value }
        { Test-OSDCloudDiskLayout -DiskSize 256GB @parameters } | Should -Throw
    }

    It 'rejects unsafe or invalid label <Label>' -TestCases @(
        @{ Label = '' }
        @{ Label = '   ' }
        @{ Label = 'a' * 33 }
        @{ Label = 'bad"label' }
        @{ Label = "bad`nlabel" }
        @{ Label = 'bad\label' }
        @{ Label = 'bad:label' }
        @{ Label = 'bad|label' }
        @{ Label = 'bad[label]' }
    ) {
        param ($Label)
        { Test-OSDCloudDiskLayout -DiskSize 256GB -LabelWindows $Label } | Should -Throw
        { Test-OSDCloudDiskLayout -DiskSize 256GB -LabelRecovery $Label } | Should -Throw
    }

    It 'accepts spaces and a 32-character label' {
        { Test-OSDCloudDiskLayout -DiskSize 256GB -LabelWindows 'Windows OS' -LabelRecovery ('r' * 32) } | Should -Not -Throw
    }

    It 'accounts for system, MSR, recovery and alignment at the capacity boundary' {
        $required = 500MB + 16MB + 32GB + 2000MB + 5MB
        { Test-OSDCloudDiskLayout -DiskSize $required -SizeWindows 32GB } | Should -Not -Throw
        { Test-OSDCloudDiskLayout -DiskSize ($required - 1) -SizeWindows 32GB } | Should -Throw '*target disk capacity*'
        { Test-OSDCloudDiskLayout -DiskSize ($required - 2000MB) -SizeWindows 32GB -NoRecoveryPartition } | Should -Not -Throw
    }

    It 'accounts for the MBR system size without an MSR' {
        $required = 1GB + 32GB + 2000MB + 5MB
        { Test-OSDCloudDiskLayout -DiskSize $required -PartitionStyle MBR -SizeSystemMbr 1GB -SizeWindows 32GB } | Should -Not -Throw
        { Test-OSDCloudDiskLayout -DiskSize ($required - 1) -PartitionStyle MBR -SizeSystemMbr 1GB -SizeWindows 32GB } | Should -Throw
    }

    It 'rejects extremely large requests without arithmetic overflow' {
        { Test-OSDCloudDiskLayout -DiskSize 256GB -SizeWindows ([uint64]::MaxValue) } | Should -Throw '*target disk capacity*'
    }
}
