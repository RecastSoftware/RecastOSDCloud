# Unattended Deployment with a USB Startup Profile

## When to use this

Use a USB startup profile when:

- You want the operator to **insert USB, power on, walk away**.
- Different sites / labs need different deployment policy from the same boot image.
- You want to skip the Wi-Fi prompt because the site is wired.
- You want to run a custom PowerShell script (or PSCloudScript URL) automatically after WinPE comes up.

The same WinPE boot image can drive any number of policies — the
difference is the JSON file on the USB.

## Why profiles exist

`Invoke-WinPEStartup` accepts parameters for everything it does. Hard-coding
those parameters means rebuilding the boot image whenever a policy changes.
Profiles invert that: the boot image is generic, and a JSON file on USB
supplies the per-site / per-scenario settings at boot time.

## Precedence

```
Explicit -Parameter on the command line    ← highest
USB startup profile JSON
core/PSDefaultParameterValues.json         ← module defaults (lowest)
```

The module defaults are loaded into `$PSDefaultParameterValues` when the
module imports. A profile overrides any matching key. Explicit parameters
passed on the `Invoke-WinPEStartup` command line override both.

## How to create a profile

### 1. Drop a file on USB

Place a JSON file at:

```
<USB drive>:\WinPEStartup\Profiles\<anything>.json
```

Any partition on any drive connected at boot is scanned. The OSDCloud USB's
NTFS data partition (`OSDCloud` label, created by
`New-OSDeployBootUSB`) is the usual home for it.

- If exactly **one** profile is found, it is applied silently.
- If **multiple** profiles are found, a numbered menu is shown and the
  operator picks one.

### 2. Choose keys

Profile keys are the `Invoke-WinPEStartup` parameter names. Both forms work:

```jsonc
{ "SkipWiFi": true }                              // plain key
{ "Invoke-WinPEStartup:SkipWiFi": true }          // prefixed key
```

`//` line comments and `/* */` block comments are stripped before parsing.

## Full key reference

Every key shipped in `OSDCloud/core/PSDefaultParameterValues.json`.

| Key | Type | Module default | Purpose |
|---|---|---|---|
| `SkipOnScreenKeyboard` | bool | `false` | Skip on-screen keyboard launch |
| `ShowPnpDevices` | bool | `false` | Open PnP device window |
| `ShowPnpErrors` | bool | `false` | Open PnP error window |
| `SkipWiFi` | bool | `false` | Skip Wi-Fi connect prompt |
| `SkipIPConfig` | bool | `false` | Skip `ipconfig /all` display |
| `SkipUpdateOSDCloud` | bool | `false` | Skip module self-update |
| `InstallModule` | string[] | `[]` | Extra PowerShell modules to install at startup |
| `InvokeStartupCommand` | string[] | `[]` | Commands / URLs run in startup phase |
| `InvokeStartupCommandNoExit` | bool | `false` | Keep startup child window open |
| `InvokeStartupCommandEA` | string | `"Continue"` | Error action — `Continue` or `Stop` |
| `InvokeMainCommand` | string[] | `["Show-OSDCloudDeviceInfo","Deploy-OSDCloud"]` | Commands / URLs run in main phase |
| `InvokeMainCommandNoExit` | bool | `true` | Keep main child window open (so the operator sees results) |
| `InvokeMainCommandEA` | string | `"Continue"` | Error action |
| `InvokeShutdownCommand` | string[] | `[]` | Commands / URLs run in shutdown phase |
| `InvokeShutdownCommandNoExit` | bool | `false` | Keep shutdown child window open |
| `InvokeShutdownCommandEA` | string | `"Continue"` | Error action |

### URL auto-wrap

Any entry in `InvokeStartupCommand`, `InvokeMainCommand`, or
`InvokeShutdownCommand` that starts with `https://` or `http://` is
automatically converted to:

```powershell
Invoke-RestMethod -Uri '<url>' | Invoke-Expression
```

This is the PSCloudScript mechanism — point at a script in your repo and
the device fetches and runs it.

> **Security:** `Invoke-RestMethod | Invoke-Expression` runs whatever is at
> that URL with full WinPE privileges. Only point at URLs you control. Use
> HTTPS, not HTTP.

## Recipes

### Recipe — wired-only, fully unattended

```jsonc
{
  // Wired site — no Wi-Fi, no IP prompt
  "SkipWiFi": true,
  "SkipIPConfig": true,

  // Deploy without the UX
  "InvokeMainCommand": [
    "Show-OSDCloudDeviceInfo",
    "Deploy-OSDCloud -CLI"
  ],

  // Close the window when done so wpeutil reboot can run
  "InvokeMainCommandNoExit": false,

  // Reboot when the main phase ends
  "InvokeShutdownCommand": ["wpeutil reboot"]
}
```

### Recipe — site-specific PSCloudScript

```jsonc
{
  "InvokeMainCommand": [
    "https://raw.githubusercontent.com/contoso/winpe-config/main/sydney-deploy.ps1"
  ]
}
```

The script can call `Deploy-OSDCloud -CLI` or build its own flow — it has
full access to the OSDCloud module.

### Recipe — deployment options + extra modules

```jsonc
{
  "InstallModule": ["OSD", "WindowsAutopilotIntune"],
  "InvokeMainCommand": [
    "Show-OSDCloudDeviceInfo",
    "Deploy-OSDCloud -CLI -OperatingSystem 'Windows 11 24H2'"
  ]
}
```

### Recipe — diagnostics build (open the PnP windows)

```jsonc
{
  "ShowPnpDevices": true,
  "ShowPnpErrors": true,
  "InvokeMainCommand": []
}
```

Empty `InvokeMainCommand` means startup runs but no deployment is triggered
— useful for hardware checks.

## Validate a profile before deploying

On any Windows machine with the module installed:

```powershell
Get-Content '<USB>:\WinPEStartup\Profiles\mysite.json' -Raw |
    ForEach-Object { $_ -replace '//[^\r\n]*','' -replace '/\*.*?\*/','' } |
    ConvertFrom-Json
```

If `ConvertFrom-Json` errors, the file has a syntax problem the WinPE
loader will also reject.

## Next

- [Deploy to ARM64 devices](07-arm64-devices.md)
- [Troubleshoot](09-troubleshooting.md) if a profile doesn't seem to apply.
