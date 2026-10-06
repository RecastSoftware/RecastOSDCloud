BeforeAll {
    . "$PSScriptRoot\step-install-expandwindowsimage.ps1"
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
}
