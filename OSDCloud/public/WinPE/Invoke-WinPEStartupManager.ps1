<#
.SYNOPSIS
    Invokes a WinPE startup utility action by Id.

.DESCRIPTION
    Routes WinPE startup actions to the corresponding helper command.
    Actions include on-screen keyboard handling, hardware and error display,
    network utilities, and module update operations.

.PARAMETER Id
    Specifies the startup action to invoke.
    Valid values are OSK, DeviceErrors, DeviceHardware, Info, IPConfig,
    UpdateModule, and WiFi.

.PARAMETER Value
    Optional value used by specific actions.
    For UpdateModule, set this value to the module name to update.

.EXAMPLE
    Invoke-WinPEStartupManager -Id OSK

    Launches the on-screen keyboard when no physical keyboard is detected.

.EXAMPLE
    Invoke-WinPEStartupManager -Id DeviceErrors

    Displays non-OK Plug and Play device status details.

.EXAMPLE
    Invoke-WinPEStartupManager -Id DeviceHardware

    Displays Plug and Play device hardware details.

.EXAMPLE
    Invoke-WinPEStartupManager -Id Info

    Shows comprehensive device information.

.EXAMPLE
    Invoke-WinPEStartupManager -Id IPConfig

    Launches IP configuration display in a minimized window.

.EXAMPLE
    Invoke-WinPEStartupManager -Id WiFi

    Starts Wi-Fi connection workflow when network connectivity is not detected.

.EXAMPLE
    Invoke-WinPEStartupManager -Id UpdateModule -Value OSDCloud

    Updates the OSDCloud module.

.OUTPUTS
    System.Void

.NOTES
    This function is intended for WinPE startup workflows.
    The UpdateModule action requires Value to be set to a module name.

.LINK
    https://github.com/OSDeploy/OSDCloud
#>
function Invoke-WinPEStartupManager {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet(
            'OSK',
            'DeviceErrors',
            'DeviceHardware',
            'Info',
            'IPConfig',
            'UpdateModule',
            'WiFi'
        )]
        [System.String]
        $Id,

        [Parameter(Position = 1)]
        [System.String]
        $Value
    )
    #=================================================
    $Error.Clear()
    #=================================================
    switch ($Id) {
        'OSK' {
            # OSK should not be launched if a physical keyboard is detected
            if (Get-CimInstance -ClassName Win32_Keyboard -ErrorAction SilentlyContinue) {
                Write-Host "OSDCloud OSK: Keyboard detected. Not launching On-Screen Keyboard."
            }
            else {
                # osk.exe is not present in all versions of WinPE, so check for it before trying to launch it
                if (Get-Command -Name 'osk.exe' -ErrorAction Ignore) {
                    Write-Host "OSDCloud OSK: Keyboard not detected. Launching On-Screen Keyboard."
                    Start-Process -FilePath 'osk.exe' -WindowStyle Minimized
                }
                else {
                    Write-Host "OSDCloud OSK: Unable to launch On-Screen Keyboard due to osk.exe not found."
                    Write-Host "OSDCloud OSK: OSDWorkspace should be used to create WinPE to resolve this issue."
                }
            }
        }
        'DeviceErrors' {
            Invoke-PEStartupCommand Show-WinPEStartupDeviceErrors -NoExit -Wait
        }
        'DeviceHardware' {
            Invoke-PEStartupCommand Show-WinPEStartupDevices -WindowStyle Minimized -NoExit
        }
        'WiFi' {
            # Wait a few seconds for the network stack to initialize before checking for connectivity
            Start-Sleep -Seconds 2

            # Primary check: raw TCP socket to 1.1.1.1:80 — Test-NetConnection is not available in WinPE
            $isConnected = try { $tcp = [System.Net.Sockets.TcpClient]::new('1.1.1.1', 80); $tcp.Close(); $true } catch { $false }
            # Secondary check: Microsoft NCSI endpoint — plain HTTP, no TLS, what Windows uses natively
            if (-not $isConnected) {
                $isConnected = Test-OSDCloudInternetConnection -Uri 'http://www.msftconnecttest.com/connecttest.txt'
            }
            # Final check: generic HTTP via Test-OSDCloudInternetConnection
            if (-not $isConnected) {
                $isConnected = Test-OSDCloudInternetConnection
            }
            if ($isConnected) {
                Write-Host "OSDCloud Wi-Fi: Network connection detected. Not launching Wi-Fi connection."
            }
            else {
                Write-Host "OSDCloud Wi-Fi: Network connection not detected. Launching Wi-Fi connection."
                Invoke-PEStartupCommand Show-WinPEStartupWifi -Wait
            }
        }
        'IPConfig' {
            Write-Host "OSDCloud IPConfig: Launching IPConfig in minimized window."
            Invoke-PEStartupCommand Show-WinPEStartupIpconfig -Run Asynchronous -WindowStyle Minimized -NoExit
        }
        'UpdateModule' {
            # Value must be specified for this function to work
            if ($Value) {
                # Make sure we are online before attempting to update
                # Primary check: raw TCP socket to 1.1.1.1:80 — Test-NetConnection is not available in WinPE
                $isConnected = try { $tcp = [System.Net.Sockets.TcpClient]::new('1.1.1.1', 80); $tcp.Close(); $true } catch { $false }
                # Secondary check: Microsoft NCSI endpoint — plain HTTP, no TLS, what Windows uses natively
                if (-not $isConnected) {
                    $isConnected = Test-OSDCloudInternetConnection -Uri 'http://www.msftconnecttest.com/connecttest.txt'
                }
                # Final check: generic HTTP via Test-OSDCloudInternetConnection
                if (-not $isConnected) {
                    $isConnected = Test-OSDCloudInternetConnection
                }
                if (-not $isConnected) {
                    Write-Host "OSDCloud UpdateModule: Unable to reach the internet. Please check your network connection."
                    return
                }
                Invoke-PEStartupUpdateModule -Name $Value -Wait
            }
        }
        'Info' {
            Invoke-PEStartupCommand Show-OSDCloudDeviceInfo -NoExit -Wait
        }
    }
    #=================================================
}
