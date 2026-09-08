function step-Add-WindowsDriver-Firmware {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    if ($global:OSDCloudWorkflowInvoke.SkipFirmwareUpdate -eq $true) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] SkipFirmwareUpdate is true."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Firmware update steps were disabled by -SkipFirmwareUpdate. Skip."
        return
    }

    $LogPath = "C:\Windows\Temp\osdcloud-logs"

    $DriverPath = "C:\Windows\Temp\osdcloud-drivers-firmware"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPath: $DriverPath; LogPath: $LogPath"

    if (Test-Path -Path $DriverPath) {
        if (-not (Test-Path -Path $LogPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating log path: $LogPath"
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver from firmware driver path."
        Add-WindowsDriver -Path "C:\" -Driver "$DriverPath" -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-firmware.log" -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPath was not found. Skipping firmware driver injection."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
