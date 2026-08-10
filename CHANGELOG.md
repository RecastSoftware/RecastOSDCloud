# Changelog

All notable changes to this project will be documented in this file.

## 26.8.10.1 - August 10, 2026

### Added

- Added `Initialize-DeployOSDCloud` as the new deployment initialization implementation with expanded deployment/device state handling and validation flow.
- Added cache and validation helpers across core systems:
  - `Initialize-OSDCoreCache`
  - `Get-OSDCoreDriverPackCacheObject`
  - `Get-OSDCoreOperatingSystemCacheObject`
  - `Test-OSDCoreDriverPackCloudObject`
  - `Test-OSDCoreOperatingSystemCloudObject`
- Added workflow operating system helper functions:
  - `Get-OSDCloudWorkflowSettingsOSFile`
  - `Resolve-OSDCloudWorkflowOSActivation`
  - `Test-OSDCloudWorkflowSettingsOS`
- Added deployment hardware override support for workflow-driven operating system selection constraints.
- Added repository documentation pages `docs/about_osdcorecache.md` and `docs/about_osdcoredevice.md`.
- Added the `osdcore-operating-system-cloud-object` Copilot skill for core operating system object mapping and maintenance.

### Changed

- Refactored deployment initialization by replacing `Initialize-OSDCloudDeploy` usage with `Initialize-DeployOSDCloud` across deployment entry points (`Deploy-OSDCloud`, `Deploy-OSDCloudCLI`, and `Deploy-OSDCloudGUI`).
- Renamed module catalog initializer functions to align naming and intent:
  - `Get-ModuleCoreDriverPacks` -> `Initialize-ModuleCoreDriverPacks`
  - `Get-ModuleCoreOperatingSystems` -> `Initialize-ModuleCoreOperatingSystems`
- Centralized and reorganized cache handling by moving cache helpers from `private/core-device/` to `private/core-cache/` and improving USB cache object refresh behavior.
- Improved core operating system and driver pack selection reliability by validating cloud/cache objects, normalizing schema handling, and supporting file-path based operating system URL checks.
- Improved workflow operating system resolution and parameter flow by centralizing OS settings selection and activation resolution logic.
- Updated workflow and task execution scripts with standardized informational logging markers and aligned step/test behavior for target disk, driver pack, and Windows image validation.
- Updated WinPE startup components, including Wi-Fi and USB drive-letter initialization paths, to align with the revised deployment/core orchestration flow.
- Updated Microsoft Update Catalog save helpers and related driver workflow step behavior to match revised validation and logging patterns.
- Updated workflow UI `MainWindow` scripts across classic, default, dev, insiders, and vNext channels for consistency with the updated deployment flow.
- Updated repository guidance in Copilot instruction assets and catalog update instructions.

### Removed

- Removed legacy `Initialize-OSDCloudDeploy.ps1` in favor of `Initialize-DeployOSDCloud.ps1`.

## 26.8.5.1 - August 5, 2026

### Added

- Added core device cache helpers: `Get-OSDCoreCacheContent`, `Get-OSDCoreCacheDrive`, `Get-OSDCoreCacheUSBPath`, and `Test-OSDCoreCacheUSB`.
- Added `Update-RecastOSDCloudUSBCache` for USB cache refresh and maintenance workflows.
- Added `ConvertTo-TrimmedString` private helper for normalized string handling.
- Added `Get-ModuleCoreDriverPacks` and `Get-OSDCoreDriverPackCatalogSurface` to the reorganized core driver pack pipeline.
- Added `Get-OSDCoreOperatingSystems` and `Set-OSDCoreOperatingSystemCloudObject` for core operating system catalog selection.

### Changed

- Module version bumped to `26.8.5.1`.
- Refactored core device initialization into `Initialize-OSDCoreDevice` and updated deployment flow wiring.
- Reorganized core helper layout by moving driver pack and operating system catalog functions out of `private/core/` into `private/core-driverpack/` and `private/core-operatingsystem/`.
- Updated `Initialize-OSDCloudDeploy` to consume `Get-ModuleCoreDriverPacks`.
- Renamed and relocated date/time sync helper from `Sync-OSDCloudDateTime` to `Sync-OSDCoreDateTime`.
- Updated `Show-OSDCloudDeviceInfo` implementation and related help output.
- Refreshed workflow and UX assets across classic, default, dev, insiders, and vNext channels, including `MainWindow.xaml` updates.
- Updated disk, workflow task, and driver step scripts for alignment with the reorganized core helper model.
- Updated repository documentation and guidance including `README.md`, Copilot instructions, workflow task instructions, and Surface catalog maintenance skill assets.

### Removed

- Removed legacy `Get-OSDCloudCoreDriverPacks` and legacy `Get-OSDCloudCatalogSurface` private core helpers.
- Removed legacy `Sync-InternetDateTime` helper.
- Removed standalone `Get-OSDCloudCache` markdown help page and aligned module help XML.

## 26.8.3.1 - August 3, 2026

### Added

- Added Microsoft Surface driver pack catalog entries for Surface Laptop 8 Intel, Surface Laptop 8 Snapdragon, and Surface Laptop 13in 1st Intel.
- Added the `add-surface-model` Copilot skill, Surface model template, and catalog validation guidance for maintaining `surface.json`.

### Changed

- Module version bumped to `26.8.3.1`.
- Renamed the Surface Laptop Snapdragon 13-inch catalog entry to Surface Laptop 13in 1st Snapdragon to align with Surface catalog naming.

### Removed

- Removed the legacy `surface.xml` driver pack snapshot now superseded by `surface.json`.

## 26.8.1.1 - August 1, 2026

### Changed

- Module version bumped to `26.8.1.1`.
- Updated `step-test-targetdisk` to keep the existing non-boot-disk filter in WinPE and include all local disks when running outside WinPE.
- Temporarily disabled `step-Save-WindowsDriver-MSUpdate` with a skip message while a Microsoft Update Catalog issue is being addressed.

## 26.7.29.1 - July 29, 2026

### Added

- Added WinPE startup profiles for `Deploy-OSDCloud` and `Show-OSDCloudDeviceInfo`.

### Changed

- Module version bumped to `26.7.29.1`.
- Updated `Deploy-OSDCloud` help content and module help XML to document CLI usage through `Deploy-OSDCloud -CLI`, profile selection, force support, and workflow runtime parameters.
- Improved `Invoke-OSDCloudWifi` wireless adapter detection in WinPE by handling `Get-SmbClientNetworkInterface` failures and falling back to CIM-based adapter discovery when SMB networking is not yet initialized.
- Improved `Show-OSDCloudDeviceInfo` network adapter output filtering when adapter GUID values are missing.
- Updated the privacy policy with expanded disclosures for analytics payloads, local device data and logs, network operations, and external service interactions.

### Removed

- Removed `Deploy-OSDCloudCLI` from the exported module cmdlet surface; CLI deployments should now use `Deploy-OSDCloud -CLI`.
- Removed the standalone `Deploy-OSDCloudCLI` help page.

## 26.7.22.1 - July 22, 2026

### Added

- Added module-level `osdcloud.env` defaults for organization and deployment branch values.
- Added environment and profile support for pre-seeding deployment settings and overriding device and operating system selections.
- Added dynamic workflow runtime parameters generated from workflow operating system and task definitions.
- Added centralized download handling with curl validation, error handling, and improved warnings.
- Added `Sync-OSDCloudDateTime` error handling for internet time synchronization.
- Added `Get-DeploymentDiskObject` and reorganized disk-management helpers for deployment disk filtering and partition operations.
- Added Windows 11 25H2 operating system catalog build `26200.8873`.
- Added detailed documentation for disk-management and device-initialization functions, plus an ENV files guide.

### Changed

- Module version bumped to `26.7.22.1`.
- Updated `Deploy-OSDCloud` and `Deploy-OSDCloudCLI` to share workflow parameter discovery, support profile selection, and handle dynamic operating system, edition, activation, language, and task parameters.
- Updated deployment and device initialization to apply environment overrides for manufacturer, model, product, architecture, operating system, edition, activation, and language settings.
- Updated driver pack catalog retrieval to use the core driver pack function and module-relative catalog paths.
- Improved module path resolution, workflow parameter handling, download diagnostics, catalog loading messages, date/time synchronization, and deployment logging.
- Improved device initialization documentation and retained deployment architecture detection from collected device information.
- Updated the privacy policy with detailed deployment analytics, local device data and log handling, external service disclosures, and user choices.

### Removed

- Removed the superseded disk-management helper layout in favor of the reorganized disk implementation.

## 26.6.29.1 - June 29, 2026

### Changed

- Module version bumped to `26.6.29.1`.
- Refactored `Get-OSDCloudCatalogLenovo` by commenting out the redundant `HashMD5` grouping/sort pass when filtering the latest driver packs per model.

## 26.6.26.1 - June 26, 2026

### Changed

- Module version bumped to `26.6.26.1`.
- Renamed the generic driver pack catalog mapping from `default` to `generic` and updated catalog path references from `core\\driverpacks\\default.json` to `core\\driverpacks\\generic.json`.
- Standardized `Write-Host` output formatting across deployment, workflow, CLI, Wi-Fi startup, date/time sync, and driver-step scripts by removing redundant function-name prefixes from host messages.
- Improved `Initialize-OSDCloudDeploy` console output to include detected `OSDManufacturer`, `OSDModel`, `OSDProduct`, and selected driver pack name/URL details.
- Updated OEM catalog retrieval logging in Dell, HP, Lenovo, Panasonic, and Surface catalog functions to provide clearer host-level download/load/extract progress messages.
- Applied consistency and readability formatting updates in affected PowerShell scripts.

### Maintenance

- Updated catalog-update guidance and driver pack catalog update prompt content to align with the `generic` driver pack catalog naming.

## 26.6.25.2 - June 25, 2026

### Changed

- Module version bumped to `26.6.25.2`.
- `Get-OSDCloudCache` now supports a `Profiles` type that returns folders under `<DriveLetter>:\OSDCloud\Profiles`.

## 26.6.25.1 - June 25, 2026

### Added

- Added `Get-OSDCloudCoreOperatingSystems` and updated operating system retrieval flow to use core operating system records.

### Changed

- Module version bumped to `26.6.25.1`.
- Updated deployment operating system architecture filtering to align with the new core operating system retrieval path.
- Replaced references to `Get-MCTOperatingSystemsOSDCloud` with `Get-OSDCloudCoreOperatingSystems` and removed redundant related change-log code blocks.

## 26.6.23.1 - June 23, 2026

### Changed

- Module version bumped to `26.6.23.1`.

## 26.6.17.1 - June 17, 2026

### Added

- `Get-OSDCloudCache` cmdlet to enumerate OSDCloud cache content and volume metadata.
- `Deploy-OSDCloudCLI` cmdlet and `vNext` workflow support for CLI-based deployment flows.
- New Fluent `vNext` workflow UI updates, including Cloud Operating System download actions and Driver Pack cache presentation.

### Changed

- Module version bumped to `26.6.17.1`.
- Refactored deployment and workflow UX orchestration, including function naming and task alignment updates.
- Improved WinPE initialization behavior for USB drive-letter reassignment and disk handling reliability.
- Updated Microsoft and HP driver pack catalog handling and version extraction behavior.
- Simplified workflow task sequencing by removing redundant driver application steps.

### Maintenance

- Updated Microsoft Surface driver pack catalog snapshots.
- Increased driver pack catalog update workflow cadence.

## 26.6.12.1 - June 12, 2026

### Added

- OS catalog updated with Windows 11 25H2 build `26200.8653`.
- WinPE support added to reassign USB drive letters starting at `H:` to avoid drive-letter conflicts during deployment.
- Driver Folder selection and management support added to `MainWindow`, including dynamic panel visibility and selection handling.

### Changed

- Module version bumped to `26.6.12.1`.
- Driver folder path resolution and matching logic improved, including support for `.zip` and `.ps1` driver package inputs.
- Fluent workflow `MainWindow` layouts refined with local ISO support and improved navigation/content presentation.

## 26.6.3.1 - June 3, 2026

### Added

- Added comprehensive guides for deploying Windows 11 with OSDCloud.

### Changed

- Module version bumped to `26.6.3.1`.
- `MainWindow` layout and branding updated for improved navigation and content display.

## 26.5.24.1 - May 25, 2026

### Changed

- Module version bumped to `26.5.24.1`.
- Microsoft Surface driver pack catalog updated (`2026-05-25`).

## 26.5.22.1 - May 22, 2026

### Changed

- Module version bumped to `26.5.22.1`.
- `Start-OSDCloudExplorer`: full high-DPI display support.
  - `SetProcessDPIAware()` P/Invoke called before any window is created so the OS reports true physical pixels.
  - DPI scale factor derived from `Graphics.DpiX / 96` after `EnableVisualStyles`; form initial size, minimum size, toolbar padding, and address bar width all multiplied by the scale factor at runtime.
  - Icon helper functions (`New-DriveIcon`, `New-FolderIcon`, `New-ComputerIcon`, `New-UpIcon`, `New-FileIcon`) now accept a `$Size` parameter; each applies `ScaleTransform` and `InterpolationMode::HighQualityBicubic` to render crisp bitmaps at any DPI.
  - `ImageList.ImageSize` and per-icon `New-*` calls updated to pass the computed `$iconSize` (16 × dpiScale).
  - `Form.AutoScaleMode` set to `None` to prevent WinForms from double-scaling after the manual DPI adjustment.

## 26.5.20.1 - May 20, 2026

### Added

- `Get-OSDCloudCatalogSurface`: when `$global:OSDCloudDevice.OSDProduct` is set, live `UpdatePage` network requests are limited to the single matching catalog entry; all other entries return base JSON values, eliminating the full catalog scan during deployment.

### Changed

- Module version bumped to `26.5.20.1`.
- Microsoft Surface driver pack catalog updated with latest MSI versions for 18 models (all bumped to `26.04x` builds).

## 26.5.19.1 - May 19, 2026

### Added

- OS catalog updated with Windows 11 25H2 build 26200.8457 (compiled 2026-05-07).

### Changed

- Module version bumped to `26.5.19.1`.
- Dell driver pack catalog updated to version `2026.05.04` (dated 2026-05-15).
- HP driver pack catalog updated (DateReleased `2026-05-19`).
- Lenovo driver pack catalog refreshed from upstream `catalogv2.xml`.
- GitHub Actions catalog-update workflows (`update-catalog-dell.yaml`, `update-catalog-hp.yaml`, `update-catalog-lenovo.yaml`) changed to on-demand (`workflow_dispatch`) only — weekly cron schedule removed.
- `docs/workflows.md` simplified to only describe the `default` deployment channel.
- `publish-module.yaml` corrected to check out the current repository without a hardcoded `path`, `repository`, or `ref`; publish step switched to `shell: pwsh`; permissions tightened to `contents: read`.

## 26.4.27.1 - April 27, 2026

### Added

- Reference documentation for all 12 exported functions in `OSDCloud/docs/`:
  - New pages: `Invoke-WinPEStartup.md`, `Invoke-WinPEStartupManager.md`,
    `Show-WinPEStartupDevices.md`, `Show-WinPEStartupDeviceErrors.md`,
    `Show-WinPEStartupIpconfig.md`, `Show-WinPEStartupWifi.md`,
    `Update-WinPEStartupModule.md`
  - Updated existing pages to fill in blank `ProgressAction` descriptions,
    add `INPUTS`/`OUTPUTS`/`NOTES` sections, and cross-link related pages.
- Conceptual guides in `docs/`:
  - `getting-started.md` — installation, quick start, and cmdlet overview.
  - `winpe-startup.md` — WinPE startup sequence, script hooks, USB profiles,
    and `InvokeXxxCommand` behaviour.
  - `psoptions.md` — two-layer `PSDefaultParameterValues` system with full
    key reference table and override examples.
  - `workflows.md` — deployment channels, the 39-step default task (grouped
    by phase), and skip-flag semantics.

### Changed

- `README.md` updated with a complete command table (all 12 exported cmdlets
  with aliases), a Guides section, and a Function reference table linking to
  all docs pages.
- `CONTRIBUTING.md` expanded with PowerShell coding conventions, WinPE guard
  rules, documentation requirements, workflow/task contribution guide,
  catalog update pointer, Pester testing guidance, and a PR checklist.
- `PRIVACY.md` updated with effective date, confirmed SHA-256 hashing
  algorithm for the device identifier, and clarified external service
  interactions.

## 26.4.17.1 - April 17, 2026

### Changed

- Updated OSDCloud OS catalog with Windows 11 25H2 build 26200.8246.

## 26.4.7.1 - April 7, 2026

### Added

- `Show-OSDCloudDeviceInfo` function for enhanced device information display (#59)
- GitHub Copilot instructions for catalog updates, workflow tasks, and driver pack updates (#58)

### Changed

- Updated Microsoft Surface device driver pack catalog versions and release dates (#57)
- Enhanced device info display and updated logging messages across core functions (#59)
- Refactored `Initialize-OSDCloudDevice` with improved device info collection (#59)
- Updated Dell driver pack catalog (DriverPackManifest version 2026.03.04)
- Updated HP driver pack catalog (HPClientDriverPackCatalog DateReleased 2026-04-06)
- Updated Lenovo driver pack catalog (catalogv2.xml version 1.0, 2026-04-07)

## 26.3.27.1 - March 27, 2026

### Changed

- Updated Dell driver pack catalog (DriverPackCatalog v2026.03.02, releaseID F3GCP)
- Updated HP driver pack catalog (HPClientDriverPackCatalog v2.00 A 1)
- Updated Lenovo driver pack catalog (catalogv2.xml v1.0)

## 26.3.23.1 - March 23, 2026

### Added

- Dev-device workflow with full WPF application structure and UI (#53)
- Enhanced clipboard functionality in MainWindow UI (#53)

### Changed

- Updated Microsoft driver pack catalog (#53)
- Changed verbose logging to host output for time synchronization (#50)
- Refactored MainWindow code across default, dev-alpha, dev-beta, and insiders workflows (#53)

## 26.3.12.1 - March 12, 2026

### Added

- Updated OSDCloud OS catalog with Windows 11 25H2 build 26200.8037.

## 26.3.4.1 - March 4, 2026

### Added

- Panasonic driver pack catalog support (#45)
- `Sync-InternetDateTime` function for time synchronization (#45)
- `step-Add-WindowsDriver-Disk` and `step-Export-WindowsDriver-OemWinPE` driver steps (#45)

### Changed

- Enhanced download process with validation and error handling (#46)
- Updated log copying mechanism for improved efficiency (#47)
- Renamed driver export steps to follow consistent `step-Add-WindowsDriver-*` and `step-Save-WindowsDriver-*` naming convention (#45)
- Enhanced logging across multiple workflow steps (#45)
- Updated HP, Lenovo, and default driver pack catalogs (#44)
- Reorganized WiFi and network connection modules (#44)
- Improved PE startup functions and UI handling in MainWindow (#44)

### Removed

- Deprecated `step-drivers-recast-winos.ps1` and `step-drivers-recast-winpe.ps1` (#45)
- Removed `Invoke-PEStartupOSK.ps1` (#44)

## 26.2.16.1 - February 16, 2026

### Added

- Windows 11 25H2 February 2026 OS catalog release (#39)
- OSDCloud by Recast branding (#37)
- `Invoke-OSDCloudDownloadFile` function for centralized download handling (#33)
- Curl availability check for downloads (#34)

### Changed

- Updated OSDCloud workflows and task names (#35, #34)
- Improved UI with adjusted column widths in MainWindow layout (#31)
- Updated driver pack management for Windows 11 (#43)
- Updated OS configurations (#38)

### Removed

- Deprecated tasks and unused workflow code (#38, #35)
- Redundant code changes sections (#30)
