<#
.SYNOPSIS
    Runs automated driver and update tasks before Windows OOBE continues.
.DESCRIPTION
    Self-contained inbox Windows PowerShell 5.1/WPF script for AMD64 and ARM64.
    Run synchronously at the end of OOBE.cmd as SYSTEM. If necessary, a copy of this script
    is launched as SYSTEM in the console session and attached to its input desktop.
    The sequence waits for Start, and after the tasks finish it waits for Continue to OOBE,
    then returns 0. Startup failures return 1.
    Shells are independent SYSTEM processes and remain open when the menu closes.
.PARAMETER Preview
    Simulates tasks and tools without network or system changes.
.PARAMETER InteractiveChild
    Internal session-launch flag. Not needed in OOBE.cmd.
.PARAMETER ReadyEvent
    Internal SYSTEM-only named event used to acknowledge a visible child window.
.EXAMPLE
    powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File .\OSDCloudPreOOBE.ps1
.EXAMPLE
    powershell.exe -NoLogo -NoProfile -STA -File .\OSDCloudPreOOBE.ps1 -Preview
.NOTES
    No OSDCloud module, external executable, or user logon required.
    Windows Update actions require network access to the configured update service.
    Dot-sourcing defines helpers only; it does not show UI or exit the caller.
#>
[CmdletBinding()]
param (
    [switch]$Preview,
    [Parameter(DontShow)][switch]$InteractiveChild,
    [Parameter(DontShow)]
    [ValidatePattern('^Global\\RecastOSDCloud\.OOBE\.[0-9a-f-]{36}$')]
    [string]$ReadyEvent
)

function Write-OOBEMenuLog {
    <#
    .SYNOPSIS
        Writes local menu diagnostics.
    .DESCRIPTION
        Appends a timestamp and process ID; log-write errors are reported to stderr.
    .PARAMETER Message
        Diagnostic message without credentials.
    .EXAMPLE
        Write-OOBEMenuLog -Message 'Menu closed.'
    .NOTES
        Preview diagnostics use the current user's TEMP, not Windows setup paths.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$Message)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] $Message"
    $logRoot = if ($Preview) { $env:TEMP } else { Join-Path $env:WINDIR 'Temp\osdcloud-logs' }
    try {
        [void][System.IO.Directory]::CreateDirectory($logRoot)
        [System.IO.File]::AppendAllText(
            (Join-Path $logRoot 'OSDCloudPreOOBE.log'),
            "[$(Get-Date -Format s)] [PID $PID] $Message`r`n",
            [System.Text.Encoding]::UTF8
        )
    }
    catch {
        Write-Error -Message "Could not write OOBE menu diagnostics: $($_.Exception.Message). Original message: $Message" -ErrorAction Continue
    }
}

function Get-OOBEMenuNativePath {
    <#
    .SYNOPSIS
        Resolves an inbox executable without WOW64 redirection.
    .DESCRIPTION
        Uses Sysnative only from a 32-bit process on a 64-bit installation.
    .PARAMETER PowerShell
        Returns Windows PowerShell instead of Command Prompt.
    .PARAMETER Notepad
        Returns the inbox Notepad executable.
    .EXAMPLE
        Get-OOBEMenuNativePath -PowerShell
    .NOTES
        Does not hard-code AMD64; applies equally to ARM64.
    #>
    [CmdletBinding()]
    param ([switch]$PowerShell, [switch]$Notepad)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Resolve native executable"
    $directory = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        'Sysnative'
    } else { 'System32' }
    if ($PowerShell -and $Notepad) { throw 'Select only one executable.' }
    $relativePath = if ($PowerShell) { 'WindowsPowerShell\v1.0\powershell.exe' } elseif ($Notepad) { 'notepad.exe' } else { 'cmd.exe' }
    $path = Join-Path (Join-Path $env:WINDIR $directory) $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Inbox executable is missing: $path"
    }
    return $path
}

function Set-OOBEMenuClock {
    <#
    .SYNOPSIS
        Applies explicitly selected local date, time, and Windows time zone.
    .DESCRIPTION
        Validates all input before changing the clock. Preview makes no changes.
        Daylight-saving gaps and ambiguous local times must be corrected first.
    .PARAMETER Date
        Selected calendar date.
    .PARAMETER Time
        Local time in 24-hour HH:mm:ss format.
    .PARAMETER TimeZoneId
        Windows time zone ID.
    .PARAMETER PreviewOnly
        Reports the intended change without applying it.
    .EXAMPLE
        Set-OOBEMenuClock -Date (Get-Date) -Time '14:30:00' -TimeZoneId 'UTC' -PreviewOnly
    .NOTES
        Called by the clock page; applying changes requires SYSTEM.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][datetime]$Date,
        [Parameter(Mandatory)][string]$Time,
        [Parameter(Mandatory)][string]$TimeZoneId,
        [switch]$PreviewOnly
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Validate clock settings"
    $parsedTime = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Time, 'HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$parsedTime)) {
        throw 'Enter time in 24-hour HH:mm:ss format, for example 14:30:00.'
    }
    $zone = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
    $localDate = [datetime]::SpecifyKind($Date.Date.Add($parsedTime.TimeOfDay), [DateTimeKind]::Unspecified)
    if ($zone.IsInvalidTime($localDate) -or $zone.IsAmbiguousTime($localDate)) {
        throw 'This local time falls in a daylight-saving gap or repeated hour. Select an unambiguous time.'
    }
    $utcDate = [TimeZoneInfo]::ConvertTimeToUtc($localDate, $zone)
    if ($utcDate.Year -lt 1601) { throw 'Windows system dates must be on or after 1601-01-01 UTC.' }
    $description = '{0:yyyy-MM-dd HH:mm:ss} ({1})' -f $localDate, $zone.Id
    if ($PreviewOnly) { return "Preview: would set $description." }
    if (-not (Get-OOBEMenuContext).IsSystem) { throw 'Clock changes require SYSTEM.' }
    Set-TimeZone -Id $zone.Id -ErrorAction Stop
    [TimeZoneInfo]::ClearCachedData()
    Write-OOBEMenuLog -Message "Time zone set to $($zone.Id); applying local date/time $localDate."
    # Windows PowerShell Set-Date calls SetLocalTime with the DateTime fields and ignores Kind,
    # so it must receive local time in the newly applied time zone, never UTC.
    Set-Date -Date ([datetime]::SpecifyKind($localDate, [DateTimeKind]::Local)) -ErrorAction Stop | Out-Null
    Write-OOBEMenuLog -Message "Date, time, and time zone set to $description."
    return "Date, time, and time zone set to $description."
}

function Write-OOBEMenuUpdateStatus {
    <#
    .SYNOPSIS
        Publishes update progress without accessing WPF from the worker.
    .DESCRIPTION
        Queues a message, updates the current status, and writes diagnostics.
    .PARAMETER State
        Synchronized update state shared with the menu.
    .PARAMETER Message
        Progress or error text.
    .EXAMPLE
        Write-OOBEMenuUpdateStatus -State $state -Message 'Searching for updates.'
    .NOTES
        Called on the update worker thread.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State, [Parameter(Mandatory)][string]$Message)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] $Message"
    $State.Status = $Message
    $State.Messages.Enqueue($Message)
    Write-OOBEMenuLog -Message $Message
}

function Get-OSDCloudPreOOBEErrorMessage {
    <#
    .SYNOPSIS
        Returns a short, user-facing error message.
    .DESCRIPTION
        Unwraps PowerShell method-invocation and aggregate wrappers and returns the innermost
        exception message on one line. Log the full exception separately for diagnostics.
    .PARAMETER Exception
        Exception to summarize.
    .EXAMPLE
        Get-OSDCloudPreOOBEErrorMessage -Exception $_.Exception
    .NOTES
        Never returns stack traces.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][Exception]$Exception)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Summarize $($Exception.GetType().FullName)"
    $inner = $Exception
    while ($inner.InnerException) { $inner = $inner.InnerException }
    return (($inner.Message -split '\r?\n')[0]).Trim()
}

function Invoke-OOBEMenuWindowsUpdate {
    <#
    .SYNOPSIS
        Downloads and installs applicable software or driver updates using inbox WUA.
    .DESCRIPTION
        Honors the configured update service. Excludes hidden and Preview updates
        and updates requiring user input. Accepts update EULAs for the technician's
        requested install. Checks search, download and individual installation
        results, reports failures and reboot requirements, and never reboots.
    .PARAMETER Type
        Software for Windows 11 updates, or Driver for driver updates.
    .PARAMETER State
        Synchronized status, message queue, cancellation and reboot state.
    .EXAMPLE
        Invoke-OOBEMenuWindowsUpdate -Type Driver -State $state
    .NOTES
        Runs on a dedicated STA runspace as SYSTEM, not on the WPF dispatcher.
        Cancellation is cooperative between WUA calls; never kills an installation.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][ValidateSet('Software', 'Driver')][string]$Type,
        [Parameter(Mandatory)][hashtable]$State
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start $Type updates"
    $owned = [Collections.Generic.List[object]]::new()
    $installed = 0
    $failed = 0
    $skipped = 0
    $State.Succeeded = $false
    try {
        if ($env:SystemDrive -eq 'X:' -or -not (Get-OOBEMenuContext).IsSystem) {
            throw 'Windows Update requires full Windows running as SYSTEM.'
        }
        $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        if ($os.InstallationType -ne 'Client' -or [int]$os.CurrentBuildNumber -lt 22000) {
            throw 'These update actions require Windows 11.'
        }
        if ($State.CancelRequested) {
            Write-OOBEMenuUpdateStatus -State $State -Message 'Updates cancelled before starting.'
            return
        }
        $session = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $owned.Add($session)
        $session.ClientApplicationID = 'Recast OSDCloud OOBE'
        $searcher = $session.CreateUpdateSearcher()
        $owned.Add($searcher)
        Write-OOBEMenuUpdateStatus -State $State -Message "Searching for $Type updates."
        $search = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='$Type'")
        $owned.Add($search)
        Write-OOBEMenuUpdateStatus -State $State -Message "WUA search result $($search.ResultCode); configured service selection $($searcher.ServerSelection)."
        if ([int]$search.ResultCode -ne 2) {
            throw "Update search did not succeed (result $($search.ResultCode)); no updates were installed."
        }
        $updates = $search.Updates
        $owned.Add($updates)
        Write-OOBEMenuUpdateStatus -State $State -Message "Applicable $Type updates: $($updates.Count)."
        $downloader = $session.CreateUpdateDownloader()
        $owned.Add($downloader)
        $installer = $session.CreateUpdateInstaller()
        $owned.Add($installer)
        $installer.ForceQuiet = $true
        $installer.AllowSourcePrompts = $false
        if ($installer.RebootRequiredBeforeInstallation) {
            $State.RebootRequired = $true
            throw 'Windows Update requires a reboot before installation. No reboot was initiated.'
        }
        for ($index = 0; $index -lt $updates.Count; $index++) {
            if ($State.CancelRequested) { break }
            $itemObjects = [Collections.Generic.List[object]]::new()
            try {
                $update = $updates.Item($index)
                $itemObjects.Add($update)
                $behavior = $update.InstallationBehavior
                $itemObjects.Add($behavior)
                $identity = $update.Identity
                if ($identity) { $itemObjects.Add($identity) }
                Write-OOBEMenuUpdateStatus -State $State -Message "Update $($index + 1): $($update.Title); identity $($identity.UpdateID); revision $($identity.RevisionNumber)."
                if ($update.Title -match 'Preview' -or $behavior.CanRequestUserInput) {
                    $skipped++
                    Write-OOBEMenuUpdateStatus -State $State -Message "Skipped: $($update.Title)"
                    continue
                }
                if (-not $update.EulaAccepted) { $update.AcceptEula() }
                $selection = New-Object -ComObject Microsoft.Update.UpdateColl -ErrorAction Stop
                $itemObjects.Add($selection)
                [void]$selection.Add($update)
                $downloader.Updates = $selection
                Write-OOBEMenuUpdateStatus -State $State -Message "Downloading $($index + 1)/$($updates.Count): $($update.Title)"
                $download = $downloader.Download()
                $itemObjects.Add($download)
                $downloadResult = $download.GetUpdateResult(0)
                $itemObjects.Add($downloadResult)
                Write-OOBEMenuUpdateStatus -State $State -Message "Download results: overall $($download.ResultCode), individual $($downloadResult.ResultCode), HRESULT $('0x{0:X8}' -f ([long]$downloadResult.HResult -band 0xFFFFFFFFL)), content present $($update.IsDownloaded)."
                if ([int]$download.ResultCode -ne 2 -or [int]$downloadResult.ResultCode -ne 2 -or -not $update.IsDownloaded) {
                    $code = '0x{0:X8}' -f ([long]$downloadResult.HResult -band 0xFFFFFFFFL)
                    throw "Download failed (result $($downloadResult.ResultCode), HRESULT $code)."
                }
                if ($State.CancelRequested) { break }
                $installer.Updates = $selection
                Write-OOBEMenuUpdateStatus -State $State -Message "Installing $($index + 1)/$($updates.Count): $($update.Title)"
                $State.InstallationActive = $true
                try { $install = $installer.Install() }
                finally { $State.InstallationActive = $false }
                $itemObjects.Add($install)
                $installResult = $install.GetUpdateResult(0)
                $itemObjects.Add($installResult)
                Write-OOBEMenuUpdateStatus -State $State -Message "Install results: overall $($install.ResultCode), individual $($installResult.ResultCode), reboot required $($install.RebootRequired -or $installResult.RebootRequired)."
                if ($install.RebootRequired -or $installResult.RebootRequired) { $State.RebootRequired = $true }
                $code = '0x{0:X8}' -f ([long]$installResult.HResult -band 0xFFFFFFFFL)
                if ([int]$install.ResultCode -ne 2 -or [int]$installResult.ResultCode -ne 2) {
                    throw "Installation failed or partially succeeded (result $($installResult.ResultCode), HRESULT $code)."
                }
                $installed++
                Write-OOBEMenuUpdateStatus -State $State -Message "Installed: $($update.Title) (HRESULT $code)."
            }
            catch {
                $failed++
                Write-OOBEMenuUpdateStatus -State $State -Message "Failed update $($index + 1) ($($update.Title)): $($_.Exception.Message)"
            }
            finally {
                for ($item = $itemObjects.Count - 1; $item -ge 0; $item--) {
                    if ([Runtime.InteropServices.Marshal]::IsComObject($itemObjects[$item])) {
                        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($itemObjects[$item])
                    }
                }
            }
        }
        $State.Succeeded = -not $State.CancelRequested -and $failed -eq 0
        $summary = if ($State.CancelRequested) { 'Cancelled.' } elseif ($updates.Count -eq 0) { 'No updates found.' } else { 'Finished.' }
        $summary += " Installed: $installed. Failed: $failed. Skipped: $skipped."
        if ($State.RebootRequired) { $summary += ' Reboot required; no reboot initiated.' }
        Write-OOBEMenuUpdateStatus -State $State -Message $summary
    }
    catch {
        $State.Succeeded = $false
        Write-OOBEMenuUpdateStatus -State $State -Message "Windows Update failed: $($_.Exception.Message)"
    }
    finally {
        for ($item = $owned.Count - 1; $item -ge 0; $item--) {
            if ([Runtime.InteropServices.Marshal]::IsComObject($owned[$item])) {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($owned[$item])
            }
        }
    }
}

function Get-OSDCloudPreOOBEClock {
    <#
    .SYNOPSIS
        Returns the running OS date, time and time zone.
    .DESCRIPTION
        Refreshes cached time zone data so changes made by the calendar tool or
        internet time synchronization are reflected, and formats the full local
        date and time using the running OS culture.
    .EXAMPLE
        (Get-OSDCloudPreOOBEClock).Text
    .NOTES
        Read-only; safe to call from the WPF dispatcher.
    #>
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Read clock"
    [TimeZoneInfo]::ClearCachedData()
    $zone = [TimeZoneInfo]::Local
    $utcNow = [datetime]::UtcNow
    $localNow = [datetime]::SpecifyKind([TimeZoneInfo]::ConvertTimeFromUtc($utcNow, $zone), [DateTimeKind]::Local)
    $zoneName = if ($zone.IsDaylightSavingTime($localNow)) { $zone.DaylightName } else { $zone.StandardName }
    $offset = $zone.GetUtcOffset($localNow)
    $sign = if ($offset -lt [TimeSpan]::Zero) { '-' } else { '+' }
    $text = '{0} {1} (UTC{2}{3})' -f $localNow.ToString('F', [Globalization.CultureInfo]::CurrentCulture), $zoneName, $sign, $offset.Duration().ToString('hh\:mm')
    return [pscustomobject]@{ Local = $localNow; Utc = $utcNow; TimeZoneId = $zone.Id; TimeZoneName = $zoneName; Text = $text }
}

function Sync-OSDCloudPreOOBETime {
    <#
    .SYNOPSIS
        Bootstraps the system clock from an internet HTTP Date header.
    .DESCRIPTION
        Uses the existing OSDCloud Google HTTP time-source convention without TLS,
        so an incorrect local date cannot prevent time retrieval. Requests are
        bounded and redirects or stale cached responses are rejected.
    .PARAMETER State
        Shared cancellation and diagnostic state.
    .EXAMPLE
        Sync-OSDCloudPreOOBETime -State $state
    .NOTES
        Requires SYSTEM. Does not change the time zone or disable TLS validation.
        HTTP time is unauthenticated; use only on trusted deployment networks.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Synchronize clock"
    if (-not (Get-OOBEMenuContext).IsSystem) { throw 'Internet time synchronization requires SYSTEM.' }
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if ($State.CancelRequested) { $State.Outcome = 'Cancelled'; return }
        $handler = [Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $false
        $handler.DefaultProxyCredentials = [Net.CredentialCache]::DefaultCredentials
        $client = New-Object -TypeName System.Net.Http.HttpClient -ArgumentList $handler -ErrorAction Stop
        $client.Timeout = [TimeSpan]::FromSeconds(5)
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Head, 'http://www.google.com')
        [void]$request.Headers.TryAddWithoutValidation('Cache-Control', 'no-cache, no-store')
        $response = $null
        try {
            Write-OOBEMenuUpdateStatus -State $State -Message "Retrieving internet time from http://www.google.com (attempt $attempt, five-second timeout)."
            $pending = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead)
            if (-not $pending.Wait(5000)) {
                $client.CancelPendingRequests()
                throw 'Internet time request timed out after five seconds.'
            }
            $response = $pending.GetAwaiter().GetResult()
            if ([int]$response.StatusCode -ne 200) { throw "Unexpected time-source status: $($response.StatusCode)." }
            if ($null -eq $response.Headers.Date) { throw 'Time source returned no HTTP Date header.' }
            if ($response.Headers.Age -and $response.Headers.Age.TotalSeconds -gt 60) { throw 'Time source returned a stale cached response.' }
            $utcTime = $response.Headers.Date.UtcDateTime
            if ($utcTime.Year -lt 2024) { throw "Time source returned an invalid Windows 11 deployment date: $utcTime." }
            if ($State.CancelRequested) { $State.Outcome = 'Cancelled'; return }
            [TimeZoneInfo]::ClearCachedData()
            $zone = [TimeZoneInfo]::Local
            $before = (Get-Date).ToUniversalTime()
            # Windows PowerShell Set-Date calls SetLocalTime and ignores Kind; convert UTC to the running OS time zone.
            $localTime = [datetime]::SpecifyKind([TimeZoneInfo]::ConvertTimeFromUtc($utcTime, $zone), [DateTimeKind]::Local)
            Write-OOBEMenuUpdateStatus -State $State -Message "Clock before: $($before.ToString('o')); internet UTC: $($utcTime.ToString('o')); correction: $(($utcTime - $before).TotalSeconds) seconds."
            Write-OOBEMenuUpdateStatus -State $State -Message "Setting local time $($localTime.ToString('F')) in time zone $($zone.Id) ($($zone.DisplayName))."
            Set-Date -Date $localTime -ErrorAction Stop | Out-Null
            $after = (Get-Date).ToUniversalTime()
            if ([Math]::Abs(($after - $utcTime).TotalSeconds) -gt 10) { throw "Clock verification failed; UTC after setting: $($after.ToString('o'))." }
            Write-OOBEMenuUpdateStatus -State $State -Message "Internet time synchronized; UTC now $($after.ToString('o')), local $($after.ToLocalTime().ToString('F')). Time zone $($zone.Id) unchanged."
            $State.Succeeded = $true
            $State.Outcome = 'Succeeded'
            return
        }
        catch {
            Write-OOBEMenuUpdateStatus -State $State -Message "Internet time attempt $attempt failed: $($_.Exception.GetBaseException().Message)"
            if ($attempt -eq 2) { throw }
        }
        finally {
            if ($response) { $response.Dispose() }
            $request.Dispose()
            $client.Dispose()
            $handler.Dispose()
        }
    }
}

function Test-OSDCloudPreOOBEConnectivity {
    <#
    .SYNOPSIS
        Verifies internet connectivity and HTTPS certificate validation.
    .DESCRIPTION
        First requests the Windows NCSI content over HTTP (as Windows does; this
        endpoint does not serve a matching HTTPS certificate) and rejects redirects
        and unexpected content. Then sends HEAD to the Windows Update service
        locator over HTTPS; any HTTP status proves TLS and the clock are usable.
        Uses the SYSTEM default proxy. Two attempts of at most five seconds per
        request; no network changes are made. When HTTPS certificate validation
        fails, logs TLS certificate-chain diagnostics and runs the ±1 hour clock
        test before reporting failure.
    .PARAMETER State
        Shared cancellation and diagnostic state.
    .PARAMETER Attempts
        Number of probe attempts (1 or 2).
    .PARAMETER NoDiagnostics
        Skips certificate troubleshooting; used by the clock test itself.
    .EXAMPLE
        Test-OSDCloudPreOOBEConnectivity -State $state
    .NOTES
        Endpoint blocking can cause an offline skip even with reachable WSUS.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][hashtable]$State,
        [ValidateRange(1, 2)][int]$Attempts = 2,
        [switch]$NoDiagnostics
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Check connectivity"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $reason = 'Cancelled'
    $certificateError = $false
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    for ($attempt = 1; $attempt -le $Attempts -and -not $State.CancelRequested; $attempt++) {
        $handler = [Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $false
        $handler.DefaultProxyCredentials = [Net.CredentialCache]::DefaultCredentials
        $client = New-Object -TypeName System.Net.Http.HttpClient -ArgumentList $handler -ErrorAction Stop
        $client.Timeout = [TimeSpan]::FromSeconds(5)
        $client.MaxResponseContentBufferSize = 64
        $response = $null
        $tlsResponse = $null
        try {
            [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('Cache-Control', 'no-cache')
            $request = $client.GetAsync('http://www.msftconnecttest.com/connecttest.txt')
            if (-not $request.Wait(5000)) {
                $client.CancelPendingRequests()
                throw 'Connectivity probe timed out after five seconds.'
            }
            $response = $request.GetAwaiter().GetResult()
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ([int]$response.StatusCode -eq 200 -and $content.Trim() -eq 'Microsoft Connect Test') {
                Write-OOBEMenuUpdateStatus -State $State -Message "Internet probe succeeded (attempt $attempt, $($watch.ElapsedMilliseconds) ms); checking HTTPS certificate validation."
                $tlsRequest = $client.GetAsync('https://sls.update.microsoft.com/', [Net.Http.HttpCompletionOption]::ResponseHeadersRead)
                if (-not $tlsRequest.Wait(5000)) {
                    $client.CancelPendingRequests()
                    throw 'HTTPS probe timed out after five seconds.'
                }
                $tlsResponse = $tlsRequest.GetAwaiter().GetResult()
                Write-OOBEMenuUpdateStatus -State $State -Message "HTTPS probe succeeded: https://sls.update.microsoft.com/ certificate valid (status $([int]$tlsResponse.StatusCode), $($watch.ElapsedMilliseconds) ms)."
                return [pscustomobject]@{ Connected = $true; Reason = 'Expected Microsoft content received and HTTPS certificate valid'; DurationMs = $watch.ElapsedMilliseconds }
            }
            $reason = "Unexpected connectivity response (status $($response.StatusCode)); possible captive portal."
        }
        catch {
            $reason = "Connectivity probe failed: $($_.Exception.GetBaseException().Message)"
            $inner = $_.Exception
            while ($inner) {
                if ($inner -is [Security.Authentication.AuthenticationException] -or $inner.Message -like '*certificate*') { $certificateError = $true }
                $inner = $inner.InnerException
            }
        }
        finally {
            if ($tlsResponse) { $tlsResponse.Dispose() }
            if ($response) { $response.Dispose() }
            $client.Dispose()
            $handler.Dispose()
        }
        Write-OOBEMenuUpdateStatus -State $State -Message "$reason Attempt $attempt, elapsed $($watch.ElapsedMilliseconds) ms; clock UTC $([datetime]::UtcNow.ToString('o'))."
    }
    if ($certificateError -and -not $NoDiagnostics -and -not $State.CancelRequested) {
        Write-OOBEMenuUpdateStatus -State $State -Message 'Certificate validation failed; starting TLS and clock troubleshooting.'
        try { Write-OSDCloudPreOOBETlsDiagnostic -State $State }
        catch { Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic failed: $($_.Exception.GetBaseException().Message)" }
        try {
            $retry = Test-OSDCloudPreOOBEClockShift -State $State
            if ($retry -and $retry.Connected) {
                return [pscustomobject]@{ Connected = $true; Reason = 'Connected after clock troubleshooting'; DurationMs = $watch.ElapsedMilliseconds }
            }
        }
        catch { Write-OOBEMenuUpdateStatus -State $State -Message "Clock troubleshooting failed: $($_.Exception.GetBaseException().Message)" }
    }
    return [pscustomobject]@{ Connected = $false; Reason = $reason; DurationMs = $watch.ElapsedMilliseconds; CertificateError = $certificateError }
}

function Set-OSDCloudPreOOBEUtcClock {
    <#
    .SYNOPSIS
        Sets the system clock to a UTC instant in the running OS time zone.
    .DESCRIPTION
        Windows PowerShell Set-Date calls SetLocalTime and ignores DateTimeKind,
        so the UTC instant is converted to local time first. Verifies the result.
    .PARAMETER UtcTime
        Target UTC time.
    .EXAMPLE
        Set-OSDCloudPreOOBEUtcClock -UtcTime ([datetime]::UtcNow.AddHours(1))
    .NOTES
        Requires SYSTEM. Does not change the time zone.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][datetime]$UtcTime)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Set clock"
    $UtcTime = [datetime]::SpecifyKind($UtcTime, [DateTimeKind]::Utc)
    [TimeZoneInfo]::ClearCachedData()
    $localTime = [datetime]::SpecifyKind([TimeZoneInfo]::ConvertTimeFromUtc($UtcTime, [TimeZoneInfo]::Local), [DateTimeKind]::Local)
    Set-Date -Date $localTime -ErrorAction Stop | Out-Null
    $after = (Get-Date).ToUniversalTime()
    if ([Math]::Abs(($after - $UtcTime).TotalSeconds) -gt 10) { throw "Clock verification failed; requested UTC $($UtcTime.ToString('o')), actual $($after.ToString('o'))." }
    return $after
}

function Test-OSDCloudPreOOBEClockShift {
    <#
    .SYNOPSIS
        Tests connectivity with the clock 1 hour forward and 1 hour back.
    .DESCRIPTION
        Troubleshoots certificate validation failures caused by clock or time
        zone offsets. Probes once at +1 hour and once at -1 hour, always restores
        the original clock (adjusted for elapsed time), then probes once more.
    .PARAMETER State
        Shared cancellation and diagnostic state.
    .EXAMPLE
        Test-OSDCloudPreOOBEClockShift -State $state
    .NOTES
        Requires SYSTEM. Clock changes from the calendar are blocked meanwhile.
        Returns the connectivity result after the clock is restored.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Clock shift test"
    if (-not (Get-OOBEMenuContext).IsSystem) {
        Write-OOBEMenuUpdateStatus -State $State -Message 'Clock shift test skipped: changing the clock requires SYSTEM.'
        return
    }
    $baseUtc = [datetime]::UtcNow
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $results = [Collections.Generic.List[string]]::new()
    $State.ClockTestActive = $true
    try {
        foreach ($hours in 1, -1) {
            if ($State.CancelRequested) { break }
            $shifted = Set-OSDCloudPreOOBEUtcClock -UtcTime ($baseUtc.AddHours($hours) + $watch.Elapsed)
            Write-OOBEMenuUpdateStatus -State $State -Message ("Clock test: shifted {0:+0;-0} hour; UTC now {1}, local {2}." -f $hours, $shifted.ToString('o'), $shifted.ToLocalTime().ToString('F'))
            $result = Test-OSDCloudPreOOBEConnectivity -State $State -Attempts 1 -NoDiagnostics
            $status = if ($result.Connected) { 'connected' } else { "failed: $($result.Reason)" }
            $results.Add(("{0:+0;-0} hour {1}" -f $hours, $status))
            Write-OOBEMenuUpdateStatus -State $State -Message ("Clock test {0:+0;-0} hour: {1}" -f $hours, $status)
        }
    }
    finally {
        try {
            $restored = Set-OSDCloudPreOOBEUtcClock -UtcTime ($baseUtc + $watch.Elapsed)
            Write-OOBEMenuUpdateStatus -State $State -Message "Clock test: restored UTC $($restored.ToString('o')), local $($restored.ToLocalTime().ToString('F'))."
        }
        catch { Write-OOBEMenuUpdateStatus -State $State -Message "Clock test: RESTORE FAILED, verify Date and Time manually: $($_.Exception.GetBaseException().Message)" }
        finally { $State.ClockTestActive = $false }
    }
    if ($State.CancelRequested) { return }
    $final = Test-OSDCloudPreOOBEConnectivity -State $State -Attempts 1 -NoDiagnostics
    $status = if ($final.Connected) { 'connected' } else { "failed: $($final.Reason)" }
    Write-OOBEMenuUpdateStatus -State $State -Message "Clock test summary: $($results -join '; '); restored clock $status."
    if (-not $final.Connected -and ($results -like '*connected')) {
        Write-OOBEMenuUpdateStatus -State $State -Message 'Clock test: connectivity works only with a shifted clock. Verify Date, Time and TimeZone with the calendar.'
    }
    elseif (-not $final.Connected) {
        Write-OOBEMenuUpdateStatus -State $State -Message 'Clock test: certificate validation fails at every tested time, so the clock is unlikely to be the cause. Review the certificate chain status above (for example UntrustedRoot, PartialChain or a TLS-inspecting proxy).'
    }
    return $final
}

function Write-OSDCloudPreOOBETlsDiagnostic {
    <#
    .SYNOPSIS
        Logs why the connectivity endpoint certificate fails validation.
    .DESCRIPTION
        Logs the clock, time services, proxy, DNS and a diagnostic-only TLS
        handshake recording the server certificate, chain elements and chain
        status. The certificate is never trusted and no data is sent.
    .PARAMETER State
        Shared diagnostic state.
    .PARAMETER HostName
        Endpoint host name.
    .EXAMPLE
        Write-OSDCloudPreOOBETlsDiagnostic -State $state
    .NOTES
        Direct TCP to port 443; a proxy may present a different certificate.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State, [string]$HostName = 'sls.update.microsoft.com')
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] TLS diagnostic"
    [TimeZoneInfo]::ClearCachedData()
    $zone = [TimeZoneInfo]::Local
    Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic: clock UTC $([datetime]::UtcNow.ToString('o')), local $((Get-Date).ToString('F')), time zone $($zone.Id) ($($zone.BaseUtcOffset))."
    foreach ($serviceName in 'W32Time', 'vmictimesync') {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        $text = if ($service) { "$($service.Status), $($service.StartType)" } else { 'not installed' }
        Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic: service $serviceName $text."
    }
    try {
        $uri = [Uri]"https://$HostName/"
        $proxy = [Net.WebRequest]::GetSystemWebProxy().GetProxy($uri)
        $proxyText = if ($proxy -eq $uri) { 'direct (no proxy)' } else { "$proxy (TLS inspection by a proxy can cause certificate failures)" }
        Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic: proxy for $uri is $proxyText."
    }
    catch { Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic: proxy lookup failed: $($_.Exception.GetBaseException().Message)" }
    try {
        $addresses = [Net.Dns]::GetHostAddresses($HostName) | ForEach-Object { $_.IPAddressToString }
        Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic: $HostName resolves to $($addresses -join ', ')."
    }
    catch { Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic: DNS lookup failed: $($_.Exception.GetBaseException().Message)" }
    try {
        $rootCount = @(Get-ChildItem -Path Cert:\LocalMachine\Root -ErrorAction Stop).Count
        $authRootCount = @(Get-ChildItem -Path Cert:\LocalMachine\AuthRoot -ErrorAction SilentlyContinue).Count
        Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic: LocalMachine Root store $rootCount certificates, AuthRoot $authRootCount."
    }
    catch { Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic: root store read failed: $($_.Exception.GetBaseException().Message)" }
    if (-not ('Recast.OOBE.TlsProbe' -as [type])) {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
namespace Recast.OOBE {
    public static class TlsProbe {
        public static string[] Inspect(string host, int port, int timeoutMs) {
            List<string> lines = new List<string>();
            using (TcpClient tcp = new TcpClient()) {
                IAsyncResult connect = tcp.BeginConnect(host, port, null, null);
                if (!connect.AsyncWaitHandle.WaitOne(timeoutMs)) { lines.Add("TCP connect to " + host + ":" + port + " timed out."); return lines.ToArray(); }
                tcp.EndConnect(connect);
                tcp.ReceiveTimeout = timeoutMs;
                tcp.SendTimeout = timeoutMs;
                lines.Add("TCP connected to " + tcp.Client.RemoteEndPoint + ".");
                RemoteCertificateValidationCallback callback = delegate (object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors errors) {
                    lines.Add("SSL policy errors: " + errors + "; validated at UTC " + DateTime.UtcNow.ToString("o") + ".");
                    if (certificate != null) {
                        X509Certificate2 leaf = new X509Certificate2(certificate);
                        lines.Add("Server certificate: " + leaf.Subject + "; issuer " + leaf.Issuer + "; valid " + leaf.NotBefore.ToUniversalTime().ToString("o") + " to " + leaf.NotAfter.ToUniversalTime().ToString("o") + "; thumbprint " + leaf.Thumbprint + ".");
                    }
                    if (chain != null) {
                        foreach (X509ChainElement element in chain.ChainElements) {
                            List<string> flags = new List<string>();
                            foreach (X509ChainStatus status in element.ChainElementStatus) { flags.Add(status.Status + " (" + status.StatusInformation.Trim() + ")"); }
                            lines.Add("Chain element: " + element.Certificate.Subject + "; valid to " + element.Certificate.NotAfter.ToUniversalTime().ToString("o") + "; thumbprint " + element.Certificate.Thumbprint + "; status " + (flags.Count == 0 ? "OK" : string.Join(", ", flags.ToArray())) + ".");
                        }
                        List<string> overall = new List<string>();
                        foreach (X509ChainStatus status in chain.ChainStatus) { overall.Add(status.Status + " (" + status.StatusInformation.Trim() + ")"); }
                        lines.Add("Chain status: " + (overall.Count == 0 ? "OK" : string.Join(", ", overall.ToArray())) + ".");
                    }
                    return errors == SslPolicyErrors.None;
                };
                using (SslStream ssl = new SslStream(tcp.GetStream(), false, callback)) {
                    try {
                        ssl.AuthenticateAsClient(host, null, SslProtocols.Tls12, false);
                        lines.Add("TLS handshake succeeded: " + ssl.SslProtocol + ", " + ssl.CipherAlgorithm + ".");
                    }
                    catch (Exception ex) { lines.Add("TLS handshake failed: " + ex.GetBaseException().Message); }
                }
            }
            return lines.ToArray();
        }
    }
}
'@
    }
    foreach ($line in [Recast.OOBE.TlsProbe]::Inspect($HostName, 443, 5000)) {
        Write-OOBEMenuUpdateStatus -State $State -Message "TLS diagnostic: $line"
    }
}

function Invoke-OSDCloudPreOOBETask {
    <#
    .SYNOPSIS
        Executes one fixed PreOOBE task with an explicit terminal outcome.
    .DESCRIPTION
        Internet time and driver work precede updates. Connectivity failures skip
        updates, not drivers.
        Preview produces managed sample results without external calls.
    .PARAMETER Type
        Time, DriverPack, Software, or Driver.
    .PARAMETER State
        Shared task state.
    .PARAMETER PreviewOnly
        Simulates the task.
    .EXAMPLE
        Invoke-OSDCloudPreOOBETask -Type Software -State $state
    .NOTES
        Called only on a dedicated STA worker.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][ValidateSet('Time', 'DriverPack', 'Software', 'Driver')][string]$Type,
        [Parameter(Mandatory)][hashtable]$State,
        [switch]$PreviewOnly
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start $Type"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $State.Outcome = 'Running'
    try {
        if ($PreviewOnly) {
            Write-OOBEMenuUpdateStatus -State $State -Message "Preview: would run $Type. No network, installation or system changes."
            $State.Succeeded = $true
            $State.Outcome = 'Succeeded'
        }
        elseif ($State.CancelRequested) { $State.Outcome = 'Cancelled' }
        elseif ($Type -eq 'Time') {
            Sync-OSDCloudPreOOBETime -State $State
        }
        elseif ($Type -eq 'DriverPack') {
            Invoke-OSDCloudPreOOBEDriverPack -State $State
        }
        else {
            $connection = Test-OSDCloudPreOOBEConnectivity -State $State
            if ($State.CancelRequested) { $State.Outcome = 'Cancelled' }
            elseif (-not $connection.Connected) {
                $State.Outcome = 'Skipped'
                Write-OOBEMenuUpdateStatus -State $State -Message "Skipped $Type updates: internet unavailable. $($connection.Reason)"
            }
            else {
                Invoke-OOBEMenuWindowsUpdate -Type $Type -State $State
                $State.Outcome = if ($State.CancelRequested) { 'Cancelled' } elseif ($State.Succeeded) { 'Succeeded' } else { 'Failed' }
            }
        }
    }
    catch {
        $State.Outcome = 'Failed'
        $State.Succeeded = $false
        Write-OOBEMenuLog -Message "$Type task failed: $($_.Exception.ToString())"
        Write-OOBEMenuUpdateStatus -State $State -Message "$Type task failed: $(Get-OSDCloudPreOOBEErrorMessage -Exception $_.Exception)"
    }
    finally {
        $State.DurationMs = $watch.ElapsedMilliseconds
        Write-OOBEMenuUpdateStatus -State $State -Message "$Type task $($State.Outcome), duration $($State.DurationMs) ms; reboot required $($State.RebootRequired)."
    }
}

function Start-OOBEMenuUpdateWorker {
    <#
    .SYNOPSIS
        Starts the inbox update engine on an isolated STA runspace.
    .DESCRIPTION
        Shares only managed status data with WPF and creates all COM objects on
        the worker. The caller owns and disposes the returned pipeline/runspace.
    .PARAMETER Type
        Time, DriverPack, Software, or Driver action.
    .PARAMETER State
        Synchronized progress and cooperative cancellation state.
    .EXAMPLE
        $worker = Start-OOBEMenuUpdateWorker -Type Software -State $state
    .NOTES
        No background process, downloaded module or persistent job is created.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][ValidateSet('Time', 'DriverPack', 'Software', 'Driver')][string]$Type,
        [Parameter(Mandatory)][hashtable]$State,
        [switch]$PreviewOnly
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start worker"
    $initialState = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($name in 'Write-OOBEMenuLog', 'Get-OOBEMenuContext', 'Write-OOBEMenuUpdateStatus', 'Get-OSDCloudPreOOBEErrorMessage', 'Invoke-OOBEMenuWindowsUpdate',
        'Sync-OSDCloudPreOOBETime', 'Test-OSDCloudPreOOBEConnectivity', 'Set-OSDCloudPreOOBEUtcClock', 'Test-OSDCloudPreOOBEClockShift',
        'Write-OSDCloudPreOOBETlsDiagnostic', 'Invoke-OSDCloudPreOOBEDriverPack', 'Invoke-OSDCloudPreOOBETask') {
        $definition = (Get-Command -Name $name -CommandType Function -ErrorAction Stop).Definition
        $initialState.Commands.Add([Management.Automation.Runspaces.SessionStateFunctionEntry]::new($name, $definition))
    }
    $initialState.Variables.Add([Management.Automation.Runspaces.SessionStateVariableEntry]::new('Preview', [bool]$PreviewOnly, 'Inert preview'))
    $runspace = [Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialState)
    $pipeline = $null
    try {
        $runspace.ApartmentState = 'STA'
        $runspace.ThreadOptions = 'ReuseThread'
        $runspace.Open()
        $pipeline = [PowerShell]::Create()
        $pipeline.Runspace = $runspace
        [void]$pipeline.AddCommand('Invoke-OSDCloudPreOOBETask').AddParameter('Type', $Type).AddParameter('State', $State).AddParameter('PreviewOnly', $PreviewOnly)
        $handle = $pipeline.BeginInvoke()
        return [pscustomobject]@{ Pipeline = $pipeline; Runspace = $runspace; Handle = $handle }
    }
    catch {
        if ($pipeline) { $pipeline.Dispose() }
        $runspace.Dispose()
        throw
    }
}

function Initialize-OOBEMenuNative {
    <#
    .SYNOPSIS
        Loads pointer-safe Win32 launch and desktop helpers.
    .DESCRIPTION
        Compiles embedded C# using inbox .NET Framework; does not launch anything.
    .EXAMPLE
        Initialize-OOBEMenuNative
    .NOTES
        Native handles are owned and disposed; no external binary is staged.
    #>
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Load native helpers"
    if ('Recast.OOBE.Native' -as [type]) { return }
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Recast.OOBE {
    public sealed class ChildProcess : IDisposable {
        private SafeWaitHandle handle;
        public uint Id { get; private set; }
        internal ChildProcess(IntPtr process, uint id) {
            handle = new SafeWaitHandle(process, true); Id = id;
        }
        public bool Wait(int milliseconds) {
            uint result = Native.WaitForSingleObject(handle, (uint)milliseconds);
            if (result == 0xFFFFFFFF) throw new Win32Exception(Marshal.GetLastWin32Error());
            return result == 0;
        }
        public int ExitCode {
            get {
                uint code;
                if (!Native.GetExitCodeProcess(handle, out code))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                return unchecked((int)code);
            }
        }
        public void Terminate() {
            if (!Wait(0) && !Native.TerminateProcess(handle, 1))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        public void Dispose() { handle.Dispose(); }
    }
    public static class Native {
        // WPF retains dispatcher windows until thread exit. Keep its assigned
        // desktop open for this child process's lifetime; Windows closes it on exit.
        private static IntPtr assignedDesktop;
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct StartupInfo {
            public uint cb; public string reserved; public string desktop; public string title;
            public uint x, y, xSize, ySize, xCountChars, yCountChars, fillAttribute, flags;
            public ushort showWindow, reserved2; public IntPtr reservedPointer;
            public IntPtr stdInput, stdOutput, stdError;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInfo {
            public IntPtr process, thread; public uint processId, threadId;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct Luid { public uint low; public int high; }
        [StructLayout(LayoutKind.Sequential)]
        private struct TokenPrivileges { public uint count; public Luid luid; public uint attributes; }
        [StructLayout(LayoutKind.Sequential)]
        private struct Point { public int x, y; }
        [StructLayout(LayoutKind.Sequential)]
        private struct Rect { public int left, top, right, bottom; }
        [StructLayout(LayoutKind.Sequential)]
        private struct MonitorInfo { public uint size; public Rect monitor, work; public uint flags; }
        [StructLayout(LayoutKind.Sequential)]
        private struct MinMaxInfo { public Point reserved, maxSize, maxPosition, minTrackSize, maxTrackSize; }
        [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo information);
        [DllImport("kernel32.dll")] public static extern uint WTSGetActiveConsoleSessionId();
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern uint WaitForSingleObject(SafeWaitHandle handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern bool GetExitCodeProcess(SafeWaitHandle process, out uint code);
        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern bool TerminateProcess(SafeWaitHandle process, uint code);
        [DllImport("user32.dll")] private static extern IntPtr GetProcessWindowStation();
        [DllImport("user32.dll")] private static extern IntPtr GetThreadDesktop(uint thread);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
        [DllImport("user32.dll", SetLastError = true)]
        internal static extern bool SetThreadDesktop(IntPtr desktop);
        [DllImport("user32.dll", SetLastError = true)]
        internal static extern bool CloseDesktop(IntPtr desktop);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool GetUserObjectInformation(IntPtr handle, int index,
            StringBuilder value, uint length, out uint needed);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr process, uint access, out SafeAccessTokenHandle token);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool DuplicateTokenEx(SafeAccessTokenHandle token, uint access,
            IntPtr attributes, int impersonation, int type, out SafeAccessTokenHandle duplicate);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool SetTokenInformation(SafeAccessTokenHandle token, int information,
            ref uint value, uint length);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool LookupPrivilegeValue(string system, string name, out Luid luid);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool AdjustTokenPrivileges(SafeAccessTokenHandle token, bool disable,
            ref TokenPrivileges privileges, uint length, out TokenPrivileges previous, out uint needed);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcessAsUser(SafeAccessTokenHandle token, string application,
            StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inherit,
            uint flags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo process);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcess(string application, StringBuilder command,
            IntPtr processAttributes, IntPtr threadAttributes, bool inherit, uint flags,
            IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo process);

        private static string ObjectName(IntPtr handle) {
            StringBuilder name = new StringBuilder(256); uint needed;
            if (!GetUserObjectInformation(handle, 2, name, 512, out needed))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Get desktop/window station name");
            return name.ToString();
        }
        public static string Station { get { return ObjectName(GetProcessWindowStation()); } }
        public static string Desktop { get { return ObjectName(GetThreadDesktop(GetCurrentThreadId())); } }
        public static void AdjustMaximize(IntPtr window, IntPtr parameter) {
            MonitorInfo monitor = new MonitorInfo();
            monitor.size = (uint)Marshal.SizeOf(typeof(MonitorInfo));
            if (!GetMonitorInfo(MonitorFromWindow(window, 2), ref monitor))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Get monitor work area");
            MinMaxInfo sizes = (MinMaxInfo)Marshal.PtrToStructure(parameter, typeof(MinMaxInfo));
            sizes.maxPosition.x = monitor.work.left - monitor.monitor.left;
            sizes.maxPosition.y = monitor.work.top - monitor.monitor.top;
            sizes.maxSize.x = monitor.work.right - monitor.work.left;
            sizes.maxSize.y = monitor.work.bottom - monitor.work.top;
            Marshal.StructureToPtr(sizes, parameter, false);
        }
        public static bool IsInputDesktop() {
            if (Process.GetCurrentProcess().SessionId != WTSGetActiveConsoleSessionId() ||
                !String.Equals(Station, "WinSta0", StringComparison.OrdinalIgnoreCase)) return false;
            IntPtr input = OpenInputDesktop(0, false, 1);
            if (input == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Open input desktop");
            try { return String.Equals(Desktop, ObjectName(input), StringComparison.OrdinalIgnoreCase); }
            finally {
                if (!CloseDesktop(input)) throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
        public static void AttachInputDesktop() {
            if (Process.GetCurrentProcess().SessionId != WTSGetActiveConsoleSessionId() ||
                !String.Equals(Station, "WinSta0", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Child is not on the interactive console window station.");
            if (assignedDesktop != IntPtr.Zero) throw new InvalidOperationException("Input desktop already attached.");
            IntPtr input = OpenInputDesktop(0, false, 0x1FF);
            if (input == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Open input desktop");
            if (!SetThreadDesktop(input)) {
                int error = Marshal.GetLastWin32Error(); CloseDesktop(input);
                throw new Win32Exception(error, "Attach input desktop before loading WPF");
            }
            assignedDesktop = input;
        }
        private static TokenPrivileges Enable(SafeAccessTokenHandle token, string name) {
            TokenPrivileges privileges = new TokenPrivileges(); privileges.count = 1; privileges.attributes = 2;
            if (!LookupPrivilegeValue(null, name, out privileges.luid))
                throw new Win32Exception(Marshal.GetLastWin32Error(), name);
            TokenPrivileges previous; uint needed;
            if (!AdjustTokenPrivileges(token, false, ref privileges,
                (uint)Marshal.SizeOf(typeof(TokenPrivileges)), out previous, out needed))
                throw new Win32Exception(Marshal.GetLastWin32Error(), name);
            int error = Marshal.GetLastWin32Error();
            if (error != 0) throw new Win32Exception(error, name);
            return previous;
        }
        private static void Restore(SafeAccessTokenHandle token, TokenPrivileges previous) {
            if (previous.count == 0) return;
            TokenPrivileges unused; uint needed;
            if (!AdjustTokenPrivileges(token, false, ref previous,
                (uint)Marshal.SizeOf(typeof(TokenPrivileges)), out unused, out needed))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Restore launch privilege");
        }
        public static ChildProcess Launch(string executable, string arguments, bool console, uint session) {
            StartupInfo startup = new StartupInfo();
            startup.cb = (uint)Marshal.SizeOf(typeof(StartupInfo));
            startup.desktop = console ? "WinSta0\\" + Desktop : "WinSta0\\Default";
            StringBuilder command = new StringBuilder("\"" + executable + "\" " + arguments);
            ProcessInfo process = new ProcessInfo();
            uint flags = console ? 0x10u : 0x08000000u;
            if (console) {
                if (!IsInputDesktop()) throw new InvalidOperationException("Menu desktop is no longer visible.");
                if (!CreateProcess(executable, command, IntPtr.Zero, IntPtr.Zero, false, flags,
                    IntPtr.Zero, Environment.GetFolderPath(Environment.SpecialFolder.Windows), ref startup, out process))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Launch shell");
            } else {
                if (session == 0xFFFFFFFF) throw new InvalidOperationException("No console session is available.");
                SafeAccessTokenHandle token;
                using (Process current = Process.GetCurrentProcess()) {
                    if (!OpenProcessToken(current.Handle, 0x2Bu, out token))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Open SYSTEM token");
                }
                using (token) {
                    TokenPrivileges tcb = new TokenPrivileges(), assign = new TokenPrivileges(), quota = new TokenPrivileges();
                    try {
                        tcb = Enable(token, "SeTcbPrivilege");
                        assign = Enable(token, "SeAssignPrimaryTokenPrivilege");
                        quota = Enable(token, "SeIncreaseQuotaPrivilege");
                        SafeAccessTokenHandle duplicate;
                        if (!DuplicateTokenEx(token, 0x02000000, IntPtr.Zero, 2, 1, out duplicate))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "Duplicate SYSTEM token");
                        using (duplicate) {
                            if (!SetTokenInformation(duplicate, 12, ref session, 4))
                                throw new Win32Exception(Marshal.GetLastWin32Error(), "Set console session");
                            if (!CreateProcessAsUser(duplicate, executable, command, IntPtr.Zero, IntPtr.Zero,
                                false, flags, IntPtr.Zero, Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                                ref startup, out process))
                                throw new Win32Exception(Marshal.GetLastWin32Error(), "Launch interactive SYSTEM child");
                        }
                    } finally {
                        try { Restore(token, quota); Restore(token, assign); Restore(token, tcb); }
                        catch {
                            if (process.process != IntPtr.Zero) {
                                using (SafeWaitHandle thread = new SafeWaitHandle(process.thread, true)) { }
                                using (ChildProcess failed = new ChildProcess(process.process, process.processId)) {
                                    failed.Terminate(); failed.Wait(5000);
                                }
                            }
                            throw;
                        }
                    }
                }
            }
            using (SafeWaitHandle thread = new SafeWaitHandle(process.thread, true)) { }
            return new ChildProcess(process.process, process.processId);
        }
    }
}
'@
}

function Get-OOBEMenuContext {
    <#
    .SYNOPSIS
        Reports the identity and actual desktop used by this process.
    .DESCRIPTION
        Separates launch routing from UI and records console desktop visibility.
    .EXAMPLE
        Get-OOBEMenuContext
    .NOTES
        Requires the embedded native helpers to be loaded first.
    #>
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Inspect launch context"
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $process = [System.Diagnostics.Process]::GetCurrentProcess()
    try {
        return [pscustomobject]@{
            IsSystem       = $identity.User.Value -eq 'S-1-5-18'
            Identity       = $identity.Name
            SessionId      = $process.SessionId
            Station        = [Recast.OOBE.Native]::Station
            Desktop        = [Recast.OOBE.Native]::Desktop
            ConsoleSession = [Recast.OOBE.Native]::WTSGetActiveConsoleSessionId()
            IsInputDesktop = [Recast.OOBE.Native]::IsInputDesktop()
        }
    }
    finally { $identity.Dispose(); $process.Dispose() }
}

function Invoke-OOBEMenuChild {
    <#
    .SYNOPSIS
        Launches and waits for only the interactive menu process.
    .DESCRIPTION
        Requires a ready signal within 60 seconds. An invisible or failed child is
        terminated, with a nonzero result. A visible menu has no operator timeout.
    .PARAMETER ScriptPath
        Full path of this standalone script.
    .EXAMPLE
        Invoke-OOBEMenuChild -ScriptPath $PSCommandPath
    .NOTES
        The random global event grants access only to SYSTEM; no file-based IPC.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$ScriptPath)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Launch interactive child"
    $eventName = "Global\RecastOSDCloud.OOBE.$([guid]::NewGuid())"
    $security = [System.Security.AccessControl.EventWaitHandleSecurity]::new()
    $security.AddAccessRule([System.Security.AccessControl.EventWaitHandleAccessRule]::new(
        [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18'),
        [System.Security.AccessControl.EventWaitHandleRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
    ))
    $created = $false
    $ready = [System.Threading.EventWaitHandle]::new(
        $false, [System.Threading.EventResetMode]::ManualReset, $eventName, [ref]$created, $security
    )
    $child = $null
    try {
        if (-not $created) { throw 'The menu readiness event already exists.' }
        $arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -InteractiveChild -ReadyEvent "{1}"' -f $ScriptPath, $eventName
        $child = [Recast.OOBE.Native]::Launch(
            (Get-OOBEMenuNativePath -PowerShell), $arguments, $false,
            [Recast.OOBE.Native]::WTSGetActiveConsoleSessionId()
        )
        Write-OOBEMenuLog -Message "Waiting for interactive menu PID $($child.Id)."
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $ready.WaitOne(200)) {
            if ($child.Wait(0)) {
                throw "Menu child exited before displaying a visible window (exit $($child.ExitCode))."
            }
            if ($timer.Elapsed.TotalSeconds -ge 60) {
                $child.Terminate()
                [void]$child.Wait(5000)
                throw 'Menu child did not acknowledge a visible window within 60 seconds.'
            }
        }
        [void]$child.Wait(-1)
        return $child.ExitCode
    }
    finally {
        if ($child) {
            try {
                if (-not $child.Wait(0)) {
                    $child.Terminate()
                    [void]$child.Wait(5000)
                }
            } finally { $child.Dispose() }
        }
        $ready.Dispose()
    }
}



#region PreOOBE version
$OSDCloudPreOOBEVersion = try {
    $manifestText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\OSDCloud.psd1'))
    [regex]::Match($manifestText, "(?m)^\s*ModuleVersion\s*=\s*'([^']+)'").Groups[1].Value
} catch { '' }
#endregion

#region PreOOBE components
. (Join-Path $PSScriptRoot 'Invoke-OSDCloudPreOOBEDriverPack.ps1')
. (Join-Path $PSScriptRoot 'Show-OSDCloudPreOOBEWindow.ps1')
#endregion

function Invoke-OOBEMenu {
    <#
    .SYNOPSIS
        Coordinates startup, optional session launch, and menu exit status.
    .DESCRIPTION
        Returns 0 for normal closure and 1 for failure; never exits the caller.
    .PARAMETER ScriptPath
        Full path to the standalone script for session relaunch.
    .EXAMPLE
        Invoke-OOBEMenu -ScriptPath $PSCommandPath
    .NOTES
        Default execution requires SYSTEM. Preview cannot launch elevated shells.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$ScriptPath)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start"
    try {
        if ($PSVersionTable.PSEdition -ne 'Desktop' -or
            $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
            throw 'Use inbox Windows PowerShell 5.1, not PowerShell 7.'
        }
        if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
            throw 'Use powershell.exe -STA.'
        }
        if ($Preview -and ($InteractiveChild -or $ReadyEvent)) {
            throw 'Preview cannot use the SYSTEM session launcher.'
        }
        if ($InteractiveChild -and -not $ReadyEvent) { throw 'Interactive child is missing its readiness event.' }
        if ($ReadyEvent -and -not $InteractiveChild) { throw 'Readiness event requires interactive child mode.' }
        Initialize-OOBEMenuNative
        $context = Get-OOBEMenuContext
        if (-not $Preview -and -not $context.IsSystem) {
            throw 'The setup menu must run as SYSTEM. Use -Preview for an inert desktop test.'
        }
        Write-OOBEMenuLog -Message "Start OSDCloudPreOOBE $OSDCloudPreOOBEVersion`: identity $($context.Identity), session $($context.SessionId), station $($context.Station), desktop $($context.Desktop), console $($context.ConsoleSession), architecture $env:PROCESSOR_ARCHITECTURE."
        if ($InteractiveChild) {
            [Recast.OOBE.Native]::AttachInputDesktop()
        } elseif (-not $context.IsInputDesktop) {
            if ($Preview) { throw 'Preview must run on the local console input desktop.' }
            return Invoke-OOBEMenuChild -ScriptPath $ScriptPath
        }
        $exitCode = Show-OOBEMenuWindow -ReadyEventName $ReadyEvent
        Write-OOBEMenuLog -Message "Menu closed with exit code $exitCode."
        return $exitCode
    }
    catch {
        $message = "OOBE menu startup failed: $($_.Exception.Message)"
        Write-Error -Message $message -ErrorAction Continue
        Write-OOBEMenuLog -Message $message
        return 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-OOBEMenu -ScriptPath $PSCommandPath)
}
