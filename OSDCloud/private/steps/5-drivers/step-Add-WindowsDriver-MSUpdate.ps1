function step-Add-WindowsDriver-MSUpdate {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    $LogPath = "C:\Windows\Temp\osdcloud-logs"

    $DriverPath = "C:\Windows\Temp\osdcloud-drivers-msupdate"

    if (Test-Path -Path $DriverPath) {
        if (-not (Test-Path -Path $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        Add-WindowsDriver -Path "C:\" -Driver "$DriverPath" -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-msupdate.log" -ErrorAction SilentlyContinue
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
