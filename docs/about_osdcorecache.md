# OSDCoreCache: OSDCloud's Local Supply Shelf

OSDCloud normally downloads Windows installation files and driver packs when it needs them. That is convenient when the internet is fast and reliable, but it can be slow—or impossible—when a connection is limited.

**OSDCoreCache** is OSDCloud's way of checking whether useful deployment content is already nearby. Think of it as a supply shelf: before ordering another copy from the internet, OSDCloud looks on the connected drives to see what is already available.

## What it does in plain English

`Initialize-OSDCoreCache` refreshes OSDCloud's in-memory list of cached content and stores the result in `$global:OSDCoreCache`.

It uses `Get-OSDCoreCacheContent` to look through every mounted file-system drive for an `OSDCloud` folder. When it finds one, it checks the familiar folders inside it and records the useful deployment content it contains.

The inventory includes:

| Folder below `OSDCloud` | What OSDCloud looks for |
|---|---|
| `OS` | Windows ESD files (`.esd`) |
| `ISO` | Windows ISO files (`.iso`) |
| `DriverPacks` | OEM driver-pack files (`.cab`, `.exe`, `.msi`, and `.zip`) |
| `Drivers` | Driver folders containing `.inf` files |
| `Profiles` | Deployment profile folders |
| `WIM` | Windows image files (`.wim`) |

For every item it finds, the cache records useful details such as the file name, full path, size, drive letter, volume label, and whether the drive is connected by USB.

## Why this is awesome

### It can save a lot of download time

Windows images and driver packs are large. If the right ESD or driver pack is already on an OSDCloud USB drive, OSDCloud can use that local copy instead of downloading it again.

That is especially helpful when you are rebuilding several computers, working at a branch office, or using a slow connection.

### It gives USB media a second job

A boot USB can be more than just the tool that starts WinPE. With an `OSDCloud` folder and cached content, it can also carry Windows images, driver packs, drivers, and deployment profiles.

This makes a prepared USB drive a practical field kit for technicians.

### It works with more than USB drives

The inventory checks mounted file-system drives, not only USB media. That means content can be discovered on an internal disk, another removable drive, or a mapped location that appears as a normal drive letter.

When OSDCloud specifically needs an eligible USB cache location, `Get-OSDCoreCacheUSBPath` narrows the choice to USB drives with:

- an `OSDCloud` folder;
- an NTFS or exFAT file system; and
- more than the configured amount of free space (10 GB by default).

### It makes deployment decisions visible

Rather than silently finding files somewhere on a drive, OSDCoreCache builds a clear inventory. Deployment and workflow steps can use the same list to determine whether an operating system image or driver pack is available locally.

The inventory is also exported as `%TEMP%\OSDCoreCache.xml`, which can help with troubleshooting.

### It reduces repeated searching

Once the cache is initialized, later OSDCloud steps can use `$global:OSDCoreCache` instead of each searching every drive again. This gives the deployment process one consistent view of the available local content.

## A simple example

Suppose a technician has a USB drive with this layout:

```text
E:\OSDCloud\
├── OS\
│   └── Windows 11 25H2\Windows11.esd
├── DriverPacks\
│   └── Dell-Latitude-DriverPack.cab
└── Profiles\
    └── BranchOffice\
```

When OSDCoreCache is refreshed, it recognizes the Windows ESD, the Dell driver pack, and the `BranchOffice` profile. OSDCloud can then tell that these items are available locally instead of assuming everything must come from the internet.

## What it does not do

OSDCoreCache is an inventory system. By itself, it does **not**:

- download a Windows image or driver pack;
- create an `OSDCloud` folder on a drive;
- decide which Windows edition to deploy;
- copy content to a USB drive automatically;
- guarantee that a cached file is the correct version for every device.

It answers a simpler but important question: **what useful OSDCloud content is already available here?** Other deployment steps choose whether and how to use it.

## A simple way to think about it

Imagine a technician opening a parts cabinet before ordering replacements. They check which parts are already on the shelf, note where they are stored, and give the rest of the team the same list.

`Initialize-OSDCoreCache` does that for deployment files. It makes local Windows images, driver packs, drivers, WIM files, and profiles easy for OSDCloud to find and reuse.

## Where to find the details

The cache initializer is an internal helper located at [OSDCloud/private/core-cache/Initialize-OSDCoreCache.ps1](../OSDCloud/private/core-cache/Initialize-OSDCoreCache.ps1). The drive scan is implemented in [OSDCloud/private/core-cache/Get-OSDCoreCacheContent.ps1](../OSDCloud/private/core-cache/Get-OSDCoreCacheContent.ps1).
