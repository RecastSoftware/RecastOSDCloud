# Troubleshoot a Failed Deployment

## When to use this

A deployment didn't finish, or finished but produced a device that won't
boot. Work through this guide before opening an issue.

## Why most failures are one of five things

In order of frequency:

1. **No network** in WinPE — driver missing or Wi-Fi credentials wrong.
2. **Wrong / missing driver pack** — `Test-DriverPack` failed.
3. **Disk too small or not present** — `Test-TargetDisk` failed.
4. **ESD download interrupted** — slow link, Microsoft throttling, or proxy.
5. **Low memory** — under 4 GB RAM, WinPE runs out of working set during ESD expansion.

## Where logs live

| Phase | Path | When |
|---|---|---|
| WinPEStartup | `X:\Windows\Temp\osdcloud-logs\` | While in WinPE |
| Workflow (early) | `X:\OSDCloud\Logs\` | Before disk is partitioned |
| Workflow (post-disk) | `C:\Windows\Temp\osdcloud-logs\` | After step 14 (log restart) |
| First boot | `C:\Windows\Temp\osdcloud-logs\` | After OOBE |

The log restart (step 14) switches paths the moment the local disk is
writable, so older entries are on `X:`, newer on `C:`.

To collect logs from WinPE before a reboot:

```powershell
Copy-Item X:\OSDCloud\Logs\* D:\osdcloud-logs\ -Recurse
Copy-Item C:\Windows\Temp\osdcloud-logs\* D:\osdcloud-logs\ -Recurse
```

(`D:` is the NTFS partition of the OSDCloud USB.)

## Diagnostic cmdlets

| Cmdlet | What it shows |
|---|---|
| `Show-OSDCloudDeviceInfo` | Make, model, serial, TPM, Secure Boot, disk, RAM, battery, IP |
| `Show-WinPEStartupDevices` | All PnP devices in WinPE |
| `Show-WinPEStartupDeviceErrors` | PnP devices reporting an error (missing driver) |
| `Show-WinPEStartupIpconfig` | `ipconfig /all` output |
| `Show-WinPEStartupWifi` | Connect / reconnect to Wi-Fi |
| `Start-OSDCloudExplorer` | WinForms file browser — useful for reading logs in WinPE |

Run any of them at the `X:\` prompt.

## Common failures

### "No network adapter" in WinPE

```powershell
Show-WinPEStartupDeviceErrors
```

If the Ethernet or Wi-Fi NIC shows here, WinPE is missing a driver. Fix:
add the driver to `%ProgramData%\OSDeployCore\OSDRepo\winpe-drivers\` on
the build machine and re-run `Build-OSDeployBoot`. For a quick test, copy
`.inf`-based drivers to `D:\Drivers\` on the USB and run:

```powershell
Add-WindowsDriver -Path X:\ -Driver D:\Drivers -Recurse
```

### "Wi-Fi connects but no IP"

```powershell
Show-WinPEStartupWifi    # reconnect
Show-WinPEStartupIpconfig
```

DHCP retry is built in. If the IP stays `169.254.x.x`, the access point
likely rejected the device. Verify the SSID/PSK and re-run.

### `Test-TargetDisk` fails

Run `Show-OSDCloudDeviceInfo` and confirm:

- A disk is reported (no disk → BIOS not seeing it, possibly RAID/Intel VMD).
- The disk is large enough (64 GB+ recommended).

For Intel VMD systems, ensure the VMD driver is in your WinPE driver folder
(`OSDRepo\winpe-drivers\`).

### `Test-DriverPack` reports "no driver pack"

Means OSDCloud has no OEM driver pack catalogued for this Make+Model. The
deployment will still proceed using firmware + Microsoft Update drivers.
To add a pack permanently, see the catalog instructions referenced from
`CONTRIBUTING.md`.

### ESD download fails or restarts

```
step-install-downloadwindowsimage : ...
```

- Confirm the device can reach `software.download.prss.microsoft.com`.
- Behind a proxy? WinPE doesn't honour Windows proxy settings — set them with
  `netsh winhttp set proxy ...` before running.
- Slow link? Retry. The download is resumable.

### "Low memory warning" then ESD expand fails

Devices with less than 6 GB RAM print a warning at startup; expansion can
still succeed at 4 GB but is fragile. Mitigations:

- Set BIOS/UEFI to allocate maximum RAM to the OS (disable iGPU UMA boost).
- Use a USB drive with an NTFS data partition so the ESD can be downloaded
  to disk first and expanded from there.

### Device boots to "no boot device"

Step 17 (BCDBoot) failed silently or partitioning was wrong (legacy MBR
disk). Check:

```powershell
Get-Disk
Get-Partition -DiskNumber 0
```

The EFI system partition should be present and FAT32. If the device booted
WinPE in BIOS/CSM mode, change UEFI mode in firmware and re-deploy.

### Workflow ran in WinPE but no Windows on disk

Confirm `Deploy-OSDCloud` was not invoked with `-CLI` from a full Windows
session — most steps are skipped outside WinPE (only those with
`testinfullos: true` run).

### A USB profile isn't applied

```powershell
Get-ChildItem -Path *:\WinPEStartup\profiles\*.json
```

- Profile must be at `<drive>:\WinPEStartup\profiles\*.json` — exact path.
- File must parse as JSON (after stripping `//` and `/* */` comments). Validate on Windows:
  ```powershell
  Get-Content profile.json -Raw |
      ForEach-Object { $_ -replace '//[^\r\n]*','' -replace '/\*.*?\*/','' } |
      ConvertFrom-Json
  ```
- If multiple profiles are on USB the operator was prompted to choose — make sure they picked the right one.

### Module didn't self-update

```
[Invoke-WinPEStartup] Update-WinPEStartupModule -Name OSDCloud  → SKIPPED
```

`-SkipUpdateOSDCloud` is `true` (somewhere in your profile or call). Either
remove it or run `Install-Module OSDCloud -SkipPublisherCheck -Force` by hand.

## Get more detail

Run with `-Verbose`:

```powershell
Invoke-WinPEStartup -Verbose
Deploy-OSDCloud -CLI -Verbose
```

Verbose lines are timestamped and tagged with the calling function name —
the bracketed prefix tells you which file to look at under
`OSDCloud/private/` if you need to read the implementation.

## Still stuck?

Collect the contents of `C:\Windows\Temp\osdcloud-logs\` plus
`Show-OSDCloudDeviceInfo` output and open an issue:

<https://github.com/OSDeploy/OSDCloud/issues>
