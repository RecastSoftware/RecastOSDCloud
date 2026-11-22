# Use OSDCloud PreOOBE

**When:** you want a technician to run a guided, interactive stage on the
freshly deployed device, after Windows is applied but before the OOBE screens.

**What it does:** PreOOBE shows a **Recast Software - OSDCloud PreOOBE** window
on the setup desktop (running as SYSTEM) and runs these tasks in a fixed order:

1. OEM driver pack install (Lenovo / Surface)
2. Internet time synchronization
3. Windows 11 software updates (including .NET)
4. Driver updates
5. Custom applications you stage (optional)

Nothing runs until the technician selects **Start**. It never reboots the
device and never continues automatically.

This guide is the quick how-to. The full behavior, security notes and
validation checklist are in [Hand off to Autopilot and OOBE](08-autopilot-oobe.md#osdcloudpreoobe-automated-tasks-recast).

## Prerequisites

- A deployment that uses a `recast` workflow task (`osdcloud` or
  `osdcloud-nofirmware`). Only these enable the `step-update-preoobe` step.
- Windows 11 on AMD64 or ARM64. The runtime uses inbox Windows PowerShell 5.1
  and WPF; it needs no OSDCloud module, PowerShell 7, PsExec or downloads.
- A technician at the device when it reaches OOBE.
- A trusted network for time sync (the HTTP time source is unauthenticated)
  and for Windows Update.

## 1. Deploy with PreOOBE enabled

Deploy normally (see [Deploy Windows 11](04-deploy-windows.md)) with a
`recast` task. During the WinPE phase the `step-update-preoobe` step:

- copies the module to `C:\Windows\Setup\Modules\OSDCloudPreOOBE`
- appends a launch block to `C:\Windows\Setup\Scripts\OOBE.cmd`, after any
  existing commands (repeat runs are idempotent)

To **turn PreOOBE off** (for example for end-user deployments), set
`"skip": true` on `step-update-preoobe` in the task **before** deploying.
Editing the task afterward does not remove an already staged hook.

## 2. (Optional) Stage custom applications

PreOOBE discovers application folders, one level deep, in these roots:

| Order | Root |
|---|---|
| 1 | `%SystemRoot%\Setup\PreOOBE` (local disk) |
| 2 | `<drive>:\OSDCloud\core\PreOOBE` on A: through Z: (for example a USB drive) |

A folder becomes a task if it contains either:

- **`Invoke-AppDeployToolkit.exe`** (PSADT). Runs with
  `-DeploymentType Install -DeployMode Silent`, checked by default.
- **`OSDCloudPreOOBE.json`** beside any installer. This takes precedence over
  PSADT detection in the same folder.

Example layout on a USB drive:

```text
G:\OSDCloud\core\PreOOBE\Workspace Agent\
    OSDCloudPreOOBE.json
    AgentBootstrapper.exe
    AgentRegistration.cer
```

```json
{
    "Version": 1,
    "Name": "Workspace Agent",
    "Executable": "AgentBootstrapper.exe",
    "Arguments": "--certificate AgentRegistration.cer --startDeployment --wait",
    "DefaultSelected": false
}
```

Start from the samples in
[files/](../OSDCloud/core/modules/OSDCloudPreOOBE/files/): copy one next to
your installer and rename it to `OSDCloudPreOOBE.json`.

| Field | Required | Notes |
|---|---|---|
| `Version` | Yes | Must be `1` |
| `Executable` | Yes | Relative `.exe` path inside the folder |
| `Name` | No | Display name; defaults to the folder name |
| `Arguments` | No | Literal command line; no expressions are evaluated |
| `DefaultSelected` | No | `false` starts unchecked |
| `CopyToLocal` | No | `true` copies the folder to `C:\Windows\Temp\OSDCloudOOBE\<folder>` and runs from there (use for ISO or read-only media) |
| `Conditions` | No | Filter by `ComputerManufacturer`, `ComputerModel` (wildcards, case-insensitive) and `OSArchitecture` (`amd64`/`arm64`). Different fields are AND, values in an array are OR |

Rules to remember:

- Exit code 0 is success, 3010 records a reboot requirement, anything else
  fails the task. Other tasks continue.
- Invalid manifests are rejected with a warning and do **not** fall back to
  PSADT.
- Packages run as SYSTEM. Deploy only trusted packages, configured not to
  reboot, and keep credentials out of manifests.

## 3. Check it before deploying (Preview)

Preview is inert: no network, installs, shells or clock changes. From a
Windows PowerShell 5.1 console in the repository root:

```powershell
powershell.exe -NoLogo -NoProfile -STA -Command "Import-Module .\OSDCloud\core\modules\OSDCloudPreOOBE\OSDCloudPreOOBE.psd1 -ErrorAction Stop; exit (OSDCloudPreOOBE -Preview)"
```

Use it to confirm your application folders are discovered, labelled
(drive-hosted ones show a suffix such as `[G:]`) and checked as intended.
Preview does not prove that the installer works or that Windows invokes
`OOBE.cmd`.

## 4. Operate it at the device

When the device reaches OOBE, the window opens at the top-left of the screen.

1. Review the task list on the left. Uncheck anything to skip; checkboxes lock
   once a task starts.
2. Select **Start**. Each task shows a 10-second countdown; **Start** begins
   it immediately.
3. Watch live output in the window. While an update runs the button reads
   **Skip Step**.
4. If **Updating Windows 11** fails, the sequence pauses. Use **Shell** to
   check date, time and time zone, then **Retry** or **Continue**.
5. When all tasks finish, select **Continue to OOBE**.

Closing the window (or Esc / Alt+F4) cancels the active update, waits for an
running installer to finish, skips the remaining tasks and lets setup continue.

Tools in the title bar:

- **Shell**: CMD Prompt or Windows PowerShell as SYSTEM.
- **Tools**: open `oobe.cmd`, `setupcomplete.cmd`, `Autopilot.csv` (when
  present) in Notepad, and **Connect to Wi-Fi**.

### No network or wrong clock

If time sync or the connectivity check fails and a physical Wi-Fi adapter is
present, a **Connect to Wi-Fi** dialog opens (also under **Tools**). It
supports saved profiles, open networks and WPA2/WPA3-Personal. New connections
use a temporary in-memory profile: nothing is saved to disk, and it may not
survive a reboot. After you connect, time sync (or the update check) retries.
If recovery fails, update tasks are **Skipped**; local driver install and
applications still run.

## 5. Logs and results

| File (on the device) | Contents |
|---|---|
| `%SystemRoot%\Temp\osdcloud-logs\OSDCloudPreOOBE.log` | Full diagnostic log |
| `%SystemRoot%\Temp\osdcloud-logs\OSDCloudPreOOBE-results.json` | Terminal outcome of each task |
| `PreOOBE-*.stdout.log` / `.stderr.log` | Installer output, including applications |

If the window never appears, also collect the staged module manifest,
`OOBE.cmd`, `SetupComplete.cmd`, and
`C:\Windows\Panther\setupact.log` (plus `Panther\UnattendGC\setupact.log`).
Note that an early `exit` or `goto :eof` in the original `OOBE.cmd` can skip
the appended launch; staging warns when it sees one.

See [Troubleshoot a failed deployment](09-troubleshooting.md) for general
diagnosis.

## Before you rely on it

Validate on a **disposable** AMD64 and ARM64 device: the window must be
visible and interactive, setup must wait while it is open, and setup must
continue after closing it. Mocked tests and Preview do not establish that.
