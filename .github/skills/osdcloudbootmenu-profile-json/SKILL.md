---
name: osdcloudbootmenu-profile-json
description: "Create, edit, validate, or consume osdcloudbootmenu.json BootMenu Profiles. Use for Invoke-OSDCloudBootMenu, bootmenu-profiles, info GUID identity, osdcloudBoot build requirements and modules, osdcloudBootStartup phases, env, and osdcloudBootMenu settings. Keep Invoke-WinpeStartup and winpestartup.json legacy behavior separate."
---

# OSDCloud BootMenu Profiles

Read the existing JSON before editing. The bundled PowerShell and Recovery
Environment profiles under `OSDCloudBoot\core\bootmenu-profiles` are the schema
examples. Do not execute stored commands during authoring or validation.

## Locations and identity

- Shared user content: `C:\ProgramData\OSDeployCore\boot-assets\bootmenu-profiles\<name>\osdcloudbootmenu.json`.
- Bundled content: `{ModuleRoot}\core\bootmenu-profiles\<name>\osdcloudbootmenu.json`
  in OSDCloudBoot, OSDCloud, and OSD.
- Optional build-profile-local content: `bootmenu-profiles\<name>\osdcloudbootmenu.json`
  beside the build's `osdcloudboot.json`.
- Image/runtime content: `<drive>:\OSDCloud\core\bootmenu-profiles\<name>\osdcloudbootmenu.json`.
- Only that exact filename in profile folders is discovered. Do not list legacy
  `winpestartup.json`, root-level JSON, or saved paths outside discovery roots.
- Display names and IDs come from `info.name` and `info.id`, not folder names.
  Supply a nonempty name and a unique `[guid]::NewGuid().ToString()` ID. Preserve
  IDs on edits; generate a new ID when cloning.
- Runtime searches X: first, then C: through Z:, and ignores duplicate GUIDs.
  A malformed profile stops discovery rather than triggering default deployment.

## Schema version 1

| Section | Supported settings |
|---|---|
| `info` | `id` (GUID string), `name`, `author`, `description` |
| `env` | Map of environment variable names to strings; no secrets |
| `osdcloudBoot` | `requireWinPE`, `requireWinRE`, `installModule`, `buildPacks`, `importPacks` |
| `osdcloudBootStartup` | `enabled`, `onScreenKeyboard`, `showPnpDevices`, `showPnpErrors`, `wifi`, `ipConfig`, `updateOSDCloud`, `installModules`, `startup`, `main`, `shutdown` |
| `osdcloudBootMenu` | `enabled`, `command` (`Invoke-OSDCloudBootMenu`), `parameters` object |

- Keep native JSON types: `schemaVersion: 1`, booleans, string arrays, and objects.
  The retired `bootImage`, `winpeStartup`, `osdcloud`, and `osdcloudMenu` sections
  are not accepted in this format.
- `osdcloudBoot.requireWinRE` requires a Windows RE source; `requireWinPE`
  requires an ADK Windows PE source. Both cannot be true. Omitted or false
  requirements allow either source. These gates apply to UI selections and builds.
- `osdcloudBoot.installModule` adds modules at build time. Entries may be module
  name strings or `{ "name": "Module", "version": "1.2.3", "source": "PSGallery", "enabled": true }`.
  Version and source are optional; disabled entries are skipped.
- `osdcloudBoot.buildPacks` and `osdcloudBoot.importPacks` are arrays of
  `{ "id": "<Pack GUID>", "name": "<display name>" }` references to OSDCloud
  BootPacks (licensed). `id` is required and matched to `bootpack.json` `info.id`
  in the build profile's `boot-packs` folder, then `boot-assets\boot-packs`; `name`
  is informational. Build Packs are applied to the image when the profile is built.
  Import Packs are copied to `OSDCloud\core\bootmenu-profiles\<profile>\boot-packs\<id>`
  and applied by `Invoke-OSDCloudBootMenu` only when that profile is selected:
  `.env`, `.reg`, and `.cer` items are imported, then Execute scripts run. Use the
  OSDCloudBoot Packs page (or `Set-OSDCloudBootMenuProfilePack`) to edit them.
- `osdcloudBootStartup.installModules` is an array of names updated at runtime,
  not an image-injection list.
- Each `startup`/`main`/`shutdown` object accepts `enabled`, `commands` (string
  array), `noExit`, and `errorAction` (`Continue` or `Stop`). Commands for each
  phase execute in one child Windows PowerShell process. URLs are supported.
- Add deployment commands directly to `osdcloudBootStartup.main.commands`.
  Import OSDCloud explicitly in that command list when needed.
- An omitted startup enable flag defaults to enabled. `enabled: false` disables
  the checks, module updates, and startup command stages; explicitly enabled
  deployment/menu commands still apply. Disabled command stages clear commands.
- Enabled `osdcloudBootMenu` commands append to the main phase. Parameter values
  are strings, numbers, or booleans; true becomes a
  switch, false is omitted, and strings are quoted literally. Enabling a menu
  command re-enters the menu, so leave it disabled unless that is intended.
- `env` overrides process environment values. `info.name`/`info.author` supply
  `OSDCLOUDBOOTMENU_PROFILE`/`OSDCLOUDBOOT_AUTHOR` defaults, which explicit env
  values override. Licensed selected-profile `.env` assets apply afterwards.
- Explicit caller parameters override profile settings, which override module
  defaults with the `Invoke-OSDCloudBootMenu:` prefix.

## Lifecycle and validation

The standalone runtime is bundled at `OSDCloud\core\modules\OSDCloudBootMenu`.
Import its manifest explicitly on a technician host; Invoke/Test commands are
not exported by OSDCloud. OSDCloudBoot stages the complete folder as a top-level
Windows PowerShell module and explicitly imports it in standard startnet.cmd.
Do not add OSDCloudBootMenu to Gallery `installModule` entries.
Profile child sessions import BootMenu automatically. OSDCloud commands should
import OSDCloud explicitly.
Keep bundled examples mirrored in the runtime's `core\bootmenu-profiles`,
OSDCloud's `core\bootmenu-profiles`, and OSDCloudBoot's matching folders.

The builder copies the new JSON unchanged to the image's `OSDCloud\core\bootmenu-profiles`;
it does not render `winpestartup.json`. Standard startnet.cmd launches
`Invoke-OSDCloudBootMenu`. Zero profiles runs `Deploy-OSDCloud` after startup
checks; one auto-selects; multiple show a window (or `-CLI` prompt). Cancellation
or invalid selected JSON stops execution without starting deployment.

Dot-source `Assert-OSDCloudBootMenuProfile.ps1` and
`ConvertFrom-OSDCloudBootMenuProfile.ps1` from the owning module's `private`
directory, then validate with `Assert-OSDCloudBootMenuProfile -Path <file>`.
Conversion returns settings without executing commands. The helper sources in
OSDCloudBoot and `OSDCloud\core\modules\OSDCloudBootMenu` are mirrored to support independent module deployment;
keep their schema and conversion behavior aligned and test on PowerShell 5.1.

`Invoke-WinpeStartup`, `core\winpestartup-profiles`, and the flat
`winpestartup.json` format are legacy and must not be modified as part of this
schema. Use the legacy profile skill only for explicitly legacy requests.
