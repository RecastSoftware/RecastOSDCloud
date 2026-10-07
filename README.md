# OSDCloud

[![PSGallery Version](https://img.shields.io/powershellgallery/v/OSDCloud.svg?style=flat&logo=powershell&label=PSGallery%20Version)](https://www.powershellgallery.com/packages/OSDCloud) [![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/OSDCloud.svg?style=flat&logo=powershell&label=PSGallery%20Downloads)](https://www.powershellgallery.com/packages/OSDCloud) [![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue?style=flat&logo=powershell)](https://www.powershellgallery.com/packages/OSDCloud)

OSDCloud is a PowerShell module for deploying Windows with cloud-hosted operating system and driver content.

## Overview

- Current repository module version: `26.10.6.1`.
- Defaults to Windows 11 26H2 for amd64 and arm64 deployments.
- Focused on Windows deployment workflows driven by PowerShell.
- Supports WinpeStartup helpers and deployment UX options.
- Provides cmdlets for device info, Wi-Fi setup, and module updates in PE.

---

## What's New in 26.10.6.1

Released October 6, 2026.

- **Improved startup configuration:** WinpeStartup supports folder-based profiles, `.env` environment defaults, and importing registry and certificate files during environment setup.
- **Startup logging:** Startup output is transcribed to `X:\Windows\Temp\winpestartup.log`.
- **Profile cleanup:** Removed the obsolete German CLI startup profile.

See [CHANGELOG.md](CHANGELOG.md) for the complete release history and [WinpeStartup documentation](docs/about_winpestartup.md) for startup configuration.

---

## Requirements

- PowerShell 5.1 or PowerShell 7+ on Windows
- Windows or WinPE environment (for PE-specific cmdlets)

## Install

```powershell
# In WinPE
Install-Module -Name OSDCloud -SkipPublisherCheck -Force

# In Windows (elevated session)
Install-Module -Name OSDCloud -Scope AllUsers
```

## Quick start

```powershell
Import-Module OSDCloud

# Show device hardware information
Show-OSDCloudDeviceInfo

# Launch the interactive deployment experience
Deploy-OSDCloud
```

## Commands

**All environments**

| Cmdlet | Description |
|---|---|
| `Deploy-OSDCloud` | Starts an OS deployment workflow (GUI or CLI mode). |
| `Get-OSDCloudModulePath` | Returns the module installation directory. |
| `Get-OSDCloudModuleVersion` | Returns the loaded module version. |
| `Show-OSDCloudDeviceInfo` | Displays device hardware and environment information. |
| `Start-OSDCloudExplorer` | Opens a WinForms file browser (useful in WinPE/WinRE). |

**WinPE only** (`SystemDrive == X:`)

| Cmdlet | Alias | Description |
|---|---|---|
| `Invoke-WinpeStartup` | — | Runs the full WinpeStartup workflow. |
| `Invoke-WinpeStartupManager` | `Invoke-OSDCloudPEStartup` | Dispatches individual startup actions. |
| `Show-WinpeStartupDevices` | `Show-PEStartupHardware` | Shows all PnP devices. |
| `Show-WinpeStartupDeviceErrors` | `Show-PEStartupErrors` | Shows PnP devices with errors. |
| `Show-WinpeStartupIpconfig` | `Show-PEStartupIpconfig` | Displays `ipconfig /all`. |
| `Show-WinpeStartupWifi` | `Show-PEStartupWifi` | Connects to Wi-Fi and waits for DHCP. |
| `Update-WinpeStartupModule` | `Use-PEStartupUpdateModule` | Updates a module from PSGallery. |

## Documentation

### How-to guides

Task-oriented guides for IT admins. Start at the [docs index](docs/README.md), or jump straight to a topic:

| Guide | When to read |
|---|---|
| [docs/01-overview.md](docs/01-overview.md) | Decide whether OSDCloud is the right tool. |
| [docs/02-build-boot-image.md](docs/02-build-boot-image.md) | Produce a custom WinPE WIM/ISO. |
| [docs/03-boot-device.md](docs/03-boot-device.md) | Boot a target device into WinPE (USB / ISO / PXE). |
| [docs/04-deploy-windows.md](docs/04-deploy-windows.md) | End-to-end Windows 11 deployment. |
| [docs/05-customize-deployment.md](docs/05-customize-deployment.md) | Workflow channels, OS / edition / language, skip steps. |
| [docs/06-unattended-usb-profile.md](docs/06-unattended-usb-profile.md) | Zero-touch deployment with a USB JSON profile. |
| [docs/07-arm64-devices.md](docs/07-arm64-devices.md) | Deploy to Snapdragon / Surface Pro 11 / Copilot+ PCs. |
| [docs/08-autopilot-oobe.md](docs/08-autopilot-oobe.md) | Hand off to OOBE and Autopilot. |
| [docs/09-troubleshooting.md](docs/09-troubleshooting.md) | Diagnose a failed deployment. |

### Function reference

| Reference page | Function |
|---|---|
| [OSDCloud/docs/Deploy-OSDCloud.md](OSDCloud/docs/Deploy-OSDCloud.md) | `Deploy-OSDCloud` |
| [OSDCloud/docs/Get-OSDCloudModulePath.md](OSDCloud/docs/Get-OSDCloudModulePath.md) | `Get-OSDCloudModulePath` |
| [OSDCloud/docs/Get-OSDCloudModuleVersion.md](OSDCloud/docs/Get-OSDCloudModuleVersion.md) | `Get-OSDCloudModuleVersion` |
| [OSDCloud/docs/Show-OSDCloudDeviceInfo.md](OSDCloud/docs/Show-OSDCloudDeviceInfo.md) | `Show-OSDCloudDeviceInfo` |
| [OSDCloud/docs/Start-OSDCloudExplorer.md](OSDCloud/docs/Start-OSDCloudExplorer.md) | `Start-OSDCloudExplorer` |

WinpeStartup cmdlets are currently documented through in-module help. In WinPE, run `Get-Help <CmdletName> -Detailed` for usage details.

### External links

- [PowerShell Gallery — OSDCloud](https://www.powershellgallery.com/packages/OSDCloud)
- [GitHub Issues](https://github.com/OSDeploy/OSDCloud/issues)

## Release notes

See [CHANGELOG.md](CHANGELOG.md) for module release history.

## Privacy policy

OSDCloud sends anonymous deployment analytics during workflow execution. See [PRIVACY.md](PRIVACY.md) for details on what data is collected and how to opt out.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

See [LICENSE](LICENSE).
