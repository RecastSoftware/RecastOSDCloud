BeforeAll {
    . "$PSScriptRoot\step-preinstall-partitiontargetdisk.ps1"
    . "$PSScriptRoot\..\..\disk\disk-osdcloud-v2.ps1"
    . "$PSScriptRoot\..\..\disk\Get-OSDCloudDiskParameters.ps1"
    $originalInvoke = $global:OSDCloudWorkflowInvoke
    $originalDevice = $global:OSDCoreDevice
    $originalIsVM = Get-Variable IsVM -Scope Global -ErrorAction SilentlyContinue
}

AfterAll {
    $global:OSDCloudWorkflowInvoke = $originalInvoke
    $global:OSDCoreDevice = $originalDevice
    if ($originalIsVM) { $global:IsVM = $originalIsVM.Value }
    else { Remove-Variable IsVM -Scope Global -ErrorAction SilentlyContinue }
}

Describe 'Partition step disk customization' {
    BeforeEach {
        $global:OSDCoreDevice = [pscustomobject]@{ IsVM = $false }
        $global:IsVM = $false
        $global:OSDCloudWorkflowInvoke = [ordered]@{
            DeploymentDiskNumber = 0
            RecoveryPartition = [pscustomobject]@{ Force = $false; Skip = $false }
        }
        Mock New-OSDCloudDisk {}
        Mock Get-PSDrive { [pscustomobject]@{ Name = 'C' } }
        Mock Start-Sleep {}
        Mock Write-Host {}
    }

    It 'passes the legacy default layout without binding SizeWindows' {
        step-preinstall-partitiontargetdisk
        Should -Invoke New-OSDCloudDisk -Times 1 -Exactly -ParameterFilter {
            $DiskNumber -eq 0 -and $PartitionStyle -eq 'GPT' -and $Force -and
            $LabelWindows -eq 'OS' -and $LabelRecovery -eq 'Recovery' -and
            $SizeSystemGpt -eq 500MB -and $SizeRecovery -eq 2000MB -and
            -not $NoRecoveryPartition -and -not $PesterBoundParameters.ContainsKey('SizeWindows')
        }
    }

    It 'forwards each override independently: <Property>' -TestCases @(
        @{ Property = 'DiskLabelOS'; Value = 'Windows'; Parameter = 'LabelWindows' }
        @{ Property = 'DiskLabelRecovery'; Value = 'WinRE'; Parameter = 'LabelRecovery' }
        @{ Property = 'DiskSizeSystem'; Value = 1GB; Parameter = 'SizeSystemGpt' }
        @{ Property = 'DiskSizeOS'; Value = 32GB; Parameter = 'SizeWindows' }
        @{ Property = 'DiskSizeRecovery'; Value = 3GB; Parameter = 'SizeRecovery' }
    ) {
        param ($Property, $Value, $Parameter)
        $global:OSDCloudWorkflowInvoke[$Property] = $Value
        step-preinstall-partitiontargetdisk
        Should -Invoke New-OSDCloudDisk -Times 1 -Exactly -ParameterFilter { $PesterBoundParameters[$Parameter] -eq $Value }
    }

    It 'supports a nonzero disk with recovery disabled and combined overrides' {
        $global:OSDCloudWorkflowInvoke.DiskLabelOS = 'Windows'
        $global:OSDCloudWorkflowInvoke.DiskLabelRecovery = 'WinRE'
        $global:OSDCloudWorkflowInvoke.DiskSizeSystem = 1GB
        $global:OSDCloudWorkflowInvoke.DiskSizeOS = 32GB
        $global:OSDCloudWorkflowInvoke.DiskSizeRecovery = 3GB
        step-preinstall-partitiontargetdisk -DiskNumber 1 -RecoveryPartitionSkip $true
        Should -Invoke New-OSDCloudDisk -Times 1 -Exactly -ParameterFilter {
            $DiskNumber -eq 1 -and $NoRecoveryPartition -and $SizeWindows -eq 32GB -and
            $SizeSystemGpt -eq 1GB -and $SizeRecovery -eq 3GB -and
            $LabelWindows -eq 'Windows' -and $LabelRecovery -eq 'WinRE'
        }
    }

    It 'retains default disk selection when no target number is available' {
        $global:OSDCloudWorkflowInvoke.DeploymentDiskNumber = $null
        step-preinstall-partitiontargetdisk
        Should -Invoke New-OSDCloudDisk -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey('DiskNumber') }
    }

    It 'allows force to override a virtual machine and recovery skip' {
        $global:OSDCoreDevice.IsVM = $true
        step-preinstall-partitiontargetdisk -RecoveryPartitionSkip $true -RecoveryPartitionForce $true
        Should -Invoke New-OSDCloudDisk -Times 1 -Exactly -ParameterFilter { -not $NoRecoveryPartition }
    }
}
