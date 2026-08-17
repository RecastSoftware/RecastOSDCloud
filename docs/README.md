# OSDCloud How-To Guides

Task-oriented guides for IT admins deploying Windows 11 with OSDCloud.
Each guide answers **when**, **why**, and **how** for a specific scenario.

If you are new to OSDCloud, read the guides in order. If you already have
a boot image and just want to deploy, start at [`04-deploy-windows.md`](04-deploy-windows.md).

## Reading order

| # | Guide | Read this when you want to… |
|---|---|---|
| 1 | [Overview](01-overview.md) | Decide whether OSDCloud is the right tool for the job |
| 2 | [Build a WinPE boot image](02-build-boot-image.md) | Produce a custom WinPE WIM/ISO with OSDCloud baked in |
| 3 | [Boot a device into WinPE](03-boot-device.md) | Get a target device running WinPE from USB, ISO, or PXE |
| 4 | [Deploy Windows 11](04-deploy-windows.md) | Walk an operator through a first deployment end-to-end |
| 5 | [Customize the deployment](05-customize-deployment.md) | Change OS edition, language, workflow settings, or skip steps |
| 6 | [Unattended deployment with a USB profile](06-unattended-usb-profile.md) | Drop a JSON file on USB for zero-touch deployments |
| 7 | [Deploy to ARM64 devices](07-arm64-devices.md) | Image a Snapdragon / Surface Pro 11 / Copilot+ PC |
| 8 | [Hand off to Autopilot and OOBE](08-autopilot-oobe.md) | Enrol the device in Intune after deployment |
| 9 | [Troubleshoot a failed deployment](09-troubleshooting.md) | Diagnose a deployment that didn't finish |

## Function reference

These how-tos focus on tasks. For cmdlet-by-cmdlet parameter reference
see the available generated pages in [`../OSDCloud/docs/`](../OSDCloud/docs/).

## Related modules

- [OSDeploy](https://github.com/OSDeploy/RecastOSDeploy) — builds the WinPE boot image OSDCloud runs inside (see [guide 2](02-build-boot-image.md)).
- [OSD](https://www.powershellgallery.com/packages/OSD) — earlier deployment module; OSDCloud supersedes its `Start-OSDCloud*` functions.
