function Initialize-OSDCloudPreOOBEWireless {
    <#
    .SYNOPSIS
        Loads the inbox Native Wi-Fi interop

    .DESCRIPTION
        Enumerates wireless interfaces and networks without parsing localized output.
        New credentials are passed in memory as a temporary connection profile.

    .EXAMPLE
        PS> Initialize-OSDCloudPreOOBEWireless

        Loads the interop without opening a wireless handle.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
        Uses wlanapi.dll on AMD64 and ARM64. Does not require a user logon.
    #>
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Load Native Wi-Fi"
    if ('Recast.PreOOBE.Wireless' -as [type]) { return }
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security;
using System.Text;

namespace Recast.PreOOBE {
    public sealed class Wireless : IDisposable {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct InterfaceInfo {
            public Guid Id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Description;
            public int State;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct Ssid {
            public uint Length;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] Bytes;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct AvailableNetwork {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Profile;
            public Ssid Ssid;
            public uint BssType, BssidCount;
            [MarshalAs(UnmanagedType.Bool)] public bool Connectable;
            public uint Reason, PhyCount;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)] public uint[] Phys;
            [MarshalAs(UnmanagedType.Bool)] public bool MorePhys;
            public uint Signal;
            [MarshalAs(UnmanagedType.Bool)] public bool Security;
            public uint Auth, Cipher, Flags, Reserved;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct Connection {
            public int Mode;
            [MarshalAs(UnmanagedType.LPWStr)] public string Profile;
            public IntPtr Ssid, BssidList;
            public uint BssType, Flags;
        }
        [DllImport("wlanapi.dll")] private static extern uint WlanOpenHandle(uint version, IntPtr reserved, out uint negotiated, out IntPtr handle);
        [DllImport("wlanapi.dll")] private static extern uint WlanCloseHandle(IntPtr handle, IntPtr reserved);
        [DllImport("wlanapi.dll")] private static extern uint WlanEnumInterfaces(IntPtr handle, IntPtr reserved, out IntPtr list);
        [DllImport("wlanapi.dll")] private static extern uint WlanGetAvailableNetworkList(IntPtr handle, ref Guid id, uint flags, IntPtr reserved, out IntPtr list);
        [DllImport("wlanapi.dll")] private static extern uint WlanScan(IntPtr handle, ref Guid id, IntPtr ssid, IntPtr ies, IntPtr reserved);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] private static extern uint WlanConnect(IntPtr handle, ref Guid id, ref Connection connection, IntPtr reserved);
        [DllImport("wlanapi.dll")] private static extern void WlanFreeMemory(IntPtr memory);
        private IntPtr handle;

        public sealed class Network {
            public Guid InterfaceId;
            public string Name, Profile, SsidHex;
            public uint Signal, Auth, Cipher;
            public bool Connectable, Connected;
            public override string ToString() {
                string security = Auth == 1 && Cipher == 0 ? "Open" :
                    Auth == 6 ? "WPA2-Personal" : Auth == 9 ? "WPA3-Personal" : "Secured";
                return Name + " - " + Signal + "% - " + security + (String.IsNullOrEmpty(Profile) ? "" : " (saved)");
            }
        }
        private static void Check(uint code) {
            if (code != 0) throw new Win32Exception((int)code);
        }
        public Wireless() {
            uint version;
            Check(WlanOpenHandle(2, IntPtr.Zero, out version, out handle));
        }
        private InterfaceInfo[] Interfaces() {
            IntPtr list;
            Check(WlanEnumInterfaces(handle, IntPtr.Zero, out list));
            try {
                int count = Marshal.ReadInt32(list);
                InterfaceInfo[] result = new InterfaceInfo[count];
                int size = Marshal.SizeOf(typeof(InterfaceInfo));
                for (int i = 0; i < count; i++)
                    result[i] = (InterfaceInfo)Marshal.PtrToStructure(IntPtr.Add(list, 8 + i * size), typeof(InterfaceInfo));
                return result;
            } finally { WlanFreeMemory(list); }
        }
        public void Scan() {
            foreach (InterfaceInfo item in Interfaces()) {
                Guid id = item.Id;
                Check(WlanScan(handle, ref id, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero));
            }
        }
        public Network[] Networks() {
            List<Network> result = new List<Network>();
            foreach (InterfaceInfo item in Interfaces()) {
                Guid id = item.Id;
                IntPtr list;
                Check(WlanGetAvailableNetworkList(handle, ref id, 0, IntPtr.Zero, out list));
                try {
                    int count = Marshal.ReadInt32(list);
                    int size = Marshal.SizeOf(typeof(AvailableNetwork));
                    for (int i = 0; i < count; i++) {
                        AvailableNetwork n = (AvailableNetwork)Marshal.PtrToStructure(IntPtr.Add(list, 8 + i * size), typeof(AvailableNetwork));
                        if (n.Ssid.Length == 0 || n.Ssid.Length > 32) continue;
                        result.Add(new Network {
                            InterfaceId = id, Name = Encoding.UTF8.GetString(n.Ssid.Bytes, 0, (int)n.Ssid.Length),
                            SsidHex = BitConverter.ToString(n.Ssid.Bytes, 0, (int)n.Ssid.Length).Replace("-", ""),
                            Profile = n.Profile, Signal = n.Signal, Auth = n.Auth, Cipher = n.Cipher,
                            Connectable = n.Connectable, Connected = (n.Flags & 1) != 0
                        });
                    }
                } finally { WlanFreeMemory(list); }
            }
            return result.ToArray();
        }
        public static string ProfileXml(Network network, string password) {
            string auth, cipher, key = "";
            if (network.Auth == 1 && network.Cipher == 0) {
                auth = "open"; cipher = "none";
            } else {
                if ((network.Auth != 6 && network.Auth != 9) || network.Cipher != 4)
                    throw new InvalidOperationException("This security type requires a saved Windows Wi-Fi profile.");
                if (password == null || password.Length < 8 || password.Length > 63)
                    throw new ArgumentException("Enter a password of 8 to 63 characters.");
                auth = network.Auth == 9 ? "WPA3SAE" : "WPA2PSK"; cipher = "AES";
                key = "<sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>" +
                    SecurityElement.Escape(password) + "</keyMaterial></sharedKey>";
            }
            return "<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\"><name>OSDCloudPreOOBE</name>" +
                "<SSIDConfig><SSID><hex>" + network.SsidHex + "</hex></SSID></SSIDConfig>" +
                "<connectionType>ESS</connectionType><connectionMode>manual</connectionMode><MSM><security><authEncryption>" +
                "<authentication>" + auth + "</authentication><encryption>" + cipher +
                "</encryption><useOneX>false</useOneX></authEncryption>" + key + "</security></MSM></WLANProfile>";
        }
        public void Connect(Network network, string password) {
            Connection connection = new Connection();
            connection.BssType = 1;
            if (!String.IsNullOrEmpty(network.Profile)) {
                connection.Mode = 0; connection.Profile = network.Profile;
            } else {
                connection.Mode = 1; connection.Profile = ProfileXml(network, password);
            }
            Guid id = network.InterfaceId;
            Check(WlanConnect(handle, ref id, ref connection, IntPtr.Zero));
        }
        public void Dispose() {
            if (handle != IntPtr.Zero) {
                uint code = WlanCloseHandle(handle, IntPtr.Zero);
                handle = IntPtr.Zero;
                Check(code);
            }
        }
    }
}
'@
}

function Invoke-OSDCloudPreOOBEWirelessRecovery {
    <#
    .SYNOPSIS
        Offers Wi-Fi recovery after an unsuccessful internet check

    .DESCRIPTION
        Detects physical wireless adapters, starts WLAN AutoConfig if needed, and
        opens the standalone dialog. Errors are reported and preserve offline skips.

    .PARAMETER State
        Shared progress and cooperative cancellation state.

    .EXAMPLE
        PS> Invoke-OSDCloudPreOOBEWirelessRecovery -State $state

        Offers recovery for the active task if physical wireless hardware exists.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Boolean. True after wireless association; otherwise false.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
        Preview and cancelled tasks never enumerate hardware or open a dialog.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Check wireless recovery"
    if ($Preview -or $State.CancelRequested) { return $false }
    try {
        $adapters = @(Get-CimInstance -Namespace root\StandardCimv2 -ClassName MSFT_NetAdapter -Filter 'HardwareInterface = TRUE' -ErrorAction Stop |
            Where-Object { $_.NdisPhysicalMedium -in 1, 9 })
        if ($State.CancelRequested) { return $false }
        if (-not $adapters.Count) {
            Write-OOBEMenuUpdateStatus -State $State -Message 'No physical Wi-Fi adapter detected. Check the wireless hardware and driver.'
            return $false
        }
        Write-OOBEMenuUpdateStatus -State $State -Message 'Wireless adapter detected. Opening Wi-Fi connection dialog.'
        $service = Get-Service -Name WlanSvc -ErrorAction Stop
        if ($service.Status -ne 'Running') {
            Start-Service -Name WlanSvc -ErrorAction Stop
            $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(10))
        }
        if ($State.CancelRequested) { return $false }
        return (Show-OSDCloudPreOOBEWireless -State $State)
    }
    catch {
        # Native failures must not include a profile or password in diagnostics.
        Write-OOBEMenuLog -Message "Wireless recovery failed ($($_.Exception.GetType().Name))."
        Write-OOBEMenuUpdateStatus -State $State -Message 'Wi-Fi recovery could not start. Check the wireless driver, radio and WLAN AutoConfig service; continuing offline.'
        return $false
    }
}

function Show-OSDCloudPreOOBEWireless {
    <#
    .SYNOPSIS
        Displays available Wi-Fi networks on the setup desktop

    .DESCRIPTION
        Offers saved profiles or temporary open/WPA2/WPA3 personal connections.
        Closes on cancellation, Skip, or after two minutes without interaction.
        A connection request has a 25-second association budget before retry.

    .PARAMETER State
        Shared progress and cooperative cancellation state.

    .EXAMPLE
        PS> Show-OSDCloudPreOOBEWireless -State $state

        Offers network selection, a masked password field, Connect and Skip.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Boolean. True only after association, not proof of internet access.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
        Runs on the task's STA worker. Credentials are never written to disk or logs.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Show Wi-Fi"
    if ($Preview -or $State.CancelRequested) { return $false }
    Initialize-OSDCloudPreOOBEWireless
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="OSDCloud PreOOBE - Connect to Wi-Fi" Width="560" Height="460" MinWidth="460" MinHeight="400"
 WindowStartupLocation="CenterScreen" Background="#161F5B" Foreground="#F5F5F5"
 FontFamily="Segoe UI" FontSize="14" Topmost="True">
 <Grid Margin="24">
  <Grid.RowDefinitions>
   <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
   <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
  </Grid.RowDefinitions>
  <TextBlock Text="Select a wireless network." TextWrapping="Wrap" Margin="0,0,0,16"/>
  <ListBox x:Name="Networks" Grid.Row="1" Background="#1C2868" Foreground="#F5F5F5"
   AutomationProperties.Name="Available wireless networks" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
  <StackPanel Grid.Row="2" Margin="0,16,0,0">
   <Label Content="_Password (new personal networks only)" Target="{Binding ElementName=Password}" Foreground="#F5F5F5"/>
   <PasswordBox x:Name="Password" AutomationProperties.Name="Wireless password" MaxLength="63" IsEnabled="False"/>
  </StackPanel>
  <TextBlock x:Name="Status" Grid.Row="3" Text="Scanning... Saved profiles do not require a password."
   TextWrapping="Wrap" Margin="0,12,0,12" AutomationProperties.LiveSetting="Polite"/>
  <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right">
   <Button x:Name="Refresh" Content="_Refresh" Padding="12,7" Margin="0,0,8,0"/>
   <Button x:Name="Connect" Content="_Connect" Padding="12,7" Margin="0,0,8,0" IsDefault="True"/>
   <Button x:Name="Skip" Content="_Skip" Padding="12,7" IsCancel="True"/>
  </StackPanel>
 </Grid>
</Window>
'@
    $reader = [Xml.XmlNodeReader]::new($xaml)
    try { $window = [Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }
    $wireless = $null
    Add-OSDCloudPreOOBESoftwarePointer -Window $window
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $ui = @{ Connected = $false; Pending = $null; Attempt = $null; Idle = [Diagnostics.Stopwatch]::StartNew(); Ticks = 0 }
    $loadNetworks = {
        $selected = $window.FindName('Networks').SelectedItem
        $networks = @($wireless.Networks() | Sort-Object -Property Signal -Descending)
        $window.FindName('Networks').ItemsSource = $networks
        if ($selected) {
            $window.FindName('Networks').SelectedItem = $networks | Where-Object {
                $_.InterfaceId -eq $selected.InterfaceId -and $_.SsidHex -eq $selected.SsidHex -and $_.Profile -eq $selected.Profile
            } | Select-Object -First 1
        }
    }
    $reportFailure = {
        Write-OOBEMenuLog -Message 'Wi-Fi operation failed; credentials and profile data omitted.'
        $window.FindName('Status').Text = 'Wi-Fi operation failed. Check the radio, driver or password, then retry or Skip.'
    }
    $window.FindName('Networks').Add_SelectionChanged({
        $window.FindName('Password').Clear()
        $network = $window.FindName('Networks').SelectedItem
        $window.FindName('Password').IsEnabled = $null -ne $network -and -not $network.Profile -and $network.Auth -in 6, 9 -and $network.Cipher -eq 4
        $ui.Idle.Restart()
    })
    $window.FindName('Password').Add_PasswordChanged({ $ui.Idle.Restart() })
    $window.FindName('Refresh').Add_Click({
        $ui.Idle.Restart()
        try { $wireless.Scan(); & $loadNetworks }
        catch { & $reportFailure }
    })
    $window.FindName('Connect').Add_Click({
        $ui.Idle.Restart()
        $network = $window.FindName('Networks').SelectedItem
        if (-not $network) { $window.FindName('Status').Text = 'Select a network first.'; return }
        if (-not $network.Connectable) { $window.FindName('Status').Text = 'This network is not connectable. Check radio and driver support.'; return }
        if (-not $network.Profile) {
            if (-not (($network.Auth -eq 1 -and $network.Cipher -eq 0) -or ($network.Auth -in 6, 9 -and $network.Cipher -eq 4))) {
                $window.FindName('Status').Text = 'This security type requires a saved Windows Wi-Fi profile. New connections support open and WPA2/WPA3-Personal networks.'
                return
            }
            if ($network.Auth -in 6, 9 -and $window.FindName('Password').Password.Length -lt 8) {
                $window.FindName('Status').Text = 'Enter a password of 8 to 63 characters.'
                return
            }
        }
        try {
            $wireless.Connect($network, $window.FindName('Password').Password)
            $ui.Pending = $network
            $ui.Attempt = [Diagnostics.Stopwatch]::StartNew()
            $window.FindName('Connect').IsEnabled = $false
            $window.FindName('Refresh').IsEnabled = $false
            $window.FindName('Networks').IsEnabled = $false
            $window.FindName('Status').Text = 'Connecting... Waiting for wireless association.'
        }
        catch { & $reportFailure }
        finally { $window.FindName('Password').Clear() }
    })
    $window.FindName('Skip').Add_Click({ $window.Close() })
    $timer.Add_Tick({
        if ($State.CancelRequested -or $ui.Idle.Elapsed.TotalSeconds -ge 120) { $window.Close(); return }
        try {
            if ($ui.Pending) {
                $connected = @($wireless.Networks() | Where-Object {
                    $_.Connected -and $_.InterfaceId -eq $ui.Pending.InterfaceId -and $_.SsidHex -eq $ui.Pending.SsidHex
                })
                if ($connected.Count) { $ui.Connected = $true; $window.Close(); return }
                if ($ui.Attempt.Elapsed.TotalSeconds -ge 25) {
                    $ui.Pending = $null
                    $window.FindName('Connect').IsEnabled = $true
                    $window.FindName('Refresh').IsEnabled = $true
                    $window.FindName('Networks').IsEnabled = $true
                    $window.FindName('Status').Text = 'Connection timed out. Check the password and signal, then retry or Skip.'
                }
            }
            elseif ($ui.Ticks -lt 3) {
                $ui.Ticks++
                if ($ui.Ticks -eq 3 -and -not $window.FindName('Networks').SelectedItem) {
                    & $loadNetworks
                    $window.FindName('Status').Text = 'Select a network, then Connect. Use Refresh to scan again.'
                }
            }
        }
        catch {
            & $reportFailure
            $window.Close()
        }
    })
    $window.Add_Closed({ $timer.Stop(); $window.FindName('Password').Clear() })
    try {
        $wireless = New-Object -TypeName Recast.PreOOBE.Wireless -ErrorAction Stop
        try { $wireless.Scan() }
        catch { & $reportFailure }
        & $loadNetworks
        $timer.Start()
        [void]$window.ShowDialog()
    }
    finally {
        $timer.Stop()
        if ($wireless) { $wireless.Dispose() }
    }
    $message = if ($ui.Connected) { 'Wi-Fi associated. Association alone does not verify internet access.' } else { 'Wi-Fi recovery skipped, cancelled or timed out; continuing without a new connection.' }
    Write-OOBEMenuUpdateStatus -State $State -Message $message
    return $ui.Connected
}
