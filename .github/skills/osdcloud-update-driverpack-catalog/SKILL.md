---
name: osdcloud-update-driverpack-catalog
description: "Step-by-step guide for updating OSDCloud driver pack catalogs: refresh Dell/HP/Lenovo XML snapshots, add or update Surface models in OSDCloud/core/driverpacks/surface.json, update OSDCloud/core/driverpacks/panasonic.json, or add ARM64 entries to OSDCloud/core/driverpacks/generic.json."
disable-model-invocation: true
argument-hint: "dell | hp | lenovo | microsoft | panasonic | generic | all"
---
Perform a driver pack catalog update for OSDCloud following the rules in [osdcloud-catalog-update.instructions.md](../instructions/osdcloud-catalog-update.instructions.md).

## Step 1 -- Determine scope

If the user provided an argument, use it to determine which catalogs to update:

| Argument | Catalog file(s) |
|---|---|
| `dell` | `OSDCloud/core/driverpacks/dell.xml` |
| `hp` | `OSDCloud/core/driverpacks/hp.xml` |
| `lenovo` | `OSDCloud/core/driverpacks/lenovo.xml` |
| `microsoft` | `OSDCloud/core/driverpacks/surface.json` |
| `panasonic` | `OSDCloud/core/driverpacks/panasonic.json` |
| `generic` | `OSDCloud/core/driverpacks/generic.json` |
| `all` | All of the above |

If no argument was provided, ask: **Which catalog(s) need updating?** (list the options above).

---

## Dell / HP / Lenovo -- snapshot refresh

For each OEM XML catalog being refreshed:

1. **Confirm the source URL** from `OSDCloud/core/module.json`:
   - Dell: `https://downloads.dell.com/catalog/DriverPackCatalog.cab`
   - HP: `https://hpia.hpcloud.hp.com/downloads/driverpackcatalog/HPClientDriverPackCatalog.cab`
   - Lenovo: `https://download.lenovo.com/cdrt/td/catalogv2.xml` (direct XML -- no CAB extraction needed)

2. **Download and extract** (Dell and HP -- CAB -> XML):
   ```powershell
   # Example for Dell
   Invoke-WebRequest -Uri 'https://downloads.dell.com/catalog/DriverPackCatalog.cab' -OutFile "$env:TEMP\DriverPackCatalog.cab"
   & expand.exe "$env:TEMP\DriverPackCatalog.cab" "$env:TEMP\DriverPackCatalog.xml"
   ```

3. **Replace the local snapshot**:
   ```powershell
   Copy-Item "$env:TEMP\DriverPackCatalog.xml" 'OSDCloud\core\driverpacks\dell.xml' -Force
   ```

4. **Do not edit the XML content** -- it is consumed as-is.

5. Report the file size and first `<version>` or `<DriverPackManifest version>` attribute from the new file to confirm it updated correctly.

---

## Microsoft (Surface) -- surface.json

`surface.json` is the sole source of truth for Surface driver packs. `Get-OSDCoreDriverPackCatalogSurface` reads it directly at runtime and enriches entries from live download pages for models that have an `UpdatePage` URL. **There is no `surface.xml` to regenerate.**

### If adding or updating a model entry manually

Ask the user for the following fields for each new/changed entry:

| Field | Example |
|---|---|
| `Model` | `Surface Pro 11 Intel` |
| `SystemId` | `Surface_Pro_11th_Edition_With_Intel_For_Business_2103` (must match WMI `Win32_ComputerSystemProduct.Name`) |
| `OperatingSystem` | `Windows 11` |
| `OSArchitecture` | `amd64` or `arm64` |
| `FileName` | `SurfacePro11withIntel_Win11_22631_<ver>.msi` |
| `Url` | Full `https://download.microsoft.com/...` URL |
| `HashMD5` | MD5 hash string, or `null` |
| `UpdatePage` | URL to Microsoft download details page, or `null` |

Then:

1. Set `CatalogVersion` and `ReleaseDate` to today's date in `YY.MM.DD` format.
2. Set `Name` to `"Surface <Model> [<ReleaseDate>]"` (no "Microsoft" prefix in the Name field).
3. Edit `OSDCloud/core/driverpacks/surface.json` -- insert the new entry in the correct position (sort by Model name).
4. Confirm the file is saved.

### Automated update via GitHub Actions

The `.github/workflows/update-catalog-microsoft.yaml` workflow runs `.github/scripts/Update-MicrosoftCatalog.ps1` every 4 hours and on demand. It scrapes every `UpdatePage` URL in `OSDCloud/core/driverpacks/surface.json`, selects the best available MSI, and updates the JSON file when changes are detected. Trigger the workflow manually with `workflow_dispatch` to run it immediately.

---

## Panasonic -- panasonic.json

### If adding a new model

Ask the user for:

| Field | Example |
|---|---|
| `Alias` | `FZ55-3` |
| `Product` | `FZ55-3H` (WMI `Win32_ComputerSystemProduct.Name`) |
| Driver pack entries per OS release (OSVer, OSRelease, Version, URL, Size, Hash, ReleaseDate) | -- |

### If adding a new driver pack version to an existing model

Ask which model (`Alias`) and which release is being added or updated.

Then:

1. Update `LastDateModified` at the root to the current UTC timestamp: `"YYYY-MM-DDTHH:MM:SSZ"`.
2. Use `"OSVer": "Win11"` -- **never** `"Win10"` (filtered out at runtime).
3. `ReleaseDate` format: `"YYYY-MM-DD"`.
4. Do not remove existing OS release entries -- append the new one.

---

## Generic (ARM64 / generic) -- generic.json

Ask the user for the new entry fields (same schema as `surface.json`):
`CatalogVersion`, `ReleaseDate`, `Name`, `Manufacturer`, `Model`, `SystemId`, `FileName`, `Url`, `OperatingSystem`, `OSArchitecture`, `HashMD5`.

Rules:
- Set `OSArchitecture` to `"arm64"` for ARM64-only packs.
- Set `CatalogVersion` to today's date (`YY.MM.DD`) for all new/changed entries.
- Keep the array sorted by `Manufacturer` then `Model`.

---

## Final checklist

After all edits, confirm each item:

- [ ] OEM XML snapshots replaced (Dell/HP/Lenovo as applicable)
- [ ] `OSDCloud/core/driverpacks/surface.json` edited (if applicable)
- [ ] `OSDCloud/core/driverpacks/panasonic.json` updated with new `LastDateModified` (if applicable)
- [ ] `OSDCloud/core/driverpacks/generic.json` updated (if applicable)
- [ ] No manual edits made to Dell/HP/Lenovo XML content

Report a one-line summary of each file changed and what was updated.
