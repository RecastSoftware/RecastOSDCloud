<#
.SYNOPSIS
    Establishes and validates Wi-Fi connectivity in WinPE.

.DESCRIPTION
    Performs Wi-Fi startup operations for WinPE. If internet access is not
    detected, it validates required wireless components and attempts to connect
    by using configured options or interactive Wi-Fi flow. It then validates
    local IP assignment and renews DHCP leases when needed.

.EXAMPLE
    Show-WinPEStartupWifi

    Attempts to establish Wi-Fi connectivity and validates network initialization.

.OUTPUTS
    System.Void

.NOTES
    This function is intended for WinPEStartup workflows.
    If required wireless components are missing, Wi-Fi start is skipped.
#>
function Show-WinPEStartupWifi {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $host.ui.RawUI.WindowTitle = "[$(Get-Date -format s)] OSDCloud - WinPEStartup Wi-Fi"
    #=================================================
    # Test-OSDCloudInternetConnection
    if (Test-OSDCloudInternetConnection -Uri 'google.com') {
        # Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Ping google.com success. Device is already connected to the Internet"
        $StartOSDCloudWifi = $false
    }
    else {
        # Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Ping google.com failed. Will attempt to connect to a Wireless Network"
        $StartOSDCloudWifi = $true
    }
    #=================================================
    # Test WinPE Required Components
    if ($StartOSDCloudWifi) {
        $RequiredDlls = @(
            'dmcmnutils.dll',
            'mdmpostprocessevaluator.dll',
            'mdmregistration.dll',
            'raschap.dll',
            'raschapext.dll',
            'rastls.dll',
            'rastlsext.dll'
        )

        $MissingDlls = @()
        foreach ($Dll in $RequiredDlls) {
            $DllPath = "$ENV:SystemRoot\System32\$Dll"
            if (!(Test-Path -Path $DllPath)) {
                $MissingDlls += $Dll
                $StartOSDCloudWifi = $false
            }
        }

        if (!$StartOSDCloudWifi) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Unable to enable Wireless Network due to missing components"
            if ($MissingDlls.Count -gt 0) {
                Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Missing DLL files: $($MissingDlls -join ', ')"
            }
        }
    }
    #=================================================
    # Invoke-OSDCloudWifi
    if ($StartOSDCloudWifi) {
        if ($WirelessConnect) {
            #TODO - Enable functionality for WirelessConnect.exe
            Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] Starting WirelessConnect.exe"
            Start-Process PowerShell -ArgumentList 'Invoke-OSDCloudWifi -WirelessConnect' -Wait
        }
        elseif ($WifiProfile) {
            #TODO - Enable functionality for Wi-Fi profile connection
            Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] Starting Wi-Fi Profile"
            $Global:WifiProfile = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne 'C' } | ForEach-Object {
                Get-ChildItem "$($_.Root)OSDCloud\Config\Scripts" -Include "WiFiProfile.xml" -File -Recurse -Force -ErrorAction Ignore
            }
            Start-Process PowerShell -ArgumentList "Invoke-OSDCloudWifi -WifiProfile `"$Global:WifiProfile`"" -Wait
        }
        else {
            Write-Verbose "[$(Get-Date -format s)] Starting Wi-Fi"
            # Start-Process PowerShell Invoke-OSDCloudWifi -Wait
            Invoke-OSDCloudWifi
            Start-Sleep -Seconds 2
        }
    }
    #=================================================
    # Initialize Network Connections
    Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] Initialize Network Connections"
    $timeout = 0
    while ($timeout -lt 20) {
        Start-Sleep -Seconds $timeout
        $timeout = $timeout + 5

        $IP = Test-Connection -ComputerName $(HOSTNAME) -Count 1 | Select-Object -ExpandProperty IPV4Address
        if ($null -eq $IP) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Network adapter error. This should not happen!"
            Start-Sleep -Seconds 2
        }
        elseif ($IP.IPAddressToString.StartsWith('169.254') -or $IP.IPAddressToString.Equals('127.0.0.1')) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] IP address not yet assigned by DHCP. Trying to get a new DHCP lease."
            ipconfig /release | Out-Null
            ipconfig /renew | Out-Null
            Start-Sleep -Seconds 2
        }
        else {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Network configuration renewed with IP: $($IP.IPAddressToString)"
            Start-Sleep -Seconds 2
            break
        }
    }
    Start-Sleep -Seconds 2
    #=================================================
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
