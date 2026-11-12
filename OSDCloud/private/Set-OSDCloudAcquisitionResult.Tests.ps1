BeforeAll {
    . "$PSScriptRoot\Set-OSDCloudAcquisitionResult.ps1"
    . "$PSScriptRoot\Invoke-OSDCloudTimedOperation.ps1"
    . "$PSScriptRoot\steps\4-install\step-install-downloadwindowsimage.ps1"
    . "$PSScriptRoot\steps\5-drivers\step-Save-WindowsDriver-DriverPack.ps1"
    function Get-DeviceUSBVolume { [CmdletBinding()] param () }
    function Invoke-RecastOSDDownloadFile {
        [CmdletBinding()]
        param ($SourceUrl, $DestinationDirectory, $DestinationName)
    }
    function Resolve-OSDCoreModelDriversPath { [CmdletBinding()] param ($CacheObject) }
    function Expand { [CmdletBinding()] param ([switch]$R, $F, [Parameter(ValueFromRemainingArguments)]$Arguments) }
    function 7za { [CmdletBinding()] param ($Mode, $File, $Destination) }
    function Add-WindowsDriver { [CmdletBinding()] param ($Path, $Driver, [switch]$Recurse, [switch]$ForceUnsigned, $LogPath) }
    function Get-ChildItem {
        [CmdletBinding()]
        param ($Path, $LiteralPath, $Include, $Filter, [switch]$File, [switch]$Recurse, [switch]$Force)
    }
    $originalInvoke = Get-Variable -Name OSDCloudWorkflowInvoke -Scope Global -ErrorAction SilentlyContinue
    $originalNativeExitCode = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
}

AfterAll {
    if ($originalInvoke) { $global:OSDCloudWorkflowInvoke = $originalInvoke.Value }
    else { Remove-Variable -Name OSDCloudWorkflowInvoke -Scope Global -ErrorAction SilentlyContinue }
    if ($originalNativeExitCode) { $global:LASTEXITCODE = $originalNativeExitCode.Value }
    else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
}

Describe 'OS and driver pack acquisition measurements' {
    BeforeEach {
        $global:OSDCloudWorkflowInvoke = [ordered]@{
            OperatingSystemCloudObject = [pscustomobject]@{
                FilePath = 'https://example.invalid/os.esd'; FileName = 'os.esd'
            }
            OperatingSystemCacheObject = $null
            FileInfoWindowsImage = $null
            WindowsImagePath = $null
            DriverPackName = 'Test pack'
            DriverPackCloudObject = [pscustomobject]@{
                Url = 'https://example.invalid/pack.unknown'; FileName = 'pack.unknown'; Manufacturer = 'OEM'
            }
            ModelDriversCacheObject = $null
            ModelDriversStaged = $false
            OSAcquisition = $null
            DriverPackAcquisition = $null
        }
        $osFile = [pscustomobject]@{ Name = 'os.esd'; FullName = 'C:\OSDCloud\OS\os.esd'; Length = 5.5MB }
        $packFile = [pscustomobject]@{
            Name = 'pack.unknown'; FullName = 'C:\Windows\Temp\osdcloud-driverpack-download\pack.unknown'
            Length = [long]1.49MB; Extension = '.unknown'
        }
        Mock Write-Host {}
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200 } }
        Mock Get-PSDrive { [pscustomobject]@{ Name = 'F' } }
        Mock Get-ChildItem {}
        Mock Get-DeviceUSBVolume {}
        Mock Join-Path { "$($Path.TrimEnd('\'))\$ChildPath" }
        $script:downloadReady = $false
        Mock Test-Path {
            if ($PathType -eq 'Leaf') { $script:downloadReady }
            else { $true }
        }
        Mock New-Item {}
        Mock Remove-Item {}
        Mock Copy-Item { [System.Threading.Thread]::Sleep(20) }
        Mock Out-File {}
        Mock Get-Item {
            if ("$LiteralPath $Path" -like '*pack.unknown*') { $packFile }
            else { $osFile }
        }
        Mock Invoke-RecastOSDDownloadFile {
            [System.Threading.Thread]::Sleep(20)
            $script:downloadReady = $true
            if ($SourceUrl -like '*pack.unknown') { $packFile } else { $osFile }
        }
    }

    It 'measures the selected OS cache without network access' {
        $global:OSDCloudWorkflowInvoke.OperatingSystemCacheObject = 'F:\OSDCloud\OS\os.esd'
        step-install-downloadwindowsimage
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Bytes | Should -Be 5.5MB
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Copied | Should -BeTrue
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Downloaded | Should -BeFalse
        $global:OSDCloudWorkflowInvoke.Durations.stepOSCopy | Should -BeGreaterOrEqual 0
        $global:OSDCloudWorkflowInvoke.Durations.stepOSDownload | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke Invoke-RecastOSDDownloadFile -Times 0 -Exactly
    }

    It 'measures an OS discovered offline' {
        Mock Get-ChildItem { $osFile }
        step-install-downloadwindowsimage
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Bytes | Should -Be 5.5MB
        Should -Invoke Invoke-RecastOSDDownloadFile -Times 0 -Exactly
    }

    It 'measures OS downloads including USB cache copy: USB=<USB>' -TestCases @(
        @{ USB = $false }
        @{ USB = $true }
    ) {
        param ($USB)
        if ($USB) {
            Mock Get-DeviceUSBVolume {
                [pscustomobject]@{ DriveLetter = 'F'; FileSystemLabel = 'OSDCloud'; SizeGB = 64; SizeRemainingGB = 32 }
            }
        }
        step-install-downloadwindowsimage
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Bytes | Should -Be 5.5MB
        $phase = if ($USB) { 'stepOSCache' } else { 'stepOSDownload' }
        $otherPhase = if ($USB) { 'stepOSDownload' } else { 'stepOSCache' }
        $global:OSDCloudWorkflowInvoke.Durations[$phase] | Should -BeGreaterOrEqual 0.02
        $global:OSDCloudWorkflowInvoke.Durations[$otherPhase] | Should -BeNullOrEmpty
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Downloaded | Should -Be (-not $USB)
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Cached | Should -Be $USB
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Copied | Should -Be $USB
        if ($USB) { $global:OSDCloudWorkflowInvoke.Durations.stepOSCopy | Should -BeGreaterOrEqual 0.02 }
        else { $global:OSDCloudWorkflowInvoke.Durations.stepOSCopy | Should -BeNullOrEmpty }
        Should -Invoke Invoke-RecastOSDDownloadFile -Times 1 -Exactly
        Should -Invoke Copy-Item -Times ([int]$USB) -Exactly
    }

    It 'measures a driver pack copied from offline cache' {
        $script:downloadReady = $true
        Mock Invoke-WebRequest { throw 'Offline' }
        Mock Get-ChildItem { $packFile }
        step-Save-WindowsDriver-DriverPack
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Bytes | Should -Be ([long]1.49MB)
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackCopy | Should -BeGreaterOrEqual 0.02
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Copied | Should -BeTrue
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Downloaded | Should -BeFalse
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackDownload | Should -BeNullOrEmpty
        Should -Invoke Copy-Item -Times 1 -Exactly
        Should -Invoke Invoke-RecastOSDDownloadFile -Times 0 -Exactly
    }

    It 'measures driver pack downloads including USB cache copy: USB=<USB>' -TestCases @(
        @{ USB = $false }
        @{ USB = $true }
    ) {
        param ($USB)
        if ($USB) {
            Mock Get-DeviceUSBVolume {
                [pscustomobject]@{ DriveLetter = 'F'; FileSystemLabel = 'OSDCloud'; SizeGB = 64; SizeRemainingGB = 32 }
            }
        }
        step-Save-WindowsDriver-DriverPack
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Bytes | Should -Be ([long]1.49MB)
        $phase = if ($USB) { 'stepDriverPackCache' } else { 'stepDriverPackDownload' }
        $otherPhase = if ($USB) { 'stepDriverPackDownload' } else { 'stepDriverPackCache' }
        $global:OSDCloudWorkflowInvoke.Durations[$phase] | Should -BeGreaterOrEqual 0.02
        $global:OSDCloudWorkflowInvoke.Durations[$otherPhase] | Should -BeNullOrEmpty
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Downloaded | Should -Be (-not $USB)
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Cached | Should -Be $USB
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Copied | Should -Be $USB
        if ($USB) { $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackCopy | Should -BeGreaterOrEqual 0.02 }
        else { $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackCopy | Should -BeNullOrEmpty }
        Should -Invoke Invoke-RecastOSDDownloadFile -Times 1 -Exactly
        Should -Invoke Copy-Item -Times ([int]$USB) -Exactly
    }

    It 'measures ModelDrivers content after a successful cache copy' {
        $global:OSDCloudWorkflowInvoke.ModelDriversCacheObject = 'cache'
        Mock Resolve-OSDCoreModelDriversPath { 'F:\ModelDrivers' }
        Mock Test-Path { $false }
        Mock Get-ChildItem {
            [pscustomobject]@{ FullName = 'F:\ModelDrivers\driver.inf'; Length = 1.25MB }
            [pscustomobject]@{ FullName = 'F:\ModelDrivers\driver.sys'; Length = 7MB }
        }
        Mock Get-ChildItem {
            [pscustomobject]@{ FullName = 'C:\Windows\Temp\osdcloud-driverpack-expand\nested\driver.inf'; Length = 0.5MB }
            [pscustomobject]@{ FullName = 'C:\Windows\Temp\osdcloud-driverpack-expand\nested\driver.sys'; Length = 2MB }
            [pscustomobject]@{ FullName = 'C:\Windows\Temp\osdcloud-driverpack-expand\hidden.dat'; Length = 1.25MB }
        } -ParameterFilter {
            $LiteralPath -eq 'C:\Windows\Temp\osdcloud-driverpack-expand' -and $Recurse -and $File -and $Force
        }
        step-Save-WindowsDriver-DriverPack
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged | Should -BeTrue
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Bytes | Should -Be 3.75MB
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Copied | Should -BeTrue
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Downloaded | Should -BeFalse
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Cached | Should -BeFalse
        $global:OSDCloudWorkflowInvoke.CompletedTransfers.stepDriverPackCopy | Should -BeTrue
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackCopy | Should -BeGreaterOrEqual 0.02
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackDownload | Should -BeNullOrEmpty
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackCache | Should -BeNullOrEmpty
        Should -Invoke Copy-Item -Times 2 -Exactly -ParameterFilter {
            $LiteralPath -like 'F:\ModelDrivers\*' -and
            $Destination -eq 'C:\Windows\Temp\osdcloud-driverpack-expand' -and $Recurse -and $Force
        }
        Should -Invoke Get-ChildItem -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq 'C:\Windows\Temp\osdcloud-driverpack-expand' -and
            $Recurse -and $File -and $Force -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Invoke-RecastOSDDownloadFile -Times 0 -Exactly
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'measures a driver download once after USB failure and local fallback' {
        Mock Get-DeviceUSBVolume {
            [pscustomobject]@{ DriveLetter = 'F'; FileSystemLabel = 'OSDCloud'; SizeGB = 64; SizeRemainingGB = 32 }
        }
        Mock Invoke-RecastOSDDownloadFile { throw 'USB unavailable' } -ParameterFilter { $DestinationDirectory -like 'F:\*' }
        step-Save-WindowsDriver-DriverPack
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Bytes | Should -Be ([long]1.49MB)
        Should -Invoke Invoke-RecastOSDDownloadFile -Times 2 -Exactly
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Cached | Should -BeFalse
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition.Downloaded | Should -BeTrue
    }

    It 'retains a completed USB OS download when the subsequent local copy fails' {
        Mock Get-DeviceUSBVolume {
            [pscustomobject]@{ DriveLetter = 'F'; FileSystemLabel = 'OSDCloud'; SizeGB = 64; SizeRemainingGB = 32 }
        }
        Mock Copy-Item { throw 'Local copy failed' }
        { step-install-downloadwindowsimage } | Should -Throw '*Local copy failed*'
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Bytes | Should -Be 5.5MB
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Cached | Should -BeTrue
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Copied | Should -BeFalse
        $global:OSDCloudWorkflowInvoke.OSAcquisition.Downloaded | Should -BeFalse
    }

    It 'does not record a failed OS download as acquired content' {
        Mock Invoke-RecastOSDDownloadFile { throw 'OS acquisition failed' }
        { step-install-downloadwindowsimage } | Should -Throw '*OS acquisition failed*'
        $global:OSDCloudWorkflowInvoke.OSAcquisition | Should -BeNullOrEmpty
    }

    It 'classifies download-helper cache reuse as copy rather than network download' {
        $script:downloadReady = $true
        step-Save-WindowsDriver-DriverPack
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackDownload | Should -BeNullOrEmpty
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackCopy | Should -BeGreaterOrEqual 0.02
    }

    It 'finishes OS acquisition timing before hash verification' {
        $global:OSDCloudWorkflowInvoke.OperatingSystemCloudObject | Add-Member -NotePropertyName Sha256 -NotePropertyValue 'abc'
        Mock Get-FileHash {
            $script:durationAtVerification = $global:OSDCloudWorkflowInvoke.Durations.stepOSDownload
            [pscustomobject]@{ Hash = 'abc' }
        }
        step-install-downloadwindowsimage
        Should -Invoke Get-FileHash -Times 1 -Exactly
        $script:durationAtVerification | Should -BeGreaterOrEqual 0.02
        $global:OSDCloudWorkflowInvoke.Durations.stepOSDownload | Should -Be $script:durationAtVerification
    }

    It 'does not invent sizes for bypassed or failed driver acquisition: Mode=<Mode>' -TestCases @(
        @{ Mode = 'None' }
        @{ Mode = 'Failed' }
    ) {
        param ($Mode)
        if ($Mode -eq 'None') { $global:OSDCloudWorkflowInvoke.DriverPackName = 'None' }
        else { Mock Invoke-RecastOSDDownloadFile { throw 'Acquisition failed' } }
        step-Save-WindowsDriver-DriverPack
        $global:OSDCloudWorkflowInvoke.DriverPackAcquisition | Should -BeNullOrEmpty
    }

    It 'times driver expansion separately from injection: <Format>' -TestCases @(
        @{ Format = 'CAB' }
        @{ Format = 'ZIP' }
        @{ Format = 'Dell' }
        @{ Format = 'HP' }
    ) {
        param ($Format)
        $packFile.Extension = if ($Format -in @('CAB', 'ZIP')) { ".$($Format.ToLowerInvariant())" } else { '.exe' }
        $packFile | Add-Member -NotePropertyName VersionInfo -NotePropertyValue ([pscustomobject]@{
            FileDescription = if ($Format -eq 'Dell') { 'Dell' } else { 'Test' }
            InternalName = if ($Format -eq 'HP') { 'hpsoftpaqwrapper' } else { 'Test' }
        })
        Mock Expand { [System.Threading.Thread]::Sleep(30); $global:LASTEXITCODE = 0 }
        Mock Expand-Archive { [System.Threading.Thread]::Sleep(30) }
        Mock Start-Process { [System.Threading.Thread]::Sleep(30); [pscustomobject]@{ ExitCode = 0 } }
        Mock 7za { [System.Threading.Thread]::Sleep(30); $global:LASTEXITCODE = 0 }
        Mock Add-WindowsDriver {
            $script:durationBeforeInjection = $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackExpand
            [System.Threading.Thread]::Sleep(30)
        }
        step-Save-WindowsDriver-DriverPack
        Should -Invoke Add-WindowsDriver -Times 1 -Exactly
        $script:durationBeforeInjection | Should -BeGreaterOrEqual 0.03
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackExpand | Should -Be $script:durationBeforeInjection
    }

    It 'preserves native extraction failure handling: <Format>' -TestCases @(
        @{ Format = 'CAB' }
        @{ Format = 'HP' }
    ) {
        param ($Format)
        $packFile.Extension = if ($Format -eq 'CAB') { '.cab' } else { '.exe' }
        $packFile | Add-Member -NotePropertyName VersionInfo -NotePropertyValue ([pscustomobject]@{ InternalName = 'hpsoftpaqwrapper' })
        Mock Expand { $global:LASTEXITCODE = 7 }
        Mock 7za { $global:LASTEXITCODE = 7 }
        Mock Add-WindowsDriver {}
        step-Save-WindowsDriver-DriverPack
        Should -Invoke Add-WindowsDriver -Times 0 -Exactly
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackExpand | Should -Not -BeNullOrEmpty
    }
}
