# Deploy to ARM64 Devices

## When to use this

You are deploying to an ARM-based Windows device:

- Microsoft Surface Pro 11 / Surface Laptop 7 (Snapdragon X)
- Other Copilot+ PCs (Snapdragon, ARM-based)
- Windows Dev Kit 2023
- ARM64 VMs

## Why this is different

ARM64 and amd64 are separate code paths end-to-end:

- A **different boot image** — WinPE compiled for ARM64.
- A **different OS catalog** — fewer editions are licensed for ARM64.
- A **different OEM driver pack** — most ARM64 devices are Surface (Microsoft) or Snapdragon reference designs.

You cannot boot an amd64 WinPE image on an ARM64 device or vice-versa.

## Prerequisites

Same as amd64 (see [guide 4](04-deploy-windows.md)) **plus**:

- The Windows ADK with the **WinPE ARM64 add-on** installed on the build machine.
- An ARM64-capable build of WinRE (or use `-UseAdkWinPE`).

## How to build an ARM64 boot image

```powershell
Build-OSDeployBoot -Name 'OSDCloud-arm64' -UseAdkWinPE -Architecture arm64
```

`-UseAdkWinPE` is the most reliable source for ARM64 — the ADK provides a
clean ARM64 `winpe.wim`. See
[`Build-OSDeployBoot`](https://github.com/OSDeploy/RecastOSDeploy/blob/main/OSDeploy/docs/Build-OSDeployBoot.md)
for full parameter detail.

## How to boot an ARM64 device

Same as amd64 — see [guide 3](03-boot-device.md). Most ARM64 devices boot
USB and ISO normally. PXE varies by vendor.

## OS choices for ARM64

The `default` channel ships these ARM64 options (`workflow/default/os-arm64.json`):

| Setting | Default | Available values |
|---|---|---|
| Operating System | Windows 11 25H2 | 25H2, 24H2, 23H2 |
| Activation | Retail | Retail, Volume |
| **Edition** | Pro | **Home, Pro, Enterprise only** — no N or Education editions |
| Language | en-us | 37 codes (no `bs-latn-ba` or `ms-my`) |

If you need Education or an N-edition you have to deploy amd64.

## OEM driver packs on ARM64

`Test-DriverPack` (step 5) checks whether a vendor driver pack is available
for the detected device. For Surface devices the pack is published by
Microsoft and discovered automatically. For other ARM64 hardware:

- If a pack exists, it is downloaded in step 23 and applied/staged in step 24.
- If no pack exists, OSDCloud falls back to the Microsoft Update Catalog drivers (steps 26–29).

Check what was used in `C:\Windows\Temp\osdcloud-logs\` after deployment.

## How to deploy

Exactly the same operator flow as amd64:

```powershell
Invoke-WinPEStartup
Deploy-OSDCloud           # or -CLI
```

The UX automatically loads `os-arm64.json` because the running architecture
is ARM64. The 40-step workflow is the same set of steps.

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `Test-TargetDriverPack` reports no pack | No vendor pack for this exact model | Continue — MU drivers will be applied. Capture the device's `Make` / `Model` and add a custom pack later. |
| Edition picker is missing N / Education | These editions are not licensed on ARM64 | Use Home / Pro / Enterprise. |
| ESD download is much slower | ARM64 ESDs are smaller but throttled by Microsoft regionally | Use a wired connection. |
| Device won't boot the ISO | Booted into 32-bit UEFI shim, or Secure Boot policy needs the 2023 CA | Use `bootmedia_ca2023.iso`. |

## Next

- [Hand off to Autopilot](08-autopilot-oobe.md) — Autopilot works identically on ARM64.
- [Troubleshoot](09-troubleshooting.md)
