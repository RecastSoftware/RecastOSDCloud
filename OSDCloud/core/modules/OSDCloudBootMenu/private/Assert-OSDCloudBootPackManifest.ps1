#Requires -Version 5.1

function Assert-OSDCloudBootPackManifest {
    <#
    .SYNOPSIS
        Validates an OSDCloud BootPack manifest

    .DESCRIPTION
        Validates a bootpack.json document (schemaVersion 1) without expanding or applying
        the Pack. Supported top-level properties are schemaVersion, info, type, architecture,
        and items. Invalid content produces a terminating error that identifies the source.

        Build Pack items use kind File or Folder, a cab-relative source below payload/NNNN/,
        and a destination that starts with {MountPath}\. Destinations cannot be rooted after
        the token, use drive or UNC syntax, or contain . or .. segments. The optional execute
        flag is allowed only on File items with a .ps1 source.

        Import Pack items use kind Environment, Registry, Certificate, or Script. Sources must
        use the fixed runtime layout: *.env at the root, winpe-reg/*.reg, winpe-root-cer/*.cer,
        and scripts/*.cmd or scripts/*.ps1. Script items require action Execute or Copy; other
        kinds cannot specify an action or destination.

    .PARAMETER Path
        Specifies a bootpack.json file to validate.

    .PARAMETER InputObject
        Specifies a manifest object, such as the result of ConvertFrom-Json, to validate.

    .PARAMETER SourceName
        Specifies the source name used in error messages for InputObject validation.

    .EXAMPLE
        PS> Assert-OSDCloudBootPackManifest -Path 'C:\ProgramData\OSDeployCore\boot-assets\boot-packs\CMTrace\bootpack.json'

        Validates the CMTrace Pack manifest.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-10-29
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [System.String]
        $Path,

        [Parameter(Mandatory, ParameterSetName = 'InputObject')]
        [System.Object]
        $InputObject,

        [Parameter(ParameterSetName = 'InputObject')]
        [System.String]
        $SourceName = 'manifest'
    )
    if ((Get-Variable -Name OSDTraceLogSession -Scope Script -ValueOnly -ErrorAction Ignore) -and (Get-Command -Name Write-OSDTraceLog -ErrorAction SilentlyContinue)) {
        Write-OSDTraceLog -Component $script:OSDTraceLogSession.CommandName -Message 'Calling private function: Assert-OSDCloudBootPackManifest' -Parameters $PSBoundParameters
    }

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $SourceName = $Path
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "OSDCloud BootPack manifest was not found: $Path"
        }
        try {
            $InputObject = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Invalid OSDCloud BootPack manifest JSON '$Path': $($_.Exception.Message)"
        }
    }

    $Fail = { param ($Message) throw "Invalid OSDCloud BootPack manifest '$SourceName': $Message" }
    $AssertKeys = {
        param ($Object, $Name, $Allowed)
        foreach ($Property in $Object.PSObject.Properties) {
            if ($Property.Name -notin $Allowed) { & $Fail "Unsupported property '$Name$($Property.Name)'." }
        }
    }
    $IsObject = { param ($Value) $Value -is [System.Management.Automation.PSCustomObject] }

    if (-not (& $IsObject $InputObject)) { & $Fail 'The manifest must contain one JSON object.' }
    & $AssertKeys $InputObject '' @('schemaVersion', 'info', 'type', 'architecture', 'items')

    $SchemaVersion = $InputObject.PSObject.Properties['schemaVersion']
    if (-not $SchemaVersion -or ($SchemaVersion.Value -isnot [System.Int64] -and $SchemaVersion.Value -isnot [System.Int32]) -or $SchemaVersion.Value -ne 1) {
        & $Fail "'schemaVersion' is required and must be 1."
    }

    $Info = $InputObject.PSObject.Properties['info']
    if (-not $Info -or -not (& $IsObject $Info.Value)) { & $Fail "'info' is required and must be a JSON object." }
    $Info = $Info.Value
    & $AssertKeys $Info 'info.' @('id', 'name', 'author', 'description', 'created', 'modified')
    $ParsedId = [guid]::Empty
    if ($Info.id -isnot [System.String] -or -not [guid]::TryParse($Info.id, [ref]$ParsedId) -or $ParsedId -eq [guid]::Empty) {
        & $Fail "'info.id' must be a GUID string."
    }
    if ($Info.name -isnot [System.String] -or -not (Test-OSDCloudBootPackName -Name $Info.name)) {
        & $Fail "'info.name' must be a non-empty folder-safe name of 64 characters or fewer."
    }
    foreach ($Key in 'author', 'description', 'created', 'modified') {
        $Property = $Info.PSObject.Properties[$Key]
        # PowerShell 7 ConvertFrom-Json converts ISO 8601 strings to DateTime.
        if ($Property -and $null -ne $Property.Value -and $Property.Value -isnot [System.String] -and $Property.Value -isnot [System.DateTime]) { & $Fail "'info.$Key' must be a string." }
    }

    if ($InputObject.type -notin @('Build', 'Import')) { & $Fail "'type' must be 'Build' or 'Import'." }
    $Architecture = $InputObject.PSObject.Properties['architecture']
    if ($Architecture -and $Architecture.Value -notin @('any', 'amd64', 'arm64')) {
        & $Fail "'architecture' must be 'any', 'amd64', or 'arm64'."
    }

    $Items = $InputObject.PSObject.Properties['items']
    if (-not $Items -or $Items.Value -isnot [System.Array] -or $Items.Value.Count -eq 0) {
        & $Fail "'items' must be a non-empty JSON array."
    }

    $SeenSources = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Index = 0
    foreach ($Item in $Items.Value) {
        $Name = "items[$Index]."
        $Index++
        if (-not (& $IsObject $Item)) { & $Fail "'items' must contain JSON objects." }
        if ($Item.source -isnot [System.String] -or [System.String]::IsNullOrWhiteSpace($Item.source)) {
            & $Fail "'${Name}source' must be a non-empty string."
        }
        $Source = $Item.source
        if ($Source -match '\\' -or $Source.StartsWith('/') -or $Source -match '(^|/)\.{1,2}(/|$)' -or $Source -match ':' -or $Source -match '[^\x20-\x7E]') {
            & $Fail "'${Name}source' must be a relative cab path using forward slashes and printable ASCII characters."
        }
        if (-not $SeenSources.Add($Source)) { & $Fail "'${Name}source' duplicates another item source." }

        if ($InputObject.type -eq 'Build') {
            & $AssertKeys $Item $Name @('source', 'kind', 'destination', 'execute')
            if ($Item.kind -notin @('File', 'Folder')) { & $Fail "'${Name}kind' must be 'File' or 'Folder' for a Build Pack." }
            if ($Source -notmatch '^payload/\d{4}/[^/]+$') { & $Fail "'${Name}source' must be payload/NNNN/<name>." }
            if (-not (Test-OSDCloudBootPackDestination -Destination $Item.destination)) {
                & $Fail "'${Name}destination' must start with {MountPath}\ and stay inside the mounted image."
            }
            $Execute = $Item.PSObject.Properties['execute']
            if ($Execute) {
                if ($Execute.Value -isnot [System.Boolean]) { & $Fail "'${Name}execute' must be a JSON boolean." }
                if ($Execute.Value -and ($Item.kind -ne 'File' -or $Source -notmatch '\.ps1$')) {
                    & $Fail "'${Name}execute' is allowed only on .ps1 File items."
                }
            }
        }
        else {
            & $AssertKeys $Item $Name @('source', 'kind', 'action')
            $Layout = @{
                Environment = '^[^/]+\.env$'
                Registry    = '^winpe-reg/[^/]+\.reg$'
                Certificate = '^winpe-root-cer/[^/]+\.cer$'
                Script      = '^scripts/[^/]+\.(cmd|ps1)$'
            }
            if ($Item.kind -notin $Layout.Keys) {
                & $Fail "'${Name}kind' must be 'Environment', 'Registry', 'Certificate', or 'Script' for an Import Pack."
            }
            if ($Source -notmatch $Layout[$Item.kind]) { & $Fail "'${Name}source' does not match the $($Item.kind) layout." }
            $Action = $Item.PSObject.Properties['action']
            if ($Item.kind -eq 'Script') {
                if (-not $Action -or $Action.Value -notin @('Execute', 'Copy')) { & $Fail "'${Name}action' must be 'Execute' or 'Copy' for Script items." }
            }
            elseif ($Action) {
                & $Fail "'${Name}action' is allowed only on Script items."
            }
        }
    }
}

function Test-OSDCloudBootPackName {
    <#
    .SYNOPSIS
        Tests whether a BootPack name is folder-safe

    .DESCRIPTION
        Returns $true when the name is 1-64 printable ASCII characters, contains no
        Windows path-invalid characters or reserved device names, and does not start or
        end with a space or period.

    .PARAMETER Name
        Specifies the Pack name to test.

    .EXAMPLE
        PS> Test-OSDCloudBootPackName -Name 'CMTrace'

        Returns $true.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Boolean.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-10-29
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param ([AllowEmptyString()][AllowNull()][System.String]$Name)
    if ([System.String]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 64) { return $false }
    if ($Name -match '[^\x20-\x7E]' -or $Name -match '[\\/:*?"<>|]') { return $false }
    if ($Name -match '^[ .]|[ .]$') { return $false }
    if ($Name -match '^(?i)(CON|PRN|AUX|NUL|COM\d|LPT\d)$') { return $false }
    return $true
}

function Test-OSDCloudBootPackDestination {
    <#
    .SYNOPSIS
        Tests whether a Build Pack destination stays inside the mounted image

    .DESCRIPTION
        Returns $true when the destination starts with {MountPath}\ (case-insensitive) and
        the remaining relative path is non-empty, uses printable ASCII, has no drive, UNC,
        rooted, empty, . or .. segments, and contains no Windows path-invalid characters.

    .PARAMETER Destination
        Specifies the destination to test.

    .EXAMPLE
        PS> Test-OSDCloudBootPackDestination -Destination '{MountPath}\Windows\cmtrace.exe'

        Returns $true.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Boolean.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-10-29
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param ([AllowEmptyString()][AllowNull()][System.Object]$Destination)
    if ($Destination -isnot [System.String]) { return $false }
    if ($Destination -notmatch '^(?i)\{MountPath\}\\(.+)$') { return $false }
    $Relative = $Matches[1]
    if ($Relative -match '[^\x20-\x7E]' -or $Relative -match '[/:*?"<>|]' -or $Relative.StartsWith('\')) { return $false }
    foreach ($Segment in $Relative.Split('\')) {
        if ([System.String]::IsNullOrWhiteSpace($Segment) -or $Segment -in @('.', '..') -or $Segment -match '[ .]$') { return $false }
    }
    return $true
}
