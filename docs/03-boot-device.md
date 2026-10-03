# Boot a Device into WinPE

## When to use this

You have a built boot image (see [guide 2](02-build-boot-image.md)) and
need to get a target device running it. Pick the delivery method that
fits the situation:

| Method | Use when | Don't use when |
|---|---|---|
| **USB drive** | One device, branch office, ad-hoc reimage | Imaging dozens of devices in parallel |
| **ISO** | Booting a VM, IPMI/iLO/iDRAC virtual media, Hyper-V | Physical bare-metal — needs more setup |
| **PXE / network boot** | Lab, rack, classroom — many devices at once | No DHCP/TFTP infrastructure available |

## Option A — Boot from USB

### Why USB

Simplest path. One stick is enough to reimage any number of devices
sequentially. The USB also gives you an NTFS data partition for logs,
scripts, and a USB startup profile (see [guide 6](06-unattended-usb-profile.md)).

### How

```powershell
New-OSDeployBootUSB
```

Pick:

1. The completed build to copy.
2. Which media folder (`bootmedia` or `bootmedia_ca2023`).
3. The target USB disk (7 GB minimum).

The function wipes the disk, creates a FAT32 boot partition (`BOOT-AMD64` or
`BOOT-ARM64`, based on Architecture in the selected build's `properties.json`) and
an NTFS data partition (`OSDCloud`), then copies the WinPE files. Use `-BootLabel`
to override the automatic boot label.

To refresh an existing OSDCloud USB without repartitioning:

```powershell
Update-OSDeployBootUSB
```

By default, updates target USB boot volumes labeled for the selected build's
architecture and legacy `OSDEPLOY` volumes. Legacy volumes are relabeled to
`BOOT-AMD64` or `BOOT-ARM64` after a successful copy and metadata write.
Volumes labeled for the other architecture are left untouched. Supplying
`-BootLabel` targets only that label and disables automatic relabeling.
Automatic labeling requires valid build metadata; missing or unsupported
Architecture stops creation or updating before USB preparation or copying.

Then on the target device: power on, F12/F10/Esc into the boot menu, select
the USB device. UEFI mode is required.

## Option B — Boot from ISO

### Why ISO

Best for VMs and out-of-band management consoles (iDRAC, iLO, IPMI, Hyper-V,
VMware). No USB hardware involved.

### How

The ISO is already produced by `Build-OSDeployBoot` — use one of:

- `bootmedia.iso` for normal Secure Boot.
- `bootmedia_ca2023.iso` when the device's Secure Boot policy requires the 2023 UEFI CA boot manager (most 2024+ devices once the 2023 CA is enrolled).

Mount the ISO through your hypervisor or management controller and boot from
virtual CD.

## Option C — PXE / network boot

### Why PXE

Best for high-volume deployment: racks, classrooms, training labs. No USB
handling between devices.

### How

OSDeploy doesn't ship a PXE server. Use the boot files produced by
`Build-OSDeployBoot`:

1. Stand up a PXE service (Windows Deployment Services, iPXE, dnsmasq, etc.).
2. Publish the contents of the build's `bootmedia\` folder.
3. Point PXE clients at `bootmgfw.efi` (UEFI) and `boot\boot.wim` as the WinPE source.

Detailed PXE setup varies by infrastructure and is out of scope for OSDCloud.

## After WinPE boots

Whichever boot method you used, WinPE loads to an `X:\Windows\System32`
command prompt or directly into the OSDCloud startup sequence depending on
how the boot image was customized. Continue with
[guide 4 — Deploy Windows 11](04-deploy-windows.md).
