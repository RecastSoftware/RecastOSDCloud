# OSDCloud SetupComplete package examples

These are templates, not automatically executed deployment tasks. Choose one
numbered JSON example, copy it into a package folder, and rename it to
`OSDCloudSetupComplete.json`. Copy `Example-SetupComplete.ps1` and
`Example-Content.json` beside it:

```text
G:\OSDCloud\core\SetupComplete\010-Example\
    OSDCloudSetupComplete.json
    Example-SetupComplete.ps1
    Example-Content.json
```

Alternatively stage that package folder under
`%SystemRoot%\Setup\SetupComplete` on the deployed Windows installation.
The deployment staging step copies the runtime module, not external packages.
Keep drive-hosted content attached and accessible during SetupComplete.

| Example | Purpose |
|---|---|
| `Example-01-All-Devices.json` | Enabled on all devices |
| `Example-02-Dell-Devices.json` | Dell manufacturer wildcard |
| `Example-03-Selected-Models.json` | OR across several model patterns |
| `Example-04-Arm64-Copy-Local.json` | ARM64, quoted arguments, and local copying |
| `Example-05-Dell-Latitude-Amd64.json` | AND across manufacturer, model, and architecture |

Replace `Script` with your own direct-child `.ps1` filename. Include any supporting
content in the same folder and resolve it using `$PSScriptRoot`, as the harmless
companion script does. All configured scripts run automatically: `Enabled`
defaults to `true`; set it to `false` to disable a package. There is no checkbox,
confirmation, or GUI.

`Arguments` is a literal Windows command-line string passed to PowerShell `-File`,
not evaluated as a PowerShell expression. Quote values containing spaces:
`"-Message \"Setup completed\""`. Do not put credentials in configuration or output.

`Conditions` supports `ComputerManufacturer`, `ComputerModel`, and `OSArchitecture`
with the same AND/OR rules as PreOOBE. Architecture is `amd64` or `arm64`.
Omitting conditions runs on all supported devices.

`CopyToLocal: true` copies the whole package to
`%SystemRoot%\Temp\OSDCloudSetupComplete\<FolderName>` before execution. Repeated
copies use `-2`, `-3`, etc. Script root and working directory become that copied
folder. Copies are retained, and copied read-only attributes are cleared.

Scripts run sequentially as SYSTEM in noninteractive Windows PowerShell 5.1.
Make scripts silent and synchronous, use `$ErrorActionPreference = 'Stop'`,
check native tool exit codes, and `throw` or `exit` nonzero on failure.
PowerShell `-File` does not turn nonterminating errors into a failed exit code.
Exit `3010` means success with reboot required; this module never reboots.
Never invoke rebooting installers or depend on an interactive desktop.

Every invocation runs eligible packages again; scripts should be idempotent.
Diagnostics append to `%SystemRoot%\Temp\osdcloud-logs\OSDCloudSetupComplete.log`.
Each child has unique stdout/stderr logs there. Only deploy trusted content;
configuration is not a signature check or sandbox.
