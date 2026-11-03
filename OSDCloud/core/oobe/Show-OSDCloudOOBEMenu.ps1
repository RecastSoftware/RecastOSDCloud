<#
.SYNOPSIS
    Displays an interactive technician menu before Windows Setup continues.
.DESCRIPTION
    Self-contained inbox Windows PowerShell 5.1/WPF script for AMD64 and ARM64.
    Run synchronously from OOBE.cmd or SetupComplete.cmd as SYSTEM. If necessary, a copy of this script
    is launched as SYSTEM in the console session and attached to its input desktop.
    Closing the menu returns 0. Startup failures are logged and return 1.
    Shells are independent SYSTEM processes and remain open when the menu closes.
.PARAMETER Preview
    Displays the menu as the current user without crossing sessions. Shell buttons
    only report their intended actions. Does not prove first-boot interactivity.
.PARAMETER Phase
    Selects OOBE or SetupComplete. SetupComplete also provides clock settings.
.PARAMETER InteractiveChild
    Internal session-launch flag. Not needed in OOBE.cmd.
.PARAMETER ReadyEvent
    Internal SYSTEM-only named event used to acknowledge a visible child window.
.EXAMPLE
    powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File .\Show-OSDCloudOOBEMenu.ps1
.EXAMPLE
    powershell.exe -NoLogo -NoProfile -STA -File .\Show-OSDCloudOOBEMenu.ps1 -Preview
.NOTES
    No OSDCloud module, external executable, network access, or user logon required.
    Dot-sourcing defines helpers only; it does not show UI or exit the caller.
#>
[CmdletBinding()]
param (
    [switch]$Preview,
    [ValidateSet('OOBE', 'SetupComplete')]
    [string]$Phase = 'OOBE',
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
            (Join-Path $logRoot 'OOBEMenu.log'),
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
        Called only by the SetupComplete page; applying changes requires SYSTEM.
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
    # Set-Date converts DateTime to UTC before updating the system clock.
    Set-Date -Date $utcDate -ErrorAction Stop | Out-Null
    Write-OOBEMenuLog -Message "Date, time, and time zone set to $description."
    return "Date, time, and time zone set to $description."
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
        $arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Phase {1} -InteractiveChild -ReadyEvent "{2}"' -f $ScriptPath, $Phase, $eventName
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

function Show-OOBEMenuWindow {
    <#
    .SYNOPSIS
        Shows the standalone dark WPF technician menu.
    .DESCRIPTION
        Contains no deployment or profile execution. Errors launching shells stay
        visible in the menu. Closing the window does not wait for child shells.
    .PARAMETER ReadyEventName
        Optional internal readiness event acknowledged after visible rendering.
    .EXAMPLE
        Show-OOBEMenuWindow
    .NOTES
        Must run on an STA thread attached to the console input desktop.
    #>
    [CmdletBinding()]
    param ([string]$ReadyEventName)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Show window"
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Recast Software - OSDCloud OOBE Menu" Width="640" Height="480" MinWidth="480" MinHeight="360"
        WindowStartupLocation="Manual" Background="#161F5B" Foreground="#F5F5F5"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" Topmost="True"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        AutomationProperties.Name="OSDCloud OOBE technician menu">
    <shell:WindowChrome.WindowChrome>
        <shell:WindowChrome CaptionHeight="48" GlassFrameThickness="0"
                            ResizeBorderThickness="{x:Static SystemParameters.WindowResizeBorderThickness}"
                            UseAeroCaptionButtons="False"/>
    </shell:WindowChrome.WindowChrome>
    <Window.Resources>
        <SolidColorBrush x:Key="AccentBrush" Color="#31D1FF"/>
        <SolidColorBrush x:Key="SurfaceBrush" Color="#1C2868"/>
        <SolidColorBrush x:Key="ControlBrush" Color="#243475"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#53639C"/>
        <SolidColorBrush x:Key="HoverBrush" Color="#2D4088"/>
        <SolidColorBrush x:Key="SecondaryTextBrush" Color="#CDD9F3"/>
        <SolidColorBrush x:Key="SidebarBrush" Color="#111949"/>
        <Style x:Key="ScrollBarThumbStyle" TargetType="Thumb">
            <Setter Property="Background" Value="{StaticResource ControlBrush}"/>
            <Setter Property="Margin" Value="2"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border CornerRadius="4" Background="{TemplateBinding Background}"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollBarPageButtonStyle" TargetType="RepeatButton">
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Track x:Name="PART_Track" IsDirectionReversed="True"
                               Minimum="{TemplateBinding Minimum}" Maximum="{TemplateBinding Maximum}"
                               Value="{TemplateBinding Value}" ViewportSize="{TemplateBinding ViewportSize}">
                            <Track.DecreaseRepeatButton>
                                <RepeatButton Command="ScrollBar.PageUpCommand" Style="{StaticResource ScrollBarPageButtonStyle}"/>
                            </Track.DecreaseRepeatButton>
                            <Track.Thumb><Thumb Style="{StaticResource ScrollBarThumbStyle}"/></Track.Thumb>
                            <Track.IncreaseRepeatButton>
                                <RepeatButton Command="ScrollBar.PageDownCommand" Style="{StaticResource ScrollBarPageButtonStyle}"/>
                            </Track.IncreaseRepeatButton>
                        </Track>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="CardTitleStyle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="LineHeight" Value="24"/>
        </Style>
        <Style x:Key="IconStyle" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
            <Setter Property="FontSize" Value="20"/>
            <Setter Property="Foreground" Value="{StaticResource AccentBrush}"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource ControlBrush}"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder" CornerRadius="4" BorderThickness="1"
                                Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}">
                            <ContentPresenter Margin="{TemplateBinding Padding}"
                                              HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Background" Value="{StaticResource SurfaceBrush}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                                <Setter TargetName="ButtonBorder" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="TitleBarFocusVisualStyle">
            <Setter Property="Control.Template">
                <Setter.Value>
                    <ControlTemplate>
                        <Rectangle Margin="4,6" RadiusX="4" RadiusY="4" Stroke="#F5F5F5" StrokeThickness="1"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="TitleBarButtonStyle" TargetType="Button">
            <Setter Property="Width" Value="46"/>
            <Setter Property="Height" Value="48"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource TitleBarFocusVisualStyle}"/>
            <Setter Property="shell:WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="CaptionBorder" Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CaptionBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="CaptionBorder" Property="Background" Value="{StaticResource ControlBrush}"/>
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="Tag" Value="Close"/><Condition Property="IsMouseOver" Value="True"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="CaptionBorder" Property="Background" Value="#C42B1C"/>
                            </MultiTrigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="Tag" Value="Close"/><Condition Property="IsPressed" Value="True"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="CaptionBorder" Property="Background" Value="#A82418"/>
                            </MultiTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="TitleBarCloseButtonStyle" TargetType="Button" BasedOn="{StaticResource TitleBarButtonStyle}">
            <Setter Property="Tag" Value="Close"/>
        </Style>
        <Style x:Key="TitleBarIconStyle" TargetType="TextBlock" BasedOn="{StaticResource IconStyle}">
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
        </Style>
        <Style x:Key="SidebarButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="Margin" Value="4,1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="RowBorder" Background="{TemplateBinding Background}" BorderBrush="Transparent"
                                BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="RowBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="RowBorder" Property="Background" Value="{StaticResource ControlBrush}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="RowBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource ControlBrush}"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Padding" Value="8,6"/>
        </Style>
        <Style TargetType="DatePickerTextBox">
            <Setter Property="Background" Value="{StaticResource ControlBrush}"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="ItemBorder" Background="Transparent" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="{StaticResource ControlBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="Background" Value="{StaticResource ControlBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton Focusable="False"
                                          IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="DropDownBorder" Background="{StaticResource ControlBrush}"
                                                BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" CornerRadius="4">
                                            <TextBlock Text="&#xE70D;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"
                                                       FontSize="10" Foreground="#F5F5F5" HorizontalAlignment="Right" Margin="8"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="DropDownBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              Margin="8,6,28,6" IsHitTestVisible="False" ClipToBounds="True"/>
                            <Border x:Name="FocusBorder" BorderBrush="{StaticResource AccentBrush}" BorderThickness="1"
                                    CornerRadius="4" IsHitTestVisible="False" Visibility="Collapsed"/>
                            <Popup x:Name="PART_Popup" Placement="Bottom" AllowsTransparency="True"
                                   IsOpen="{TemplateBinding IsDropDownOpen}" Focusable="False">
                                <Border Background="{StaticResource SurfaceBrush}" BorderBrush="{StaticResource BorderBrush}"
                                        BorderThickness="1" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                                    <ScrollViewer MaxHeight="{TemplateBinding MaxDropDownHeight}" CanContentScroll="True">
                                        <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocusWithin" Value="True">
                                <Setter TargetName="FocusBorder" Property="Visibility" Value="Visible"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition x:Name="SidebarColumn" Width="200"/><ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="48"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.ColumnSpan="2" Background="{StaticResource SidebarBrush}">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="56"/><ColumnDefinition Width="*"/><ColumnDefinition Width="46"/>
                <ColumnDefinition Width="46"/><ColumnDefinition Width="46"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="PaneToggleButton" Style="{StaticResource TitleBarButtonStyle}"
                    ToolTip="Collapse navigation" AutomationProperties.Name="Collapse navigation">
                <TextBlock Text="&#xE700;" Style="{StaticResource TitleBarIconStyle}"/>
            </Button>
            <TextBlock x:Name="TitleText" Grid.Column="1" Text="OSDCloud OOBE Menu" Margin="8,0"
                       VerticalAlignment="Center" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
            <Button x:Name="MinimizeButton" Grid.Column="2" Style="{StaticResource TitleBarButtonStyle}"
                    ToolTip="Minimize" AutomationProperties.Name="Minimize">
                <TextBlock Text="&#xE921;" Style="{StaticResource TitleBarIconStyle}"/>
            </Button>
            <Button x:Name="MaximizeButton" Grid.Column="3" Style="{StaticResource TitleBarButtonStyle}"
                    ToolTip="Maximize" AutomationProperties.Name="Maximize">
                <TextBlock x:Name="MaximizeGlyph" Text="&#xE922;" Style="{StaticResource TitleBarIconStyle}"/>
            </Button>
            <Button x:Name="CloseButton" Grid.Column="4" Style="{StaticResource TitleBarCloseButtonStyle}"
                    ToolTip="Continue Windows Setup" AutomationProperties.Name="Close menu and continue Windows Setup">
                <TextBlock Text="&#xE8BB;" Style="{StaticResource TitleBarIconStyle}"/>
            </Button>
        </Grid>
        <Border Grid.Row="1" Background="{StaticResource SidebarBrush}">
            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel Margin="0,8">
                    <Button x:Name="CommandButton" Style="{StaticResource SidebarButtonStyle}"
                            AutomationProperties.Name="Cmd Prompt" ToolTip="Cmd Prompt">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock x:Name="CommandIcon" Text="&#xE756;" Style="{StaticResource IconStyle}" FontSize="18" Width="20"/>
                            <TextBlock x:Name="CommandLabel" Text="Cmd Prompt" Margin="12,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="PowerShellButton" Style="{StaticResource SidebarButtonStyle}"
                            AutomationProperties.Name="Windows PowerShell" ToolTip="Windows PowerShell">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock x:Name="PowerShellIcon" Text="&#xE756;" Style="{StaticResource IconStyle}" FontSize="18" Width="20"/>
                            <TextBlock x:Name="PowerShellLabel" Text="Windows PowerShell" Margin="12,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="ToolsButton" Style="{StaticResource SidebarButtonStyle}"
                            AutomationProperties.Name="Setup scripts" ToolTip="Setup scripts">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="&#xE70F;" Style="{StaticResource IconStyle}" FontSize="18" Width="20"/>
                            <TextBlock x:Name="ToolsLabel" Text="Setup scripts" Margin="12,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="ClockButton" Style="{StaticResource SidebarButtonStyle}" Visibility="Collapsed"
                            AutomationProperties.Name="Date, Time and TimeZone" ToolTip="Date, Time and TimeZone">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="&#xE787;" Style="{StaticResource IconStyle}" FontSize="18" Width="20"/>
                            <TextBlock x:Name="ClockLabel" Text="Date, Time &amp; TimeZone" TextWrapping="Wrap"
                                       MaxWidth="144" Margin="12,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                </StackPanel>
            </ScrollViewer>
        </Border>
        <Grid Grid.Row="1" Grid.Column="1" Margin="24">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <StackPanel Margin="0,0,0,16">
                <TextBlock x:Name="PageTitleText" Text="Technician tools" Style="{StaticResource CardTitleStyle}" TextWrapping="Wrap"/>
                <TextBlock Text="Windows Setup is waiting. Close this menu to continue."
                           Foreground="{StaticResource SecondaryTextBrush}" TextWrapping="Wrap" Margin="0,6,0,0"/>
            </StackPanel>
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <Border Background="{StaticResource SurfaceBrush}" CornerRadius="4" Padding="16">
                    <Grid>
                        <StackPanel x:Name="ToolsPage">
                            <Button x:Name="OpenOOBEButton" Margin="0,0,0,12" AutomationProperties.Name="Open oobe.cmd in Notepad">
                                <TextBlock Text="Open oobe.cmd" TextWrapping="Wrap"/>
                            </Button>
                            <Button x:Name="OpenSetupCompleteButton" AutomationProperties.Name="Open setupcomplete.cmd in Notepad">
                                <TextBlock Text="Open setupcomplete.cmd" TextWrapping="Wrap"/>
                            </Button>
                            <TextBlock Text="Open a setup script in Notepad. Use the shortcuts on the left to open SYSTEM shells."
                                       Foreground="{StaticResource SecondaryTextBrush}" TextWrapping="Wrap" Margin="0,12,0,0"/>
                        </StackPanel>
                        <StackPanel x:Name="ClockPage" Visibility="Collapsed">
                            <UniformGrid x:Name="ClockDateTimeGrid" Columns="2">
                                <StackPanel Margin="0,0,8,8">
                                    <TextBlock Text="Date" Margin="0,0,0,4"/>
                                    <DatePicker x:Name="DatePicker" Height="34" Foreground="#F5F5F5"
                                                Background="{StaticResource ControlBrush}" BorderBrush="{StaticResource BorderBrush}"
                                                AutomationProperties.Name="Local date"/>
                                </StackPanel>
                                <StackPanel Margin="0,0,0,8">
                                    <TextBlock Text="Time (HH:mm:ss)" Margin="0,0,0,4"/>
                                    <TextBox x:Name="TimeTextBox" Height="34" AutomationProperties.Name="Local time in 24-hour HH:mm:ss format"/>
                                </StackPanel>
                            </UniformGrid>
                            <TextBlock Text="TimeZone" Margin="0,4,0,4"/>
                            <ComboBox x:Name="TimeZoneComboBox" DisplayMemberPath="DisplayName" SelectedValuePath="Id"
                                      AutomationProperties.Name="Windows time zone" MaxDropDownHeight="240"/>
                            <Button x:Name="ApplyClockButton" Margin="0,12,0,0"
                                    AutomationProperties.Name="Apply Date, Time and TimeZone">
                                <TextBlock Text="Apply Date, Time and TimeZone" TextWrapping="Wrap"/>
                            </Button>
                        </StackPanel>
                    </Grid>
                </Border>
            </ScrollViewer>
            <TextBlock x:Name="StatusText" Grid.Row="2" Margin="0,12,0,0" TextWrapping="Wrap"
                       Foreground="{StaticResource SecondaryTextBrush}" Text="Shell windows remain open when this menu closes."
                       AutomationProperties.LiveSetting="Polite"/>
        </Grid>
        <Border Grid.Row="2" Grid.ColumnSpan="2" Background="{StaticResource SidebarBrush}" Padding="16,10"
                BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0">
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="ContextText" Text="OSDCloud by Recast | SYSTEM" VerticalAlignment="Center"
                           Foreground="{StaticResource SecondaryTextBrush}" TextWrapping="Wrap" Margin="0,0,12,0"/>
                <Button x:Name="ContinueButton" Grid.Column="1" Content="Continue Windows Setup"
                        AutomationProperties.Name="Close menu and continue Windows Setup"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    try { $window = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }
    $state = @{ ExitCode = 0; Source = $null; PaneExpanded = $true; ClockLoaded = $false }
    $status = $window.FindName('StatusText')
    $commandButton = $window.FindName('CommandButton')
    $powerShellButton = $window.FindName('PowerShellButton')
    $continueButton = $window.FindName('ContinueButton')
    $title = "OSDCloud $Phase Menu"
    $window.Title = $title
    $window.FindName('TitleText').Text = $title
    [System.Windows.Automation.AutomationProperties]::SetName($window, $title)
    $clockButton = $window.FindName('ClockButton')
    $clockButton.Visibility = if ($Phase -eq 'SetupComplete') { 'Visible' } else { 'Collapsed' }
    $window.FindName('DatePicker').Add_DateValidationError({
        $_.ThrowException = $false
        $message = "Invalid date: $($_.Exception.Message). Select a date using the calendar."
        $status.Text = $message
        Write-Error -Message $message -ErrorAction Continue
        Write-OOBEMenuLog -Message $message
    })
    if ($Preview) {
        $window.Title += ' (Preview)'
        $window.FindName('ContextText').Text = 'Preview | Changes and launches disabled'
    }
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $window.MinWidth = [Math]::Min($window.MinWidth, $workArea.Width)
    $window.MinHeight = [Math]::Min($window.MinHeight, $workArea.Height)
    $window.Width = [Math]::Min($window.Width, $workArea.Width)
    $window.Height = [Math]::Min($window.Height, $workArea.Height)
    $window.Left = $workArea.Left + [Math]::Min(20, [Math]::Max(0, $workArea.Width - $window.Width))
    $window.Top = $workArea.Top + [Math]::Min(20, [Math]::Max(0, $workArea.Height - $window.Height))
    $maximizeHook = [System.Windows.Interop.HwndSourceHook]{
        param ([IntPtr]$Handle, [int]$Message, [IntPtr]$WParam, [IntPtr]$LParam, [ref]$Handled)
        if ($Message -eq 0x24) {
            [Recast.OOBE.Native]::AdjustMaximize($Handle, $LParam)
            $Handled.Value = $true
        }
        return [IntPtr]::Zero
    }
    $window.Add_SourceInitialized({
        $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
        $state.Source = [System.Windows.Interop.HwndSource]::FromHwnd($handle)
        $state.Source.AddHook($maximizeHook)
    })
    $window.Add_Closed({
        if ($state.Source) { $state.Source.RemoveHook($maximizeHook) }
    })
    $window.FindName('ClockDateTimeGrid').Add_SizeChanged({
        $grid = $window.FindName('ClockDateTimeGrid')
        $grid.Columns = if ($grid.ActualWidth -lt 280) { 1 } else { 2 }
    })
    $launchShell = {
        param ([bool]$PowerShell)
        try {
            $executable = Get-OOBEMenuNativePath -PowerShell:$PowerShell
            $arguments = if ($PowerShell) { '-NoLogo -NoProfile -NoExit -STA' } else { '/d /k' }
            if ($Preview) {
                $status.Text = "Preview: would open $executable $arguments"
            } else {
                $shell = [Recast.OOBE.Native]::Launch($executable, $arguments, $true, 0)
                try { Write-OOBEMenuLog -Message "Opened shell PID $($shell.Id) on $([Recast.OOBE.Native]::Desktop)." }
                finally { $shell.Dispose() }
                $status.Text = 'Shell opened. Close this menu when you are ready to continue setup.'
            }
        }
        catch {
            $message = "Unable to open shell: $($_.Exception.Message)"
            $status.Text = $message
            Write-Error -Message $message -ErrorAction Continue
            Write-OOBEMenuLog -Message $message
        }
    }
    $commandButton.Add_Click({ & $launchShell $false })
    $powerShellButton.Add_Click({ & $launchShell $true })
    $openScript = {
        param ([string]$FileName)
        try {
            $path = Join-Path $env:WINDIR "Setup\Scripts\$FileName"
            $executable = Get-OOBEMenuNativePath -Notepad
            if ($Preview) {
                $status.Text = "Preview: would open $executable `"$path`""
            } else {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Setup script is missing: $path" }
                $editor = [Recast.OOBE.Native]::Launch($executable, "`"$path`"", $true, 0)
                try { Write-OOBEMenuLog -Message "Opened $FileName in Notepad PID $($editor.Id)." }
                finally { $editor.Dispose() }
                $status.Text = "$FileName opened in Notepad. Save changes before continuing setup."
            }
        }
        catch {
            $message = "Unable to open ${FileName}: $($_.Exception.Message)"
            $status.Text = $message
            Write-Error -Message $message -ErrorAction Continue
            Write-OOBEMenuLog -Message $message
        }
    }
    $window.FindName('OpenOOBEButton').Add_Click({ & $openScript 'oobe.cmd' })
    $window.FindName('OpenSetupCompleteButton').Add_Click({ & $openScript 'setupcomplete.cmd' })
    $toolsButton = $window.FindName('ToolsButton')
    $toolsButton.Background = $window.Resources['ControlBrush']
    $toolsButton.Add_Click({
        $window.FindName('ToolsPage').Visibility = 'Visible'
        $window.FindName('ClockPage').Visibility = 'Collapsed'
        $window.FindName('PageTitleText').Text = 'Technician tools'
        $toolsButton.Background = $window.Resources['ControlBrush']
        $clockButton.Background = [System.Windows.Media.Brushes]::Transparent
    })
    $clockButton.Add_Click({
        if ($Phase -ne 'SetupComplete') { return }
        try {
            if (-not $state.ClockLoaded) {
                $now = Get-Date
                $window.FindName('DatePicker').SelectedDate = $now.Date
                $window.FindName('TimeTextBox').Text = $now.ToString('HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
                $zones = $window.FindName('TimeZoneComboBox')
                $zones.ItemsSource = [TimeZoneInfo]::GetSystemTimeZones()
                $zones.SelectedValue = (Get-TimeZone -ErrorAction Stop).Id
                $state.ClockLoaded = $true
            }
            $window.FindName('ToolsPage').Visibility = 'Collapsed'
            $window.FindName('ClockPage').Visibility = 'Visible'
            $window.FindName('PageTitleText').Text = 'Date, Time & TimeZone'
            $clockButton.Background = $window.Resources['ControlBrush']
            $toolsButton.Background = [System.Windows.Media.Brushes]::Transparent
            $status.Text = 'Select local date, time and time zone, then Apply. Nothing changes until you apply.'
        }
        catch {
            $message = "Unable to load clock settings: $($_.Exception.Message)"
            $status.Text = $message
            Write-Error -Message $message -ErrorAction Continue
            Write-OOBEMenuLog -Message $message
        }
    })
    $window.FindName('ApplyClockButton').Add_Click({
        if ($Phase -ne 'SetupComplete') { return }
        try {
            $selectedDate = $window.FindName('DatePicker').SelectedDate
            $selectedZone = $window.FindName('TimeZoneComboBox').SelectedValue
            if ($null -eq $selectedDate -or -not $selectedZone) { throw 'Select a date and time zone before applying.' }
            $status.Text = Set-OOBEMenuClock -Date $selectedDate -Time $window.FindName('TimeTextBox').Text `
                -TimeZoneId $selectedZone -PreviewOnly:$Preview
        }
        catch {
            $message = "Unable to apply clock settings: $($_.Exception.Message). Check the current clock/time zone before retrying."
            $status.Text = $message
            Write-Error -Message $message -ErrorAction Continue
            Write-OOBEMenuLog -Message $message
        }
    })
    $paneToggle = $window.FindName('PaneToggleButton')
    $paneToggle.Add_Click({
        $state.PaneExpanded = -not $state.PaneExpanded
        $window.FindName('SidebarColumn').Width = if ($state.PaneExpanded) { 200 } else { 56 }
        foreach ($labelName in 'CommandLabel', 'PowerShellLabel', 'ToolsLabel', 'ClockLabel') {
            $window.FindName($labelName).Visibility = if ($state.PaneExpanded) { 'Visible' } else { 'Collapsed' }
        }
        foreach ($button in $commandButton, $powerShellButton, $toolsButton, $clockButton) {
            $button.HorizontalContentAlignment = if ($state.PaneExpanded) { 'Stretch' } else { 'Center' }
        }
        $name = if ($state.PaneExpanded) { 'Collapse navigation' } else { 'Expand navigation' }
        $paneToggle.ToolTip = $name
        [System.Windows.Automation.AutomationProperties]::SetName($paneToggle, $name)
    })
    $continueButton.Add_Click({ $window.Close() })
    $window.FindName('CloseButton').Add_Click({ $window.Close() })
    $window.FindName('MinimizeButton').Add_Click({ $window.WindowState = 'Minimized' })
    $window.FindName('MaximizeButton').Add_Click({
        $window.WindowState = if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
    })
    $window.Add_StateChanged({
        $window.FindName('MaximizeGlyph').Text = if ($window.WindowState -eq 'Maximized') { [char]0xE923 } else { [char]0xE922 }
        $name = if ($window.WindowState -eq 'Maximized') { 'Restore' } else { 'Maximize' }
        $window.FindName('MaximizeButton').ToolTip = $name
        [System.Windows.Automation.AutomationProperties]::SetName($window.FindName('MaximizeButton'), $name)
    })
    $window.Add_PreviewKeyDown({
        if ($_.Key -eq [System.Windows.Input.Key]::Escape) { $_.Handled = $true; $window.Close() }
    })
    $window.Add_ContentRendered({
        try {
            if (-not [Recast.OOBE.Native]::IsInputDesktop()) {
                throw 'The rendered menu is not on the console input desktop.'
            }
            Write-OOBEMenuLog -Message "Menu visible: session $([System.Diagnostics.Process]::GetCurrentProcess().SessionId), station $([Recast.OOBE.Native]::Station), desktop $([Recast.OOBE.Native]::Desktop)."
            if ($ReadyEventName) {
                $signal = [System.Threading.EventWaitHandle]::OpenExisting($ReadyEventName)
                try { [void]$signal.Set() } finally { $signal.Dispose() }
            }
            [void]$commandButton.Focus()
            [void]$window.Activate()
            $window.Topmost = $false
        }
        catch {
            $state.ExitCode = 1
            $message = "Menu visibility/readiness failed: $($_.Exception.Message)"
            Write-Error -Message $message -ErrorAction Continue
            Write-OOBEMenuLog -Message $message
            $window.Close()
        }
    })
    [void]$window.ShowDialog()
    return $state.ExitCode
}

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
        Write-OOBEMenuLog -Message "Start $Phase menu: identity $($context.Identity), session $($context.SessionId), station $($context.Station), desktop $($context.Desktop), console $($context.ConsoleSession), architecture $env:PROCESSOR_ARCHITECTURE."
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
