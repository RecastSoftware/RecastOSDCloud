# WinPEStartup: OSDCloud's Boot-Time Checklist

WinPE is a small, temporary operating system. That makes it fast and useful for deployment, but it also means the environment starts with very little state. Drive letters may not be stable, networking may still be waking up, optional storage or network drivers may be needed, and a technician may have plugged in a USB drive with extra files or a startup profile.

`Invoke-WinPEStartup` is OSDCloud's answer to that early boot problem. It gives WinPE a predictable startup checklist before the user or deployment workflow starts making larger decisions.

## What it does in plain English

`Invoke-WinPEStartup` runs only when `SystemDrive` is `X:`, which is the normal WinPE RAM disk. If it is called from a full Windows installation, it writes a warning and exits. That guard matters because several startup actions are WinPE-specific and should not change a normal Windows session.

At a high level, the startup flow does this:

| Phase | What happens | Why it matters |
|---|---|---|
| Load defaults | Reads module-level JSON defaults for `Invoke-WinPEStartup:*` keys. | Lets a boot image carry sensible startup behavior without hard-coding it in the function. |
| Prepare the shell | Creates profile folders, sets key environment variables, and configures PowerShell execution policy for the WinPE session. | Gives PowerShell and user-profile paths enough structure to behave like a normal shell. |
| Load drivers | Scans attached drives for `WinPEStartup\Drivers` and loads discovered `.inf` files with `drvload.exe`. | Allows storage, network, or input drivers to be supplied from USB without rebuilding the boot image. |
| Copy files | Scans attached drives for `WinPEStartup\Files` and copies content into the WinPE RAM disk. | Makes helper files, tools, or configuration available at `X:\` for the current session. |
| Initialize WinPE | Runs `wpeinit`, disables the firewall, updates boot info, normalizes USB drive letters, renews networking, and opens a minimized PowerShell session. | Establishes hardware, networking, and predictable removable-drive layout before later steps run. |
| Select a profile | Scans `WinPEStartup\profiles` on attached drives for JSON profiles. A single profile is selected automatically; multiple profiles are shown as a menu. | Lets one USB drive hold site, customer, or workflow-specific startup settings. |
| Apply parameters | Merges defaults, profile values, and explicit caller parameters. Explicit caller parameters win. | Keeps the configuration flexible while preserving operator intent. |
| Run startup actions | Optionally launches the on-screen keyboard, device views, Wi-Fi connection UI, IP configuration display, module updates, and startup/main/shutdown commands. | Handles the common things a technician needs immediately after WinPE starts. |

## The basic flow

The entry point is `Invoke-WinPEStartup`. It does not try to deploy Windows by itself. Instead, it prepares the temporary WinPE session so the next command has a sane environment.

The flow is intentionally front-loaded:

1. Confirm the session is really WinPE.
2. Load default startup settings from the module JSON file if present.
3. Prepare the WinPE shell profile and environment variables.
4. Load supplemental drivers from attached media.
5. Copy supplemental files from attached media.
6. Run `wpeinit` and `wpeutil` setup work.
7. Move USB drive letters into the `H:` through `Z:` range when possible.
8. Refresh networking.
9. Discover and apply a startup profile if one is available.
10. Run optional operator-facing tools and command hooks.

That order is deliberate. Drivers and copied files are available before the main WinPE initialization finishes. USB letters are normalized before later commands need to find removable media. Profiles are applied after the system is initialized enough to discover attached drives reliably.

## Defaults and profiles

WinPEStartup configuration has two useful layers.

Module defaults are read from the OSDCloud PSDefaultParameterValues JSON file. Keys use the normal PowerShell default-parameter style, such as:

```json
{
  "Invoke-WinPEStartup:SkipWiFi": true,
  "Invoke-WinPEStartup:SkipIPConfig": true
}
```

Startup profiles are JSON files under this layout on any attached drive:

```text
H:\WinPEStartup\profiles\BranchOffice.json
```

Profiles may use either prefixed keys, such as `Invoke-WinPEStartup:SkipWiFi`, or plain splat-style keys, such as `SkipWiFi`. That makes profiles easier to read while still supporting the same parameters.

If exactly one profile is found, OSDCloud selects it automatically. If several profiles are found, OSDCloud shows a numbered list and lets the operator choose. Pressing Enter or typing `q` cancels the profile selection and stops the remaining startup sequence.

Explicit parameters passed to `Invoke-WinPEStartup` take precedence over JSON values. That rule is important: a profile can supply defaults, but a real command-line choice from the operator should not be silently overridden.

## Command hooks

`Invoke-WinPEStartup` supports three command phases:

| Parameter | When it runs |
|---|---|
| `InvokeStartupCommand` | Early custom commands after the standard startup manager steps are available. |
| `InvokeMainCommand` | Main custom command phase. |
| `InvokeShutdownCommand` | Final custom command phase. |

Each command parameter accepts one or more command strings. HTTP and HTTPS entries are treated as remote PowerShell content and are wrapped as:

```powershell
Invoke-RestMethod -Uri '<url>' | Invoke-Expression
```

The combined commands run in a child `powershell.exe` process with `-NoLogo`, `-NoProfile`, `-ExecutionPolicy Bypass`, and `-EncodedCommand`. Each phase also has a matching `NoExit` switch and an error-action setting that can either continue with a warning or stop on failure.

This design keeps custom startup logic outside the main function while still giving profiles a clean way to run site-specific automation.

## Why this makes sense

### WinPE needs a setup pass

Full Windows has persistent profiles, established services, stable drive letters, and installed drivers. WinPE does not. Treating WinPE like a normal OS leads to fragile scripts because the first few seconds of the session are still settling.

A startup checklist gives OSDCloud one predictable place to handle that early instability.

### USB media becomes more useful

The same USB drive can provide more than a boot image. With a `WinPEStartup` folder, it can also carry:

| Folder | Purpose |
|---|---|
| `WinPEStartup\Drivers` | Supplemental `.inf` drivers loaded into WinPE. |
| `WinPEStartup\Files` | Files copied into the WinPE RAM disk. |
| `WinPEStartup\profiles` | JSON startup profiles selected at boot. |

That lets a technician adapt one boot image to different sites or hardware without rebuilding the image every time.

### The flow protects normal Windows

Every startup helper checks whether it is running from `X:` before doing WinPE-specific work. That makes the functions safer to import in the module outside WinPE because accidental calls do not start changing a technician's normal Windows session.

### Configuration stays layered

Module defaults, USB profiles, and explicit parameters each have a job:

| Layer | Best use |
|---|---|
| Module defaults | General behavior baked into the boot image or module content. |
| USB profile | Site, customer, or scenario-specific startup behavior. |
| Explicit parameter | One-off operator intent for the current boot. |

The precedence order keeps the broad settings convenient while still letting the person at the keyboard override them.

### Optional windows stay optional

Not every startup needs the on-screen keyboard, device hardware window, PnP error window, Wi-Fi UI, or IP configuration window. `Invoke-WinPEStartupManager` routes those actions only when the corresponding setting asks for them.

That keeps quiet, unattended runs clean while still making technician-driven troubleshooting easy.

### Network work is checked before it is needed

The Wi-Fi and module-update paths check for connectivity before launching connection or update work. WinPE does not always have the same networking tools as full Windows, so OSDCloud uses lightweight checks that work in WinPE, including a raw TCP connection and simple HTTP tests.

That avoids wasting time on module updates when the device is clearly offline and avoids launching the Wi-Fi UI when the network is already usable.

## What it does not do

`Invoke-WinPEStartup` prepares the WinPE session. By itself, it does **not**:

- deploy Windows;
- partition or wipe disks;
- select an operating system image;
- choose an OEM driver pack for the installed OS;
- enroll a device in Autopilot;
- guarantee internet access;
- permanently change the installed Windows operating system.

It answers a smaller but important question: **is this WinPE session ready enough for OSDCloud or a technician to continue?**

## A simple way to think about it

Imagine a technician arriving at a workbench before starting a rebuild. They plug in the USB drive, lay out the extra tools, check that the network is working, make sure the keyboard is usable, pick the right instruction sheet, and only then start the deployment.

`Invoke-WinPEStartup` is that setup routine for WinPE. It does the practical boot-time chores first so deployment logic can start from a cleaner, more predictable place.

## Where to find the details

The main entry point is [OSDCloud/public/WinPE/Invoke-WinPEStartup.ps1](../OSDCloud/public/WinPE/Invoke-WinPEStartup.ps1). Optional startup actions are dispatched by [OSDCloud/public/WinPE/Invoke-WinPEStartupManager.ps1](../OSDCloud/public/WinPE/Invoke-WinPEStartupManager.ps1).

The private helper functions live under [OSDCloud/private/WinPEStartup](../OSDCloud/private/WinPEStartup). The most important pieces are:

- [Initialize-WinPEStartupEnvironment.ps1](../OSDCloud/private/WinPEStartup/Initialize-WinPEStartupEnvironment.ps1) for shell folders, environment variables, and execution policy.
- [Initialize-WinPEStartupDrivers.ps1](../OSDCloud/private/WinPEStartup/Initialize-WinPEStartupDrivers.ps1) for supplemental driver loading.
- [Initialize-WinPEStartupFiles.ps1](../OSDCloud/private/WinPEStartup/Initialize-WinPEStartupFiles.ps1) for copying startup files into the RAM disk.
- [Initialize-WinPEStartupMain.ps1](../OSDCloud/private/WinPEStartup/Initialize-WinPEStartupMain.ps1) for `wpeinit`, `wpeutil`, drive-letter cleanup, and network refresh.
- [Set-WinPEStartupUSBDriveLetter.ps1](../OSDCloud/private/WinPEStartup/Set-WinPEStartupUSBDriveLetter.ps1) for deterministic USB drive-letter assignment.
