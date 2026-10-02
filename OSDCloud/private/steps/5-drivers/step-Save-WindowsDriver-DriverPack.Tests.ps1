BeforeAll {
    . "$PSScriptRoot\step-Save-WindowsDriver-DriverPack.ps1"
    . "$PSScriptRoot\step-Add-WindowsDriver-DriverPack.ps1"
    . "$PSScriptRoot\..\2-test\step-test-targetdriverpack.ps1"
    . "$PSScriptRoot\..\..\core-driverpack\Resolve-OSDCoreModelDriversPath.ps1"
    $originalInvoke = $global:OSDCloudWorkflowInvoke
}

AfterAll {
    $global:OSDCloudWorkflowInvoke = $originalInvoke
}

Describe 'ModelDrivers shared workflow validation, staging, and injection' {
    BeforeEach {
        $sourcePath = 'F:\OSDCloud\modeldrivers-amd64\HP_8CD1_Model [description]_26200.100'
        $expandPath = 'C:\Windows\Temp\osdcloud-driverpack-expand'
        $global:OSDCloudWorkflowInvoke = [ordered]@{
            DriverPackName = 'None'
            DriverPackCloudObject = $null
            ModelDriversCacheObject = [pscustomobject]@{ Type = 'ModelDrivers'; FullName = $sourcePath }
            ModelDriversStaged = $false
        }
        Mock Resolve-OSDCoreModelDriversPath { $sourcePath }
        Mock Invoke-WebRequest { throw 'Unexpected OEM network access' }
        Mock Test-Path { $false }
        Mock New-Item {}
        Mock Get-ChildItem {
            [pscustomobject]@{ Name = 'nested'; FullName = "$sourcePath\nested" }
        }
        Mock Get-ChildItem {
            [pscustomobject]@{ Name = 'driver.inf'; FullName = "$expandPath\nested\driver.inf" }
        } -ParameterFilter { $LiteralPath -eq $expandPath -and $Filter -eq '*.inf' }
        Mock Copy-Item {}
        Mock Add-WindowsDriver {}
        Mock Write-Host {}
    }

    It 'validates ModelDrivers before OEM bypasses or network tests' {
        step-test-targetdriverpack
        Should -Invoke Resolve-OSDCoreModelDriversPath -Times 1 -Exactly
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke Get-ChildItem -Times 0 -Exactly
    }

    It 'stops validation before disk clearing when the source is unsafe or missing' {
        Mock Resolve-OSDCoreModelDriversPath {}
        { step-test-targetdriverpack } | Should -Throw '*Stopping before disk clearing*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'stages ModelDrivers without OEM downloads even with a bypass name' {
        step-Save-WindowsDriver-DriverPack
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged | Should -BeTrue
        Should -Invoke Resolve-OSDCoreModelDriversPath -Times 1 -Exactly
        Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq "$sourcePath\nested" -and $Destination -eq $expandPath -and $Recurse -and $Force -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'injects staged ModelDrivers into the offline Windows image' {
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged = $true
        Mock Test-Path { $true }
        step-Add-WindowsDriver-DriverPack
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'C:\' -and $Driver -eq $expandPath -and $Recurse -and $ForceUnsigned -and
            $LogPath -eq 'C:\Windows\Temp\osdcloud-logs\dism-add-windowsdriver-driverpack.log' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'does not change to OEM drivers if the selected source disappears after disk clearing' {
        Mock Resolve-OSDCoreModelDriversPath {}
        { step-Save-WindowsDriver-DriverPack } | Should -Throw '*no longer available*'
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged | Should -BeFalse
        Should -Invoke Copy-Item -Times 0 -Exactly
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'refuses to mix ModelDrivers with an existing expansion directory' {
        Mock Test-Path { $true }
        { step-Save-WindowsDriver-DriverPack } | Should -Throw '*Refusing to mix driver sources*'
        Should -Invoke Copy-Item -Times 0 -Exactly
    }

    It 'surfaces staging copy failures without marking staging complete' {
        Mock Copy-Item { throw 'Copy failed' }
        { step-Save-WindowsDriver-DriverPack } | Should -Throw '*Copy failed*'
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged | Should -BeFalse
    }

    It 'fails if staging contains no INF files' {
        Mock Get-ChildItem {} -ParameterFilter { $LiteralPath -eq $expandPath -and $Filter -eq '*.inf' }
        { step-Save-WindowsDriver-DriverPack } | Should -Throw '*No INF files were staged*'
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged | Should -BeFalse
    }

    It 'refuses injection when staging was skipped or incomplete' {
        Mock Test-Path { $true }
        { step-Add-WindowsDriver-DriverPack } | Should -Throw '*staging did not complete*'
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }

    It 'fails if staged content disappears' {
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged = $true
        { step-Add-WindowsDriver-DriverPack } | Should -Throw '*staging did not complete*'
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
    }

    It 'surfaces ModelDrivers injection failures' {
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged = $true
        Mock Test-Path { $true }
        Mock Add-WindowsDriver { throw 'DISM failed' }
        { step-Add-WindowsDriver-DriverPack } | Should -Throw '*DISM failed*'
    }

    It 'retains the original OEM bypass behavior with no ModelDrivers and choice <Choice>' -TestCases @(
        @{ Choice = 'None' }
        @{ Choice = 'Microsoft Update Catalog' }
    ) {
        param ($Choice)
        $global:OSDCloudWorkflowInvoke.DriverPackName = $Choice
        $global:OSDCloudWorkflowInvoke.ModelDriversCacheObject = $null
        step-test-targetdriverpack
        step-Save-WindowsDriver-DriverPack
        Should -Invoke Resolve-OSDCoreModelDriversPath -Times 0 -Exactly
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke Copy-Item -Times 0 -Exactly
    }

    It 'retains existing OEM archive injection behavior when no ModelDrivers are selected' {
        $global:OSDCloudWorkflowInvoke.ModelDriversCacheObject = $null
        Mock Test-Path { $true }
        step-Add-WindowsDriver-DriverPack
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly -ParameterFilter {
            $Driver -eq $expandPath -and $ErrorAction -eq 'SilentlyContinue'
        }
    }
}
