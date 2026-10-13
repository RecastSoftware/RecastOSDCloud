#requires -Version 5.1

function New-WinpeStartupProfile {
    <#
    .SYNOPSIS
        Creates a WinpeStartup profile for OSDCloud

    .DESCRIPTION
        Saves <ProfileName>\winpestartup.json under the existing
        C:\ProgramData\OSDeployCore\boot-assets\winpestartup-profiles folder and
        WinpeStartup\Profiles on each mounted, writable USB volume labeled OSDCloud.
        Uses the actual USB drive letters. Administrator rights are required only
        for the Boot-Assets destination; USB destinations are still attempted when
        the session is not elevated.

        Writes all 16 startup settings with Invoke-WinpeStartup: prefixes and an
        unprefixed Environment object. Defaults come from the module's
        PSDefaultParameterValues.json, overlaid by the bundled OSDCloud
        winpestartup.json. Supplied parameters override those defaults, including
        explicit false switches and empty arrays. A supplied Environment
        hashtable replaces the bundled environment values. Environment is first
        in the JSON, followed by display/skip settings, modules, and the startup,
        main, and shutdown command groups. WINPESTARTUP_AUTHOR is always the
        current username and WINPESTARTUP_PROFILE is always ProfileName.

        Existing files require Force for replacement. Destination errors are
        reported independently and remaining destinations are attempted unless
        ErrorAction Stop is requested. Successful saves are not rolled back.
        No usable destinations or no successful saves produces a terminating error.
        WhatIf and Confirm gate all filesystem changes. Stored commands are never
        executed, and environment variables are not set during profile creation.
        Each successfully saved file opens in Notepad for editing without waiting
        for the editor to close. Copies are independent; edits are not synchronized.
        Editor failures are reported separately and do not undo saved files.

    .PARAMETER ProfileName
        A single Windows folder name. Paths, invalid filename characters, reserved
        device names, and names ending in a space or period are not accepted.

    .PARAMETER SkipOnScreenKeyboard
        Stores whether Invoke-WinpeStartup skips the on-screen keyboard check.

    .PARAMETER ShowPnpDevices
        Stores whether Invoke-WinpeStartup displays Plug and Play hardware.

    .PARAMETER ShowPnpErrors
        Stores whether Invoke-WinpeStartup displays Plug and Play errors.

    .PARAMETER SkipWiFi
        Stores whether Invoke-WinpeStartup skips Wi-Fi startup and connection checks.

    .PARAMETER SkipIPConfig
        Stores whether Invoke-WinpeStartup skips IP configuration display.

    .PARAMETER SkipUpdateOSDCloud
        Stores whether Invoke-WinpeStartup skips updating the OSDCloud module.

    .PARAMETER InstallModule
        Additional module names to update. An empty array clears inherited modules.
        Entries must be non-empty strings.

    .PARAMETER InvokeStartupCommand
        Ordered commands or URLs for the startup phase. HTTP/HTTPS URLs are
        interpreted by Invoke-WinpeStartup, not downloaded by this cmdlet.
        An empty array clears inherited commands. Entries must be non-empty strings.

    .PARAMETER InvokeStartupCommandNoExit
        Stores whether the startup child PowerShell remains open. The runtime
        waits for that process to close. Use :$false to explicitly disable it.

    .PARAMETER InvokeStartupCommandEA
        Stores Continue (warn and proceed) or Stop (terminate startup) for startup
        child-process failures. If omitted, uses the bundled default.

    .PARAMETER InvokeMainCommand
        Ordered commands or URLs for the main phase. An empty array clears inherited
        commands. Entries must be non-empty strings. Commands are not executed here.

    .PARAMETER InvokeMainCommandNoExit
        Stores whether the main child PowerShell remains open. Use :$false to
        explicitly disable it.

    .PARAMETER InvokeMainCommandEA
        Stores Continue or Stop for main child-process failures.
        If omitted, uses the bundled default.

    .PARAMETER InvokeShutdownCommand
        Ordered commands or URLs for the shutdown phase. An empty array clears
        inherited commands. Entries must be non-empty strings.

    .PARAMETER InvokeShutdownCommandNoExit
        Stores whether the shutdown child PowerShell remains open. Use :$false to
        explicitly disable it.

    .PARAMETER InvokeShutdownCommandEA
        Stores Continue or Stop for shutdown child-process failures.
        If omitted, uses the bundled default.

    .PARAMETER Environment
        A hashtable of process environment variables for the selected profile.
        Names must be non-empty strings without equals signs or null characters.
        Values must be strings, finite numbers, or booleans. Nulls, arrays, and
        nested objects are not accepted. Values are stored in plaintext; do not
        include secrets. An empty hashtable removes bundled environment values
        except the generated WINPESTARTUP_AUTHOR and WINPESTARTUP_PROFILE metadata.
        These two values cannot be overridden through this parameter.

    .PARAMETER Force
        Allows replacing existing profile files. Does not bypass permissions,
        WhatIf, or Confirm.

    .PARAMETER PassThru
        Returns a FileInfo object for each successfully saved profile.

    .EXAMPLE
        PS> New-WinpeStartupProfile -ProfileName 'Deploy-And-Restart' -InvokeMainCommand 'Deploy-OSDCloud' -InvokeMainCommandEA Stop -InvokeShutdownCommand 'Restart-Computer -Force' -PassThru

        Saves a deployment and restart profile to all available destinations.
        Run elevated to include the existing Boot-Assets destination.

    .EXAMPLE
        PS> New-WinpeStartupProfile -ProfileName 'BranchOffice' -SkipWiFi:$false -InstallModule @() -Environment @{ OSDCLOUD_SITE = 'BranchOffice' } -Force -WhatIf

        Previews replacement without writing files. The profile explicitly enables
        Wi-Fi checks, clears inherited additional modules, and sets a site variable.

    .EXAMPLE
        PS> New-WinpeStartupProfile -ProfileName 'Runtime-Defaults'

        Creates a complete profile using the bundled OSDCloud defaults and opens
        each saved copy in Notepad.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.IO.FileInfo. Returned only when PassThru is supplied, once per save.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-10-13
        Requires Windows PowerShell 5.1 or PowerShell on Windows and Storage
        cmdlets for USB discovery, and notepad.exe for editing.
        Does not create the shared Boot-Assets root.

    .LINK
        Invoke-WinpeStartup
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if ([string]::IsNullOrWhiteSpace($_) -or $_.Length -gt 255 -or
                $_ -match '[<>:"/\\|?*\x00-\x1f]' -or
                $_ -match '[ .]$' -or
                $_ -match '^(?i:CON|CONIN\$|CONOUT\$|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(?:\.|$)') {
                throw 'ProfileName must be a single valid Windows folder name, not a path or reserved device name.'
            }
            $true
        })]
        [string]$ProfileName,

        [Parameter()]
        [switch]$SkipOnScreenKeyboard,
        [Parameter()]
        [switch]$ShowPnpDevices,
        [Parameter()]
        [switch]$ShowPnpErrors,
        [Parameter()]
        [switch]$SkipWiFi,
        [Parameter()]
        [switch]$SkipIPConfig,
        [Parameter()]
        [switch]$SkipUpdateOSDCloud,
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$InstallModule,
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$InvokeStartupCommand,
        [Parameter()]
        [switch]$InvokeStartupCommandNoExit,
        [Parameter()]
        [ValidateSet('Continue', 'Stop')]
        [string]$InvokeStartupCommandEA,
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$InvokeMainCommand,
        [Parameter()]
        [switch]$InvokeMainCommandNoExit,
        [Parameter()]
        [ValidateSet('Continue', 'Stop')]
        [string]$InvokeMainCommandEA,
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$InvokeShutdownCommand,
        [Parameter()]
        [switch]$InvokeShutdownCommandNoExit,
        [Parameter()]
        [ValidateSet('Continue', 'Stop')]
        [string]$InvokeShutdownCommandEA,
        [Parameter()]
        [ValidateNotNull()]
        [hashtable]$Environment,
        [Parameter()]
        [switch]$Force,
        [Parameter()]
        [switch]$PassThru
    )

    Write-Verbose "[$($MyInvocation.MyCommand.Name)] Start"
    $profileSettings = [ordered]@{ Environment = $null }
    $arrayParameters = @('InstallModule', 'InvokeStartupCommand', 'InvokeMainCommand', 'InvokeShutdownCommand')
    $switchParameters = @(
        'SkipOnScreenKeyboard', 'ShowPnpDevices', 'ShowPnpErrors', 'SkipWiFi',
        'SkipIPConfig', 'SkipUpdateOSDCloud', 'InvokeStartupCommandNoExit',
        'InvokeMainCommandNoExit', 'InvokeShutdownCommandNoExit'
    )
    $moduleDefaultsPath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\core\PSDefaultParameterValues.json'
    $bundledProfilePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\core\winpestartup-profiles\OSDCloud\winpestartup.json'
    $moduleDefaults = Get-Content -LiteralPath $moduleDefaultsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $bundledProfile = Get-Content -LiteralPath $bundledProfilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($moduleDefaults -isnot [pscustomobject] -or $bundledProfile -isnot [pscustomobject]) {
        throw 'New-WinpeStartupProfile: Module defaults and the bundled OSDCloud profile must be JSON objects.'
    }
    $orderedParameters = @(
        'ShowPnpDevices', 'ShowPnpErrors', 'SkipOnScreenKeyboard',
        'SkipWiFi', 'SkipIPConfig', 'SkipUpdateOSDCloud', 'InstallModule',
        'InvokeStartupCommand', 'InvokeStartupCommandEA', 'InvokeStartupCommandNoExit',
        'InvokeMainCommand', 'InvokeMainCommandEA', 'InvokeMainCommandNoExit',
        'InvokeShutdownCommand', 'InvokeShutdownCommandEA', 'InvokeShutdownCommandNoExit'
    )
    foreach ($parameterName in $orderedParameters) {
        $propertyName = "Invoke-WinpeStartup:$parameterName"
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            $value = $PSBoundParameters[$parameterName]
        }
        elseif ($bundledProfile.PSObject.Properties[$propertyName]) {
            $value = $bundledProfile.$propertyName
        }
        elseif ($moduleDefaults.PSObject.Properties[$propertyName]) {
            $value = $moduleDefaults.$propertyName
        }
        else {
            throw "New-WinpeStartupProfile: Missing bundled default for '$parameterName'."
        }

        if ($parameterName -in $arrayParameters) {
            if ($null -eq $value -or @($value | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
                throw "$parameterName must be an array of non-empty strings; use @() to clear inherited values."
            }
            $profileSettings["Invoke-WinpeStartup:$parameterName"] = [string[]]$value
        }
        elseif ($parameterName -in $switchParameters) {
            if ($value -isnot [bool] -and $value -isnot [System.Management.Automation.SwitchParameter]) {
                throw "New-WinpeStartupProfile: '$parameterName' must have a boolean default."
            }
            $profileSettings[$propertyName] = [bool]$value
        }
        else {
            if ($value -notin @('Continue', 'Stop')) {
                throw "New-WinpeStartupProfile: '$parameterName' must be Continue or Stop."
            }
            $profileSettings[$propertyName] = if ($value -ieq 'Stop') { 'Stop' } else { 'Continue' }
        }
    }

    if (-not $PSBoundParameters.ContainsKey('Environment')) {
        $Environment = @{}
        $bundledEnvironment = $bundledProfile.Environment
        if ($bundledProfile.PSObject.Properties['env']) {
            $bundledEnvironment = $bundledProfile.env
        }
        if ($null -ne $bundledEnvironment) {
            if ($bundledEnvironment -isnot [pscustomobject]) {
                throw 'New-WinpeStartupProfile: The bundled environment must be a JSON object.'
            }
            foreach ($property in $bundledEnvironment.PSObject.Properties) {
                $Environment[$property.Name] = $property.Value
            }
        }
    }
    if ($null -ne $Environment) {
        foreach ($entry in $Environment.GetEnumerator()) {
            if ($entry.Key -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Key) -or
                $entry.Key.Contains('=') -or $entry.Key.Contains([char]0)) {
                throw 'Environment variable names must be non-empty strings without equals signs or null characters.'
            }
            $typeCode = if ($null -ne $entry.Value) { [System.Type]::GetTypeCode($entry.Value.GetType()) } else { [System.TypeCode]::Empty }
            if ($typeCode -notin @(
                [System.TypeCode]::String, [System.TypeCode]::Boolean,
                [System.TypeCode]::Byte, [System.TypeCode]::SByte,
                [System.TypeCode]::Int16, [System.TypeCode]::UInt16,
                [System.TypeCode]::Int32, [System.TypeCode]::UInt32,
                [System.TypeCode]::Int64, [System.TypeCode]::UInt64,
                [System.TypeCode]::Single, [System.TypeCode]::Double, [System.TypeCode]::Decimal
            ) -or $entry.Value -is [System.Enum] -or
                (($entry.Value -is [double] -or $entry.Value -is [single]) -and
                    ([double]::IsNaN($entry.Value) -or [double]::IsInfinity($entry.Value)))) {
                throw "Environment variable '$($entry.Key)' must have a string, finite numeric, or boolean value."
            }
        }
        $profileEnvironment = [ordered]@{
            WINPESTARTUP_AUTHOR = [System.Environment]::UserName
            WINPESTARTUP_PROFILE = $ProfileName
        }
        foreach ($entry in $Environment.GetEnumerator() | Sort-Object -Property Key) {
            if ($entry.Key -notin @('WINPESTARTUP_AUTHOR', 'WINPESTARTUP_PROFILE')) {
                $profileEnvironment[$entry.Key] = $entry.Value
            }
        }
        $profileSettings['Environment'] = $profileEnvironment
    }
    $json = ConvertTo-Json -InputObject $profileSettings -Depth 4 -ErrorAction Stop

    $destinations = [System.Collections.Generic.List[object]]::new()
    $bootAssetsRoot = 'C:\ProgramData\OSDeployCore\boot-assets\winpestartup-profiles'
    try {
        if (Test-Path -LiteralPath $bootAssetsRoot -PathType Container -ErrorAction Stop) {
            $destinations.Add([pscustomobject]@{ Root = $bootAssetsRoot; RequiresAdministrator = $true })
        }
    }
    catch {
        $PSCmdlet.WriteError($_)
    }
    $volumes = @()
    try {
        $volumes = @(Get-Volume -ErrorAction Stop | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter })
    }
    catch {
        $PSCmdlet.WriteError($_)
    }
    foreach ($volume in $volumes) {
        try {
            $partition = Get-Partition -DriveLetter $volume.DriveLetter -ErrorAction Stop
            $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
            if ($disk.BusType -ne 'USB') {
                continue
            }
            if ($disk.IsReadOnly -or $disk.IsOffline -or $partition.IsReadOnly -or $partition.IsOffline) {
                Write-Warning "[$($MyInvocation.MyCommand.Name)] Skipping unavailable or read-only OSDCloud USB volume '$($volume.DriveLetter):'."
                continue
            }
            $destinations.Add([pscustomobject]@{
                Root = Join-Path -Path "$($volume.DriveLetter):\" -ChildPath 'WinpeStartup\Profiles'
                RequiresAdministrator = $false
            })
        }
        catch {
            $PSCmdlet.WriteError($_)
        }
    }

    if ($destinations.Count -eq 0) {
        throw 'New-WinpeStartupProfile: No usable destinations found. The Boot-Assets folder must exist or a writable USB volume labeled OSDCloud must be mounted.'
    }

    $savedCount = 0
    $attemptedCount = 0
    foreach ($destination in $destinations) {
        $profileDirectory = Join-Path -Path $destination.Root -ChildPath $ProfileName
        $profilePath = Join-Path -Path $profileDirectory -ChildPath 'winpestartup.json'
        if (-not $PSCmdlet.ShouldProcess($profilePath, 'Save WinpeStartup profile')) {
            continue
        }
        $attemptedCount++
        $temporaryPath = $null
        $profileSaved = $false
        try {
            if ($destination.RequiresAdministrator) {
                $principal = New-Object -TypeName System.Security.Principal.WindowsPrincipal -ArgumentList ([System.Security.Principal.WindowsIdentity]::GetCurrent())
                if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
                    throw [System.UnauthorizedAccessException]::new("Administrator rights are required to save '$profilePath'. Run PowerShell as administrator.")
                }
            }
            if ([System.IO.File]::Exists($profilePath) -and -not $Force) {
                throw [System.IO.IOException]::new("Profile '$profilePath' already exists. Use -Force to replace it.")
            }

            $null = [System.IO.Directory]::CreateDirectory($profileDirectory)
            $candidatePath = Join-Path -Path $profileDirectory -ChildPath "$([guid]::NewGuid().ToString('N')).tmp"
            $stream = [System.IO.File]::Open($candidatePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $temporaryPath = $candidatePath
            try {
                # A BOM lets Windows PowerShell 5.1 read non-ASCII commands without guessing ANSI.
                $encoding = [System.Text.UTF8Encoding]::new($true)
                $preamble = $encoding.GetPreamble()
                $stream.Write($preamble, 0, $preamble.Length)
                $bytes = $encoding.GetBytes($json + [System.Environment]::NewLine)
                $stream.Write($bytes, 0, $bytes.Length)
            }
            finally {
                $stream.Dispose()
            }

            # Move refuses concurrent creation; Replace preserves the old file if publication fails.
            if ($Force -and [System.IO.File]::Exists($profilePath)) {
                [System.IO.File]::Replace($temporaryPath, $profilePath, [System.Management.Automation.Language.NullString]::Value)
            }
            else {
                [System.IO.File]::Move($temporaryPath, $profilePath)
            }
            $savedCount++
            $profileSaved = $true
            Write-Verbose "[$($MyInvocation.MyCommand.Name)] Saved '$profilePath'."
            if ($PassThru) {
                Get-Item -LiteralPath $profilePath -ErrorAction Stop
            }
        }
        catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception, 'WinpeStartupProfileSaveFailed',
                [System.Management.Automation.ErrorCategory]::WriteError, $profilePath
            )
            $PSCmdlet.WriteError($errorRecord)
        }
        finally {
            if ($temporaryPath -and [System.IO.File]::Exists($temporaryPath)) {
                try {
                    [System.IO.File]::Delete($temporaryPath)
                }
                catch {
                    $PSCmdlet.WriteError($_)
                }
            }
        }
        if ($profileSaved) {
            try {
                Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$profilePath`"" -ErrorAction Stop
            }
            catch {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $_.Exception, 'WinpeStartupProfileEditorFailed',
                    [System.Management.Automation.ErrorCategory]::OpenError, $profilePath
                )
                $PSCmdlet.WriteError($errorRecord)
            }
        }
    }
    if ($attemptedCount -gt 0 -and $savedCount -eq 0) {
        throw "New-WinpeStartupProfile: No profile was saved to any of the $attemptedCount attempted destinations."
    }
    Write-Verbose "[$($MyInvocation.MyCommand.Name)] End"
}
