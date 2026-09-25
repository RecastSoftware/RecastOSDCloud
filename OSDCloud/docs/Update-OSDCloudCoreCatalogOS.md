---
external help file: OSDCloud-help.xml
Module Name: OSDCloud
schema: 2.0.0
---

# Update-OSDCloudCoreCatalogOS

## SYNOPSIS
Updates the Windows 11 products operating system catalog.

## SYNTAX

```
Update-OSDCloudCoreCatalogOS [[-MinimumItemCount] <Int32>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Queries the Microsoft Update Metadata Service for the current Windows 11 products catalog,
verifies the downloaded CAB size and SHA256 digest, and validates the extracted catalog before
changing persistent content.

The validated catalog is published under `core\operatingsystems` in the OSDCloud module. It is
also copied to `OSDCloud\catalogs\operatingsystems` on each writable drive letter that already
contains an `OSDCloud` directory.

Existing module catalogs remain in place. An existing module catalog name is never overwritten
with different content. Failure to update one external drive does not prevent other eligible
drives from being updated.

## EXAMPLES

### EXAMPLE 1
```
Update-OSDCloudCoreCatalogOS
```

Downloads and validates the current catalog, publishes it to the module, and synchronizes it to
eligible writable drives.

### EXAMPLE 2
```
Update-OSDCloudCoreCatalogOS -WhatIf
```

Downloads and validates the current catalog, then previews publication and drive synchronization
without changing persistent content.

## PARAMETERS

### -MinimumItemCount
Specifies the minimum number of ESD records required before a catalog is accepted. The default is
50. Valid values are 1 through 100000.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases: None

Required: False
Position: 0
Default value: 50
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the command runs. The catalog is still downloaded, extracted, and
validated, but persistent files are not changed.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts for confirmation before changing persistent catalog files.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction,
-InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and
-WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None
This command does not accept pipeline input.

## OUTPUTS

### System.Management.Automation.PSCustomObject
Returns the detected build, module catalog path, publication status, synchronized drive catalog
paths, item count, and SHA256 hash after successful validation.

## NOTES
Requires Windows, Windows PowerShell 5.1 or later, internet access, expand.exe, writable temporary
storage, and write access to the module catalog directory when updating.

## RELATED LINKS
