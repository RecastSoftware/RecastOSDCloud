function step-Add-WindowsDriver-OemWinRE {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    $LogPath = "C:\Windows\Temp\osdcloud-logs"
    $DriverPath = "C:\Windows\Temp\osdcloud-drivers-winpe"
    $WinrePath = "C:\Windows\System32\Recovery\winre.wim"
    $WinreMountPath = "C:\Windows\Temp\mount-winre"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPath: $DriverPath; WinrePath: $WinrePath; WinreMountPath: $WinreMountPath; LogPath: $LogPath"

    if ((Test-Path -Path $DriverPath) -and (Test-Path -Path $WinrePath)) {
        if (-not (Test-Path -Path $LogPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating log path: $LogPath"
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        if (-not (Test-Path -Path $WinreMountPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating WinRE mount path: $WinreMountPath"
            New-Item -ItemType Directory -Path $WinreMountPath -Force | Out-Null
        }

        $Params = @{
            Path        = $WinreMountPath
            ImagePath   = $WinrePath
            Index       = 1
            LogPath     = "$LogPath\dism-mount-windowsimage-winre.log"
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Mounting WinRE image with parameters: $($Params | Out-String)"
        $MountWinRE = Mount-WindowsImage @Params | Out-Null

        if ($MountWinRE) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver against mounted WinRE image."
            Add-WindowsDriver -Path $WinreMountPath -Driver "$DriverPath" -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-winre.log" -ErrorAction SilentlyContinue
        }
        else {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Mount-WindowsImage did not return a mount result."
        }

        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Dismounting WinRE image and saving changes."
        Dismount-WindowsImage -Path $WinreMountPath -Save -LogPath "$LogPath\dism-dismount-windowsimage-winre.log" -ErrorAction SilentlyContinue | Out-Null

        if (Test-Path -Path $WinreMountPath) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Removing WinRE mount path: $WinreMountPath"
            Remove-Item -Path $WinreMountPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPath or WinrePath was not found. Skipping WinRE driver injection."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
