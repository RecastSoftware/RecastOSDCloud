#Requires -Version 5.1

function ConvertFrom-OSDCloudBootMenuProfile {
    <#
    .SYNOPSIS
        Converts a standalone OSDCloud BootMenu profile to runtime settings

    .DESCRIPTION
        Reads an osdcloudbootmenu.json file and returns the flat settings consumed by
        Invoke-OSDCloudBootMenu in the boot image. Settings that are omitted stay omitted
        so runtime defaults apply. Positive menu settings such as wifi map
        to the Skip* settings. A disabled osdcloudBootStartup section skips the
        startup checks and command stages, but retains
        environment variables. A disabled startup, main, or shutdown command section
        returns an empty command list.

        When osdcloudBootMenu is enabled, its command and parameters are appended to
        the main command list. Boolean parameters become switches when true and are
        omitted when false. Other values are single-quoted. Deployment commands are
        configured directly in osdcloudBootStartup.main.commands.

        Environment variables OSDCLOUDBOOTMENU_PROFILE and OSDCLOUDBOOT_AUTHOR are set from
        info.name and info.author when present. Entries in the env object are added
        as environment variables and override those defaults. Optional encryptedEnv tokens
        and the profile password token are returned separately without prompting or
        decrypting. Stored commands are not executed.

    .PARAMETER Path
        Specifies the osdcloudbootmenu.json file or its containing profile folder.

    .EXAMPLE
        PS> ConvertFrom-OSDCloudBootMenuProfile -Path 'C:\Profiles\PowerShell' | ConvertTo-Json

        Shows the WinpeStartup settings generated for the profile.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-10-28

    .LINK
        Assert-OSDCloudBootMenuProfile
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param (
        [Parameter(Mandatory)]
        [System.String]
        $Path
    )
    if ((Get-Variable -Name OSDTraceLogSession -Scope Script -ValueOnly -ErrorAction Ignore) -and (Get-Command -Name Write-OSDTraceLog -ErrorAction SilentlyContinue)) {
        Write-OSDTraceLog -Component $script:OSDTraceLogSession.CommandName -Message 'Calling private function: ConvertFrom-OSDCloudBootMenuProfile' -Parameters $PSBoundParameters
    }

    $ProfileFilePath = if (Test-Path -LiteralPath $Path -PathType Container) {
        Join-Path $Path 'osdcloudbootmenu.json'
    }
    else { $Path }
    Assert-OSDCloudBootMenuProfile -Path $ProfileFilePath
    $profileData = Get-Content -LiteralPath $ProfileFilePath -Raw | ConvertFrom-Json

    $Result = [ordered]@{}
    if ($profileData.password) { $Result['password'] = $profileData.password }
    $Environment = [ordered]@{}
    if ($profileData.info.name) { $Environment['OSDCLOUDBOOTMENU_PROFILE'] = $profileData.info.name }
    if ($profileData.info.author) { $Environment['OSDCLOUDBOOT_AUTHOR'] = $profileData.info.author }
    if ($profileData.env) {
        foreach ($Variable in $profileData.env.PSObject.Properties) { $Environment[$Variable.Name] = $Variable.Value }
    }
    if ($Environment.Count -gt 0) { $Result['env'] = $Environment }
    if ($profileData.encryptedEnv) {
        $EncryptedEnvironment = [ordered]@{}
        foreach ($Variable in $profileData.encryptedEnv.PSObject.Properties) { $EncryptedEnvironment[$Variable.Name] = $Variable.Value }
        if ($EncryptedEnvironment.Count -gt 0) { $Result['encryptedEnv'] = $EncryptedEnvironment }
    }

    $Startup = $profileData.osdcloudBootStartup
    $StartupEnabled = $Startup -and ($null -eq $Startup.enabled -or $Startup.enabled)
    $MainCommands = [System.Collections.Generic.List[string]]::new()

    if ($StartupEnabled) {
        $Inverted = [ordered]@{
            onScreenKeyboard = 'SkipOnScreenKeyboard'
            wifi             = 'SkipWiFi'
            ipConfig         = 'SkipIPConfig'
            updateOSDCloud   = 'SkipUpdateOSDCloud'
        }
        foreach ($Key in $Inverted.Keys) {
            if ($null -ne $Startup.$Key) { $Result["Invoke-OSDCloudBootMenu:$($Inverted[$Key])"] = -not $Startup.$Key }
        }
        foreach ($Key in 'showPnpDevices', 'showPnpErrors') {
            if ($null -ne $Startup.$Key) { $Result["Invoke-OSDCloudBootMenu:$([char]::ToUpper($Key[0]) + $Key.Substring(1))"] = $Startup.$Key }
        }
        if ($null -ne $Startup.installModules) { $Result['Invoke-OSDCloudBootMenu:InstallModule'] = @($Startup.installModules) }

        foreach ($Stage in 'startup', 'main', 'shutdown') {
            $Section = $Startup.$Stage
            if (-not $Section) { continue }
            $Label = [char]::ToUpper($Stage[0]) + $Stage.Substring(1)
            $Commands = if ($null -eq $Section.enabled -or $Section.enabled) { @($Section.commands) } else { @() }
            if ($Stage -eq 'main') { foreach ($Command in $Commands) { $MainCommands.Add($Command) } }
            else { $Result["Invoke-OSDCloudBootMenu:Invoke${Label}Command"] = $Commands }
            if ($null -ne $Section.noExit) { $Result["Invoke-OSDCloudBootMenu:Invoke${Label}CommandNoExit"] = $Section.noExit }
            if ($Section.errorAction) { $Result["Invoke-OSDCloudBootMenu:Invoke${Label}CommandEA"] = $Section.errorAction }
        }
    }
    elseif ($Startup) {
        foreach ($Key in 'SkipOnScreenKeyboard', 'SkipWiFi', 'SkipIPConfig', 'SkipUpdateOSDCloud') {
            $Result["Invoke-OSDCloudBootMenu:$Key"] = $true
        }
        foreach ($Key in 'ShowPnpDevices', 'ShowPnpErrors') { $Result["Invoke-OSDCloudBootMenu:$Key"] = $false }
        $Result['Invoke-OSDCloudBootMenu:InstallModule'] = @()
        foreach ($Stage in 'Startup', 'Main', 'Shutdown') {
            $Result["Invoke-OSDCloudBootMenu:Invoke${Stage}Command"] = @()
        }
    }

    foreach ($Key in 'osdcloudBootMenu') {
        $Section = $profileData.$Key
        if (-not $Section -or -not $Section.enabled -or -not $Section.command) { continue }
        $Parts = [System.Collections.Generic.List[string]]::new()
        $Parts.Add($Section.command)
        foreach ($Parameter in $Section.parameters.PSObject.Properties) {
            if ($Parameter.Value -is [System.Boolean]) {
                if ($Parameter.Value) { $Parts.Add("-$($Parameter.Name)") }
            }
            elseif ($Parameter.Value -is [System.String]) {
                $Parts.Add("-$($Parameter.Name) '$($Parameter.Value.Replace("'", "''"))'")
            }
            else {
                $Value = [System.Convert]::ToString($Parameter.Value, [System.Globalization.CultureInfo]::InvariantCulture)
                $Parts.Add("-$($Parameter.Name) $Value")
            }
        }
        $MainCommands.Add($Parts -join ' ')
    }

    if ($StartupEnabled -or $MainCommands.Count -gt 0) {
        $Result['Invoke-OSDCloudBootMenu:InvokeMainCommand'] = @($MainCommands)
    }
    return $Result
}
