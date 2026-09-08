#requires -Version 5.1

function Invoke-WinPEStartup {
    <#
    .SYNOPSIS
        Runs the WinPEStartup workflow for OSDCloud.

    .DESCRIPTION
        Executes the OSDCloud WinPEStartup sequence from a single entry point.
        The function can optionally load defaults from module JSON, discover and
        apply a startup profile, and then run startup steps in order including
        environment setup, drivers, files, hardware checks, connectivity, module
        updates, script execution, and optional URL/command invocations.

        This function only runs in WinPE where SystemDrive is X:. If it is called
        outside WinPE, it writes a warning and exits without running startup steps.

    .EXAMPLE
        Invoke-WinPEStartup

        Runs the startup workflow with default behavior.

    .EXAMPLE
        Invoke-WinPEStartup -Verbose

        Runs the startup workflow and writes verbose progress details.

    .EXAMPLE
        Invoke-WinPEStartup -SkipWiFi -SkipIPConfig

        Runs startup but skips Wi-Fi and IP configuration display steps.

    .PARAMETER SkipOnScreenKeyboard
        Skips launching the on-screen keyboard check.

    .PARAMETER ShowPnpDevices
        Shows the Plug and Play device hardware window (`Show-WinPEStartupDevices`). By default this window is not displayed.

    .PARAMETER ShowPnpErrors
        Shows the Plug and Play device error window (`Show-WinPEStartupDeviceErrors`). By default this window is not displayed.

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

        if ($env:SystemDrive -ne 'X:') {
            Write-Warning 'Invoke-WinPEStartup: Not running in WinPE (SystemDrive is not X:). Exiting.'
            $skipExecution = $true
            return
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
        $defaultsPrefix = 'Invoke-WinPEStartup:'
        $resolvedDefaults = [ordered]@{}
        $selectedProfile = $null

        # Snapshot the parameter names that were pre-bound via $global:PSDefaultParameterValues.
        # These must not block profile overrides — only truly explicit caller args should win.
        $globalPreBoundParameters = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($globalKey in $global:PSDefaultParameterValues.Keys) {
            if ($globalKey -like "$($defaultsPrefix)*") {
                [void]$globalPreBoundParameters.Add($globalKey.Substring($defaultsPrefix.Length))
            }
        }

        function ConvertFrom-WinPEStartupJsonContent {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [string]$RawContent
            )

            $sanitizedJson = $RawContent -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/'
            return (ConvertFrom-Json -InputObject $sanitizedJson -ErrorAction Stop)
        }

        function ConvertTo-WinPEStartupBoolean {
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

        function ConvertTo-WinPEStartupStringArray {
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

        function Add-WinPEStartupDefaults {
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
                    Write-Warning "Invoke-WinPEStartup: Skipping empty key from '$SourceName'."
                    continue
                }

                if ($entry.Value -is [System.Management.Automation.PSCustomObject] -or $entry.Value -is [System.Collections.IDictionary]) {
                    Write-Warning "Invoke-WinPEStartup: Skipping nested object value for '$($entry.Name)' from '$SourceName'. Profiles and defaults must be flat key-value maps."
                    continue
                }

                $parameterName = $entry.Name
                $hasPrefix = $parameterName.StartsWith($defaultsPrefix, [System.StringComparison]::OrdinalIgnoreCase)

                if ($KeyFormat -eq 'Prefixed' -and -not $hasPrefix) {
                    Write-Verbose "Invoke-WinPEStartup: Ignoring non-prefixed key '$($entry.Name)' from '$SourceName'."
                    continue
                }

                if ($KeyFormat -eq 'Splat' -and $hasPrefix) {
                    Write-Verbose "Invoke-WinPEStartup: Ignoring prefixed key '$($entry.Name)' from '$SourceName'."
                    continue
                }

                if ($hasPrefix) {
                    $parameterName = $parameterName.Substring($defaultsPrefix.Length)
                }

                if ([string]::IsNullOrWhiteSpace($parameterName)) {
                    continue
                }

                if ($knownParameters -notcontains $parameterName) {
                    Write-Verbose "Invoke-WinPEStartup: Ignoring unknown default key '$($entry.Name)' from '$SourceName'."
                    continue
                }

                $resolvedDefaults[$parameterName] = $entry.Value
            }
        }

        if (Test-Path -LiteralPath $Script:OSDCloudPSDefaultParameterValuesPath -PathType Leaf) {
            try {
                $rawDefaults = Get-Content -LiteralPath $Script:OSDCloudPSDefaultParameterValuesPath -Raw -ErrorAction Stop
                $moduleDefaults = ConvertFrom-WinPEStartupJsonContent -RawContent $rawDefaults
                Add-WinPEStartupDefaults -InputObject $moduleDefaults -SourceName $Script:OSDCloudPSDefaultParameterValuesPath -KeyFormat Prefixed
            }
            catch {
                Write-Warning "Invoke-WinPEStartup: Failed to load defaults from '$Script:OSDCloudPSDefaultParameterValuesPath': $($_.Exception.Message)"
            }
        }

        # Initialize WinPE environment (shell folders, env vars, registry)
        Initialize-WinPEStartupEnvironment

        # Load drivers from WinPEStartup\Drivers on attached drives
        Initialize-WinPEStartupDrivers

        # Copy files from WinPEStartup\Files on attached drives into the RAM disk
        Initialize-WinPEStartupFiles

        # Run wpeinit and wpeutil commands and wait for initialization to complete
        Initialize-WinPEStartupMain
        Start-Sleep -Seconds 3

        $candidateProfiles = [System.Collections.Generic.List[object]]::new()

        foreach ($driveLetter in [char[]](67..90)) {
            $profileRoot = '{0}:\WinPEStartup\profiles' -f $driveLetter

            if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) {
                continue
            }

            try {
                $profileFiles = Get-ChildItem -LiteralPath $profileRoot -Filter '*.json' -File -ErrorAction Stop | Sort-Object FullName

                foreach ($profileFile in $profileFiles) {
                    [void]$candidateProfiles.Add([pscustomobject]@{
                        Index = 0
                        Name  = $profileFile.Name
                        Drive = '{0}:' -f $driveLetter
                        Path  = $profileFile.FullName
                    })
                }
            }
            catch {
                Write-Verbose "Invoke-WinPEStartup: Unable to enumerate '$profileRoot': $($_.Exception.Message)"
            }
        }

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
                Write-Verbose "Invoke-WinPEStartup: Auto-selected only available profile '$($selectedProfile.Path)'"
            }
            else {
                Write-Host ''
                Write-Host 'Available WinPEStartup profiles:'
                $orderedProfiles |
                    Select-Object Index, Name, Drive, Path |
                    Format-Table -AutoSize |
                    Out-String |
                    Write-Host

                while (-not $selectedProfile) {
                    $selection = Read-Host 'Select a profile by number, or press Enter to cancel'

                    if ([string]::IsNullOrWhiteSpace($selection)) {
                        Write-Warning 'Invoke-WinPEStartup: Profile selection cancelled.'
                        $skipExecution = $true
                        return
                    }

                    if ($selection -match '^(?i)q(?:uit)?$') {
                        Write-Warning 'Invoke-WinPEStartup: Profile selection cancelled.'
                        $skipExecution = $true
                        return
                    }

                    $selectedIndex = 0
                    if ([int]::TryParse($selection, [ref]$selectedIndex)) {
                        $selectedProfile = $orderedProfiles | Where-Object { $_.Index -eq $selectedIndex } | Select-Object -First 1
                    }

                    if (-not $selectedProfile) {
                        Write-Warning "Invoke-WinPEStartup: Invalid selection '$selection'."
                    }
                }
            }
        }

        if ($selectedProfile) {
            Write-Verbose "Invoke-WinPEStartup: Selected profile '$($selectedProfile.Path)'"
            try {
                $rawProfile = Get-Content -LiteralPath $selectedProfile.Path -Raw -ErrorAction Stop
                $profileDefaults = ConvertFrom-WinPEStartupJsonContent -RawContent $rawProfile
                Add-WinPEStartupDefaults -InputObject $profileDefaults -SourceName $selectedProfile.Path -KeyFormat Any
                Write-Host "WinPE profile applied: $($selectedProfile.Path)"
            }
            catch {
                Write-Warning "Invoke-WinPEStartup: Failed to load profile '$($selectedProfile.Path)': $($_.Exception.Message)"
                $skipExecution = $true
                return
            }
        }

        foreach ($parameterName in $knownParameters) {
            if ($PSBoundParameters.ContainsKey($parameterName) -and -not $globalPreBoundParameters.Contains($parameterName)) {
                Write-Verbose "Invoke-WinPEStartup: Skipping JSON default '$parameterName' because it is already bound."
                continue
            }

            if (-not $resolvedDefaults.Contains($parameterName)) {
                continue
            }

            $parameterValue = $resolvedDefaults[$parameterName]

            switch ($parameterName) {
                'SkipOnScreenKeyboard' {
                    $SkipOnScreenKeyboard = ConvertTo-WinPEStartupBoolean -Value $parameterValue
                }
                'ShowPnpDevices' {
                    $ShowPnpDevices = ConvertTo-WinPEStartupBoolean -Value $parameterValue
                }
                'ShowPnpErrors' {
                    $ShowPnpErrors = ConvertTo-WinPEStartupBoolean -Value $parameterValue
                }
                'SkipWiFi' {
                    $SkipWiFi = ConvertTo-WinPEStartupBoolean -Value $parameterValue
                }
                'SkipIPConfig' {
                    $SkipIPConfig = ConvertTo-WinPEStartupBoolean -Value $parameterValue
                }
                'SkipUpdateOSDCloud' {
                    $SkipUpdateOSDCloud = ConvertTo-WinPEStartupBoolean -Value $parameterValue
                }
                'InstallModule' {
                    $InstallModule = ConvertTo-WinPEStartupStringArray -Value $parameterValue
                }
                'InvokeStartupCommand' {
                    $InvokeStartupCommand = ConvertTo-WinPEStartupStringArray -Value $parameterValue
                }
                'InvokeMainCommand' {
                    $InvokeMainCommand = ConvertTo-WinPEStartupStringArray -Value $parameterValue
                }
                'InvokeShutdownCommand' {
                    $InvokeShutdownCommand = ConvertTo-WinPEStartupStringArray -Value $parameterValue
                }
                'InvokeStartupCommandNoExit' {
                    $InvokeStartupCommandNoExit = ConvertTo-WinPEStartupBoolean -Value $parameterValue
                }
                'InvokeMainCommandNoExit' {
                    $InvokeMainCommandNoExit = ConvertTo-WinPEStartupBoolean -Value $parameterValue
                }
                'InvokeShutdownCommandNoExit' {
                    $InvokeShutdownCommandNoExit = ConvertTo-WinPEStartupBoolean -Value $parameterValue
                }
                'InvokeStartupCommandEA' {
                    if ($parameterValue -notin @('Continue', 'Stop')) {
                        Write-Warning "Invoke-WinPEStartup: Invalid value '$parameterValue' for 'InvokeStartupCommandEA' from JSON. Expected 'Continue' or 'Stop'. Skipping."
                    }
                    else {
                        $InvokeStartupCommandEA = [string]$parameterValue
                    }
                }
                'InvokeMainCommandEA' {
                    if ($parameterValue -notin @('Continue', 'Stop')) {
                        Write-Warning "Invoke-WinPEStartup: Invalid value '$parameterValue' for 'InvokeMainCommandEA' from JSON. Expected 'Continue' or 'Stop'. Skipping."
                    }
                    else {
                        $InvokeMainCommandEA = [string]$parameterValue
                    }
                }
                'InvokeShutdownCommandEA' {
                    if ($parameterValue -notin @('Continue', 'Stop')) {
                        Write-Warning "Invoke-WinPEStartup: Invalid value '$parameterValue' for 'InvokeShutdownCommandEA' from JSON. Expected 'Continue' or 'Stop'. Skipping."
                    }
                    else {
                        $InvokeShutdownCommandEA = [string]$parameterValue
                    }
                }
            }

            Write-Verbose "Invoke-WinPEStartup: Applied default '$parameterName' from JSON configuration."
        }

        Write-Verbose 'Invoke-WinPEStartup: Starting full WinPEStartup sequence'
    }

    process {
        if ($skipExecution) { return }

        # On Screen Keyboard if one is not detected
        if (-not $SkipOnScreenKeyboard) {
            Invoke-WinPEStartupManager OSK
        }

        if ($ShowPnpDevices) {
            Invoke-WinPEStartupManager DeviceHardware
        }

        if ($ShowPnpErrors) {
            Invoke-WinPEStartupManager DeviceErrors
        }

        if (-not $SkipWiFi) {
            Invoke-WinPEStartupManager WiFi
        }

        if (-not $SkipIPConfig) {
            Invoke-WinPEStartupManager IPConfig
        }

        if ($InstallModule) {
            foreach ($module in $InstallModule) {
                Invoke-WinPEStartupManager UpdateModule -Value $module
            }
        }

        if (-not $SkipUpdateOSDCloud) {
            Invoke-WinPEStartupManager UpdateModule -Value OSDCloud
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

        # Initialize-WinPEStartupScript -FileName 'startup.cmd'

        # Initialize-WinPEStartupScript -FileName 'startup.ps1'

        # Initialize-WinPEStartupScript -FileName 'main.cmd'

        # Initialize-WinPEStartupScript -FileName 'main.ps1'

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

        # Initialize-WinPEStartupScript -NewProcess -NoExit -FileName 'main-wait.ps1'

        # Initialize-WinPEStartupScript -FileName 'shutdown.cmd'

        # Initialize-WinPEStartupScript -FileName 'shutdown.ps1'

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

    end {
        if ($skipExecution) { return }
        Write-Verbose 'Invoke-WinPEStartup: Complete'
    }
}
