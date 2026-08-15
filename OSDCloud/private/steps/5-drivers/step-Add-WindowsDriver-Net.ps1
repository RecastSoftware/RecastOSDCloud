function step-Add-WindowsDriver-Net {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    $LogPath = "C:\Windows\Temp\osdcloud-logs"

    $DriverPath = "C:\Windows\Temp\osdcloud-drivers-net"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPath: $DriverPath; LogPath: $LogPath"

    if (Test-Path -Path $DriverPath) {
        if (-not (Test-Path -Path $LogPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating log path: $LogPath"
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver from network driver path."
        Add-WindowsDriver -Path "C:\" -Driver "$DriverPath" -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-net.log" -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPath was not found. Skipping network driver injection."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
