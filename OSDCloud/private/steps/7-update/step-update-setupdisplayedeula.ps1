function step-update-setupdisplayedeula {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    #region Main
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Updating the OOBE SetupDisplayedEula value in the registry. OK."
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Loading offline SOFTWARE hive from C:\Windows\System32\Config\SOFTWARE."
    $null = reg load HKLM\TempSOFTWARE "C:\Windows\System32\Config\SOFTWARE"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Setting SetupDisplayedEula to 1 in offline SOFTWARE hive."
    $null = reg add HKLM\TempSOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE /v SetupDisplayedEula /t REG_DWORD /d 0x00000001 /f
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unloading offline SOFTWARE hive."
    $null = reg unload HKLM\TempSOFTWARE
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
