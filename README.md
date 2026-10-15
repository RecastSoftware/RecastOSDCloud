# OSDCloud

[![PSGallery Version](https://img.shields.io/powershellgallery/v/OSDCloud.svg?style=flat&logo=powershell&label=PSGallery%20Version)](https://www.powershellgallery.com/packages/OSDCloud) [![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/OSDCloud.svg?style=flat&logo=powershell&label=PSGallery%20Downloads)](https://www.powershellgallery.com/packages/OSDCloud) [![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue?style=flat&logo=powershell)](https://www.powershellgallery.com/packages/OSDCloud)

> A PowerShell module for deploying Windows with cloud-hosted operating system and driver content, with guided deployment workflows and WinPE startup automation.

| | |
| --- | --- |
| **Author** | David Segura |
| **Company** | Recast Software |
| **Version** | 26.10.15.1 |
| **PS Editions** | CompatiblePSEditions: Core, Desktop (manifest) |
| **License** | See [LICENSE](LICENSE) |

---

## What Is OSDCloud?

**Simple explanation:** OSDCloud helps deploy Windows to supported devices using operating system images and drivers hosted in the cloud. Operators can configure deployments through a graphical or command-line experience, then use WinPE startup tools to prepare devices and complete deployment.

**Technical explanation:** OSDCloud is a PowerShell module for Windows deployment workflows across amd64 and arm64 devices, defaulting to Windows 11 26H2. It provides deployment UX options, operating system and driver catalogs, device information and Wi-Fi utilities, and WinpeStartup automation for WinPE environments.

---

## What's New — Last 30 Days

Release highlights from the last 30 days. See [CHANGELOG.md](CHANGELOG.md) for
complete release notes and older history.

- **26.10.15.1 — October 15:** Refreshes the Windows 11 26H2 catalog, adds licensed automatic OS catalog refresh and USB publication, licensed WinpeStartup environment/registry/certificate imports, licensed disk layout customization, `-Incognito` license testing, and safer disk validation and partition handling.
- **26.10.13.1 — October 13:** Adds `New-WinpeStartupProfile` to create named profiles in existing Boot-Assets folders and writable OSDCloud USB volumes, with bundled defaults and safe replacement options.
- **26.10.10.1 — October 10:** Expands device inventory and `Show-OSDCloudDeviceInfo` with processor, memory, disk, and network details.
- **26.10.6.1 — October 6:** Adds WinpeStartup logging, Core environment/registry/certificate imports, and folder-based startup profiles.
- **26.10.4.1 — October 4:** Standardizes WinpeStartup naming while retaining compatibility aliases.
- **26.10.2.1 — October 2:** Adds ModelDrivers cache deployment, WinPEDrivers inventory, and configurable post-deployment actions.
- **26.9.30.1 — September 30:** Unifies operating-system catalog handling and adds parity checks against the OSD module.
- **26.9.29.1 — September 29:** Adds Windows 11 26H2 deployment support and makes it the default release.
- **26.9.25.1 — September 25:** Adds operating-system catalog refresh and synchronization, plus centralized Windows build metadata.
- **26.9.24.1 — September 24:** Adds startup-profile environment variables and catalog discovery from ProgramData and attached OSDCloud drives.

## Licensed Features

### Catalog and startup automation

| Feature | Benefit | Requirement |
|---|---|---|
| Automatic OS catalog refresh | Keeps deployment OS choices current by refreshing the catalog before selection and publishing validated catalogs to the module and eligible OSDCloud USB drives. | Valid Recast license |
| WinpeStartup asset imports | Applies `.env` settings, registry files, and root certificates from Core and the selected folder-based profile during startup. | Valid Recast license |

### Deploy-OSDCloud parameters

These parameters customize disk layout or infer the OS language for both CLI
and GUI deployments.

| Parameter | Benefit | Requirement |
|---|---|---|
| `-KeyboardLayout` / detected keyboard layout | Automatically sets `OSLanguageCode` from the supplied or detected keyboard layout, reducing manual language selection and helping match Windows to the operator's regional settings. Applies only when `OSLanguageCode` is not explicitly supplied. | Valid Recast license |
| `-DiskLabelOS` | Gives the Windows volume an organization-specific label so operators can identify it in deployment tools and File Explorer. Defaults to `OS`. | Valid Recast license |
| `-DiskLabelRecovery` | Gives an enabled recovery volume a recognizable label, such as `WinRE`, for maintenance and troubleshooting. Defaults to `Recovery`; does not enable a skipped recovery partition. | Valid Recast license |
| `-DiskSizeSystem` | Reserves a chosen amount of space for the system partition to meet deployment requirements. Accepts `100MB`–`3000MB`; defaults to `500MB`. | Valid Recast license |
| `-DiskSizeOS` | Creates a fixed-size Windows partition of at least `32GB`, preserving the requested recovery size and leaving excess disk space unallocated for later use. When omitted, Windows uses the remaining space after reserving recovery. | Valid Recast license |
| `-DiskSizeRecovery` | Reserves a chosen amount of recovery space to accommodate recovery-image requirements. Accepts `350MB`–`80000MB`; defaults to `2000MB` and preserves the workflow's recovery skip/force rules. | Valid Recast license |

Without a valid license, explicitly supplied disk customization parameters produce
one warning and deployment uses the default labels and sizes, including automatic
Windows partition sizing. `-DiskNumber` remains available without a license.
Automatic keyboard-layout language selection falls back to `en-US` without a
valid license, with no warning. Explicit `-OSLanguageCode` selection remains
available without a license.

All features in these tables use the shared `Test-OSDCoreLicense` check, requiring
the selected `Get-OSDCoreLicense` result to have `IsValid = true`; registration
alone does not qualify. Startup profiles and
cached OS catalog indexing remain usable without a valid license. See
[WinpeStartup documentation](docs/about_winpestartup.md) and
[deployment customization](docs/05-customize-deployment.md) for details.

---

## Installation

The module source lives under the [OSDCloud/](OSDCloud/) subfolder of this repository.

### From source

```powershell
git clone https://github.com/RecastSoftware/RecastOSDCloud.git
Import-Module .\RecastOSDCloud\OSDCloud\OSDCloud.psd1 -Force
```

### From the PowerShell Gallery

Install the module in WinPE:

```powershell
Install-Module -Name OSDCloud -SkipPublisherCheck -Force
```

Install for all users from an elevated Windows session:

```powershell
Install-Module -Name OSDCloud -Scope AllUsers
```

## Quick Start

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
| `New-WinpeStartupProfile` | Creates startup profile JSON in existing Boot-Assets and on writable OSDCloud USB volumes. |
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

## Requirements

| Requirement | Details |
|---|---|
| PowerShell | 5.1 or later on Windows |
| Operating environment | Windows; PE-specific cmdlets require WinPE |

## Release notes

See [CHANGELOG.md](CHANGELOG.md) for module release history.

## Privacy policy

OSDCloud sends anonymous deployment analytics during workflow execution. See [PRIVACY.md](PRIVACY.md) for details on what data is collected and how to opt out.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

See [LICENSE](LICENSE).
