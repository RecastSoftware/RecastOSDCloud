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
