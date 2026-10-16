BeforeAll {
    . "$PSScriptRoot\step-install-expandwindowsimage.ps1"
    . "$PSScriptRoot\..\..\Invoke-OSDCloudTimedOperation.ps1"
    function Expand-WindowsImage {}
    function Out-File {
        param ($FilePath, [switch]$Append, $Encoding, $Width, [switch]$Force, $ErrorAction)
        $script:outFileCalls += [pscustomobject]@{
            FilePath    = $FilePath
            ErrorAction = $ErrorAction
        }
    }
    $originalWorkflowInvoke = $global:OSDCloudWorkflowInvoke
    $originalCoreDevice = $global:OSDCoreDevice
}

AfterAll {
    $global:OSDCloudWorkflowInvoke = $originalWorkflowInvoke
    $global:OSDCoreDevice = $originalCoreDevice
}

Describe 'step-install-expandwindowsimage' {
    BeforeEach {
        $script:outFileCalls = @()
        $global:OSDCloudWorkflowInvoke = [ordered]@{
            WindowsImagePath  = 'C:\OSDCloud\OS\install.wim'
            WindowsImageIndex = 1
        }
        $global:OSDCoreDevice = [pscustomobject]@{ IsWinPE = $true }
        Mock Test-Path { $false }
        Mock New-Item {}
        Mock Expand-WindowsImage {}
        Mock Remove-Item {}
        Mock Write-Host {}
    }

    It 'uses terminating errors when creating and writing setup scripts' {
        step-install-expandwindowsimage

        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\Windows\Setup\Scripts' -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\Windows\Setup\Scripts\SetupComplete.cmd' -and $ErrorAction -eq 'Stop'
        }
        $script:outFileCalls.Count | Should -Be 2
        $script:outFileCalls | Where-Object FilePath -eq 'C:\Windows\Setup\Scripts\SetupComplete.cmd' |
            Select-Object -ExpandProperty ErrorAction | Should -Be 'Stop'
        $script:outFileCalls | Where-Object FilePath -eq 'C:\Windows\Setup\Scripts\OOBE.cmd' |
            Select-Object -ExpandProperty ErrorAction | Should -Be 'Stop'
    }

    It 'captures only Windows expansion, not setup script creation' {
        Mock Expand-WindowsImage { [System.Threading.Thread]::Sleep(30) }
        Mock New-Item {
            if ($Path -eq 'C:\Windows\Setup\Scripts') {
                $script:expansionTime = $global:OSDCloudWorkflowInvoke.Durations.stepOSExpand
                [System.Threading.Thread]::Sleep(30)
            }
        }
        step-install-expandwindowsimage
        $script:expansionTime | Should -BeGreaterOrEqual 0.03
        $global:OSDCloudWorkflowInvoke.Durations.stepOSExpand | Should -Be $script:expansionTime
    }

    It 'does not report Windows expansion outside WinPE' {
        $global:OSDCoreDevice.IsWinPE = $false
        step-install-expandwindowsimage
        $global:OSDCloudWorkflowInvoke.Durations | Should -BeNullOrEmpty
        Should -Invoke Expand-WindowsImage -Times 0 -Exactly
    }
}
