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
Deploy-OSDCloud [[-WorkflowName] <String>] [-CLI] [-Force] [-ProfileName <String>]
 [-DiskNumber <UInt32>] [-ProgressAction <ActionPreference>] [-OperatingSystem <String>] [-OSEdition <String>]
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
