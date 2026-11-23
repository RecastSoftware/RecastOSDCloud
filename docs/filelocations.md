# OSDCloud File Locations

This reference lists the content-discovery paths and fixed configuration inputs
used by OSDCloud, the standalone BootMenu, PreOOBE, and SetupComplete. It distinguishes automatic
searches from bundled files read directly. It does not list download URLs,
output-only logs, temporary working files, or Windows executable/DLL lookups.
Boot image builder asset libraries are separate from these runtime locations.

## Path notation

- `<drive>:` means a mounted file-system drive letter, not necessarily USB.
  Individual features restrict the letters or eligible volumes as noted below.
- `<ModuleRoot>` is the installed OSDCloud module directory, not the repository root.
- `<BootMenuRoot>` is the standalone OSDCloudBootMenu module directory.
- `<arch>` is `amd64` or `arm64`.
- `<name>` and `<application>` are immediate child folders unless stated otherwise.
- `%ProgramData%` normally resolves to `C:\ProgramData`; `%SystemRoot%` normally
  resolves to `C:\Windows` in the deployed OS.

## Operating system and driver pack catalogs

| Searched or read path | Purpose | Discovery rules |
|---|---|---|
| `<ModuleRoot>\core\operatingsystems\*.xml` | Bundled Windows OS catalog metadata. | XML files are searched recursively. |
| `%ProgramData%\OSDeployCore\OSDCloud\core\operatingsystems\*.xml` | Locally cached OS catalog metadata. | Recursive search when ProgramData is available. |
| `C:\ProgramData\OSDeployCore\OSDCloud\core\operatingsystems\*.xml` | Fixed local OS catalog discovery location. | Checked in addition to the environment-based location; duplicate paths are removed. |
| `<drive>:\OSDCloud\core\operatingsystems\*.xml` | External OS catalog metadata, including catalogs saved to USB. | Recursive search on mounted drive letters. Reading does not require writable media or a license. |
| `<ModuleRoot>\core\driverpacks\dell.xml` | Dell driver pack catalog. | Default local catalog path for the Dell reader/updater. |
| `<ModuleRoot>\core\driverpacks\hp.xml` | HP driver pack catalog. | Default local catalog path for the HP reader/updater. |
| `<ModuleRoot>\core\driverpacks\lenovo.xml` | Lenovo driver pack catalog. | Default local catalog path for the Lenovo reader/updater. |
| `<ModuleRoot>\core\driverpacks\surface.json` | Microsoft Surface driver pack catalog. | Default local catalog path for the Surface reader/updater. |
| `<ModuleRoot>\core\driverpacks\panasonic.json` | Panasonic driver pack catalog. | Default local catalog path for the Panasonic reader/updater. |
| `<ModuleRoot>\core\driverpacks\generic.json` | Generic driver pack catalog. | Read during driver pack catalog initialization. |

OS catalog indexing selects the highest valid revision for each major build.
Bundled catalogs take precedence when an external catalog has the same revision.
Catalog publication to external drives is narrower than discovery: the updater
copies the freshly validated catalog only to writable, online USB volumes labeled
**OSDCloud**, and requires a valid Recast license.

Sources: [OS catalog indexing](../OSDCloud/private/core-operatingsystem/Initialize-ModuleCoreOperatingSystems.ps1),
[OS catalog publication](../OSDCloud/private/Update-OSDCloudCoreCatalogOS.ps1),
and [driver pack catalog helpers](../OSDCloud/private/core-driverpack).

## Cached deployment content

| Searched path | Purpose | Discovery rules |
|---|---|---|
| `<drive>:\OSDCloud` | Identifies an OSDCloud cache drive. | Mounted drive letters; include/exclude filters can restrict discovery. A USB label is not required for inventory. |
| `<drive>:\OSDCloud\OS\*.esd` | Cached Windows installation images. | Recursive search; deployment steps also search for the selected ESD filename here. |
| `<drive>:\OSDCloud\ISO\*.iso` | Cached ISO inventory. | Recursive search. Inventory does not mean an ISO is selected for deployment. |
| `<drive>:\OSDCloud\WIM\*.wim` | Cached WIM inventory. | Recursive search. |
| `<drive>:\OSDCloud\DriverPacks` | Cached OEM driver pack installers and archives. | Recursively inventories `.cab`, `.exe`, `.msi`, and `.zip` files. Deployment also searches here for the selected pack filename. |
| `<drive>:\OSDCloud\Drivers\<name>` | Selectable extracted driver folders. | Immediate folders containing at least one `.inf` recursively. Saved selections can be re-resolved by their relative path after a drive-letter change. |
| `<drive>:\OSDCloud\modeldrivers-<arch>\<manufacturer>_<product>_<model>_<build>.<revision>` | Model-specific extracted driver content. | Immediate folders with a valid numeric build suffix and recursive INF content. Deployment matches manufacturer/product and chooses the highest numeric folder build, excluding sources on disks that will be cleared. |
| `<drive>:\OSDCloud\winpedrivers-<arch>\<manufacturer>_<product>_<model>_<build>.<revision>` | WinPE driver cache inventory. | Same folder-name and recursive INF requirements as ModelDrivers. Inventory only; not automatically loaded or injected. |
| `<drive>:\OSDCloud\Profiles\<name>` | Cached profile folder inventory. | Immediate folders; not BootMenu or legacy WinpeStartup profile discovery. |
| `<drive>:\OSDCloud\DriverPacks\OSDManufacturer` | Additional manufacturer-matched deployment drivers or scripts. | Immediate folder names, ZIP basenames, and PowerShell script basenames starting with the device's OSDManufacturer value. |
| `<drive>:\OSDCloud\DriverPacks\OSDModel` | Additional model-matched deployment drivers or scripts. | Immediate folder names, ZIP basenames, and PowerShell script basenames containing the device's OSDModel value. |
| `<drive>:\OSDCloud\DriverPacks\OSDProduct` | Additional product-matched deployment drivers or scripts. | Immediate folder names, ZIP basenames, and PowerShell script basenames containing the device's OSDProduct value. |
| `<drive>:\OSDCloud\*` | General asset lookup by the development helper. | `Find-OSDCloudAsset` searches recursively, including hidden files; callers can override the relative path and filename pattern. |

Sources: [cache inventory](../OSDCloud/private/core-cache/Get-OSDCoreCacheContent.ps1),
[model driver selection](../OSDCloud/private/core-driverpack/Resolve-OSDCoreModelDriversPath.ps1),
[selected driver folder resolution](../OSDCloud/private/steps/5-drivers/step-Add-WindowsDriver-DriverFolder.ps1),
[additional driver matching](../OSDCloud/private/steps/5-drivers/step-Add-WindowsDriver-OSDFolder.ps1),
and [general asset lookup](../OSDCloud/private/dev/Find-OSDCloudAsset.ps1).
See [cache behavior](about_osdcorecache.md) for deployment safety and caching details.

## BootMenu and WinPE startup

| Searched or read path | Purpose | Discovery rules |
|---|---|---|
| `<drive>:\OSDCloud\core\bootmenu-profiles\<id>\osdcloudbootmenu.json` | Runtime BootMenu Profiles. | Searches X: first, then C: through Z: excluding the already-searched X:. Only this filename in immediate profile folders is discovered. The folder name matches `info.id`; `info.name` is the display name. Duplicate GUIDs use the first discovered profile. |
| `<BootMenuRoot>\core\PSDefaultParameterValues.json` | Standalone BootMenu defaults. | Fixed module-relative input, not a drive scan. Explicit caller parameters override profile settings, which override these defaults. |
| `X:\OSDCloud\boot-packs\<id>\bootpack.cab` and `bootpack.json` | Build-level Import Packs. | Immediate Pack folders; processed before standard startup initialization when licensed. |
| `<selected-BootMenu-profile>\boot-packs\<id>\bootpack.cab` and `bootpack.json` | Selected-profile Import Packs. | Immediate Pack folders; processed after profile selection when licensed. |
| `<drive>:\WinpeStartup\Drivers\*.inf` | Supplemental drivers loaded into the running WinPE session. | C: through Z:, recursively. The helper's `SubfolderPath` can override the default root. |
| `<drive>:\WinpeStartup\Files` | Files copied into the WinPE RAM disk root. | C: through Z:. Content is copied without deleting destination-only files. `SubfolderPath` can override the root. |
| `X:\WinpeStartup\core\<name>` | Core startup asset folders, including expanded build-level Import Packs. | Only immediate child folders contribute environment, registry, and certificate assets. |
| `<drive>:\WinpeStartup\profiles\<name>\winpestartup.json` | Legacy folder-based WinpeStartup profiles. | C: through Z:. These are separate from BootMenu Profiles. |
| `<drive>:\WinpeStartup\profiles\*.json` | Legacy flat WinpeStartup profiles. | Immediate JSON files on C: through Z: remain supported; they have no selected-profile asset folder. |
| `<ModuleRoot>\core\PSDefaultParameterValues.json` | Legacy WinpeStartup defaults. | Fixed module-relative input used by `Invoke-WinpeStartup`. |
| `<drive>:\OSDCloud\Config\Scripts\WiFiProfile.xml` | Saved wireless connection profile. | The Wi-Fi helper searches recursively, including hidden files, on file-system drives other than C:. |

For each applicable asset root below, imports are nonrecursive and require a
valid Recast license. Asset roots are immediate `X:\WinpeStartup\core\<name>`
folders, the selected folder-based startup profile, and expanded selected-profile
Import Pack folders. Build-level Packs expand under `X:\WinpeStartup\core`;
selected-profile Packs expand under `X:\OSDCloud\bootpack-expanded`.

| Searched path within an asset root | Purpose | Discovery rules |
|---|---|---|
| `<asset-root>\*.env` | Process environment variables. | Includes hidden `.env` files; literal `NAME=VALUE` entries. |
| `<asset-root>\winpe-reg\*.reg` | WinPE registry customization. | Immediate `.reg` files imported with `reg.exe`. |
| `<asset-root>\winpe-root-cer\*.cer` | Trusted machine root certificates for WinPE. | Immediate `.cer` files imported with `certutil.exe`. |

Sources: [BootMenu profile discovery](../OSDCloud/core/modules/OSDCloudBootMenu/private/Get-OSDCloudBootMenuProfileCandidates.ps1),
[BootMenu runtime](../OSDCloud/core/modules/OSDCloudBootMenu/public/Invoke-OSDCloudBootMenu.ps1),
[Import Pack processing](../OSDCloud/core/modules/OSDCloudBootMenu/private/Invoke-WinpeStartupBootPackScripts.ps1),
[legacy profile discovery](../OSDCloud/private/Get-WinpeStartupProfileCandidates.ps1),
[startup assets](../OSDCloud/private/WinpeStartup/Import-WinpeStartupAssets.ps1),
[startup drivers](../OSDCloud/private/WinpeStartup/Initialize-WinpeStartupDrivers.ps1),
[startup files](../OSDCloud/private/WinpeStartup/Initialize-WinpeStartupFiles.ps1),
and [Wi-Fi profile lookup](../OSDCloud/core/modules/OSDCloudBootMenu/private/Show-WinpeStartupWifi.ps1).

## PreOOBE

| Searched or read path | Purpose | Discovery rules |
|---|---|---|
| `%SystemRoot%\Setup\PreOOBE\<application>` | Applications staged on the deployed Windows installation. | Searched first; immediate application folders sorted by name. |
| `<drive>:\OSDCloud\post\PreOOBE\<application>` | Drive-hosted custom applications. | A: through Z:, after the local root; immediate folders sorted by name. Display names include the drive letter. |
| `<application>\OSDCloudPreOOBE.json` | Custom application command, conditions, and initial checkbox selection. | Takes precedence over toolkit detection. Invalid manifests do not fall back to toolkit detection. |
| `<application>\Invoke-AppDeployToolkit.exe` | PSAppDeployToolkit application entry point. | Used only when the application folder has no custom manifest. |
| `%SystemRoot%\Setup\Scripts\OSDCloudPreOOBE.DriverPack.json` | Deferred OEM driver installation handoff. | Explicit local manifest, not an external-drive scan. The installer validates the package path under `%SystemRoot%\Temp\osdcloud-driverpack-download`. |
| `%SystemRoot%\Setup\Scripts\OSDCloudPost.json` | PreOOBE task selections written from the deployment window (`WindowsUpdateOS`, `WindowsUpdateDrivers`). | Explicit local file. A cleared value starts that task unchecked; a missing or invalid file leaves both tasks checked. |
| `<ModuleRoot>\core\modules\OSDCloudPost` | Bundled standalone OSDCloudPost module source (PreOOBE and SetupComplete). | The WinPE staging step validates and copies the entire module. |
| `%SystemRoot%\Setup\Modules\OSDCloudPost\OSDCloudPost.psd1` | Staged OSDCloudPost runtime module. | Explicitly imported by the OOBE.cmd launch hook; not discovered across drives. |

Application discovery does not execute installers. The local
`%SystemRoot%\Setup\PreOOBE` location has not moved.

Sources: [application discovery](../OSDCloud/core/modules/OSDCloudPost/private/OSDCloudPreOOBE.ps1),
[driver handoff](../OSDCloud/core/modules/OSDCloudPost/private/Invoke-OSDCloudPreOOBEDriverPack.ps1),
and [module staging](../OSDCloud/private/steps/7-update/step-update-osdcloudpost.ps1).
See the [PreOOBE guide](08-autopilot-oobe.md) for package manifests and execution behavior.

## SetupComplete

| Searched or read path | Purpose | Discovery rules |
|---|---|---|
| `%SystemRoot%\Setup\SetupComplete\<name>` | Locally staged script packages. | Searched first; immediate package folders sorted by name. |
| `<drive>:\OSDCloud\post\SetupComplete\<name>` | Drive-hosted script packages and supporting content. | A: through Z: after the local root; immediate folders sorted by name. |
| `<name>\OSDCloudSetupComplete.json` | Required script configuration, enabled flag, conditions, and optional local copying. | Only enabled, matching packages execute; folders without configuration are skipped. |
| `<ModuleRoot>\core\modules\OSDCloudPost` | Bundled standalone OSDCloudPost module source and example templates. | WinPE staging copies the module, not external package content. |
| `%SystemRoot%\Setup\Modules\OSDCloudPost\OSDCloudPost.psd1` | Staged OSDCloudPost runtime module (shared with PreOOBE). | Explicitly imported synchronously by the SetupComplete hook. |

The configured entry script must be a `.ps1` directly inside its package folder.
Its `$PSScriptRoot` and working directory are that folder or the retained local
copy when `CopyToLocal` is enabled. Every invocation reruns eligible packages.

Sources: [SetupComplete runtime](../OSDCloud/core/modules/OSDCloudPost/public/Invoke-OSDCloudSetupComplete.ps1)
and [staging](../OSDCloud/private/steps/7-update/step-update-osdcloudpost.ps1).
See the [deployment guide](08-autopilot-oobe.md#osdcloudsetupcomplete-silent-scripts-recast)
and [package examples](../OSDCloud/core/modules/OSDCloudPost/files/SetupComplete/README.md).

## Deployment configuration and bundled modules

| Searched or read path | Purpose | Discovery rules |
|---|---|---|
| `%ProgramData%\OSDeployCore\OSDCloud\Profiles\<name>` | Deployment Profile parameter choices. | Immediate local folder names populate the deployment profile selector; distinct from cached profile inventory and boot profiles. |
| `%ProgramData%\Recast Software\Licenses\*.license2` | Saved Recast licenses. | Immediate files, newest first. An explicit license `Path` overrides this root; Incognito skips saved-license discovery. |
| `<ModuleRoot>\core\module.json` | OSDCloud module metadata and content-source settings. | Fixed input read during module import. |
| `<ModuleRoot>\workflow\<workflow>\os-<arch>.json` | OS, edition, activation, and language picker configuration. | Falls back to the matching file under `workflow\default` when the selected workflow's file is absent. |
| `<ModuleRoot>\workflow\<workflow>\tasks\*.json` | Deployment task definitions. | Task initialization searches recursively and filters by architecture; it falls back to `workflow\default\tasks` if the selected workflow's task search fails or finds no files. Dynamic command parameter discovery reads immediate JSON files. |
| `<ModuleRoot>\workflow\default\ui\MainWindow.ps1` | Default deployment UI script. | Default candidate; the selected workflow's UI script replaces it when present. |
| `<ModuleRoot>\workflow\<workflow>\ui\MainWindow.ps1` | Workflow-specific deployment UI script. | Takes precedence over the default candidate. |
| `<ModuleRoot>\workflow\default\ux\MainWindow.ps1` | Legacy default deployment UI script. | Checked instead of the default `ui` path only when the default `ui` directory is missing. |
| `<ModuleRoot>\workflow\<workflow>\ux\MainWindow.ps1` | Legacy workflow-specific deployment UI script. | Checked instead of the selected workflow's `ui` path only when that workflow's `ui` directory is missing. |
| `<ModuleRoot>\core\modules\OSDCloudBootMenu\OSDCloudBootMenu.psd1` | Bundled standalone BootMenu module. | Explicit module import or Boot builder staging source, not a scan of attached drives. |
| `<ModuleRoot>\classes\*.ps1` | PowerShell class definitions. | Immediate files loaded before functions; test scripts excluded. |
| `<ModuleRoot>\private\*.ps1` | Module helper implementations. | Recursive import; test scripts excluded. |
| `<ModuleRoot>\public\WinOS\*.ps1` | General exported command implementations. | Recursive import; test scripts excluded. |
| `<ModuleRoot>\public\WinPE\*.ps1` | WinPE command implementations. | Recursive import only when SystemDrive is X:; test scripts excluded. |

Sources: [deployment command](../OSDCloud/public/WinOS/Deploy-OSDCloud.ps1),
[license discovery](../OSDCloud/private/core-license/Get-OSDCoreLicense.ps1),
[OS settings resolution](../OSDCloud/private/workflow/Get-OSDCloudWorkflowSettingsOSFile.ps1),
[task initialization](../OSDCloud/private/workflow/Initialize-OSDCloudWorkflowTasks.ps1),
[dynamic parameter discovery](../OSDCloud/private/workflow/Get-OSDCloudWorkflowRuntimeParameter.ps1),
[UI resolution](../OSDCloud/private/workflow/Invoke-OSDCloudWorkflowUI.ps1),
and [module loading](../OSDCloud/OSDCloud.psm1).

## Retired locations

| Previous path | Current path | Behavior |
|---|---|---|
| `<drive>:\OSDCloud\catalogs\operatingsystems` | `<drive>:\OSDCloud\core\operatingsystems` | Old catalogs are not searched, moved, or deleted. |
| `C:\ProgramData\OSDeployCore\OSDCloud\catalogs\operatingsystems` | `C:\ProgramData\OSDeployCore\OSDCloud\core\operatingsystems` | Old catalogs are not searched, moved, or deleted. |
| `<drive>:\OSDCloud\PreOOBE` and `<drive>:\OSDCloud\core\PreOOBE` | `<drive>:\OSDCloud\post\PreOOBE` | Old drive-hosted application roots are not searched or migrated. |
| `<drive>:\OSDCloud\core\SetupComplete` | `<drive>:\OSDCloud\post\SetupComplete` | Old drive-hosted script roots are not searched or migrated. |
| `<drive>:\OSDCloud\bootmenu-profiles` | `<drive>:\OSDCloud\core\bootmenu-profiles` | Old runtime profile roots are not searched or migrated. |
| `<ModuleRoot>\modules` | `<ModuleRoot>\core\modules` | Bundled module sources moved in the package; existing external data is not migrated. |
