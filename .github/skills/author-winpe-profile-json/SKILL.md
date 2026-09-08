---
name: author-winpe-profile-json
description: Author and update OSDCloud WinPE startup profile JSON files. Use this skill whenever the user asks to create, edit, validate, or add startup, main, shutdown, restart, module, Wi-Fi, IP configuration, device display, or PowerShell command settings in OSDCloud/core/OSDRepo/winpe-profiles/*.json, even if they only describe the desired WinPE behavior without naming the profile format.
---

# Author WinPE Profile JSON

Create profiles that configure `Invoke-WinPEStartup` without embedding workflow logic in the profile. Preserve the existing JSON style and make the smallest change that satisfies the request.

## Profile location and discovery

- Store profiles in `OSDCloud/core/OSDRepo/winpe-profiles/`.
- Use a descriptive `.json` filename. The startup function discovers profile files from `WinPEStartup\Profiles` on attached drives.
- A profile is a flat map of parameter names to scalar values or arrays. Do not add nested objects.
- Prefer standard JSON. The loader tolerates comments, but comments are unnecessary and can make external validation fail.

## Property names

Use the exact `Invoke-WinPEStartup:` prefix for every profile property:

| Property | JSON value | Effect |
|---|---|---|
| `Invoke-WinPEStartup:SkipOnScreenKeyboard` | boolean | Skip the on-screen keyboard check |
| `Invoke-WinPEStartup:ShowPnpDevices` | boolean | Show PnP device hardware |
| `Invoke-WinPEStartup:ShowPnpErrors` | boolean | Show PnP device errors |
| `Invoke-WinPEStartup:SkipWiFi` | boolean | Skip Wi-Fi startup and connection checks |
| `Invoke-WinPEStartup:SkipIPConfig` | boolean | Skip IP configuration display |
| `Invoke-WinPEStartup:SkipUpdateOSDCloud` | boolean | Skip the OSDCloud module update |
| `Invoke-WinPEStartup:InstallModule` | string or string array | Update additional PowerShell modules |
| `Invoke-WinPEStartup:InvokeStartupCommand` | string or string array | Run commands before the main phase |
| `Invoke-WinPEStartup:InvokeStartupCommandNoExit` | boolean | Keep the startup child PowerShell open |
| `Invoke-WinPEStartup:InvokeStartupCommandEA` | `Continue` or `Stop` | Handle startup child-process failure |
| `Invoke-WinPEStartup:InvokeMainCommand` | string or string array | Run commands in the main phase |
| `Invoke-WinPEStartup:InvokeMainCommandNoExit` | boolean | Keep the main child PowerShell open |
| `Invoke-WinPEStartup:InvokeMainCommandEA` | `Continue` or `Stop` | Handle main child-process failure |
| `Invoke-WinPEStartup:InvokeShutdownCommand` | string or string array | Run commands in the shutdown phase |
| `Invoke-WinPEStartup:InvokeShutdownCommandNoExit` | boolean | Keep the shutdown child PowerShell open |
| `Invoke-WinPEStartup:InvokeShutdownCommandEA` | `Continue` or `Stop` | Handle shutdown child-process failure |

Use JSON booleans (`true`/`false`) rather than quoted boolean strings. Use arrays when there are multiple commands or modules; command entries execute in array order in one child PowerShell process.

## Command behavior

- Write ordinary PowerShell lines as strings, for example `Show-OSDCloudDeviceInfo` or `Deploy-OSDCloud`.
- Use `Restart-Computer -Force` for a restart at the end of the shutdown phase. Do not use `shutdown.exe` unless the request specifically requires its options.
- URLs beginning with `http://` or `https://` are automatically converted to `Invoke-RestMethod -Uri '<url>' | Invoke-Expression` by `Invoke-WinPEStartup`. Do not wrap those URLs yourself.
- A `NoExit` setting leaves the child process open. Do not set it for a normal deployment or restart profile unless the user explicitly requests an interactive window.
- `Continue` is the default failure behavior. Choose `Stop` only when a failed child command must terminate startup.
- Keep deployment commands in the appropriate phase. For example, inspection and deployment belong in `InvokeMainCommand`; reboot belongs in `InvokeShutdownCommand`.

## Examples

### Deploy and restart

```json
{
  "Invoke-WinPEStartup:InvokeMainCommand": [
    "Show-OSDCloudDeviceInfo",
    "Deploy-OSDCloud"
  ],
  "Invoke-WinPEStartup:InvokeMainCommandNoExit": true,
  "Invoke-WinPEStartup:InvokeMainCommandEA": "Continue",
  "Invoke-WinPEStartup:InvokeShutdownCommand": [
    "Restart-Computer -Force"
  ]
}
```

### Display device information only

```json
{
  "Invoke-WinPEStartup:InvokeMainCommand": [
    "Show-OSDCloudDeviceInfo"
  ],
  "Invoke-WinPEStartup:InvokeMainCommandNoExit": true,
  "Invoke-WinPEStartup:InvokeMainCommandEA": "Continue"
}
```

## Authoring workflow

1. Identify the target profile and read its existing JSON before editing.
2. Map the requested behavior to the exact parameter in the table above.
3. Preserve unrelated properties, ordering, and formatting.
4. Add or update only the required property. Keep the JSON flat.
5. Parse the edited file with PowerShell 5.1:

```powershell
$profile = Get-Content -LiteralPath '.\OSDCloud\core\OSDRepo\winpe-profiles\<profile>.json' -Raw | ConvertFrom-Json
$profile | Out-Null
```

6. For command changes, verify the resulting property explicitly:

```powershell
$profile.'Invoke-WinPEStartup:InvokeShutdownCommand'
```

Do not execute profile commands during validation. Parsing verifies syntax without starting deployment, downloading content, or restarting the workstation.
