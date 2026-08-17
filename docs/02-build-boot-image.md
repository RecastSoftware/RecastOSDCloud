# Build a WinPE Boot Image

## When to use this

Build a new boot image when:

- You are setting up OSDCloud for the first time.
- You need a new boot image for a different architecture (amd64 vs arm64).
- You want updated WinPE drivers, language packs, or a newer WinRE/ADK source.
- You added scripts or apps to `%ProgramData%\OSDeployCore\OSDRepo\` that should be in WinPE.

Rebuild **does not** automatically happen when OSDCloud publishes a new module
version. The build includes the currently loaded OSDCloud module, and WinPE
startup updates it from the PowerShell Gallery by default.

## Why a separate module

OSDCloud runs *inside* WinPE but doesn't build the boot image. Boot image
creation requires DISM, the Windows ADK, and Administrator on a full Windows
session — none of which are available in WinPE. That work lives in the
[**OSDeploy**](https://www.powershellgallery.com/packages/OSDeploy) module.

## Prerequisites

- Windows 11 25H2 or newer (build 26200+).
- PowerShell 7.4+ installed with the MSI and running as Administrator.
- Windows ADK installed.
- The OSDeploy module installed: `Install-Module OSDeploy -AllowPrerelease -Force`.

For a full prerequisite walkthrough see the OSDeploy docs:
[`Build-OSDeployBoot`](https://github.com/OSDeploy/RecastOSDeploy/blob/main/OSDeploy/docs/Build-OSDeployBoot.md).

## How to build

### 1. Download and stage a Windows source (once)

```powershell
Update-OSDeployCoreESD
Update-OSDeployCoreOS
```

This downloads a Windows Enterprise ESD and stages its WinRE source for use
as the WinPE baseline. Skip this step if you plan to use `-UseAdkWinPE` instead.

### 2. (Optional) Refresh WinPE drivers

```powershell
Update-OSDeployCoreDrivers
```

Downloads current WinPE network/storage drivers into
`%ProgramData%\OSDeployCore\OSDRepo\winpe-drivers\`. They are injected
automatically on the next build.

### 3. Build the image

```powershell
# amd64 from imported WinRE
Build-OSDeployBoot -Name 'OSDCloud-amd64'

# arm64 from the ADK
Build-OSDeployBoot -Name 'OSDCloud-arm64' -UseAdkWinPE -Architecture arm64
```

Output lands in `%ProgramData%\OSDeployCore\boot\<Name>\`:

| File / folder | Use |
|---|---|
| `bootmedia\` | Files to copy to a USB or PXE share |
| `bootmedia.iso` | Bootable ISO (UEFI CA 2011) |
| `bootmedia_ca2023.iso` | Bootable ISO using the UEFI CA 2023 boot manager (for Secure Boot policies that require it) |

### 4. Verify the OSDCloud version

`Build-OSDeployBoot` copies the currently loaded OSDCloud module into the WIM.
When `Invoke-WinPEStartup` runs, it installs the latest gallery version unless
`-SkipUpdateOSDCloud` is set.

For an air-gapped image, load the required OSDCloud version before building
and set `SkipUpdateOSDCloud` in the startup profile.

## How to rebuild without re-mounting

If you only changed files in the existing `bootmedia` folder (for example,
swapped a `startnet.cmd`), regenerate just the ISO:

```powershell
Update-OSDeployBootISO
```

This skips the DISM mount step and runs `oscdimg.exe` against the existing
folder.

## Next

- [Boot a device into WinPE](03-boot-device.md)
