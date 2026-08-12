function step-preinstall-enablehighperformance {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    if ($global:OSDCoreDevice.IsOnBattery -eq $true) {
        $classWin32Battery = (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -Property *)
        if ($classWin32Battery.BatteryStatus -eq 1) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Device has $($classWin32Battery.EstimatedChargeRemaining)% battery remaining"
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] High Performance will not be enabled while on battery"
    }
    else {
        # Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] powercfg.exe -SetActive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        powercfg.exe -SetActive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
