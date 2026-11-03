BeforeAll {
    . "$PSScriptRoot\step-Save-WindowsDriver-DriverPack.ps1"
    . "$PSScriptRoot\..\..\Invoke-OSDCloudTimedOperation.ps1"
    . "$PSScriptRoot\..\..\Set-OSDCloudAcquisitionResult.ps1"
    function Get-DeviceUSBVolume { [CmdletBinding()] param() }
    function Invoke-RecastOSDDownloadFile { [CmdletBinding()] param($SourceUrl,$DestinationDirectory) }
    $originalDeploy = $global:OSDCloudDeploy
    $originalInvoke = $global:OSDCloudWorkflowInvoke
}
AfterAll { $global:OSDCloudDeploy = $originalDeploy; $global:OSDCloudWorkflowInvoke = $originalInvoke }

Describe 'Opted-in PreOOBE OEM handoff' {
    BeforeEach {
        $global:OSDCloudDeploy = @{ WorkflowTaskObject = @{ steps = @(@{ command = 'step-update-preoobe'; skip = $false }) } }
        $global:OSDCloudWorkflowInvoke = @{}
        $package = Join-Path $TestDrive 'Lenovo.exe'
        [IO.File]::WriteAllText($package,'Inert')
        $script:packFile = Get-Item $package
        $cloud = @{ Manufacturer = 'Lenovo'; FileName = 'Lenovo.exe'; Url = 'https://invalid.example/Lenovo.exe' }
        Mock Write-Host {}
        Mock Test-Path { $true }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*OSDCloudPreOOBE.DriverPack.json' }
        Mock Invoke-WebRequest { @{ StatusCode = 200 } }
        Mock Get-PSDrive {}
        Mock Get-DeviceUSBVolume {}
        Mock Invoke-RecastOSDDownloadFile { $script:packFile }
        Mock Invoke-OSDCloudTimedOperation { & $Action }
        Mock Set-OSDCloudAcquisitionResult {}
        Mock Get-Item { $script:packFile }
        Mock Out-File {}
        Mock Remove-Item {}
        Mock Save-OSDCloudPreOOBEDriverManifest {}
    }

    It 'defers Lenovo to the engine without writing SetupComplete installation commands' {
        step-Save-WindowsDriver-DriverPack -DriverPackName Lenovo -DriverPackCloudObject $cloud -PreOOBE
        Should -Invoke Save-OSDCloudPreOOBEDriverManifest -Times 1 -Exactly
        Should -Invoke Out-File -Times 0 -ParameterFilter { $FilePath -like '*SetupComplete.cmd' }
    }

    It 'defers Surface MSI to the engine without writing SetupComplete commands' {
        $package = Join-Path $TestDrive 'Surface.msi'
        [IO.File]::WriteAllText($package,'Inert')
        $script:packFile = [IO.FileInfo]::new($package)
        $cloud.Manufacturer = 'Microsoft'; $cloud.FileName = 'Surface.msi'
        step-Save-WindowsDriver-DriverPack -DriverPackName Surface -DriverPackCloudObject $cloud -PreOOBE
        Should -Invoke Save-OSDCloudPreOOBEDriverManifest -Times 1 -Exactly
        Should -Invoke Out-File -Times 0 -ParameterFilter { $FilePath -like '*SetupComplete.cmd' }
    }

    It 'retains existing driver handling if the PreOOBE step is disabled' {
        $global:OSDCloudDeploy.WorkflowTaskObject.steps[0].skip = $true
        step-Save-WindowsDriver-DriverPack -DriverPackName Lenovo -DriverPackCloudObject $cloud -PreOOBE
        Should -Invoke Save-OSDCloudPreOOBEDriverManifest -Times 0 -Exactly
        Should -Invoke Out-File -Times 1 -ParameterFilter { $FilePath -like '*SetupComplete.cmd' }
    }

    It 'does not change other task sequences without explicit opt-in' {
        step-Save-WindowsDriver-DriverPack -DriverPackName Lenovo -DriverPackCloudObject $cloud
        Should -Invoke Save-OSDCloudPreOOBEDriverManifest -Times 0 -Exactly
        Should -Invoke Out-File -Times 1 -ParameterFilter { $FilePath -like '*SetupComplete.cmd' }
    }
}
