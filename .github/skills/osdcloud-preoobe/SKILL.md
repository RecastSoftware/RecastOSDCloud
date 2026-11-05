---
name: osdcloud-preoobe
description: "Use when creating, changing, testing, or troubleshooting OSDCloud PreOOBE: its WinPE staging step, first-boot runtime, technician window, driver handoff, Windows Update tasks, PreOOBE custom applications and Invoke-AppDeployToolkit.exe discovery, time sync, connectivity checks, or OOBE diagnostics."
---

# OSDCloud PreOOBE

Use this skill for the OSDCloud PreOOBE feature, not general Windows OOBE,
Autopilot enrollment, or legacy WinPE startup profiles. Read the relevant
runtime and workflow code before changing behavior; use
[the PreOOBE deployment guide](../../../docs/08-autopilot-oobe.md) for the
current operator-facing behavior and real-device validation requirements.

## Architecture and invariants

- The standalone module lives under
  [OSDCloudPreOOBE](../../../OSDCloud/core/modules/OSDCloudPreOOBE).
  Its public entry point is
  [Invoke-OSDCloudPreOOBE](../../../OSDCloud/core/modules/OSDCloudPreOOBE/public/Invoke-OSDCloudPreOOBE.ps1),
  exported with the `OSDCloudPreOOBE` alias. Import alone is inert; the entry point
  returns a numeric status and never exits the caller. Runtime helpers are private in
  [OSDCloudPreOOBE.ps1](../../../OSDCloud/core/modules/OSDCloudPreOOBE/private/OSDCloudPreOOBE.ps1).
  Its driver installer and WPF window are maintained in
  [Invoke-OSDCloudPreOOBEDriverPack.ps1](../../../OSDCloud/core/modules/OSDCloudPreOOBE/private/Invoke-OSDCloudPreOOBEDriverPack.ps1)
  and
  [Show-OSDCloudPreOOBEWindow.ps1](../../../OSDCloud/core/modules/OSDCloudPreOOBE/private/Show-OSDCloudPreOOBEWindow.ps1).
- The WinPE-only
  [step-update-preoobe](../../../OSDCloud/private/steps/7-update/step-update-preoobe.ps1)
  copies the entire module folder to `C:\Windows\Setup\Modules\OSDCloudPreOOBE`,
  stamps the parent OSDCloud version into the destination manifest, and appends
  an explicit manifest import and synchronous `OSDCloudPreOOBE` launch to
  `C:\Windows\Setup\Scripts\OOBE.cmd`. The SYSTEM desktop child also imports the
  same module path. It does not install an interactive
  menu in `SetupComplete.cmd`; that file is only cleaned of a legacy managed
  invocation. Change module source and staging logic, not a staged copy.
  The OEM handoff manifest remains in `Setup\Scripts\OSDCloudPreOOBE.DriverPack.json`.
- The runtime requires inbox Windows PowerShell 5.1, WPF, and `-STA`; it
  supports AMD64 and ARM64 and runs as SYSTEM during setup. It is standalone:
  do not introduce a dependency on the OSDCloud module, PowerShell 7,
  downloaded tools, or an interactive user logon.
- The feature is enabled only in the intended `recast` workflow
  tasks. Driver installation is deferred only when the driver step opts in
  with `PreOOBE` and the PreOOBE staging step is enabled. Preserve the
  original driver-install path when either condition is false.
- The technician must select **Start** before tasks run. After completion,
  **Continue to OOBE** proceeds normally; closing the window safely skips
  remaining tasks and completes setup. Preserve the fixed sequence: OEM driver
  pack, internet time synchronization, Windows software updates, then driver
  updates, then discovered custom applications. Do not add an automatic reboot
  or automatic continuation.
- Application discovery searches immediate folders under
  `%SystemRoot%\Setup\PreOOBE` first, then `A:\OSDCloud\core\PreOOBE` through
  `Z:\OSDCloud\core\PreOOBE`. Only `Invoke-AppDeployToolkit.exe` packages become
  checked tasks; drive-hosted labels append `[G:]`-style drive identifiers.
  Run selected packages sequentially with Install/Silent arguments and their
  folder as the working directory. Do not force-cancel active installers.
- Keep preview inert: it must not write the system clock, access the network,
  install drivers or updates, or launch SYSTEM tools.

## Implementation workflow

1. Identify whether the change belongs to runtime behavior, WPF presentation,
   WinPE staging, workflow opt-in, or deferred driver-pack handoff. Inspect the
   affected source and its adjacent tests before editing.
2. Keep scheduling and outcomes explicit. Tasks have terminal outcomes such
   as `Succeeded`, `Failed`, `Skipped`, and `Cancelled`; connectivity skips
   update tasks, not local OEM driver installation. Preserve safe cancellation
   and allow independent tasks to continue after failures unless the existing
   scheduler intentionally pauses for a Windows Update failure.
3. Keep the staging contract intact: validate the source and applied Windows
   image before writing, validate and copy the complete standalone module, preserve
   original `OOBE.cmd` content, and keep repeated staging idempotent. Do not
   silently rewrite original batch control flow or create a success-shaped
   invocation after a staging failure.
4. Preserve security and recovery behavior. Do not disable TLS certificate
   validation, log credentials or profile keys, weaken package validation, or
   bypass the explicit driver handoff. The wireless recovery wizard is planned,
   not shipped; do not imply it exists or implement it without an explicit
   feature request.
5. Update the deployment guide when user-visible behavior, prerequisites,
   workflow enablement, diagnostics, or validation requirements change.

## Tests and validation

Run the smallest relevant Pester tests. The main coverage is under
`OSDCloud/core/modules/OSDCloudPreOOBE/`. Tests use module scope for private helpers:

- `OSDCloudPreOOBE.Tests.ps1` for the runtime entry point
- `OSDCloudPreOOBE.Engine.Tests.ps1` for task ordering and UI automation
- `OSDCloudPreOOBE.Time.Tests.ps1` and
  `OSDCloudPreOOBE.Connectivity.Tests.ps1` for time and network checks
- `OSDCloudPreOOBE.WindowsUpdate.Tests.ps1` for update actions
- `OSDCloudPreOOBE.Application.Tests.ps1` for application discovery and installation
- `Invoke-OSDCloudPreOOBEDriverPack.Tests.ps1` for OEM package handling
- `OSDCloud/private/steps/7-update/step-update-preoobe.Tests.ps1` for module
  copying, version stamping and setup-script staging
- `OSDCloud/private/steps/5-drivers/step-Save-WindowsDriver-DriverPack.PreOOBE.Tests.ps1`
  for opt-in driver handoff

For example, run a focused selection from the repository root:

```powershell
Invoke-Pester -Path .\OSDCloud\core\modules\OSDCloudPreOOBE\OSDCloudPreOOBE.Engine.Tests.ps1,
    .\OSDCloud\core\modules\OSDCloudPreOOBE\OSDCloudPreOOBE.Connectivity.Tests.ps1
```

The local preview command is documented in the
[deployment guide](../../../docs/08-autopilot-oobe.md). Preview and mocked
tests do not establish that Windows invokes `OOBE.cmd`, that a SYSTEM window is
visible on the setup desktop, or that real Windows Update and OEM installers
work. Changes affecting first-boot integration require disposable Windows
installations; validate AMD64 and ARM64 when applicable and follow the guide's
deployment scenarios. Never use a production device for destructive
installation validation.

## Troubleshooting

Start with `%SystemRoot%\Temp\osdcloud-logs\OSDCloudPreOOBE.log` and
`OSDCloudPreOOBE-results.json`. For staging or hook issues, also inspect the
staged module manifest, `OOBE.cmd`, `SetupComplete.cmd`, installer stdout/stderr and MSI logs,
and Windows Setup logs identified in the guide. A desktop preview alone does
not prove that setup invokes the hook or displays the window.
