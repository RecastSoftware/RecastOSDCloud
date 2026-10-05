---
name: author-winpe-profile-json
description: Author and update OSDCloud WinPE startup profile JSON files. Use this skill whenever the user asks to create, edit, validate, or add startup, main, shutdown, restart, module, Wi-Fi, IP configuration, device display, or PowerShell command settings in OSDCloud/core/OSDRepo/winpe-profiles/*.json, even if they only describe the desired WinPE behavior without naming the profile format.
---

# Author WinPE Profile JSON

Create profiles that configure `Invoke-WinpeStartup` without embedding workflow logic in the profile. Preserve the existing JSON style and make the smallest change that satisfies the request.

## Profile location and discovery

- Store bundled profiles in `OSDCloud/core/winpestartup-profiles/`.
- Use a descriptive `.json` filename. The startup function discovers profile files from `WinpeStartup\Profiles` on attached drives.
- A profile is a flat map of parameter names to scalar values or arrays, with one supported nested object: the top-level `Environment` section.
- Prefer standard JSON. The loader tolerates comments, but comments are unnecessary and can make external validation fail.

## Property names

Use the exact `Invoke-WinpeStartup:` prefix for every profile property:

| Property | JSON value | Effect |
|---|---|---|
| `Invoke-WinpeStartup:SkipOnScreenKeyboard` | boolean | Skip the on-screen keyboard check |
| `Invoke-WinpeStartup:ShowPnpDevices` | boolean | Show PnP device hardware |
| `Invoke-WinpeStartup:ShowPnpErrors` | boolean | Show PnP device errors |
| `Invoke-WinpeStartup:SkipWiFi` | boolean | Skip Wi-Fi startup and connection checks |
| `Invoke-WinpeStartup:SkipIPConfig` | boolean | Skip IP configuration display |
| `Invoke-WinpeStartup:SkipUpdateOSDCloud` | boolean | Skip the OSDCloud module update |
| `Invoke-WinpeStartup:InstallModule` | string or string array | Update additional PowerShell modules |
| `Invoke-WinpeStartup:InvokeStartupCommand` | string or string array | Run commands before the main phase |
| `Invoke-WinpeStartup:InvokeStartupCommandNoExit` | boolean | Keep the startup child PowerShell open |
| `Invoke-WinpeStartup:InvokeStartupCommandEA` | `Continue` or `Stop` | Handle startup child-process failure |
| `Invoke-WinpeStartup:InvokeMainCommand` | string or string array | Run commands in the main phase |
| `Invoke-WinpeStartup:InvokeMainCommandNoExit` | boolean | Keep the main child PowerShell open |
| `Invoke-WinpeStartup:InvokeMainCommandEA` | `Continue` or `Stop` | Handle main child-process failure |
| `Invoke-WinpeStartup:InvokeShutdownCommand` | string or string array | Run commands in the shutdown phase |
| `Invoke-WinpeStartup:InvokeShutdownCommandNoExit` | boolean | Keep the shutdown child PowerShell open |
| `Invoke-WinpeStartup:InvokeShutdownCommandEA` | `Continue` or `Stop` | Handle shutdown child-process failure |

Use JSON booleans (`true`/`false`) rather than quoted boolean strings. Use arrays when there are multiple commands or modules; command entries execute in array order in one child PowerShell process.

## Environment variables

Use an unprefixed top-level `Environment` object to set process-scoped environment variables after the profile is selected:

```json
{
  "Environment": {
    "OSDCLOUD_SITE": "BranchOffice",
    "OSDCLOUD_DEPLOYMENT_RING": 2,
    "OSDCLOUD_INTERACTIVE": true
  }
}
```

- Variable values may be strings, numbers, or booleans and are converted to invariant strings.
- Existing process variables with the same name are overwritten.
- Child PowerShell sessions launched by the startup, main, and shutdown command phases inherit the values.
- Null values, arrays, nested objects, and invalid names warn and are skipped without blocking other entries.
- Values are not persisted to the registry or machine environment.
- Do not put secrets in profiles. Although values are not logged, profile files are plain text.

## Command behavior

- Write ordinary PowerShell lines as strings, for example `Show-OSDCloudDeviceInfo` or `Deploy-OSDCloud`.
- Use `Restart-Computer -Force` for a restart at the end of the shutdown phase. Do not use `shutdown.exe` unless the request specifically requires its options.
- URLs beginning with `http://` or `https://` are automatically converted to `Invoke-RestMethod -Uri '<url>' | Invoke-Expression` by `Invoke-WinpeStartup`. Do not wrap those URLs yourself.
- A `NoExit` setting leaves the child process open. Do not set it for a normal deployment or restart profile unless the user explicitly requests an interactive window.
- `Continue` is the default failure behavior. Choose `Stop` only when a failed child command must terminate startup.
- Keep deployment commands in the appropriate phase. For example, inspection and deployment belong in `InvokeMainCommand`; reboot belongs in `InvokeShutdownCommand`.

## Examples

### Deploy and restart

```json
{
  "Invoke-WinpeStartup:InvokeMainCommand": [
    "Show-OSDCloudDeviceInfo",
    "Deploy-OSDCloud"
  ],
  "Invoke-WinpeStartup:InvokeMainCommandNoExit": true,
  "Invoke-WinpeStartup:InvokeMainCommandEA": "Continue",
  "Invoke-WinpeStartup:InvokeShutdownCommand": [
    "Restart-Computer -Force"
  ]
}
```

### Display device information only

```json
{
  "Invoke-WinpeStartup:InvokeMainCommand": [
    "Show-OSDCloudDeviceInfo"
  ],
  "Invoke-WinpeStartup:InvokeMainCommandNoExit": true,
  "Invoke-WinpeStartup:InvokeMainCommandEA": "Continue"
}
```

## Authoring workflow

1. Identify the target profile and read its existing JSON before editing.
2. Map the requested behavior to the exact parameter in the table above.
3. Preserve unrelated properties, ordering, and formatting.
4. Add or update only the required property. Keep the JSON flat except for the supported `Environment` object.
5. Parse the edited file with PowerShell 5.1:

```powershell
$profile = Get-Content -LiteralPath '.\OSDCloud\core\winpestartup-profiles\<profile>.json' -Raw | ConvertFrom-Json
$profile | Out-Null
```

6. For command changes, verify the resulting property explicitly:

```powershell
$profile.'Invoke-WinpeStartup:InvokeShutdownCommand'
```

Do not execute profile commands during validation. Parsing verifies syntax without starting deployment, downloading content, or restarting the workstation.
