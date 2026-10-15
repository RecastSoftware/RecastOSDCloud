BeforeAll {
    . "$PSScriptRoot\disk-osdcloud-v2.ps1"
    . "$PSScriptRoot\disk-core.ps1"
    . "$PSScriptRoot\Test-OSDCloudDiskLayout.ps1"
    function diskpart.exe {
        [CmdletBinding()]
        param ([Parameter(ValueFromPipeline)] [string]$Command)
        throw 'DiskPart must be mocked in tests.'
    }
}

Describe 'Windows partition sizing' {
    BeforeEach {
        $script:partitionNumber = 0
        Mock Get-OSDCloudDisk { [pscustomobject]@{ LargestFreeExtent = 200GB } }
        Mock Get-Disk { [pscustomobject]@{ LargestFreeExtent = 200GB } }
        Mock New-Partition {
            $script:partitionNumber++
            [pscustomobject]@{ PartitionNumber = $script:partitionNumber }
        }
        Mock diskpart.exe {}
    }

    It 'uses fixed OS sizing and exact recovery sizing for <Style>, recovery disabled=<Disabled>' -TestCases @(
        @{ Style = 'GPT'; Disabled = $false }
        @{ Style = 'GPT'; Disabled = $true }
        @{ Style = 'MBR'; Disabled = $false }
        @{ Style = 'MBR'; Disabled = $true }
    ) {
        param ($Style, $Disabled)
        New-OSDCloudPartitionWindows -PartitionStyle $Style -DiskNumber 0 -SizeWindows 32GB -SizeRecovery 3GB -NoRecoveryPartition:$Disabled
        Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter { $Size -eq 32GB -and -not $UseMaximumSize -and $DriveLetter -eq 'C' }
        if ($Disabled) {
            Should -Invoke New-Partition -Times 1 -Exactly
        }
        else {
            Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter { $Size -eq 3GB -and -not $UseMaximumSize }
        }
        Should -Invoke New-Partition -Times 0 -Exactly -ParameterFilter { $UseMaximumSize }
    }

    It 'preserves automatic sizing for <Style>, recovery disabled=<Disabled>' -TestCases @(
        @{ Style = 'GPT'; Disabled = $false }
        @{ Style = 'GPT'; Disabled = $true }
        @{ Style = 'MBR'; Disabled = $false }
        @{ Style = 'MBR'; Disabled = $true }
    ) {
        param ($Style, $Disabled)
        New-OSDCloudPartitionWindows -PartitionStyle $Style -NoRecoveryPartition:$Disabled
        if ($Disabled) {
            Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter { $UseMaximumSize -and $DriveLetter -eq 'C' }
        }
        else {
            Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter { $Size -eq (200GB - 2000MB) -and $DriveLetter -eq 'C' }
            Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter { $UseMaximumSize -and -not $DriveLetter }
        }
    }

    It 'formats the requested labels and retains GPT recovery attributes' {
        New-OSDCloudPartitionWindows -PartitionStyle GPT -SizeWindows 32GB -LabelWindows 'Windows OS' -LabelRecovery WinRE
        Should -Invoke diskpart.exe -Times 1 -Exactly -ParameterFilter { $Command -match 'label="Windows OS"' }
        Should -Invoke diskpart.exe -Times 1 -Exactly -ParameterFilter { $Command -match 'label="WinRE"' }
        Should -Invoke diskpart.exe -Times 1 -Exactly -ParameterFilter { $Command -match 'gpt attributes=0x8000000000000001' }
        Should -Invoke New-Partition -Times 1 -Exactly -ParameterFilter { $GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' }
    }

    It 'retains MBR recovery ID 27 and drive letters for fixed sizing' {
        New-OSDCloudPartitionWindows -PartitionStyle MBR -SizeWindows 32GB -LabelWindows Windows -LabelRecovery WinRE
        Should -Invoke diskpart.exe -Times 1 -Exactly -ParameterFilter { $Command -match 'set id=27' }
        Should -Invoke diskpart.exe -Times 1 -Exactly -ParameterFilter { $Command -match 'assign letter C' -and $Command -match 'label="Windows"' }
        Should -Invoke diskpart.exe -Times 1 -Exactly -ParameterFilter { $Command -match 'assign letter R' -and $Command -match 'label="WinRE"' }
    }

    It 'rejects insufficient free space before creating or formatting a partition' {
        Mock Get-OSDCloudDisk { [pscustomobject]@{ LargestFreeExtent = 33GB } }
        { New-OSDCloudPartitionWindows -PartitionStyle GPT -SizeWindows 32GB -SizeRecovery 2GB } | Should -Throw '*insufficient free space*'
        Should -Invoke New-Partition -Times 0 -Exactly
        Should -Invoke diskpart.exe -Times 0 -Exactly
    }

    It 'guards against recovery subtraction underflow' {
        Mock Get-OSDCloudDisk { [pscustomobject]@{ LargestFreeExtent = 1GB } }
        { New-OSDCloudPartitionWindows -PartitionStyle GPT -SizeRecovery 2GB } | Should -Throw '*insufficient free space*'
        Should -Invoke New-Partition -Times 0 -Exactly
    }

    It 'checks free extent alignment allowance at the fixed-size boundary' {
        Mock Get-OSDCloudDisk { [pscustomobject]@{ LargestFreeExtent = 32GB + 2GB + 2MB - 1 } }
        { New-OSDCloudPartitionWindows -PartitionStyle GPT -SizeWindows 32GB -SizeRecovery 2GB } | Should -Throw
        Mock Get-OSDCloudDisk { [pscustomobject]@{ LargestFreeExtent = 32GB + 2GB + 2MB } }
        { New-OSDCloudPartitionWindows -PartitionStyle GPT -SizeWindows 32GB -SizeRecovery 2GB } | Should -Not -Throw
    }
}

Describe 'Disk helper forwarding and preflight' {
    BeforeEach {
        Mock Get-DeviceLocalDisk { [pscustomobject]@{ Number = 0; DiskNumber = 0; Size = 256GB; NumberOfPartitions = 0; PartitionStyle = 'RAW' } }
        Mock Initialize-Disk {}
        Mock Get-Volume {}
        Mock New-OSDCloudPartitionSystem {}
        Mock New-OSDCloudPartitionWindows {}
        Mock Get-OSDCloudDisk {}
        Mock Invoke-DiskpartClean {}
        Mock Write-Host {}
    }

    It 'forwards fixed Windows sizing and custom labels and sizes' {
        New-OSDCloudDisk -DiskNumber 0 -PartitionStyle GPT -Force -Confirm:$false `
            -LabelWindows Windows -LabelRecovery WinRE -SizeSystemGpt 1GB -SizeWindows 32GB -SizeRecovery 3GB
        Should -Invoke New-OSDCloudPartitionSystem -Times 1 -Exactly -ParameterFilter { $DiskNumber -eq 0 -and $SizeSystemGpt -eq 1GB -and $SizeMSR -eq 16MB }
        Should -Invoke New-OSDCloudPartitionWindows -Times 1 -Exactly -ParameterFilter {
            $DiskNumber -eq 0 -and $SizeWindows -eq 32GB -and $SizeRecovery -eq 3GB -and $LabelWindows -eq 'Windows' -and $LabelRecovery -eq 'WinRE'
        }
    }

    It 'does not forward an omitted Windows size as zero' {
        New-OSDCloudDisk -PartitionStyle GPT -Force -Confirm:$false
        Should -Invoke New-OSDCloudPartitionWindows -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey('SizeWindows') }
    }

    It 'fails capacity preflight before initialization, cleaning or partitioning' {
        { New-OSDCloudDisk -PartitionStyle GPT -Force -SizeWindows 256GB -Confirm:$false } | Should -Throw '*target disk capacity*'
        Should -Invoke Initialize-Disk -Times 0 -Exactly
        Should -Invoke Invoke-DiskpartClean -Times 0 -Exactly
        Should -Invoke New-OSDCloudPartitionSystem -Times 0 -Exactly
        Should -Invoke New-OSDCloudPartitionWindows -Times 0 -Exactly
    }
}
