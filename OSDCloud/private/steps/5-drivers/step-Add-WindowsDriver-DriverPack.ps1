function step-Add-WindowsDriver-DriverPack {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    $LogPath = "C:\Windows\Temp\osdcloud-logs"

    $DriverPath = "C:\Windows\Temp\osdcloud-driverpack-expand"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPath: $DriverPath; LogPath: $LogPath"

    if ($global:OSDCloudWorkflowInvoke.ModelDriversCacheObject) {
        if (-not $global:OSDCloudWorkflowInvoke.ModelDriversStaged -or
            -not (Test-Path -LiteralPath $DriverPath -PathType Container)) {
            throw 'ModelDrivers staging did not complete. Refusing to inject an unrelated driver source.'
        }
        if (-not (Test-Path -LiteralPath $LogPath)) {
            New-Item -ItemType Directory -Path $LogPath -Force -ErrorAction Stop | Out-Null
        }
        Add-WindowsDriver -Path 'C:\' -Driver $DriverPath -Recurse -ForceUnsigned `
            -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction Stop | Out-Null
        return
    }
    
    if (Test-Path -Path $DriverPath) {
        if (-not (Test-Path -Path $LogPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating log path: $LogPath"
            New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver from expanded driver pack path."
        Add-WindowsDriver -Path "C:\" -Driver "$DriverPath" -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction SilentlyContinue | Out-Null
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPath was not found. Skipping driver pack injection."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
