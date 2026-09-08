---
name: osdcore-operating-system-cloud-object
description: "Use when identifying, mapping, reviewing, or changing $OSDCoreOperatingSystemCloudObject, Set-OSDCoreOperatingSystemCloudObject, Get-OSDCoreOperatingSystems, or Get-OSDCloudCoreOperatingSystems across the OSD and OSDCloud PowerShell modules."
argument-hint: "OS filters or code path, for example: Windows 11 25H2 amd64 Retail en-us"
---

# OSD Core Operating System Cloud Object

Use this skill when working on `$global:OSDCoreOperatingSystemCloudObject` or `Set-OSDCoreOperatingSystemCloudObject` in code shared by the `OSD` and `OSDCloud` PowerShell modules.

The important rule: the selected global object is module-native. Do not assume one property schema works everywhere.

## Object Shape Detection

Identify the selected object by its properties before consuming it:

| Module shape | Strong indicators | Provider |
| --- | --- | --- |
| `OSD` | `Name`, `Version`, `ReleaseID`, `Architecture`, `Language`, `Activation`, `Build`, `Url`, `SHA1`, `SHA256` | `Get-OSDCoreOperatingSystems` |
| `OSDCloud` | `Id`, `OperatingSystem`, `OSName`, `OSVersion`, `OSArchitecture`, `OSActivation`, `OSLanguageCode`, `OSBuild`, `OSBuildVersion`, `FilePath`, `Sha1`, `Sha256` | `Get-OSDCloudCoreOperatingSystems` |

Prefer module context when it is available:

```powershell
$moduleName = $MyInvocation.MyCommand.Module.Name
```

Use property detection when an object is passed into helper code:

```powershell
if ($OperatingSystemCloudObject.PSObject.Properties.Name -contains 'OSArchitecture') {
    $objectShape = 'OSDCloud'
}
elseif ($OperatingSystemCloudObject.PSObject.Properties.Name -contains 'Architecture') {
    $objectShape = 'OSD'
}
else {
    throw 'Unable to identify operating system cloud object shape.'
}
```

## Equivalent Properties

Use these equivalences when filtering, sorting, logging, or copying values into deployment globals.

| Concept | OSD property | OSDCloud property |
| --- | --- | --- |
| Display id/name | `Name` | `Id` |
| Windows family | `Version` | `OSName` |
| Release id | `ReleaseID` | `OSVersion` |
| Architecture | `Architecture` | `OSArchitecture` |
| Language code | `Language` | `OSLanguageCode` |
| Activation | `Activation` | `OSActivation` |
| Full build | `Build` | `OSBuildVersion` |
| Major build | derive from `Build` | `OSBuild` |
| Download URL | `Url` | `FilePath` |
| SHA-1 | `SHA1` | `Sha1` |
| SHA-256 | `SHA256` | `Sha256` |
| File name | `FileName` | `FileName` |

PowerShell property lookup is case-insensitive, but preserve the native property names when creating or serializing objects.

## Selection Workflow

1. Read `OSDCloud/private/core-operatingsystem/Set-OSDCoreOperatingSystemCloudObject.ps1` and the provider functions before editing.
2. Determine whether the call is running in `OSD`, `OSDCloud`, or helper/test code without a module name.
3. Load the matching catalog provider:
   - `OSD`: `Get-OSDCoreOperatingSystems`
   - `OSDCloud`: `Get-OSDCloudCoreOperatingSystems`
4. Normalize input filters before comparing: architecture and language should be lowercase; map `x64` to `amd64` where user input or catalog data can contain either spelling.
5. Filter with equivalent properties, not a single module schema.
6. Sort by the full build equivalent: `Build` for `OSD`, `OSBuildVersion` for `OSDCloud`.
7. Assign the original selected object to `$global:OSDCoreOperatingSystemCloudObject`. Do not reshape it unless the caller explicitly needs a separate compatibility object.
8. Log using the module-native name, build, and file name properties.
9. Validate with at least one `OSD`-shape object and one `OSDCloud`-shape object when practical.

## Safe Access Pattern

For shared consumer code, resolve values through a small local adapter instead of directly reading one schema:

```powershell
$selectedOperatingSystem = $global:OSDCoreOperatingSystemCloudObject

$operatingSystemName = if ($selectedOperatingSystem.OSName) { $selectedOperatingSystem.OSName } else { $selectedOperatingSystem.Version }
$operatingSystemVersion = if ($selectedOperatingSystem.OSVersion) { $selectedOperatingSystem.OSVersion } else { $selectedOperatingSystem.ReleaseID }
$operatingSystemArchitecture = if ($selectedOperatingSystem.OSArchitecture) { $selectedOperatingSystem.OSArchitecture } else { $selectedOperatingSystem.Architecture }
$operatingSystemBuildVersion = if ($selectedOperatingSystem.OSBuildVersion) { $selectedOperatingSystem.OSBuildVersion } else { $selectedOperatingSystem.Build }
$operatingSystemUrl = if ($selectedOperatingSystem.FilePath) { $selectedOperatingSystem.FilePath } else { $selectedOperatingSystem.Url }
```

Keep this adapter close to the consumer unless multiple consumers need it. If multiple consumers repeat the same mapping, add a private helper with comment-based help and `[CmdletBinding()]` following the repo PowerShell instructions.

## Review Checklist

- The function still supports both `OSD` and `OSDCloud` module contexts.
- It does not sort `OSDCloud` records only by `Build`, because that property belongs to the `OSD` shape.
- It does not use `.FilePath` for `OSD` objects or `.Url` for `OSDCloud` objects without a fallback.
- It does not overwrite `$global:OSDCoreOperatingSystemCloudObject` with a cross-module normalized object unless all callers have been reviewed.
- Error messages include the requested release, architecture, activation, language, and OS family/version.
- Any new PowerShell function follows the repo requirements: `[CmdletBinding()]`, comment-based help, `$Error.Clear()`, full cmdlet names, and the standard verbose timestamp pattern.
