# OSDCoreDevice: OSDCloud's Device Check-In

Before OSDCloud changes a computer, it needs a reliable answer to a few important questions:

- What kind of computer is this?
- Is it a laptop, desktop, tablet, server, or virtual machine?
- Does it support modern Windows features such as TPM 2.0, UEFI, and Secure Boot?
- Is it on battery power?
- Is the network working?
- Which USB drives and disks are connected?
- Which manufacturer and model-specific driver pack should it use?

`Initialize-OSDCoreDevice` is the internal OSDCloud function that collects those answers. Think of it as a quick check-in at the start of a deployment: it looks around the device, writes down what it finds, and gives the rest of OSDCloud one consistent set of facts to work from.

## What it does in plain English

When OSDCloud starts, `Initialize-OSDCoreDevice` takes a snapshot of the computer and stores it in `$global:OSDCoreDevice`. Other OSDCloud steps use this snapshot instead of repeatedly asking Windows for the same information.

It collects information such as:

| It checks | Why that matters |
|---|---|
| Manufacturer, model, product, and serial number | Helps OSDCloud identify the computer and match it to the correct driver pack. |
| Processor and Windows architecture | Helps ensure the deployment uses the right content for AMD64 or ARM64 devices. |
| Disks, partitions, USB volumes, and free-space context | Helps OSDCloud recognize the boot USB and avoid treating it like the deployment target. |
| Network adapters, IP addresses, gateways, and `ipconfig` output | Makes it easier to see whether the device can reach Windows and driver downloads. |
| BIOS, UEFI, Secure Boot, and related certificate information | Highlights boot-security conditions that may affect newer Windows deployments. |
| TPM state and version | Indicates whether the device is ready for modern Windows security features and Intune Autopilot. |
| Memory, battery state, and chassis type | Lets OSDCloud make safer choices and explains why a device may not be ideal for a workflow. |
| Keyboard layout and time zone | Preserves useful local settings for deployment and troubleshooting. |
| Virtual-machine status | Allows workflows and support staff to tell a physical device from a VM. |

## Why this is awesome

### It reduces guesswork

A deployment is much more reliable when it begins with real information instead of assumptions. OSDCloud does not have to guess whether a device is a Surface, Dell, HP, Lenovo, a tablet, or a virtual machine—it checks.

### It helps select the right drivers

Different computer models need different drivers. The function tidies up manufacturer and model information so that names are more consistent. For example, it handles common variations in how Dell, HP, Lenovo, Microsoft, ASUS, and other manufacturers report their hardware. This gives driver-pack matching a much better chance of choosing the right download.

### It catches compatibility surprises early

TPM, Secure Boot, UEFI, available memory, architecture, and battery state can all affect a deployment. Checking them early makes warnings easier to understand and prevents a problem from appearing only after Windows has already been downloaded or installed.

### It creates evidence for troubleshooting

The function writes a set of diagnostic files to `%TEMP%\osdcloud-logs`, including hardware, firmware, disk, network, and operating-system details. It also saves the final device snapshot as `OSDCoreDevice.json`.

If a deployment fails, those files turn “it did not work” into useful information an administrator can review or share with support. When an `OSDCloudLogs` folder is available on a suitable drive, OSDCloud also tries to stage the logs there.

### It supports Autopilot preparation

When `oa3tool.exe` is available, the function can collect the device hardware hash and create an `Autopilot.csv` file in the diagnostic log folder. That can help prepare a device for Microsoft Intune Autopilot registration.

### It gives every later step the same picture

The results are stored in `$global:OSDCoreDevice`, an internal shared record used by deployment and workflow steps. That means a later driver, disk, or workflow step is working from the same device facts that were discovered at the beginning.

## What it does not do

`Initialize-OSDCoreDevice` is an information-gathering and preparation step. By itself, it does **not**:

- install Windows;
- wipe or partition a disk;
- download a driver pack;
- enable Secure Boot or TPM;
- enroll a device in Autopilot or Intune.

Instead, it gives the deployment process the information needed to do those jobs more safely and clearly.

## A simple way to think about it

Imagine a technician arriving at a device with a clipboard before beginning a rebuild. They check the make and model, confirm the power and network situation, identify the USB media, note security capabilities, take photos of the labels, and keep the notes for later.

`Initialize-OSDCoreDevice` is that careful technician—only faster, consistent, and available every time OSDCloud runs.

## Where to find the details

The function itself is an internal helper located at [OSDCloud/private/core-device/Initialize-OSDCoreDevice.ps1](../OSDCloud/private/core-device/Initialize-OSDCoreDevice.ps1). The generated snapshot is saved during a run at `%TEMP%\osdcloud-logs\OSDCoreDevice.json`.
