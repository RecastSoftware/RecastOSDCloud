#Requires -Version 5.1

function Assert-OSDCloudBootMenuProfile {
    <#
    .SYNOPSIS
        Validates a standalone OSDCloud BootMenu profile JSON file

    .DESCRIPTION
        Parses one osdcloudbootmenu.json file and verifies that the supported
        sections and properties use valid value types. Unknown sections and properties are
        ignored without a warning so profiles written by newer OSDCloudBoot versions still
        load. Supported top-level sections are
        schemaVersion (must be 1), info, env, encryptedEnv, password, osdcloudBoot, osdcloudBootStartup,
        and osdcloudBootMenu. osdcloudBoot.buildPacks and
        osdcloudBoot.importPacks contain objects with a GUID id and an optional name that
        reference OSDCloud BootPacks. Stored commands are not executed. Invalid content produces a
        terminating error that identifies the file. encryptedEnv maps environment names
        to OSDBS1 encrypted tokens. Validation never prompts or decrypts values.
        The optional password token gates starting the selected profile, not reading its JSON.

    .PARAMETER Path
        Specifies the osdcloudbootmenu.json file to validate.

    .EXAMPLE
        PS> Assert-OSDCloudBootMenuProfile -Path 'C:\ProgramData\OSDeployCore\boot-assets\bootmenu-profiles\Deploy\osdcloudbootmenu.json'

        Validates the selected BootMenu profile without executing its commands.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-10-28

    .LINK
        ConvertFrom-OSDCloudBootMenuProfile
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.String]
        $Path
    )
    if ((Get-Variable -Name OSDTraceLogSession -Scope Script -ValueOnly -ErrorAction Ignore) -and (Get-Command -Name Write-OSDTraceLog -ErrorAction SilentlyContinue)) {
        Write-OSDTraceLog -Component $script:OSDTraceLogSession.CommandName -Message 'Calling private function: Assert-OSDCloudBootMenuProfile' -Parameters $PSBoundParameters
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "OSDCloud BootMenu profile was not found: $Path"
    }

    try {
        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if (-not $Raw.TrimStart().StartsWith('{')) { throw 'Expected one JSON object.' }
        $profileData = ConvertFrom-Json -InputObject $Raw -ErrorAction Stop
    }
    catch {
        throw "Invalid OSDCloud BootMenu profile JSON '$Path': $($_.Exception.Message) Backslashes in JSON strings must be escaped as '\\'."
    }

    $Fail = { param ($Message) throw "Invalid OSDCloud BootMenu profile '$Path': $Message" }
    $IsObject = { param ($Value) $Value -is [System.Management.Automation.PSCustomObject] }
    # Forward compatibility: newer OSDCloudBoot versions may add properties this module version does not
    # know. Unknown properties are silently ignored (no error, no warning); only the known ones are validated.
    $AssertKeys = {
        param ($Object, $Name, $Allowed)
    }
    $AssertBoolean = {
        param ($Object, $Name, $Key)
        $Property = $Object.PSObject.Properties[$Key]
        if ($Property -and $Property.Value -isnot [System.Boolean]) { & $Fail "'$Name$Key' must be a JSON boolean." }
    }
    $AssertString = {
        param ($Object, $Name, $Key)
        $Property = $Object.PSObject.Properties[$Key]
        if ($Property -and ($Property.Value -isnot [System.String] -or [System.String]::IsNullOrWhiteSpace($Property.Value))) {
            & $Fail "'$Name$Key' must be a non-empty string."
        }
    }
    $AssertStringArray = {
        param ($Object, $Name, $Key)
        $Property = $Object.PSObject.Properties[$Key]
        if (-not $Property) { return }
        if ($Property.Value -isnot [System.Array]) { & $Fail "'$Name$Key' must be a JSON array." }
        foreach ($Item in $Property.Value) {
            if ($Item -isnot [System.String] -or [System.String]::IsNullOrWhiteSpace($Item)) {
                & $Fail "'$Name$Key' must contain only non-empty strings."
            }
        }
    }
    $AssertSection = {
        param ($Root, $Key)
        $Property = $Root.PSObject.Properties[$Key]
        if (-not $Property) { return $null }
        if (-not (& $IsObject $Property.Value)) { & $Fail "'$Key' must be a JSON object." }
        return $Property.Value
    }
    $AssertCommandSection = {
        param ($Section, $Key)
        $Name = "osdcloudBootStartup.$Key."
        $Command = & $AssertSection $Section $Key
        if (-not $Command) { return }
        & $AssertKeys $Command $Name @('enabled', 'commands', 'noExit', 'errorAction')
        & $AssertBoolean $Command $Name 'enabled'
        & $AssertBoolean $Command $Name 'noExit'
        & $AssertStringArray $Command $Name 'commands'
        $ErrorAction = $Command.PSObject.Properties['errorAction']
        if ($ErrorAction -and $ErrorAction.Value -notin @('Continue', 'Stop')) {
            & $Fail "'${Name}errorAction' must be 'Continue' or 'Stop'."
        }
    }
    $AssertRunSection = {
        param ($Root, $Key)
        $Section = & $AssertSection $Root $Key
        if (-not $Section) { return }
        $Name = "$Key."
        & $AssertKeys $Section $Name @('enabled', 'command', 'parameters')
        & $AssertBoolean $Section $Name 'enabled'
        & $AssertString $Section $Name 'command'
        if ($Section.enabled -and -not $Section.command) { & $Fail "'${Name}command' is required when enabled." }
        $Parameters = $Section.PSObject.Properties['parameters']
        if ($Parameters) {
            if (-not (& $IsObject $Parameters.Value)) { & $Fail "'${Name}parameters' must be a JSON object." }
            foreach ($Parameter in $Parameters.Value.PSObject.Properties) {
                if ($Parameter.Name -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
                    & $Fail "'${Name}parameters' contains an invalid parameter name '$($Parameter.Name)'."
                }
                if ($Parameter.Value -isnot [System.Boolean] -and $Parameter.Value -isnot [System.String] -and
                    $Parameter.Value -isnot [System.ValueType]) {
                    & $Fail "'${Name}parameters.$($Parameter.Name)' must be a string, number, or boolean."
                }
            }
        }
    }

    if (-not (& $IsObject $profileData)) { & $Fail 'The profile must contain one JSON object.' }
    & $AssertKeys $profileData '' @('schemaVersion', 'info', 'env', 'encryptedEnv', 'password', 'osdcloudBoot', 'osdcloudBootStartup', 'osdcloudBootMenu')

    $SchemaVersion = $profileData.PSObject.Properties['schemaVersion']
    if (-not $SchemaVersion -or $SchemaVersion.Value -isnot [System.Int64] -and $SchemaVersion.Value -isnot [System.Int32] -or $SchemaVersion.Value -ne 1) {
        & $Fail "'schemaVersion' is required and must be 1."
    }

    $Info = & $AssertSection $profileData 'info'
    if ($Info) {
        & $AssertKeys $Info 'info.' @('id', 'name', 'author', 'description')
        $IdProperty = $Info.PSObject.Properties['id']
        $ParsedId = [guid]::Empty
        if ($IdProperty -and ($IdProperty.Value -isnot [System.String] -or -not [guid]::TryParse($IdProperty.Value, [ref]$ParsedId) -or $ParsedId -eq [guid]::Empty)) {
            & $Fail "'info.id' must be a GUID string."
        }
        foreach ($Key in 'name', 'author', 'description') {
            $Property = $Info.PSObject.Properties[$Key]
            if ($Property -and $Property.Value -isnot [System.String]) { & $Fail "'info.$Key' must be a string." }
        }
    }

    $Env = & $AssertSection $profileData 'env'
    if ($Env) {
        foreach ($Property in $Env.PSObject.Properties) {
            if ($Property.Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { & $Fail "'env.$($Property.Name)' is not a valid environment variable name." }
            if ($Property.Value -isnot [System.String]) { & $Fail "'env.$($Property.Name)' must be a string." }
        }
    }

    $AssertEncryptedToken = {
        param ($Token)
        if ($Token -isnot [string] -or $Token.Length -gt 1398262 -or $Token -notmatch '^OSDBS1:[A-Za-z0-9+/]+={0,2}$') {
            & $Fail 'Expected a supported encrypted string token.'
        }
        try { $Bytes = [Convert]::FromBase64String($Token.Substring(7)) }
        catch { & $Fail 'Invalid encrypted string encoding.' }
        if ($Bytes.Length -lt 97 -or $Bytes.Length -gt 1048673 -or $Bytes[0] -ne 1 -or ($Bytes.Length - 81) % 16 -ne 0) {
            & $Fail 'Invalid or unsupported encrypted string envelope.'
        }
    }
    $Password = $profileData.PSObject.Properties['password']
    if ($Password) { & $AssertEncryptedToken $Password.Value }
    $EncryptedEnv = & $AssertSection $profileData 'encryptedEnv'
    if ($EncryptedEnv) {
        # ConvertFrom-Json can discard exact duplicate keys; inspect JSON keys before conversion loses them.
        $Depth = 0
        $EncryptedDepth = -1
        $PendingEncrypted = $false
        $SeenEncryptedSection = $false
        $RawNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Match in [regex]::Matches($Raw, '"(?:\\.|[^"\\])*"\s*:?|[{}]')) {
            $Lexeme = $Match.Value.Trim()
            if ($Lexeme -eq '{') {
                $Depth++
                if ($PendingEncrypted) { $EncryptedDepth = $Depth; $PendingEncrypted = $false }
            }
            elseif ($Lexeme -eq '}') {
                if ($Depth -eq $EncryptedDepth) { $EncryptedDepth = -1 }
                $Depth--
            }
            elseif ($Lexeme.EndsWith(':')) {
                $Key = ConvertFrom-Json -InputObject $Lexeme.Substring(0, $Lexeme.Length - 1)
                if ($Depth -eq 1 -and $Key -eq 'encryptedEnv') {
                    if ($SeenEncryptedSection) { & $Fail 'Duplicate encryptedEnv section.' }
                    $SeenEncryptedSection = $true
                    $PendingEncrypted = $true
                }
                elseif ($Depth -eq $EncryptedDepth -and -not $RawNames.Add($Key)) {
                    & $Fail 'encryptedEnv contains duplicate environment variable names.'
                }
            }
        }
        $SeenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($Env) {
            foreach ($Property in $Env.PSObject.Properties) { $null = $SeenNames.Add($Property.Name) }
        }
        foreach ($Property in $EncryptedEnv.PSObject.Properties) {
            if ($Property.Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or -not $SeenNames.Add($Property.Name)) {
                & $Fail 'encryptedEnv contains an invalid or conflicting environment variable name.'
            }
            & $AssertEncryptedToken $Property.Value
        }
    }

    $BootImage = & $AssertSection $profileData 'osdcloudBoot'
    if ($BootImage) {
        & $AssertKeys $BootImage 'osdcloudBoot.' @('requireWinPE', 'requireWinRE', 'installModule', 'buildPacks', 'importPacks')
        foreach ($PackKey in 'buildPacks', 'importPacks') {
            $Packs = $BootImage.PSObject.Properties[$PackKey]
            if (-not $Packs) { continue }
            if ($Packs.Value -isnot [System.Array]) { & $Fail "'osdcloudBoot.$PackKey' must be a JSON array." }
            $SeenPackIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Pack in $Packs.Value) {
                if (-not (& $IsObject $Pack)) { & $Fail "'osdcloudBoot.$PackKey' must contain JSON objects." }
                & $AssertKeys $Pack "osdcloudBoot.$PackKey." @('id', 'name')
                $PackId = [guid]::Empty
                if ($Pack.id -isnot [System.String] -or -not [guid]::TryParse($Pack.id, [ref]$PackId) -or $PackId -eq [guid]::Empty) {
                    & $Fail "'osdcloudBoot.$PackKey.id' must be a GUID string."
                }
                if (-not $SeenPackIds.Add($PackId.ToString())) { & $Fail "'osdcloudBoot.$PackKey' contains duplicate id '$($Pack.id)'." }
                & $AssertString $Pack "osdcloudBoot.$PackKey." 'name'
            }
        }
        & $AssertBoolean $BootImage 'osdcloudBoot.' 'requireWinRE'
        & $AssertBoolean $BootImage 'osdcloudBoot.' 'requireWinPE'
        if ($BootImage.requireWinPE -and $BootImage.requireWinRE) { & $Fail 'A profile cannot require both WinPE and WinRE.' }
        $PSModules = $BootImage.PSObject.Properties['installModule']
        if ($PSModules) {
            if ($PSModules.Value -isnot [System.Array]) { & $Fail "'osdcloudBoot.installModule' must be a JSON array." }
            foreach ($Module in $PSModules.Value) {
                if ($Module -is [string] -and -not [string]::IsNullOrWhiteSpace($Module)) { continue }
                if (-not (& $IsObject $Module)) { & $Fail "'osdcloudBoot.installModule' must contain module names or JSON objects." }
                & $AssertKeys $Module 'osdcloudBoot.installModule.' @('name', 'version', 'source', 'enabled')
                if (-not $Module.PSObject.Properties['name']) { & $Fail "'osdcloudBoot.installModule' entries require 'name'." }
                foreach ($Key in 'name', 'version', 'source') { & $AssertString $Module 'osdcloudBoot.installModule.' $Key }
                & $AssertBoolean $Module 'osdcloudBoot.installModule.' 'enabled'
            }
        }
    }

    $WinpeStartup = & $AssertSection $profileData 'osdcloudBootStartup'
    if ($WinpeStartup) {
        $Name = 'osdcloudBootStartup.'
        & $AssertKeys $WinpeStartup $Name @('enabled', 'onScreenKeyboard', 'showPnpDevices', 'showPnpErrors', 'wifi', 'ipConfig', 'updateOSDCloud', 'installModules', 'startup', 'main', 'shutdown')
        foreach ($Key in 'enabled', 'onScreenKeyboard', 'showPnpDevices', 'showPnpErrors', 'wifi', 'ipConfig', 'updateOSDCloud') {
            & $AssertBoolean $WinpeStartup $Name $Key
        }
        & $AssertStringArray $WinpeStartup $Name 'installModules'
        foreach ($Key in 'startup', 'main', 'shutdown') { & $AssertCommandSection $WinpeStartup $Key }
    }

    & $AssertRunSection $profileData 'osdcloudBootMenu'
}
