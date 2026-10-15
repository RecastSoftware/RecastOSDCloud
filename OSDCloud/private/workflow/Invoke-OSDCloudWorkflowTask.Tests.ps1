BeforeAll {
    . "$PSScriptRoot\Invoke-OSDCloudWorkflowTask.ps1"
    . "$PSScriptRoot\..\disk\Get-OSDCloudDiskParameters.ps1"
    . "$PSScriptRoot\..\disk\Test-OSDCloudDiskLayout.ps1"
    . "$PSScriptRoot\..\core-driverpack\Set-OSDCloudModelDriversCacheObject.ps1"
    . "$PSScriptRoot\..\steps\3-preinstall\step-preinstall-cleartargetdisk.ps1"
    . "$PSScriptRoot\..\steps\3-preinstall\step-preinstall-partitiontargetdisk.ps1"
    $stateNames = @('OSDCloudDeploy', 'OSDCoreDevice', 'OSDCloudWorkflowInvoke', 'OSDCloudWorkflowSettingsUser', 'OSDCloudCurrentStep', 'IsVM')
    $originalState = @{}
    foreach ($name in $stateNames) {
        $originalState[$name] = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
    }
}

AfterAll {
    foreach ($name in $stateNames) {
        if ($originalState[$name]) { Set-Variable -Name $name -Value $originalState[$name].Value -Scope Global }
        else { Remove-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue }
    }
}

Describe 'Workflow disk snapshot and preflight' {
    BeforeEach {
        $global:IsVM = $false
        $disk = [pscustomobject]@{ Number = 0; Size = 100GB }
        $global:OSDCoreDevice = [pscustomobject]@{ LocalDisk = @($disk); IsVM = $false }
        $global:OSDCloudDeploy = [pscustomobject]@{
            DeploymentDisk = $disk; DeploymentDiskNumber = 0; OSArchitecture = 'amd64'
            DiskLabelOS = 'Windows'; DiskLabelRecovery = 'WinRE'
            DiskSizeSystem = 1GB; DiskSizeOS = 32GB; DiskSizeRecovery = 3GB
            WorkflowTaskObject = [pscustomobject]@{ steps = @(
                [pscustomobject]@{ name = 'Clear'; command = 'step-preinstall-cleartargetdisk'; testinfullos = $true }
                [pscustomobject]@{ name = 'Partition'; command = 'step-preinstall-partitiontargetdisk'; testinfullos = $true }
            ) }
        }
        $global:OSDCloudWorkflowSettingsUser = [pscustomobject]@{
            RecoveryPartition = [pscustomobject]@{ Force = $false; Skip = $false }
        }
        Mock Set-OSDCloudModelDriversCacheObject {}
        Mock Get-ComputerInfo { [pscustomobject]@{ OsName = 'Test Windows' } }
        Mock Invoke-RestMethod {}
        Mock step-preinstall-cleartargetdisk {}
        Mock step-preinstall-partitiontargetdisk {}
        Mock Write-Host {}
    }

    It 'copies every disk setting and runs only mocked disk steps' {
        Invoke-OSDCloudWorkflowTask
        $global:OSDCloudWorkflowInvoke.DiskLabelOS | Should -Be 'Windows'
        $global:OSDCloudWorkflowInvoke.DiskLabelRecovery | Should -Be 'WinRE'
        $global:OSDCloudWorkflowInvoke.DiskSizeSystem | Should -Be 1GB
        $global:OSDCloudWorkflowInvoke.DiskSizeOS | Should -Be 32GB
        $global:OSDCloudWorkflowInvoke.DiskSizeRecovery | Should -Be 3GB
        $global:OSDCloudDeploy.DiskSizeOS = 64GB
        $global:OSDCloudWorkflowInvoke.DiskSizeOS | Should -Be 32GB
        Should -Invoke step-preinstall-cleartargetdisk -Times 1 -Exactly
        Should -Invoke step-preinstall-partitiontargetdisk -Times 1 -Exactly
    }

    It 'fails before any destructive step or analytics when the layout cannot fit' {
        $global:OSDCloudDeploy.DiskSizeOS = 100GB
        { Invoke-OSDCloudWorkflowTask } | Should -Throw '*target disk capacity*'
        Should -Invoke step-preinstall-cleartargetdisk -Times 0 -Exactly
        Should -Invoke step-preinstall-partitiontargetdisk -Times 0 -Exactly
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'fails before clearing if state contains an invalid label' {
        $global:OSDCloudDeploy.DiskLabelOS = "bad`nlabel"
        { Invoke-OSDCloudWorkflowTask } | Should -Throw
        Should -Invoke step-preinstall-cleartargetdisk -Times 0 -Exactly
    }

    It 'honors partition-step recovery skip during preflight instead of default recovery' {
        $global:OSDCloudDeploy.DeploymentDisk.Size = 1GB + 16MB + 32GB + 5MB
        $global:OSDCloudDeploy.WorkflowTaskObject.steps[1] |
            Add-Member -NotePropertyName parameters -NotePropertyValue ([pscustomobject]@{ RecoveryPartitionSkip = $true })
        { Invoke-OSDCloudWorkflowTask } | Should -Not -Throw
        Should -Invoke step-preinstall-cleartargetdisk -Times 1 -Exactly
    }

    It 'honors force even when recovery is skipped by workflow policy' {
        $global:OSDCloudDeploy.DeploymentDisk.Size = 1GB + 16MB + 32GB + 5MB
        $global:OSDCloudWorkflowSettingsUser.RecoveryPartition.Skip = $true
        $global:OSDCloudDeploy.WorkflowTaskObject.steps[1] |
            Add-Member -NotePropertyName parameters -NotePropertyValue ([pscustomobject]@{ RecoveryPartitionForce = $true })
        { Invoke-OSDCloudWorkflowTask } | Should -Throw '*target disk capacity*'
        Should -Invoke step-preinstall-cleartargetdisk -Times 0 -Exactly
    }

    It 'validates an explicitly overridden target disk before clearing' {
        $global:OSDCoreDevice.LocalDisk += [pscustomobject]@{ Number = 1; Size = 33GB }
        $global:OSDCloudDeploy.WorkflowTaskObject.steps[1] |
            Add-Member -NotePropertyName parameters -NotePropertyValue ([pscustomobject]@{ DiskNumber = 1 })
        { Invoke-OSDCloudWorkflowTask } | Should -Throw '*target disk capacity*'
        Should -Invoke step-preinstall-cleartargetdisk -Times 0 -Exactly
    }

    It 'does not run disk preflight for a task without disk operations' {
        $global:OSDCloudDeploy.WorkflowTaskObject.steps = @()
        $global:OSDCloudDeploy.DeploymentDisk = $null
        { Invoke-OSDCloudWorkflowTask -Test } | Should -Not -Throw
        Should -Invoke step-preinstall-cleartargetdisk -Times 0 -Exactly
    }
}
