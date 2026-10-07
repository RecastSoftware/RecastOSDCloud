#requires -Version 5.1

function Invoke-WinpeStartup {
    <#
    .SYNOPSIS
        Runs the WinpeStartup workflow for OSDCloud.

    .DESCRIPTION
        Executes the OSDCloud WinpeStartup sequence from a single entry point.
        The function can optionally load defaults from module JSON, discover and
        apply a startup profile, and then run startup steps in order including
        environment setup, drivers, files, hardware checks, connectivity, module
        updates, script execution, and optional URL/command invocations.
        Startup output is transcribed to X:\Windows\Temp\winpestartup.log.

        Environment setup imports literal NAME=VALUE entries from
        X:\WinpeStartup\core\*\*.env, including hidden .env files, in sorted
        full-path order without searching deeper folders. Core entries are
        process-scoped defaults; shell profile variables take precedence.
        Blank lines and full-line # comments are ignored, matching outer quotes
        are removed, and expressions are not evaluated. Invalid entries and
        file failures warn and continue without logging values.

        Environment setup also imports X:\WinpeStartup\core\*\winpe-reg\*.reg
        into the WinPE registry using reg.exe import, then adds certificates from
        X:\WinpeStartup\core\*\winpe-root-cer\*.cer to the local machine Root
        store using certutil.exe -addstore root. Files are sorted by full path
        within each type; discovery and import failures warn and continue.

        A selected profile may include an env or Environment object. Supported
        scalar values are converted to strings and assigned to the current
        process, overwriting existing values. Child PowerShell command sessions
        inherit the resulting environment.

        This function only runs in WinPE where SystemDrive is X:. If it is called
        outside WinPE, it writes a warning and exits without running startup steps.

    .EXAMPLE
        Invoke-WinpeStartup

        Runs the startup workflow with default behavior.

    .EXAMPLE
        Invoke-WinpeStartup -Verbose

        Runs the startup workflow and writes verbose progress details.

    .EXAMPLE
        Invoke-WinpeStartup -SkipWiFi -SkipIPConfig

        Runs startup but skips Wi-Fi and IP configuration display steps.

    .PARAMETER SkipOnScreenKeyboard
        Skips launching the on-screen keyboard check.

    .PARAMETER ShowPnpDevices
        Shows the Plug and Play device hardware window (`Show-WinpeStartupDevices`). By default this window is not displayed.

    .PARAMETER ShowPnpErrors
        Shows the Plug and Play device error window (`Show-WinpeStartupDeviceErrors`). By default this window is not displayed.

    .PARAMETER SkipWiFi
        Skips Wi-Fi startup and connection checks.

    .PARAMETER SkipIPConfig
        Skips displaying IP configuration details.

    .PARAMETER SkipUpdateOSDCloud
        Skips updating the OSDCloud module.

    .PARAMETER InstallModule
        One or more additional module names to update during startup.

    .PARAMETER InvokeStartupCommand
        One or more PowerShell command lines or URLs to execute during startup in a
        single child PowerShell process. Entries beginning with 'http://' or 'https://'
        are automatically wrapped as 'Invoke-RestMethod -Uri <url> | Invoke-Expression'.
        All entries are joined and executed together in one child process.

    .PARAMETER InvokeStartupCommandNoExit
        When specified, the child PowerShell window launched for InvokeStartupCommand
        remains open after the script completes (-NoExit).

    .PARAMETER InvokeStartupCommandEA
        Controls error handling when the InvokeStartupCommand child process fails or exits
        with a non-zero code. 'Continue' writes a warning and proceeds; 'Stop' throws
        a terminating error. Default is 'Continue'.

    .PARAMETER InvokeMainCommand
        One or more PowerShell command lines or URLs to execute during the main phase
        in a single child PowerShell process. Entries beginning with 'http://' or
        'https://' are automatically wrapped as
        'Invoke-RestMethod -Uri <url> | Invoke-Expression'. All entries are joined
        and executed together in one child process.

    .PARAMETER InvokeMainCommandNoExit
        When specified, the child PowerShell window launched for InvokeMainCommand
        remains open after the script completes (-NoExit).

    .PARAMETER InvokeMainCommandEA
        Controls error handling when the InvokeMainCommand child process fails or exits
        with a non-zero code. 'Continue' writes a warning and proceeds; 'Stop' throws
        a terminating error. Default is 'Continue'.

    .PARAMETER InvokeShutdownCommand
        One or more PowerShell command lines or URLs to execute during the shutdown
        phase in a single child PowerShell process. Entries beginning with 'http://'
        or 'https://' are automatically wrapped as
        'Invoke-RestMethod -Uri <url> | Invoke-Expression'. All entries are joined
        and executed together in one child process.

    .PARAMETER InvokeShutdownCommandNoExit
        When specified, the child PowerShell window launched for InvokeShutdownCommand
        remains open after the script completes (-NoExit).

    .PARAMETER InvokeShutdownCommandEA
        Controls error handling when the InvokeShutdownCommand child process fails or exits
        with a non-zero code. 'Continue' writes a warning and proceeds; 'Stop' throws
        a terminating error. Default is 'Continue'.

    .OUTPUTS
        System.Void

    .NOTES
        Author:  David Segura
        Module:  OSDCloud
        This function is intended for WinPE scenarios.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
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
        [string[]]$InstallModule,

        [Parameter()]
        [string[]]$InvokeStartupCommand,

        [Parameter()]
        [switch]$InvokeStartupCommandNoExit,

        [Parameter()]
        [ValidateSet('Continue', 'Stop')]
        [string]$InvokeStartupCommandEA = 'Continue',

        [Parameter()]
        [string[]]$InvokeMainCommand,

        [Parameter()]
        [switch]$InvokeMainCommandNoExit,

        [Parameter()]
        [ValidateSet('Continue', 'Stop')]
        [string]$InvokeMainCommandEA = 'Continue',

        [Parameter()]
        [string[]]$InvokeShutdownCommand,

        [Parameter()]
        [switch]$InvokeShutdownCommandNoExit,

        [Parameter()]
        [ValidateSet('Continue', 'Stop')]
        [string]$InvokeShutdownCommandEA = 'Continue'
    )

    begin {
        $Error.Clear()
        $skipExecution = $false
        $startupTranscriptStarted = $false

        if ($env:SystemDrive -ne 'X:') {
            Write-Warning 'Invoke-WinpeStartup: Not running in WinPE (SystemDrive is not X:). Exiting.'
            $skipExecution = $true
            return
        }

        $startupLogPath = 'X:\Windows\Temp\winpestartup.log'
        try {
            $startupLogDirectory = Split-Path -Path $startupLogPath -Parent
            if (-not (Test-Path -LiteralPath $startupLogDirectory -PathType Container)) {
                New-Item -Path $startupLogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }

            $null = Start-Transcript -Path $startupLogPath -Force -ErrorAction Stop
            $startupTranscriptStarted = $true
        }
        catch {
            Write-Warning "Invoke-WinpeStartup: Failed to start log '$startupLogPath': $($_.Exception.Message)"
        }

        $switchLikeParameters = @(
            'SkipOnScreenKeyboard',
            'ShowPnpDevices',
            'ShowPnpErrors',
            'SkipWiFi',
            'SkipIPConfig',
            'SkipUpdateOSDCloud',
            'InvokeStartupCommandNoExit',
            'InvokeMainCommandNoExit',
            'InvokeShutdownCommandNoExit'
        )

        $arrayParameters = @(
            'InstallModule',
            'InvokeStartupCommand',
            'InvokeMainCommand',
            'InvokeShutdownCommand'
        )

        $stringParameters = @(
            'InvokeStartupCommandEA',
            'InvokeMainCommandEA',
            'InvokeShutdownCommandEA'
        )

        $knownParameters = @($switchLikeParameters + $arrayParameters + $stringParameters)
        $defaultsPrefix = 'Invoke-WinpeStartup:'
        $resolvedDefaults = [ordered]@{}
        $selectedProfile = $null
        $profileEnvironment = $null

        # Snapshot the parameter names that were pre-bound via $global:PSDefaultParameterValues.
        # These must not block profile overrides — only truly explicit caller args should win.
        $globalPreBoundParameters = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($globalKey in $global:PSDefaultParameterValues.Keys) {
            if ($globalKey -like "$($defaultsPrefix)*") {
                [void]$globalPreBoundParameters.Add($globalKey.Substring($defaultsPrefix.Length))
            }
        }

        function ConvertFrom-WinpeStartupJsonContent {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [string]$RawContent
            )

            $sanitizedJson = $RawContent -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/'
            return (ConvertFrom-Json -InputObject $sanitizedJson -ErrorAction Stop)
        }

        function ConvertTo-WinpeStartupBoolean {
            [CmdletBinding()]
            param (
                [Parameter()]
                $Value
            )

            if ($Value -is [bool]) {
                return $Value
            }

            if ($Value -is [System.Management.Automation.SwitchParameter]) {
                return $Value.IsPresent
            }

            if ($Value -is [string]) {
                switch -Regex ($Value.Trim()) {
                    '^(?i:true|1|yes|y|on)$' {
                        return $true
                    }
                    '^(?i:false|0|no|n|off)$' {
                        return $false
                    }
                    default {
                        return [bool]$Value
                    }
                }
            }

            if ($null -eq $Value) {
                return $false
            }

            return [bool]$Value
        }

        function ConvertTo-WinpeStartupStringArray {
            [CmdletBinding()]
            param (
                [Parameter()]
                $Value
            )

            if ($null -eq $Value) {
                return @()
            }

            if ($Value -is [string]) {
                return @(
                    ($Value -split "(`r`n|`n|`r)") |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )
            }

            if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
                return @(
                    $Value |
                        ForEach-Object { [string]$_ } |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )
            }

            return @([string]$Value)
        }

        function Set-WinpeStartupProfileEnvironment {
            [CmdletBinding()]
            param (
                [Parameter()]
                $InputObject,

                [Parameter(Mandatory = $true)]
                [string]$SourceName
            )

            if ($InputObject -isnot [System.Management.Automation.PSCustomObject] -and $InputObject -isnot [System.Collections.IDictionary]) {
                Write-Warning "Invoke-WinpeStartup: Skipping invalid Environment section from '$SourceName'. Expected a JSON object."
                return
            }

            $entries = @()

            if ($InputObject -is [System.Collections.IDictionary]) {
                foreach ($entry in $InputObject.GetEnumerator()) {
                    $entries += [pscustomobject]@{
                        Name  = [string]$entry.Key
                        Value = $entry.Value
                    }
                }
            }
            else {
                foreach ($property in $InputObject.PSObject.Properties) {
                    $entries += [pscustomobject]@{
                        Name  = [string]$property.Name
                        Value = $property.Value
                    }
                }
            }

            foreach ($entry in $entries) {
                if ([string]::IsNullOrWhiteSpace($entry.Name) -or $entry.Name.Contains('=') -or $entry.Name.Contains([char]0)) {
                    Write-Warning "Invoke-WinpeStartup: Skipping invalid environment variable name from '$SourceName'."
                    continue
                }

                if ($null -eq $entry.Value -or $entry.Value -isnot [System.IConvertible]) {
                    Write-Warning "Invoke-WinpeStartup: Skipping unsupported value for environment variable '$($entry.Name)' from '$SourceName'. Expected a string, number, or boolean."
                    continue
                }

                try {
                    $environmentValue = [System.Convert]::ToString($entry.Value, [System.Globalization.CultureInfo]::InvariantCulture)
                    [System.Environment]::SetEnvironmentVariable($entry.Name, $environmentValue, [System.EnvironmentVariableTarget]::Process)
                    Write-Verbose "Invoke-WinpeStartup: Set process environment variable '$($entry.Name)' from '$SourceName'."
                }
                catch {
                    Write-Warning "Invoke-WinpeStartup: Failed to set environment variable '$($entry.Name)' from '$SourceName': $($_.Exception.Message)"
                }
            }
        }

        function Add-WinpeStartupDefaults {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                $InputObject,

                [Parameter(Mandatory = $true)]
                [string]$SourceName,

                [Parameter(Mandatory = $true)]
                [ValidateSet('Prefixed', 'Splat', 'Any')]
                [string]$KeyFormat
            )

            $entries = @()

            if ($InputObject -is [System.Collections.IDictionary]) {
                foreach ($entry in $InputObject.GetEnumerator()) {
                    $entries += [pscustomobject]@{
                        Name  = [string]$entry.Key
                        Value = $entry.Value
                    }
                }
            }
            else {
                foreach ($property in $InputObject.PSObject.Properties) {
                    $entries += [pscustomobject]@{
                        Name  = [string]$property.Name
                        Value = $property.Value
                    }
                }
            }

            foreach ($entry in $entries) {
                if ([string]::IsNullOrWhiteSpace($entry.Name)) {
                    Write-Warning "Invoke-WinpeStartup: Skipping empty key from '$SourceName'."
                    continue
                }

                if ($KeyFormat -eq 'Any' -and $entry.Name -in @('env', 'Environment')) {
                    continue
                }

                if ($entry.Value -is [System.Management.Automation.PSCustomObject] -or $entry.Value -is [System.Collections.IDictionary]) {
                    Write-Warning "Invoke-WinpeStartup: Skipping nested object value for '$($entry.Name)' from '$SourceName'. Profiles and defaults must be flat key-value maps."
                    continue
                }

                $parameterName = $entry.Name
                $hasPrefix = $parameterName.StartsWith($defaultsPrefix, [System.StringComparison]::OrdinalIgnoreCase)

                if ($KeyFormat -eq 'Prefixed' -and -not $hasPrefix) {
                    Write-Verbose "Invoke-WinpeStartup: Ignoring non-prefixed key '$($entry.Name)' from '$SourceName'."
                    continue
                }

                if ($KeyFormat -eq 'Splat' -and $hasPrefix) {
                    Write-Verbose "Invoke-WinpeStartup: Ignoring prefixed key '$($entry.Name)' from '$SourceName'."
                    continue
                }

                if ($hasPrefix) {
                    $parameterName = $parameterName.Substring($defaultsPrefix.Length)
                }

                if ([string]::IsNullOrWhiteSpace($parameterName)) {
                    continue
                }

                if ($knownParameters -notcontains $parameterName) {
                    Write-Verbose "Invoke-WinpeStartup: Ignoring unknown default key '$($entry.Name)' from '$SourceName'."
                    continue
                }

                $resolvedDefaults[$parameterName] = $entry.Value
            }
        }

        if (Test-Path -LiteralPath $Script:OSDCloudPSDefaultParameterValuesPath -PathType Leaf) {
            try {
                $rawDefaults = Get-Content -LiteralPath $Script:OSDCloudPSDefaultParameterValuesPath -Raw -ErrorAction Stop
                $moduleDefaults = ConvertFrom-WinpeStartupJsonContent -RawContent $rawDefaults
                Add-WinpeStartupDefaults -InputObject $moduleDefaults -SourceName $Script:OSDCloudPSDefaultParameterValuesPath -KeyFormat Prefixed
            }
            catch {
                Write-Warning "Invoke-WinpeStartup: Failed to load defaults from '$Script:OSDCloudPSDefaultParameterValuesPath': $($_.Exception.Message)"
            }
        }

        # Initialize WinPE environment (shell folders, env vars, registry)
        Initialize-WinpeStartupEnvironment

        # Load drivers from WinpeStartup\Drivers on attached drives
        Initialize-WinpeStartupDrivers

        # Copy files from WinpeStartup\Files on attached drives into the RAM disk
        Initialize-WinpeStartupFiles

        # Run wpeinit and wpeutil commands and wait for initialization to complete
        Initialize-WinpeStartupMain
        Start-Sleep -Seconds 3

        $candidateProfiles = @(Get-WinpeStartupProfileCandidates)

        if ($candidateProfiles.Count -gt 0) {
            # Force array semantics so .Count and indexing behave reliably on PS 5.1 even with a single item.
            $orderedProfiles = @($candidateProfiles | Sort-Object Path)
            $currentIndex = 1

            foreach ($menuEntry in $orderedProfiles) {
                $menuEntry.Index = $currentIndex
                $currentIndex += 1
            }

            # Use the underlying list's Count, which is always reliable, to decide auto-select vs. prompt.
            if ($candidateProfiles.Count -eq 1) {
                $selectedProfile = $orderedProfiles[0]
                Write-Verbose "Invoke-WinpeStartup: Auto-selected only available profile '$($selectedProfile.Path)'"
            }
            else {
                Write-Host ''
                Write-Host -ForegroundColor Cyan 'WinpeStartup Profiles:'
                $orderedProfiles |
                    Select-Object Index, Profile, Path |
                    Format-Table -AutoSize | Out-String | Write-Host

                while (-not $selectedProfile) {
                    $selection = Read-Host 'Select a profile by number, or press Enter to cancel'

                    if ([string]::IsNullOrWhiteSpace($selection)) {
                        Write-Warning 'Invoke-WinpeStartup: Profile selection cancelled.'
                        $skipExecution = $true
                        return
                    }

                    if ($selection -match '^(?i)q(?:uit)?$') {
                        Write-Warning 'Invoke-WinpeStartup: Profile selection cancelled.'
                        $skipExecution = $true
                        return
                    }

                    $selectedIndex = 0
                    if ([int]::TryParse($selection, [ref]$selectedIndex)) {
                        $selectedProfile = $orderedProfiles | Where-Object { $_.Index -eq $selectedIndex } | Select-Object -First 1
                    }

                    if (-not $selectedProfile) {
                        Write-Warning "Invoke-WinpeStartup: Invalid selection '$selection'."
                    }
                }
            }
        }

        if ($selectedProfile) {
            Write-Verbose "Invoke-WinpeStartup: Selected profile '$($selectedProfile.Path)'"
            try {
                $rawProfile = Get-Content -LiteralPath $selectedProfile.Path -Raw -ErrorAction Stop
                $profileDefaults = ConvertFrom-WinpeStartupJsonContent -RawContent $rawProfile
                $environmentProperties = @($profileDefaults.PSObject.Properties | Where-Object { $_.Name -in @('env', 'Environment') })

                if ($environmentProperties.Count -gt 1) {
                    throw "Profile cannot contain both 'env' and 'Environment' properties."
                }

                $environmentProperty = $environmentProperties | Select-Object -First 1

                if ($environmentProperty) {
                    $profileEnvironment = $environmentProperty.Value
                }

                Add-WinpeStartupDefaults -InputObject $profileDefaults -SourceName $selectedProfile.Path -KeyFormat Any
                Write-Host "WinPE profile applied: $($selectedProfile.Path)"
            }
            catch {
                Write-Warning "Invoke-WinpeStartup: Failed to load profile '$($selectedProfile.Path)': $($_.Exception.Message)"
                $skipExecution = $true
                return
            }
        }

        foreach ($parameterName in $knownParameters) {
            if ($PSBoundParameters.ContainsKey($parameterName) -and -not $globalPreBoundParameters.Contains($parameterName)) {
                Write-Verbose "Invoke-WinpeStartup: Skipping JSON default '$parameterName' because it is already bound."
                continue
            }

            if (-not $resolvedDefaults.Contains($parameterName)) {
                continue
            }

            $parameterValue = $resolvedDefaults[$parameterName]

            switch ($parameterName) {
                'SkipOnScreenKeyboard' {
                    $SkipOnScreenKeyboard = ConvertTo-WinpeStartupBoolean -Value $parameterValue
                }
                'ShowPnpDevices' {
                    $ShowPnpDevices = ConvertTo-WinpeStartupBoolean -Value $parameterValue
                }
                'ShowPnpErrors' {
                    $ShowPnpErrors = ConvertTo-WinpeStartupBoolean -Value $parameterValue
                }
                'SkipWiFi' {
                    $SkipWiFi = ConvertTo-WinpeStartupBoolean -Value $parameterValue
                }
                'SkipIPConfig' {
                    $SkipIPConfig = ConvertTo-WinpeStartupBoolean -Value $parameterValue
                }
                'SkipUpdateOSDCloud' {
                    $SkipUpdateOSDCloud = ConvertTo-WinpeStartupBoolean -Value $parameterValue
                }
                'InstallModule' {
                    $InstallModule = ConvertTo-WinpeStartupStringArray -Value $parameterValue
                }
                'InvokeStartupCommand' {
                    $InvokeStartupCommand = ConvertTo-WinpeStartupStringArray -Value $parameterValue
                }
                'InvokeMainCommand' {
                    $InvokeMainCommand = ConvertTo-WinpeStartupStringArray -Value $parameterValue
                }
                'InvokeShutdownCommand' {
                    $InvokeShutdownCommand = ConvertTo-WinpeStartupStringArray -Value $parameterValue
                }
                'InvokeStartupCommandNoExit' {
                    $InvokeStartupCommandNoExit = ConvertTo-WinpeStartupBoolean -Value $parameterValue
                }
                'InvokeMainCommandNoExit' {
                    $InvokeMainCommandNoExit = ConvertTo-WinpeStartupBoolean -Value $parameterValue
                }
                'InvokeShutdownCommandNoExit' {
                    $InvokeShutdownCommandNoExit = ConvertTo-WinpeStartupBoolean -Value $parameterValue
                }
                'InvokeStartupCommandEA' {
                    if ($parameterValue -notin @('Continue', 'Stop')) {
                        Write-Warning "Invoke-WinpeStartup: Invalid value '$parameterValue' for 'InvokeStartupCommandEA' from JSON. Expected 'Continue' or 'Stop'. Skipping."
                    }
                    else {
                        $InvokeStartupCommandEA = [string]$parameterValue
                    }
                }
                'InvokeMainCommandEA' {
                    if ($parameterValue -notin @('Continue', 'Stop')) {
                        Write-Warning "Invoke-WinpeStartup: Invalid value '$parameterValue' for 'InvokeMainCommandEA' from JSON. Expected 'Continue' or 'Stop'. Skipping."
                    }
                    else {
                        $InvokeMainCommandEA = [string]$parameterValue
                    }
                }
                'InvokeShutdownCommandEA' {
                    if ($parameterValue -notin @('Continue', 'Stop')) {
                        Write-Warning "Invoke-WinpeStartup: Invalid value '$parameterValue' for 'InvokeShutdownCommandEA' from JSON. Expected 'Continue' or 'Stop'. Skipping."
                    }
                    else {
                        $InvokeShutdownCommandEA = [string]$parameterValue
                    }
                }
            }

            Write-Verbose "Invoke-WinpeStartup: Applied default '$parameterName' from JSON configuration."
        }

        if ($selectedProfile -and $environmentProperty) {
            Set-WinpeStartupProfileEnvironment -InputObject $profileEnvironment -SourceName $selectedProfile.Path
        }

        Write-Verbose 'Invoke-WinpeStartup: Starting full WinpeStartup sequence'
    }

    process {
        if ($skipExecution) { return }

        try {
        # On Screen Keyboard if one is not detected
        if (-not $SkipOnScreenKeyboard) {
            Invoke-WinpeStartupManager OSK
        }

        if ($ShowPnpDevices) {
            Invoke-WinpeStartupManager DeviceHardware
        }

        if ($ShowPnpErrors) {
            Invoke-WinpeStartupManager DeviceErrors
        }

        if (-not $SkipWiFi) {
            Invoke-WinpeStartupManager WiFi
        }

        if (-not $SkipIPConfig) {
            Invoke-WinpeStartupManager IPConfig
        }

        if ($InstallModule) {
            foreach ($module in $InstallModule) {
                Invoke-WinpeStartupManager UpdateModule -Value $module
            }
        }

        if (-not $SkipUpdateOSDCloud) {
            Invoke-WinpeStartupManager UpdateModule -Value OSDCloud
        }

        if ($InvokeStartupCommand) {
            $startupCommandList = $InvokeStartupCommand | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            if ($startupCommandList) {
                $commandFailed = $null
                try {
                    $scriptLines = foreach ($entry in $startupCommandList) {
                        if ($entry -match '^https?://') {
                            $escapedUrl = $entry.Replace("'", "''")
                            "Invoke-RestMethod -Uri '$escapedUrl' | Invoke-Expression"
                        }
                        else {
                            $entry
                        }
                    }
                    $invokeCommand = $scriptLines -join [Environment]::NewLine
                    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($invokeCommand))
                    $psArgs = [System.Collections.Generic.List[string]]::new()
                    [void]$psArgs.Add('-NoLogo')
                    [void]$psArgs.Add('-NoProfile')
                    [void]$psArgs.Add('-ExecutionPolicy')
                    [void]$psArgs.Add('Bypass')
                    if ($InvokeStartupCommandNoExit) { [void]$psArgs.Add('-NoExit') }
                    [void]$psArgs.Add('-EncodedCommand')
                    [void]$psArgs.Add($encodedCommand)
                    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -PassThru -Wait -ErrorAction Stop

                    if ($process.ExitCode -ne 0) {
                        $commandFailed = "Step 11: InvokeStartupCommand session exited with code $($process.ExitCode)."
                    }
                }
                catch {
                    $commandFailed = "Step 11: Failed InvokeStartupCommand session. $_"
                }

                if ($commandFailed) {
                    if ($InvokeStartupCommandEA -eq 'Stop') {
                        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($commandFailed),
                            'InvokeStartupCommandFailed',
                            [System.Management.Automation.ErrorCategory]::InvalidOperation,
                            $startupCommandList
                        )
                        $PSCmdlet.ThrowTerminatingError($errorRecord)
                    }
                    else {
                        Write-Warning "$commandFailed Continuing."
                    }
                }
            }
        }

        if ($InvokeMainCommand) {
            $mainCommandList = $InvokeMainCommand | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            if ($mainCommandList) {
                $commandFailed = $null
                try {
                    $scriptLines = foreach ($entry in $mainCommandList) {
                        if ($entry -match '^https?://') {
                            $escapedUrl = $entry.Replace("'", "''")
                            "Invoke-RestMethod -Uri '$escapedUrl' | Invoke-Expression"
                        }
                        else {
                            $entry
                        }
                    }
                    $invokeCommand = $scriptLines -join [Environment]::NewLine
                    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($invokeCommand))
                    $psArgs = [System.Collections.Generic.List[string]]::new()
                    [void]$psArgs.Add('-NoLogo')
                    [void]$psArgs.Add('-NoProfile')
                    [void]$psArgs.Add('-ExecutionPolicy')
                    [void]$psArgs.Add('Bypass')
                    if ($InvokeMainCommandNoExit) { [void]$psArgs.Add('-NoExit') }
                    [void]$psArgs.Add('-EncodedCommand')
                    [void]$psArgs.Add($encodedCommand)
                    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -PassThru -Wait -ErrorAction Stop

                    if ($process.ExitCode -ne 0) {
                        $commandFailed = "Step 15: InvokeMainCommand session exited with code $($process.ExitCode)."
                    }
                }
                catch {
                    $commandFailed = "Step 15: Failed InvokeMainCommand session. $_"
                }

                if ($commandFailed) {
                    if ($InvokeMainCommandEA -eq 'Stop') {
                        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($commandFailed),
                            'InvokeMainCommandFailed',
                            [System.Management.Automation.ErrorCategory]::InvalidOperation,
                            $mainCommandList
                        )
                        $PSCmdlet.ThrowTerminatingError($errorRecord)
                    }
                    else {
                        Write-Warning "$commandFailed Continuing."
                    }
                }
            }
        }

        if ($InvokeShutdownCommand) {
            $shutdownCommandList = $InvokeShutdownCommand | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            if ($shutdownCommandList) {
                $commandFailed = $null
                try {
                    $scriptLines = foreach ($entry in $shutdownCommandList) {
                        if ($entry -match '^https?://') {
                            $escapedUrl = $entry.Replace("'", "''")
                            "Invoke-RestMethod -Uri '$escapedUrl' | Invoke-Expression"
                        }
                        else {
                            $entry
                        }
                    }
                    $invokeCommand = $scriptLines -join [Environment]::NewLine
                    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($invokeCommand))
                    $psArgs = [System.Collections.Generic.List[string]]::new()
                    [void]$psArgs.Add('-NoLogo')
                    [void]$psArgs.Add('-NoProfile')
                    [void]$psArgs.Add('-ExecutionPolicy')
                    [void]$psArgs.Add('Bypass')
                    if ($InvokeShutdownCommandNoExit) { [void]$psArgs.Add('-NoExit') }
                    [void]$psArgs.Add('-EncodedCommand')
                    [void]$psArgs.Add($encodedCommand)
                    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -PassThru -Wait -ErrorAction Stop

                    if ($process.ExitCode -ne 0) {
                        $commandFailed = "Step 20: InvokeShutdownCommand session exited with code $($process.ExitCode)."
                    }
                }
                catch {
                    $commandFailed = "Step 20: Failed InvokeShutdownCommand session. $_"
                }

                if ($commandFailed) {
                    if ($InvokeShutdownCommandEA -eq 'Stop') {
                        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($commandFailed),
                            'InvokeShutdownCommandFailed',
                            [System.Management.Automation.ErrorCategory]::InvalidOperation,
                            $shutdownCommandList
                        )
                        $PSCmdlet.ThrowTerminatingError($errorRecord)
                    }
                    else {
                        Write-Warning "$commandFailed Continuing."
                    }
                }
            }
        }
        }
        finally {
            if ($startupTranscriptStarted) {
                try {
                    $null = Stop-Transcript -ErrorAction Stop
                }
                catch {
                    Write-Warning "Invoke-WinpeStartup: Failed to stop log '$startupLogPath': $($_.Exception.Message)"
                }
                $startupTranscriptStarted = $false
            }
        }
    }

    end {
        if (-not $skipExecution) {
            Write-Verbose 'Invoke-WinpeStartup: Complete'
        }

        if ($startupTranscriptStarted) {
            try {
                $null = Stop-Transcript -ErrorAction Stop
            }
            catch {
                Write-Warning "Invoke-WinpeStartup: Failed to stop log '$startupLogPath': $($_.Exception.Message)"
            }
            $startupTranscriptStarted = $false
        }
    }
}
