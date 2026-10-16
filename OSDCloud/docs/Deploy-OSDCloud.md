---
external help file: OSDCloud-help.xml
Module Name: OSDCloud
online version: https://github.com/OSDeploy/OSDCloud/blob/main/PRIVACY.md
schema: 2.0.0
---

# Deploy-OSDCloud

## SYNOPSIS
Starts an OSDCloud operating system deployment.

## SYNTAX

```
Deploy-OSDCloud [[-WorkflowName] <String>] [-CLI] [-Incognito] [-Force] [-ProfileName <String>]
 [-DiskNumber <UInt32>] [-DiskLabelOS <String>] [-DiskLabelRecovery <String>]
 [-DiskSizeSystem <UInt64>] [-DiskSizeOS <UInt64>] [-DiskSizeRecovery <UInt64>]
 [-ProgressAction <ActionPreference>] [-OperatingSystem <String>] [-OSEdition <String>]
 [-OSActivation <String>] [-OSLanguageCode <String>] [-Task <String>] [<CommonParameters>]
```

## DESCRIPTION
Initializes and runs an OSDCloud deployment workflow.
By default, launches the
graphical UI (UX) so the operator can configure deployment settings before
starting.
Use -CLI to skip the UI and immediately begin the workflow in the
current console session.

In addition to the static parameters documented here, workflow-specific runtime
parameters are added dynamically from the selected workflow definition.

`DiskLabelOS`, `DiskLabelRecovery`, `DiskSizeSystem`, `DiskSizeOS`, and
`DiskSizeRecovery` require `Initialize-OSDCoreLicense` to report
`IsRegistered = true`. Otherwise, supplying any of these parameters produces
one warning and deployment continues with default labels and sizes. No warning
is emitted when none are supplied. `DiskNumber` does not require registration.
Parameter-binding validation still applies before the license check.

OSDCloud collects anonymous analytic data about the deployment environment and
system configuration to help improve the product.
No personally identifiable
information (PII) is collected.
By using OSDCloud you consent to this collection
as described in the privacy policy:
https://github.com/OSDeploy/OSDCloud/blob/main/PRIVACY.md

## DEPLOYMENT RESULTS

Every invocation creates a fresh `$global:OSDCloudResults` object. It contains a
reduced summary, not a copy of the full device inventory or deployment settings.
Read it after deployment, or import the saved snapshot:

```powershell
$global:OSDCloudResults
$results = Import-Clixml -LiteralPath "$env:TEMP\OSDCloudResults.clixml"
```

| Properties | Meaning |
| --- | --- |
| `SchemaVersion`, `DeploymentId` | Schema version (initially 1) and a new GUID for this invocation |
| `DistinctId` | Pseudonymous analytics identifier, using the existing hashed-device identity semantics; a random GUID is used when no device identity is available |
| `Status`, `IsComplete` | Lifecycle state and whether workflow execution reached the pre-PostAction boundary |
| `StartTimeUtc`, `EndTimeUtc`, `totalDurationRAW` | UTC workflow timestamps and elapsed time rounded to whole seconds |
| `totalDuration` | `totalDurationRAW` minus `stepClearDisk`, treating an absent wait as zero and clamping the result at zero |
| `sizeOS`, `sizeDriverPack` | Actual acquired content sizes in whole MB |
| `totalSizeMB` | `sizeOS` plus `sizeDriverPack` in whole MB |
| `totalMBps` | `totalSizeMB` divided by `totalDuration`, rounded to whole MB/s; null when duration is unavailable or zero |
| `rateOSDownload`, `rateOSCache`, `rateOSCopy`, `rateOSExpand` | `sizeOS` divided by the matching `stepOS*` seconds, rounded to whole MB/s |
| `rateDriverPackDownload`, `rateDriverPackCache`, `rateDriverPackCopy`, `rateDriverPackExpand` | `sizeDriverPack` divided by the matching `stepDriverPack*` seconds, rounded to whole MB/s |
| `Network` | `Wired` or `Wireless` from connected default-gateway adapters; null if unavailable or ambiguous |
| `ContentSource` | Combined OS/driver-pack origin: `Cloud` for newly downloaded content, `Cache` for pre-existing content, or `Mixed` when both origins were used |
| `stepOSCopy`, `stepOSDownload` | Time spent reusing/copying cached OS content and downloading OS content, measured separately |
| `stepDriverPackCopy`, `stepDriverPackDownload` | Time spent copying cached driver content and downloading driver content, measured separately |
| `stepOSCache`, `stepDriverPackCache` | Time downloading new content to USB cache, excluded from the corresponding Download phase |
| `stepOSExpand`, `stepDriverPackExpand` | Time spent applying the Windows image and extracting driver archives, excluding driver injection and setup script creation |
| `stepClearDisk` | Time waiting for the disk-cleaning confirmation response, excluding disk discovery and disk cleaning |
| `totalSizeDownloadMB` | Successfully downloaded OS and driver-pack bytes to local storage, excluding USB-cache downloads, rounded once to whole MB |
| `totalSizeCacheMB` | Successfully downloaded OS and driver-pack bytes to USB cache, rounded once to whole MB |
| `totalSizeCopyMB` | Successfully copied or reused cached OS and driver-pack bytes, rounded once to whole MB |
| `ModuleVersion`, `WorkflowName`, `WorkflowTaskName`, `LaunchMethod`, `DeploymentPhase` | Module, selected workflow/task, CLI or GUI, and WinPE or Windows |
| `OSDManufacturer`, `OSDModel`, `OSDProduct`, `ProcessorArchitecture`, `TotalPhysicalMemoryGB` | Reduced device summary |
| `OSName`, `OSVersion`, `OSBuild`, `OSBuildVersion`, `OSEditionId`, `OSActivation`, `OSLanguageCode` | Selected target OS |
| `DriverPackName` | Selected driver pack |

`Status` is `NotStarted` during initialization/selection, `Running` during workflow
execution, `Completed` when the workflow returns, `Failed` on a terminating error,
or `Cancelled` when the operator dismisses the GUI without starting deployment.
`IsComplete` starts as false and becomes true before PostAction handling. It does
**not** prove that every deployment step succeeded: existing workflows can continue
after warnings or nonterminating step errors.
After completion, finalized `OSDCloudResults` properties except `step*` and `rate*`
are displayed as a list in the console before any PostAction countdown or action,
for both GUI and CLI. Exports and analytics retain those properties.

A stopwatch measures workflow execution, including preflight and waits within the
workflow. Initialization, GUI selection, results snapshot writes, terminal analytics,
and the command's PostAction countdown/action are excluded. Timestamps in the initial
running snapshot precede its write; final `StartTimeUtc` is refreshed at workflow
invocation. Copy and download operations have separate timers; source checks, cache
searches, hash verification, and driver injection are not included in those phases.
The Cache and Copy timers are populated when a USB-cache download is followed by a local copy.
If the download helper reuses an existing destination file, that operation counts
as cache reuse under the copy timer rather than as a network download.
Selected OS images reused directly from cache normally have zero rounded copy time.
For cached ModelDrivers folders, driver size is the sum of staged file lengths and
`stepDriverPackCopy` measures the copy. Driver expansion covers CAB, ZIP, Dell,
and HP extraction during deployment. ModelDrivers requires no extraction; Lenovo
and Surface installations deferred to SetupComplete are not timed as expansion.
`stepClearDisk` wraps only the existing ShouldProcess confirmation (including a
declined response). Force, Confirm:false, and WhatIf do not introduce a prompt.
`totalDuration` subtracts the rounded confirmation wait from the rounded total.
Sizes use PowerShell's `1MB` (1,048,576 bytes), based on actual files rather than
catalog estimates. Values round to the nearest whole number, with halves rounded up.
Rates use the reported whole-MB sizes and whole-second durations, rounded to whole
MB/s with halves rounded up. A missing size or missing/zero duration produces null rather than division by zero.
Expansion rates use source archive size, not expanded size. Network detection runs
when results metadata is refreshed; it does not track connection changes per transfer.
Download, Cache, and Copy totals each sum original bytes before rounding. Existing-file reuse counts
only toward the copy total, not a new cache download. Content downloaded to USB and then copied locally counts
toward Cache and Copy, not Download; each content item counts once per category. These are obtained
content sizes, not wire-traffic measurements (retries and protocol overhead are excluded).
Unexecuted phases remain null; attempted phases accumulate time even when an
operation fails or a download falls back to another destination. Sizes remain null
until content is obtained; totals include only successfully obtained content and
remain null if neither component was obtained.
Failed started runs retain elapsed time; unstarted/cancelled runs have null timing.

`timeDownload`, `timeCache`, `timeCopy`, and `timeExpand` sum the matching
whole-second OS and driver-pack `step*` values. `timeCloud` is the sum of
`timeDownload` and `timeCache`. `timeOther` is `totalDurationRAW` minus all
reported `step*` values and is never below zero. These aggregate `time*` fields
remain in exported and analytics results but are omitted from the final console
summary. `OSFileName` and `DriverPackFileName` identify the selected content files.

`ContentSource` describes the origin of successfully obtained OS and driver-pack
content, not its staging destination. A new download saved to USB and then copied
locally is `Cloud`; only reuse of pre-existing content is `Cache`. One newly
downloaded component and one pre-existing component produces `Mixed`. Skipped or
unavailable components are ignored. The value is null if neither component was
obtained or an obtained component has no known source. Classification uses transfer
records rather than rounded sizes or durations.

`OSDCloudResults.clixml` is overwritten in current `$env:TEMP` at workflow start and
termination. At termination it is also written under the deployed Windows volume's
`Windows\Temp`, resolved from the current workflow's image application root. This is
normally `C:\Windows\Temp`, but another application root is respected. If no deployed
Windows directory is available, a warning explains why that copy was skipped.
Cancellation and initialization failure write only the current-TEMP snapshot.
Export failures warn independently and do not block deployment or PostAction.

Started deployments also send a reduced `OSDCloudResultsBeta` terminal event to PostHog,
in addition to the unchanged detailed start event. Network failures warn and
deployment continues. Raw device identifiers, license identifiers, paths, URLs, and
exception messages are excluded from the new event. See [PRIVACY.md](../../PRIVACY.md).

Results apply to `Deploy-OSDCloud` with or without `-CLI`, not the standalone
`Deploy-OSDCloudCLI`/`Deploy-OSDCloudGUI` commands or direct workflow invocation.
Abrupt power loss, forced host termination, or custom workflow steps that exit or
restart before returning cannot guarantee a terminal snapshot/event; the saved
snapshot may remain `Running`.

## EXAMPLES

### EXAMPLE 1
```
Deploy-OSDCloud
```

Launches the OSDCloud graphical UX for the default workflow.
The deployment
starts only after the operator clicks Start in the UI.

### EXAMPLE 2
```
Deploy-OSDCloud -CLI
```

Runs the default OSDCloud workflow immediately without the graphical UX.

### EXAMPLE 3
```
Deploy-OSDCloud -WorkflowName 'latest'
```

Launches the graphical UX for the 'latest' workflow.

### EXAMPLE 4
```
Deploy-OSDCloud -CLI -OperatingSystem 'Windows 11 24H2' -OSEdition 'Enterprise'
```

Runs in CLI mode using dynamic runtime overrides from the selected workflow.

### EXAMPLE 5
```
Deploy-OSDCloud -ProfileName 'Lab'
```

Launches the OSDCloud graphical UX using the 'Lab' profile Env path.

### EXAMPLE 6
```
Deploy-OSDCloud -CLI -DiskNumber 1
```

Runs the default OSDCloud workflow immediately and deploys to local disk 1.

### EXAMPLE 7
```powershell
Deploy-OSDCloud -CLI -DiskNumber 0 -DiskLabelOS 'Windows' -DiskLabelRecovery 'WinRE' `
    -DiskSizeSystem 1GB -DiskSizeOS 100GB -DiskSizeRecovery 2GB
```

On registered devices, creates a fixed 100GB Windows partition, a 1GB system partition, the standard
16MB MSR, and (when enabled by the workflow) a 2GB recovery partition.
Additional disk space remains unallocated. The same overrides work without
`-CLI`; GUI controls are unchanged.
Unregistered devices display one warning and use the default layout.

### EXAMPLE 8
```powershell
Deploy-OSDCloud -CLI -Incognito
```

Runs with `OSDCoreLicense.IsRegistered` forced to false for unlicensed testing.
The saved license is unchanged. The same switch works for GUI launches.

## PARAMETERS

### -WorkflowName
The name of the OSDCloud workflow to run.
Defaults to 'default'.
Available workflows are located in the module's workflow folder.

```yaml
Type: String
Parameter Sets: (All)
Aliases: Name

Required: False
Position: 1
Default value: Default
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: False
```

### -CLI
Skips the graphical UX and runs the deployment workflow immediately in the
current console session.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Incognito
Forces the initialized `OSDCoreLicense.IsRegistered` state to false for
unlicensed testing, even when a registered license is present. Registration-only
features, including disk customization, follow their unregistered behavior.
Does not modify the saved license or disable analytics. The in-memory state
remains unregistered until license initialization runs again; the next
`Deploy-OSDCloud` launch without this switch reloads normal license state.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Force
Suppresses supported confirmation prompts for destructive workflow steps.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProfileName
The full OS profile name used to resolve the Env file path.
Defaults to 'default'.
Ignored in WinPE.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Default
Accept pipeline input: False
Accept wildcard characters: False
```

### -DiskNumber
Specifies the local disk number to use for deployment.
The value must match a local disk detected by OSDCloud.
USB, virtual, offline, and otherwise unsupported disks are not valid deployment targets.

```yaml
Type: UInt32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -DiskLabelOS
Volume label for the Windows NTFS partition. Defaults to `OS`.
Customization requires registration; otherwise the default is used.
Labels must be nonblank and at most 32 characters. Control characters and
`\ / : * ? " < > | + , ; = [ ]` are not accepted.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: OS
Accept pipeline input: False
Accept wildcard characters: False
```

### -DiskLabelRecovery
Volume label for the recovery NTFS partition. Defaults to `Recovery`.
Customization requires registration; otherwise the default is used.
Uses the same label validation as `DiskLabelOS`. Does not enable recovery
when disabled by VM detection or workflow settings.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Recovery
Accept pipeline input: False
Accept wildcard characters: False
```

### -DiskSizeSystem
System partition size in bytes, from `100MB` through `3000MB` inclusive.
Defaults to `500MB`. The standard deployment remains GPT with a 16MB MSR.
Customization requires registration; otherwise the default is used.

```yaml
Type: UInt64
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 500MB
Accept pipeline input: False
Accept wildcard characters: False
```

### -DiskSizeOS
Fixed Windows partition size in bytes, at least `32GB`. When omitted, Windows
uses the remaining space after reserving recovery. Explicit zero is invalid.
When supplied, recovery uses `DiskSizeRecovery` and excess space remains
unallocated; no additional data partition is created.
Customization requires registration; otherwise automatic sizing is used.

```yaml
Type: UInt64
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None (automatic sizing)
Accept pipeline input: False
Accept wildcard characters: False
```

### -DiskSizeRecovery
Recovery partition size in bytes, from `350MB` through `80000MB` inclusive.
Defaults to `2000MB`. Does not change recovery creation policy: VM detection
or skip disables recovery, and force takes precedence over both.
Customization requires registration; otherwise the default is used.

```yaml
Type: UInt64
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 2000MB
Accept pipeline input: False
Accept wildcard characters: False
```

Size parameters accept PowerShell binary-unit expressions such as `500MB`,
`2GB`, or `100GB` (1MB = 1,048,576 bytes). Plain numbers represent bytes.
Invalid labels, out-of-range sizes, and layouts that exceed target disk
capacity fail before disk clearing. Unregistered deployments discard valid
customization overrides before capacity checks and validate the default layout
instead; malformed or out-of-range input still fails parameter binding.
Capacity checks include system, MSR,
enabled recovery, and alignment/metadata allowance.

### -OperatingSystem
{{ Fill OperatingSystem Description }}

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -OSActivation
{{ Fill OSActivation Description }}

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -OSEdition
{{ Fill OSEdition Description }}

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -OSLanguageCode
{{ Fill OSLanguageCode Description }}

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Task
{{ Fill Task Description }}

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Void
## NOTES
This command writes deployment status to the host and starts workflow tasks.
In GUI mode, workflow execution starts only after the operator clicks Start.
Runtime parameters are provided by Get-OSDCloudWorkflowRuntimeParameter.

## RELATED LINKS

[https://github.com/OSDeploy/OSDCloud/blob/main/PRIVACY.md](https://github.com/OSDeploy/OSDCloud/blob/main/PRIVACY.md)
