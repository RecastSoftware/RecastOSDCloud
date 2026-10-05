function step-update-setupdisplayedeula {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Preparing to update the offline SetupDisplayedEula value'
    $HiveLoaded = $false

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $Step = $global:OSDCloudCurrentStep
        $SoftwareHivePath = 'C:\Windows\System32\Config\SOFTWARE'
        $HiveMount = 'HKLM\TempSOFTWARE'
        $OobeKey = 'HKLM\TempSOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE'

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Updating the offline Windows OOBE SetupDisplayedEula registry value."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Loading the offline SOFTWARE hive from:"
        Write-Host -ForegroundColor DarkGray "  $SoftwareHivePath"

        $ProgressPhase = 'Loading the offline SOFTWARE registry hive'
        & reg.exe load $HiveMount $SoftwareHivePath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "reg.exe load returned exit code $LASTEXITCODE."
        }
        $HiveLoaded = $true

        $ProgressPhase = 'Setting SetupDisplayedEula in the offline registry'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Setting SetupDisplayedEula to 1 under:"
        Write-Host -ForegroundColor DarkGray "  $OobeKey"
        & reg.exe add $OobeKey /v SetupDisplayedEula /t REG_DWORD /d 0x00000001 /f | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "reg.exe add returned exit code $LASTEXITCODE."
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] SetupDisplayedEula was updated successfully."
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional SetupDisplayedEula update failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing OSDCloud without the SetupDisplayedEula update."
    }
    finally {
        if ($HiveLoaded) {
            try {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Unloading the offline SOFTWARE registry hive."
                & reg.exe unload $HiveMount | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] reg.exe unload returned exit code $LASTEXITCODE for $HiveMount."
                }
            }
            catch {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Could not unload the offline SOFTWARE hive: $($_.Exception.Message)"
            }
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    #=================================================
}
