function step-finalize-exportofflineosinfo {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    #=================================================
    #region Main
    $StepLogPath = "C:\Windows\Temp\osdcloud-logs"

    #Grab Build from WinPE, as 24H2 has issues with some of these commands:
    $CurrentOSInfo = Get-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $CurrentOSBuild = $($CurrentOSInfo.GetValue('CurrentBuild'))

    #=================================================
    #Get-AppxProvisionedPackage
    $StepLogFile = (Join-Path $StepLogPath 'Get-AppxProvisionedPackage.txt')
    try {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Get-AppxProvisionedPackage.txt"
        $Report = Get-AppxProvisionedPackage -Path C:\ -ErrorAction Stop
        if ($Report) {
            $Report | Select-Object * | Sort-Object DisplayName | Out-File -FilePath $StepLogFile -Force -Encoding ascii
        }
    }
    catch {
        Write-Verbose "[$(Get-Date -format s)] Unable to export $StepLogFile"
    }

    #=================================================
    #Get-WindowsCapability
    $StepLogFile = (Join-Path $StepLogPath 'Get-WindowsCapability.txt')
    try {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Get-WindowsCapability.txt"
        $Report = Get-WindowsCapability -Path C:\ -ErrorAction Stop
        if ($Report) {
            $Report | Sort-Object Name | Select-Object Name, State | Out-File -FilePath $StepLogFile -Force -Encoding ascii
        }
    }
    catch {
        Write-Verbose "[$(Get-Date -format s)] Unable to export $StepLogFile"
    }

    #=================================================
    #Get-WindowsEdition
    $StepLogFile = (Join-Path $StepLogPath 'Get-WindowsEdition.txt')
    try {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Get-WindowsEdition.txt"
        $Report = Get-WindowsEdition -Path C:\ -ErrorAction Stop
        if ($Report) {
            $Report | Select-Object Edition | Out-File -FilePath $StepLogFile -Force -Encoding ascii
        }
    }
    catch {
        Write-Verbose "[$(Get-Date -format s)] Unable to export $StepLogFile"
    }

    #=================================================
    #Get-WindowsOptionalFeature
    $StepLogFile = (Join-Path $StepLogPath 'Get-WindowsOptionalFeature.txt')
    try {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Get-WindowsOptionalFeature.txt"
        $Report = Get-WindowsOptionalFeature -Path C:\ -ErrorAction Stop
        if ($Report) {
            $Report | Sort-Object FeatureName | Select-Object FeatureName, State | Out-File -FilePath $StepLogFile -Force -Encoding ascii
        }
    }
    catch {
        Write-Verbose "[$(Get-Date -format s)] Unable to export $StepLogFile"
    }

    #=================================================
    #Get-WindowsPackage
    $StepLogFile = (Join-Path $StepLogPath 'Get-WindowsPackage.txt')
    try {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Get-WindowsPackage.txt"
        $Report = Get-WindowsPackage -Path C:\ -ErrorAction Stop
        if ($Report) {
            $Report | Sort-Object PackageName | Select-Object PackageName, PackageState, ReleaseType | Out-File -FilePath $StepLogFile -Force -Encoding ascii
        }
    }
    catch {
        Write-Verbose "[$(Get-Date -format s)] Unable to export $StepLogFile"
    }

    #endregion
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
