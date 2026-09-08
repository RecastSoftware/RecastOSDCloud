function Start-OSDCloudExplorer {
    <#
    .SYNOPSIS
        Opens a graphical file browser for WinPE and WinRE environments.

    .DESCRIPTION
        Provides a Windows Forms file browser with TreeView, ListView, navigation
        (Up), and keyboard shortcuts. Designed for use in
        Windows PE and Windows RE where Windows Explorer is not available.

        The WinPE image must include:
          - WinPE-NetFX
          - WinPE-PowerShell

    .EXAMPLE
        Start-OSDCloudExplorer

        Opens the file browser. Use the CopyPath button or Ctrl+C to copy
        a path to the clipboard.
    #>
    [CmdletBinding()]
    param (
        # Internal: run the WinForms UI inline (blocking) inside the spawned child process.
        # Not intended for direct use — hidden from tab-completion.
        [Parameter(DontShow = $true)]
        [switch]$DirectLaunch
    )

    $ErrorActionPreference = 'Stop'

    # ── Non-blocking launch: spawn a separate PowerShell process and return immediately ──
    if (-not $DirectLaunch) {
        $modulePsd1 = Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'OSDCloud.psd1'
        $exePath = if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell' }
        $cmd     = "Import-Module '$modulePsd1'; Start-OSDCloudExplorer -DirectLaunch"
        $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
        Start-Process -FilePath $exePath -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-STA', '-WindowStyle', 'Hidden',
            '-EncodedCommand', $encoded
        )
        return
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing       -ErrorAction Stop
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Cannot load WinForms assemblies. Ensure WinPE-NetFX is available.`n$($_.Exception.Message)"
                ),
                'WinFormsLoadFailed',
                [System.Management.Automation.ErrorCategory]::NotInstalled,
                $null
            )
        )
    }

# ── DPI Awareness — must be set before any window is created ─────────────────
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class OSDCloudDpiHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
'@ -ErrorAction SilentlyContinue
}
catch {
    # user32.dll always present on Windows; silently continue if type already loaded
}
try { [OSDCloudDpiHelper]::SetProcessDPIAware() | Out-Null } catch {}

# ── Native Explorer visual theme (smooth selection highlight, modern scrollbars) ──
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class OSDCloudExplorerNative {
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    public static extern int SetWindowTheme(IntPtr hwnd, string appName, string idList);
}
'@ -ErrorAction SilentlyContinue
}
catch {
    # Theme API not available — continue without native visuals
}

# ── Script-scope state ─────────────────────────────────────────────────────────
$script:NavHistory   = [System.Collections.Generic.Stack[string]]::new()
$script:NavForward   = [System.Collections.Generic.Stack[string]]::new()
$script:CurrentPath  = ''
$script:IsNavigating = $false

# Icon index constants — must match order added to the ImageList
$script:IconDrive    = 0
$script:IconFolder   = 1
$script:IconFile     = 2
$script:IconComputer = 3

function Get-AvailableDrives {
    <#
    .SYNOPSIS
        Returns all ready, accessible filesystem drives.
    #>
    $drives = [System.Collections.Generic.List[System.IO.DriveInfo]]::new()
    try {
        foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
            try {
                if ($drive.IsReady) {
                    $drives.Add($drive)
                }
            }
            catch {
                # Skip drives that throw on access (e.g. ejected media)
            }
        }
    }
    catch {
        Write-Verbose "Get-AvailableDrives: $($_.Exception.Message)"
    }
    return $drives
}

function Get-DirectoryContents {
    <#
    .SYNOPSIS
        Returns directory items (dirs first, then files) without throwing on access errors.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $items = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()
    try {
        $all = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        # Directories first, then files — both sorted by name
        $dirs  = @($all | Where-Object { $_.PSIsContainer } | Sort-Object Name)
        $files = @($all | Where-Object { -not $_.PSIsContainer } | Sort-Object Name)
        foreach ($d in $dirs)  { $items.Add($d) }
        foreach ($f in $files) { $items.Add($f) }
    }
    catch {
        Write-Verbose "Get-DirectoryContents '$Path': $($_.Exception.Message)"
    }
    return $items
}

function Test-HasSubDirectories {
    <#
    .SYNOPSIS
        Returns $true if the given path contains at least one subdirectory.
        Used to decide whether to add a dummy child to a TreeNode.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    try {
        $first = Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        return ($null -ne $first)
    }
    catch {
        return $false
    }
}

function New-DriveIcon {
    <#
    .SYNOPSIS
        Returns a Bitmap representing a classic hard-drive icon, scaled to $Size x $Size.
    #>
    param ([int]$Size = 16)
    $bmp = [System.Drawing.Bitmap]::new($Size, $Size)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.ScaleTransform(($Size / 16.0), ($Size / 16.0))
    $g.Clear([System.Drawing.Color]::Transparent)

    $bodyBrush   = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(180, 180, 180))
    $topBrush    = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(210, 210, 210))
    $outlinePen  = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(80, 80, 80), 1)
    $ledBrush    = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(0, 160, 0))

    # Drive body
    $g.FillRectangle($topBrush, 2, 3, 12, 4)
    $g.FillRectangle($bodyBrush, 2, 7, 12, 5)
    $g.DrawRectangle($outlinePen, 2, 3, 12, 9)
    # Activity LED
    $g.FillRectangle($ledBrush, 11, 9, 2, 2)

    $g.Dispose(); $bodyBrush.Dispose(); $topBrush.Dispose(); $outlinePen.Dispose(); $ledBrush.Dispose()
    return $bmp
}

function New-FolderIcon {
    <#
    .SYNOPSIS
        Returns a Bitmap representing a classic yellow folder icon, scaled to $Size x $Size.
    #>
    param ([int]$Size = 16)
    $bmp = [System.Drawing.Bitmap]::new($Size, $Size)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.ScaleTransform(($Size / 16.0), ($Size / 16.0))
    $g.Clear([System.Drawing.Color]::Transparent)

    $fillBrush   = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 205, 50))
    $tabBrush    = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 220, 100))
    $shadowBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(200, 160, 20))
    $outlinePen  = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(160, 120, 0), 1)

    # Folder tab (top-left ear)
    $tab = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $tab.AddLines([System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(1, 6),
        [System.Drawing.Point]::new(1, 3),
        [System.Drawing.Point]::new(6, 3),
        [System.Drawing.Point]::new(7, 5),
        [System.Drawing.Point]::new(14, 5),
        [System.Drawing.Point]::new(14, 6)
    ))
    $g.FillPath($tabBrush, $tab)
    $g.DrawPath($outlinePen, $tab)
    $tab.Dispose()

    # Folder body with shadow
    $g.FillRectangle($shadowBrush, 1, 12, 14, 2)
    $g.FillRectangle($fillBrush, 1, 6, 14, 8)
    $g.DrawRectangle($outlinePen, 1, 6, 14, 8)

    $g.Dispose(); $fillBrush.Dispose(); $tabBrush.Dispose(); $shadowBrush.Dispose(); $outlinePen.Dispose()
    return $bmp
}

function New-ComputerIcon {
    <#
    .SYNOPSIS
        Returns a Bitmap representing a classic computer/monitor icon, scaled to $Size x $Size.
    #>
    param ([int]$Size = 16)
    $bmp = [System.Drawing.Bitmap]::new($Size, $Size)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.ScaleTransform(($Size / 16.0), ($Size / 16.0))
    $g.Clear([System.Drawing.Color]::Transparent)

    $monitorBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(180, 180, 180))
    $screenBrush  = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(58, 110, 165))
    $baseBrush    = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(160, 160, 160))
    $outlinePen   = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(60, 60, 60), 1)

    # Monitor body
    $g.FillRectangle($monitorBrush, 1, 1, 14, 10)
    $g.DrawRectangle($outlinePen, 1, 1, 14, 10)
    # Screen (blue)
    $g.FillRectangle($screenBrush, 3, 2, 10, 7)
    # Stand
    $g.FillRectangle($baseBrush, 6, 12, 4, 1)
    $g.FillRectangle($baseBrush, 4, 13, 8, 2)
    $g.DrawRectangle($outlinePen, 4, 13, 8, 2)

    $g.Dispose(); $monitorBrush.Dispose(); $screenBrush.Dispose(); $baseBrush.Dispose(); $outlinePen.Dispose()
    return $bmp
}

function New-UpIcon {
    <#
    .SYNOPSIS
        Returns a Bitmap for the Up (parent folder) toolbar button, scaled to $Size x $Size.
    #>
    param ([int]$Size = 16)
    $bmp = [System.Drawing.Bitmap]::new($Size, $Size)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.ScaleTransform(($Size / 16.0), ($Size / 16.0))
    $g.Clear([System.Drawing.Color]::Transparent)

    $folderBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 205, 50))
    $outlinePen  = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(160, 120, 0), 1)
    $arrowBrush  = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(0, 128, 0))

    # Small folder in bottom-left
    $g.FillRectangle($folderBrush, 0, 8, 10, 7)
    $g.DrawRectangle($outlinePen, 0, 8, 10, 7)

    # Green up arrow in top-right
    $arrow = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $arrow.AddLines([System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(11, 2),
        [System.Drawing.Point]::new(15, 7),
        [System.Drawing.Point]::new(13, 7),
        [System.Drawing.Point]::new(13, 12),
        [System.Drawing.Point]::new(9, 12),
        [System.Drawing.Point]::new(9, 7),
        [System.Drawing.Point]::new(7, 7),
        [System.Drawing.Point]::new(11, 2)
    ))
    $g.FillPath($arrowBrush, $arrow)
    $arrow.Dispose()

    $g.Dispose(); $folderBrush.Dispose(); $outlinePen.Dispose(); $arrowBrush.Dispose()
    return $bmp
}

function New-FileIcon {
    <#
    .SYNOPSIS
        Returns a Bitmap representing a generic file (Fluent-style flat icon), scaled to $Size x $Size.
    #>
    param ([int]$Size = 16)
    $bmp = [System.Drawing.Bitmap]::new($Size, $Size)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.ScaleTransform(($Size / 16.0), ($Size / 16.0))
    $g.Clear([System.Drawing.Color]::Transparent)

    $fillBrush  = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $outlinePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(200, 200, 200), 1)
    $foldBrush  = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(232, 232, 232))

    # Page body (with folded top-right corner)
    $page = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $page.AddLines([System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(2,  1),
        [System.Drawing.Point]::new(10, 1),
        [System.Drawing.Point]::new(13, 4),
        [System.Drawing.Point]::new(13, 15),
        [System.Drawing.Point]::new(2,  15),
        [System.Drawing.Point]::new(2,  1)
    ))
    $g.FillPath($fillBrush, $page)
    $g.DrawPath($outlinePen, $page)

    # Folded corner triangle
    $fold = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $fold.AddLines([System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(10, 1),
        [System.Drawing.Point]::new(13, 4),
        [System.Drawing.Point]::new(10, 4),
        [System.Drawing.Point]::new(10, 1)
    ))
    $g.FillPath($foldBrush, $fold)
    $g.DrawPath($outlinePen, $fold)

    $page.Dispose(); $fold.Dispose()
    $g.Dispose(); $fillBrush.Dispose(); $outlinePen.Dispose(); $foldBrush.Dispose()
    return $bmp
}

function Add-NavigationHistory {
    <#
    .SYNOPSIS
        Pushes the given path onto the back-history stack and clears forward history.
        Call this BEFORE changing $script:CurrentPath.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path
    )
    if ($Path -ne '') {
        $script:NavHistory.Push($Path)
    }
    $script:NavForward.Clear()
}

function Update-NavigationButtons {
    <#
    .SYNOPSIS
        Enables or disables Up and CopyPath toolbar buttons based on current state.
    #>
    $script:btnSelect.Enabled  = ($script:CurrentPath -ne '')

    # Up is enabled if there is a parent directory
    if ($script:CurrentPath -ne '') {
        $parent = [System.IO.Path]::GetDirectoryName($script:CurrentPath)
        $script:btnUp.Enabled = ($null -ne $parent -and $parent -ne '')
    }
    else {
        $script:btnUp.Enabled = $false
    }
}

function Update-ListView {
    <#
    .SYNOPSIS
        Clears and repopulates the ListView with the contents of the given path.
        Requires $script:listView and $script:statusLabel to be in scope.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $script:listView.BeginUpdate()
    $script:listView.Items.Clear()

    $items = Get-DirectoryContents -Path $Path

    foreach ($item in $items) {
        $lvi = [System.Windows.Forms.ListViewItem]::new($item.Name)

        if ($item.PSIsContainer) {
            # Directory
            $lvi.ImageIndex = $script:IconFolder
            $lvi.SubItems.Add('')       # Size — blank for folders
            $lvi.SubItems.Add('File Folder')
        }
        else {
            # File
            $lvi.ImageIndex = $script:IconFile
            $sizeKb = [math]::Ceiling($item.Length / 1KB)
            $lvi.SubItems.Add("$sizeKb KB")
            $ext = $item.Extension.TrimStart('.')
            if ($ext -eq '') { $ext = 'File' }
            $lvi.SubItems.Add($ext.ToUpper())
        }

        # Modified
        try {
            $lvi.SubItems.Add($item.LastWriteTime.ToString('M/d/yyyy h:mm tt'))
        }
        catch {
            $lvi.SubItems.Add('')
        }

        # Tag = full path (used for navigation on double-click)
        $lvi.Tag = $item.FullName

        $script:listView.Items.Add($lvi) | Out-Null
    }

    $script:listView.EndUpdate()

    # Reset status bar: 0 selected, update free space for current drive
    $script:statusLabel.Text = '0 objects selected'
    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        if ($root) {
            $driveInfo = [System.IO.DriveInfo]::new($root)
            if ($driveInfo.IsReady) {
                $freeBytes = $driveInfo.AvailableFreeSpace
                if ($freeBytes -ge 1GB) {
                    $script:statusFreeSpace.Text = '(Disk free space: {0:N2} GB)' -f ($freeBytes / 1GB)
                }
                else {
                    $script:statusFreeSpace.Text = '(Disk free space: {0:N2} MB)' -f ($freeBytes / 1MB)
                }
            }
        }
    }
    catch {
        $script:statusFreeSpace.Text = ''
    }
}

function Sync-TreeViewToPath {
    <#
    .SYNOPSIS
        Selects the TreeView node whose Tag matches the given path (case-insensitive).
        Expands parent nodes as needed. Suppressed via $script:IsNavigating guard.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $script:IsNavigating = $true
    try {
        # Walk all drive-level nodes under the Computer root
        $computerNode = $script:treeView.Nodes[0]
        foreach ($driveNode in $computerNode.Nodes) {
            $drivePath = $driveNode.Tag
            if ($Path -like "$drivePath*") {
                # Ensure the drive node is expanded (triggers lazy-load if needed)
                if (-not $driveNode.IsExpanded) {
                    $driveNode.Expand()
                }
                # Walk the remaining path segments
                $relative = $Path.Substring($drivePath.Length).TrimStart('\')
                $segments = $relative -split '\\'

                $currentNode = $driveNode
                foreach ($seg in $segments) {
                    if ($seg -eq '') { continue }
                    $found = $false
                    foreach ($child in $currentNode.Nodes) {
                        if ($child.Text -eq $seg) {
                            if (-not $child.IsExpanded) {
                                $child.Expand()
                            }
                            $currentNode = $child
                            $found = $true
                            break
                        }
                    }
                    if (-not $found) { break }
                }
                $script:treeView.SelectedNode = $currentNode
                $currentNode.EnsureVisible()
                break
            }
        }
    }
    catch {
        Write-Verbose "Sync-TreeViewToPath '$Path': $($_.Exception.Message)"
    }
    finally {
        $script:IsNavigating = $false
    }
}

function Invoke-Navigate {
    <#
    .SYNOPSIS
        Central navigation function. Updates all UI state for the new path.
        Does NOT push to history — callers must call Add-NavigationHistory first when needed.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if ($Path -eq '') { return }

    # Normalise trailing backslash for drive roots (e.g. "C:\" not "C:")
    if ($Path -match '^[A-Za-z]:$') {
        $Path = $Path + '\'
    }

    $script:CurrentPath = $Path
    $script:txtAddress.Text = $Path

    Update-ListView             -Path $Path
    Sync-TreeViewToPath         -Path $Path
    Update-NavigationButtons
}

function New-TreeDriveNode {
    <#
    .SYNOPSIS
        Creates a TreeNode for a drive. Adds a dummy child "..." if the drive has subdirs.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.DriveInfo]$Drive
    )
    $label = $Drive.Name.TrimEnd('\')
    if ($Drive.DriveType -eq [System.IO.DriveType]::Fixed) {
        try {
            $volLabel = $Drive.VolumeLabel
            if ($volLabel -ne '') {
                $label = "$volLabel ($($Drive.Name.TrimEnd('\')))"
            }
        }
        catch {
            Write-Verbose "New-TreeDriveNode: cannot read volume label for $($Drive.Name) — $($_.Exception.Message)"
        }
    }

    $node            = [System.Windows.Forms.TreeNode]::new($label)
    $node.Tag        = $Drive.RootDirectory.FullName
    $node.ImageIndex = $script:IconDrive
    $node.SelectedImageIndex = $script:IconDrive

    if (Test-HasSubDirectories -Path $Drive.RootDirectory.FullName) {
        $dummy = [System.Windows.Forms.TreeNode]::new('...')
        $node.Nodes.Add($dummy) | Out-Null
    }
    return $node
}

function Add-TreeSubNodes {
    <#
    .SYNOPSIS
        Lazy-loads child folder nodes for the given TreeNode.
        Replaces the placeholder "..." dummy child with real subdirectory nodes.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TreeNode]$Node
    )
    $parentPath = $Node.Tag
    $Node.Nodes.Clear()

    $dirs = @()
    try {
        $dirs = @(Get-ChildItem -LiteralPath $parentPath -Directory -Force -ErrorAction SilentlyContinue |
                  Sort-Object Name)
    }
    catch {
        Write-Verbose "Add-TreeSubNodes '$parentPath': $($_.Exception.Message)"
        $dirs = @()
    }

    foreach ($dir in $dirs) {
        $child            = [System.Windows.Forms.TreeNode]::new($dir.Name)
        $child.Tag        = $dir.FullName
        $child.ImageIndex = $script:IconFolder
        $child.SelectedImageIndex = $script:IconFolder

        if (Test-HasSubDirectories -Path $dir.FullName) {
            $dummy = [System.Windows.Forms.TreeNode]::new('...')
            $child.Nodes.Add($dummy) | Out-Null
        }
        $Node.Nodes.Add($child) | Out-Null
    }
}

[System.Windows.Forms.Application]::EnableVisualStyles()
# Note: SetCompatibleTextRenderingDefault is intentionally omitted.
# It throws if WinForms was previously initialised in the same PS session,
# and it has no meaningful effect on this application's text rendering.

# ── DPI scale factor — measured after EnableVisualStyles so GDI+ is ready ────
$dpiScale = 1.0
try {
    $hdc = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $dpiScale = [double]$hdc.DpiX / 96.0
    $hdc.Dispose()
}
catch {
    $dpiScale = 1.0
}
$iconSize = [int](16 * $dpiScale)

# Win11-aligned color palette (matches Invoke-WinPEWifi)
$script:ColorBackground = [System.Drawing.Color]::FromArgb(243, 243, 243)  # #F3F3F3
$script:ColorSurface    = [System.Drawing.Color]::FromArgb(255, 255, 255)  # #FFFFFF
$script:ColorBorder     = [System.Drawing.Color]::FromArgb(232, 232, 232)  # #E8E8E8
$script:ColorAccent     = [System.Drawing.Color]::FromArgb(0, 95, 184)     # #005FB8
$script:ColorText       = [System.Drawing.Color]::FromArgb(26, 26, 26)     # #1A1A1A
$script:ColorSubtle     = [System.Drawing.Color]::FromArgb(92, 92, 92)     # #5C5C5C
$script:FontUI          = [System.Drawing.Font]::new('Segoe UI', 9)
$script:FontHeader      = [System.Drawing.Font]::new('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

$form                  = [System.Windows.Forms.Form]::new()
$form.Text             = 'OSDCloud Explorer'
$form.Size             = [System.Drawing.Size]::new([int](960 * $dpiScale), [int](640 * $dpiScale))
$form.MinimumSize      = [System.Drawing.Size]::new([int](640 * $dpiScale), [int](420 * $dpiScale))
$form.StartPosition    = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor        = $script:ColorBackground
$form.Font             = $script:FontUI
$form.KeyPreview       = $true
$form.AutoScaleMode    = [System.Windows.Forms.AutoScaleMode]::None

# ── Form Icon (embedded 32x32 PNG) ───────────────────────────────────────────
$iconBase64 = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAARFSURBVFhH7Zffb1NlGMf5B4zxQpm4vuecntOedqc957SnGuOvyI3RKNFo/I3GmKiJN0aMeuOFRhO9wBg76K/VbqvDuca5bKQwmDIWwuiGAiJGjLAfwJCtAxkO0y26r3mf0znartlQM2928U17Tt++76fP8/0+bdcIavJ5UWtNMU9yxcXPXcM8yYyiZyFpn6+4+LkcIMUvBE9yxcXPXQVYBagEUJNgLAJWuxXMUa4ImBSDoDZUbPZPVAnAN9ZSUJ7ohuvZHigbr9AzPVCe7IZ0dwZMjIGJUQjeyk2vRpUAShxiKA1zcBbWKGCdBaxfShX8CfClRyHd2QbG/h3E4gBWGmb/DMyDs1BfH4D66gGor+Xo0fPWIejZCwhNAMa+y5Bu3QbmjFdsvFxVB8jNwuidBhOiYDVhsJu2kBw31oPJMWjREwhNAnWbfySvlGysJOz3cb8IUQiuRMXBywPouwzBl6rYgG8s3dWGwPE5GD2X7Ba4G0gcRjSbIT+0HcrTuyFv6ITob7Qh+Zr/BEBJQAw0wxz4A8b+AkSziZLBnDFqmTlYgHUGsE7bMvt/h/uVfjs9ZRDVAQaqAzhqwpDv70RwGPB3nQdT4hRR7wc/IHQeMPqmyS/KU7ugbjpA17xdnrePUPWWBgilETgKmLkZ+lRs3Ra7n8U5IN3eCr1rEqE8oG7KwXHdR1Ae3QFrDNC356nkjrVhKrvjhjBd690XYA0Dzvs6bF9UBSjOAfmxnXC92ActdhJawxC0xDA99zWdQuDQn3Q4v8erwwG12BBFVt7QhdprP7RNyIeZEEXtNZtpjvD3eN87SuurAxCEXWbxlhYEjwHBE0DwOBA8WexprgDXS33kdoH31ZuEvvMirfG3noWv+TR86TMLajwFf/sEzRDftjF7dqjVAFy2wfwdefi/GIe0PgPpjlZIt30G570dMAdnEDg8A/HmFruf7gQEvRHGnmkEvp+D3j0FY9cU9Cu1ewr6jl+hZ/Pwvn/MnhtVAYomDByeg9lfAHMn7FI6Y3Bc/zHUNwbJaFp8eCFaapIO4q0RA2l7RHPjzovHk7dk3VYwOV4yOasCUAz3lqWAl1xLwdjzG6wRUNbnv7Dq6v9G6BygPN5NxiMvEVwDWE095Iez0NtH6PuFCQtJuDoAb5IM5HphL0LjgL/tnJ1/RwTyA50IjgL6VxchhlrsFPDJuTYM0foURu8lAuTxpQotBcDLae4vVM4B/qnkOPwdk5RtDmNXIQL1zYOwxgHzm1l43/0O7pf3wfPOEfKNNQF6fXlzINhMpvF/maeSlw8iXnL5kSwC307D1zJm95TPfxaB67mvKfPBoeIkHAGM3ilKDeV/yUlYlKg3QdQbS+6ViPvB30TVIkh+j/+QKRrTuT4D+cEuOO9ph1D3iX1/kR8xVQH+dnD5wctZw13PvcGdL8YWX1NUdYAV0irAKsA8QEb+n/4d83P/ArisDNuwOb5QAAAAAElFTkSuQmCC'
$iconBytes  = [Convert]::FromBase64String($iconBase64)
$iconStream = [System.IO.MemoryStream]::new($iconBytes)
$iconBitmap = [System.Drawing.Bitmap]::new($iconStream)
$form.Icon  = [System.Drawing.Icon]::FromHandle($iconBitmap.GetHicon())

# ── ImageList (DPI-scaled icons for TreeView + ListView) ─────────────────────
$imageList             = [System.Windows.Forms.ImageList]::new()
$imageList.ImageSize   = [System.Drawing.Size]::new($iconSize, $iconSize)
$imageList.ColorDepth  = [System.Windows.Forms.ColorDepth]::Depth32Bit
$imageList.Images.Add($(New-DriveIcon    -Size $iconSize)) | Out-Null   # index 0 = Drive
$imageList.Images.Add($(New-FolderIcon   -Size $iconSize)) | Out-Null   # index 1 = Folder
$imageList.Images.Add($(New-FileIcon     -Size $iconSize)) | Out-Null   # index 2 = File
$imageList.Images.Add($(New-ComputerIcon -Size $iconSize)) | Out-Null   # index 3 = Computer

# ── Status Strip ──────────────────────────────────────────────────────────────
$statusStrip              = [System.Windows.Forms.StatusStrip]::new()
$statusStrip.BackColor    = $script:ColorSurface
$statusStrip.ForeColor    = $script:ColorSubtle
$statusStrip.SizingGrip   = $false
$statusStrip.RenderMode   = [System.Windows.Forms.ToolStripRenderMode]::ManagerRenderMode
$statusLabel              = [System.Windows.Forms.ToolStripStatusLabel]::new()
$statusLabel.Text         = '0 objects selected'
$statusLabel.ForeColor    = $script:ColorSubtle
$statusLabel.TextAlign    = [System.Drawing.ContentAlignment]::MiddleLeft
$statusStrip.Items.Add($statusLabel) | Out-Null

$statusFreeSpace          = [System.Windows.Forms.ToolStripStatusLabel]::new()
$statusFreeSpace.Text     = ''
$statusFreeSpace.Spring   = $true
$statusFreeSpace.ForeColor = $script:ColorSubtle
$statusFreeSpace.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$statusStrip.Items.Add($statusFreeSpace) | Out-Null

$script:statusLabel     = $statusLabel
$script:statusFreeSpace = $statusFreeSpace

# ── ToolStrip (navigation bar) ─────────────────────────────────────────────────
$toolStrip             = [System.Windows.Forms.ToolStrip]::new()
$toolStrip.GripStyle   = [System.Windows.Forms.ToolStripGripStyle]::Hidden
$toolStrip.BackColor   = $script:ColorSurface
$toolStrip.RenderMode  = [System.Windows.Forms.ToolStripRenderMode]::System
$toolStrip.Padding     = [System.Windows.Forms.Padding]::new([int](4 * $dpiScale), [int](2 * $dpiScale), [int](4 * $dpiScale), [int](2 * $dpiScale))

$btnUp                 = [System.Windows.Forms.ToolStripButton]::new()
$btnUp.Image           = New-UpIcon -Size $iconSize
$btnUp.DisplayStyle    = [System.Windows.Forms.ToolStripItemDisplayStyle]::Image
$btnUp.Enabled         = $false
$btnUp.ToolTipText     = 'Up One Level (Alt+Up, Backspace)'

$sep1                  = [System.Windows.Forms.ToolStripSeparator]::new()

$lblAddress            = [System.Windows.Forms.ToolStripLabel]::new()
$lblAddress.Text       = 'Address:'
$lblAddress.ForeColor  = $script:ColorText

$txtAddress            = [System.Windows.Forms.ToolStripTextBox]::new()
$txtAddress.AutoSize   = $false
$txtAddress.Width      = [int](520 * $dpiScale)
$txtAddress.BackColor  = [System.Drawing.Color]::White
$txtAddress.ForeColor  = $script:ColorText
$txtAddress.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtAddress.ToolTipText = 'Type a path and press Enter or click Go'

$btnGo                 = [System.Windows.Forms.ToolStripButton]::new()
$btnGo.Text            = 'Go'
$btnGo.ForeColor       = $script:ColorText
$btnGo.ToolTipText     = 'Navigate to the path in the address bar'

$sep2                  = [System.Windows.Forms.ToolStripSeparator]::new()

$btnSelect             = [System.Windows.Forms.ToolStripButton]::new()
$btnSelect.Text        = 'CopyPath'
$btnSelect.Enabled     = $false
$btnSelect.Visible     = $false   # Hidden — re-enable when CopyPath feature is ready
$btnSelect.ForeColor   = $script:ColorAccent
$btnSelect.Font        = $script:FontHeader
$btnSelect.ToolTipText = 'Copy the selected path to clipboard (Ctrl+C)'

$toolStrip.Items.AddRange([System.Windows.Forms.ToolStripItem[]]@(
    $btnUp, $sep1, $lblAddress, $txtAddress, $btnGo, $sep2, $btnSelect
))

# Expose buttons to helper functions via script scope
$script:btnUp      = $btnUp
$script:btnSelect  = $btnSelect
$script:txtAddress = $txtAddress

# ── SplitContainer ─────────────────────────────────────────────────────────────
$splitContainer                   = [System.Windows.Forms.SplitContainer]::new()
$splitContainer.Dock              = [System.Windows.Forms.DockStyle]::Fill
$splitContainer.BackColor         = $script:ColorBorder
# SplitterWidth of 1 gives a thin modern divider line
$splitContainer.SplitterWidth     = 1
# Panel1MinSize, Panel2MinSize, and SplitterDistance are deferred to Form.Load.
# Setting them before layout triggers a constraint error.

# ── TreeView ───────────────────────────────────────────────────────────────────
$treeView                    = [System.Windows.Forms.TreeView]::new()
$treeView.Dock               = [System.Windows.Forms.DockStyle]::Fill
$treeView.BackColor          = $script:ColorSurface
$treeView.ForeColor          = $script:ColorText
$treeView.BorderStyle        = [System.Windows.Forms.BorderStyle]::None
$treeView.HideSelection      = $false
$treeView.ShowLines          = $true
$treeView.ShowPlusMinus      = $true
$treeView.ShowRootLines      = $true
$treeView.FullRowSelect      = $false
$treeView.ItemHeight         = [int](18 * $dpiScale)
$treeView.Indent             = [int](19 * $dpiScale)
$treeView.ImageList          = $imageList
$treeView.ImageIndex         = $script:IconFolder
$treeView.SelectedImageIndex = $script:IconFolder
# Double-buffer for flicker-free rendering
$treeView.GetType().GetProperty('DoubleBuffered',
    [System.Reflection.BindingFlags]'Instance,NonPublic').SetValue($treeView, $true, $null)
$splitContainer.Panel1.Controls.Add($treeView)

# Expose to helper functions
$script:treeView = $treeView

# ── ListView ───────────────────────────────────────────────────────────────────
$listView              = [System.Windows.Forms.ListView]::new()
$listView.Dock         = [System.Windows.Forms.DockStyle]::Fill
$listView.View         = [System.Windows.Forms.View]::Details
$listView.BackColor    = $script:ColorSurface
$listView.ForeColor    = $script:ColorText
$listView.BorderStyle  = [System.Windows.Forms.BorderStyle]::None
$listView.FullRowSelect = $true
$listView.GridLines    = $false
$listView.MultiSelect  = $false
$listView.SmallImageList = $imageList
# Double-buffer for flicker-free rendering
$listView.GetType().GetProperty('DoubleBuffered',
    [System.Reflection.BindingFlags]'Instance,NonPublic').SetValue($listView, $true, $null)

$colName     = [System.Windows.Forms.ColumnHeader]::new(); $colName.Text     = 'Name';          $colName.Width     = [int](300 * $dpiScale)
$colSize     = [System.Windows.Forms.ColumnHeader]::new(); $colSize.Text     = 'Size';          $colSize.Width     = [int](80 * $dpiScale);  $colSize.TextAlign  = [System.Windows.Forms.HorizontalAlignment]::Right
$colType     = [System.Windows.Forms.ColumnHeader]::new(); $colType.Text     = 'Type';          $colType.Width     = [int](100 * $dpiScale)
$colModified = [System.Windows.Forms.ColumnHeader]::new(); $colModified.Text = 'Modified'; $colModified.Width = [int](160 * $dpiScale)

$listView.Columns.AddRange([System.Windows.Forms.ColumnHeader[]]@(
    $colName, $colSize, $colType, $colModified
))

$splitContainer.Panel2.Controls.Add($listView)

# Expose to helper functions
$script:listView = $listView

# ── Assemble Form ──────────────────────────────────────────────────────────────
$form.Controls.Add($splitContainer)
$form.Controls.Add($toolStrip)
$form.Controls.Add($statusStrip)

# ── Auto-stretch address bar to fill available toolbar width ──────────────────
$form.add_SizeChanged({
    $fixedWidth = 0
    foreach ($item in $toolStrip.Items) {
        if ($item -is [System.Windows.Forms.ToolStripTextBox]) { continue }
        $fixedWidth += $item.Width + $item.Margin.Horizontal
    }
    $available = $toolStrip.ClientSize.Width - $fixedWidth - $toolStrip.Padding.Horizontal - 16
    if ($available -gt [int](200 * $dpiScale)) {
        $txtAddress.Width = $available
    }
})

# ── TreeView: Lazy-load on expand ─────────────────────────────────────────────
$treeView.add_BeforeExpand({
    param ($senderObj, $e)
    $node = $e.Node
    # Detect placeholder: exactly one child named "..."
    if ($node.Nodes.Count -eq 1 -and $node.Nodes[0].Text -eq '...') {
        try {
            Add-TreeSubNodes -Node $node
        }
        catch {
            Write-Verbose "BeforeExpand '${node.Tag}': $($_.Exception.Message)"
        }
    }
})

# ── TreeView: Navigate on selection ───────────────────────────────────────────
$treeView.add_AfterSelect({
    param ($senderObj, $e)
    # Guard: skip synthetic selections triggered by Invoke-Navigate → Sync-TreeViewToPath
    if ($script:IsNavigating) { return }

    $node = $e.Node
    if ($null -eq $node -or $null -eq $node.Tag) { return }

    $targetPath = $node.Tag.ToString()
    if ($targetPath -eq '' -or $targetPath -eq 'MyComputer') { return }

    Add-NavigationHistory -Path $script:CurrentPath
    Invoke-Navigate -Path $targetPath
})

# ── ListView: Update status on selection change ───────────────────────────────
$listView.add_SelectedIndexChanged({
    $count = $script:listView.SelectedItems.Count
    $script:statusLabel.Text = "$count object$(if ($count -ne 1) { 's' }) selected"
})

# ── ListView: Navigate into folder / open small file on double-click ──────────
$listView.add_DoubleClick({
    if ($script:listView.SelectedItems.Count -eq 0) { return }
    $item = $script:listView.SelectedItems[0]
    if ($null -eq $item.Tag) { return }

    $targetPath = $item.Tag.ToString()
    if ([System.IO.Directory]::Exists($targetPath)) {
        # Double-click a folder → navigate into it
        Add-NavigationHistory -Path $script:CurrentPath
        Invoke-Navigate -Path $targetPath
    }
    else {
        # Double-click a file → open in an appropriate viewer (never closes explorer)
        try {
            $fileInfo = [System.IO.FileInfo]::new($targetPath)
            $extension = $fileInfo.Extension

            if ($extension -eq '.exe') {
                # Executable → run it directly
                Start-Process -FilePath $targetPath
            }
            elseif ($extension -eq '.log' -and $fileInfo.Length -le 5MB) {
                # .log files under 5 MB → prefer CMTrace, fall back to notepad
                $cmTrace = Get-Command -Name 'cmtrace.exe' -ErrorAction Ignore
                if ($null -ne $cmTrace) {
                    Start-Process -FilePath $cmTrace.Source -ArgumentList $targetPath
                }
                elseif ($fileInfo.Length -le 100KB) {
                    Start-Process -FilePath 'notepad.exe' -ArgumentList $targetPath
                }
            }
            elseif ($fileInfo.Length -le 100KB) {
                # All other files 100 KB or smaller → notepad
                Start-Process -FilePath 'notepad.exe' -ArgumentList $targetPath
            }
        }
        catch {
            Write-Verbose "DoubleClick open file: $($_.Exception.Message)"
        }
    }
})

# ── CopyPath button ───────────────────────────────────────────────────────────
$btnSelect.add_Click({
    $pathToCopy = ''
    if ($script:listView.SelectedItems.Count -gt 0) {
        $pathToCopy = $script:listView.SelectedItems[0].Tag.ToString()
    }
    elseif ($script:CurrentPath -ne '') {
        $pathToCopy = $script:CurrentPath
    }
    if ($pathToCopy -ne '') {
        [System.Windows.Forms.Clipboard]::SetText($pathToCopy)
        $script:statusLabel.Text = "Copied: $pathToCopy"
    }
})

# ── Up button ─────────────────────────────────────────────────────────────────
$btnUp.add_Click({
    if ($script:CurrentPath -eq '') { return }
    $parent = [System.IO.Path]::GetDirectoryName($script:CurrentPath)
    if ($null -eq $parent -or $parent -eq '') { return }
    Add-NavigationHistory -Path $script:CurrentPath
    Invoke-Navigate -Path $parent
})

# ── Address bar: Enter key ────────────────────────────────────────────────────
$txtAddress.add_KeyDown({
    param ($senderObj, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Return) {
        $e.SuppressKeyPress = $true
        $target = $script:txtAddress.Text.Trim()
        if (Test-Path -LiteralPath $target) {
            Add-NavigationHistory -Path $script:CurrentPath
            Invoke-Navigate -Path $target
        }
        else {
            $script:statusLabel.Text = "Path not found: $target"
        }
    }
})

# ── Go button ─────────────────────────────────────────────────────────────────
$btnGo.add_Click({
    $target = $script:txtAddress.Text.Trim()
    if (Test-Path -LiteralPath $target) {
        Add-NavigationHistory -Path $script:CurrentPath
        Invoke-Navigate -Path $target
    }
    else {
        $script:statusLabel.Text = "Path not found: $target"
    }
})

# ── Keyboard shortcuts (form-level) ───────────────────────────────────────────
$form.add_KeyDown({
    param ($senderObj, $e)

    # Alt+Up or Backspace → Up
    if (($e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Up) -or
        ($e.KeyCode -eq [System.Windows.Forms.Keys]::Back -and -not $script:txtAddress.Focused)) {
        if ($script:btnUp.Enabled) { $script:btnUp.PerformClick() }
        $e.Handled = $true
        return
    }
    # Enter → Navigate into selected folder (like double-click)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Return) {
        if (-not $script:txtAddress.Focused -and $script:listView.SelectedItems.Count -gt 0) {
            $selectedItem = $script:listView.SelectedItems[0]
            if ($null -ne $selectedItem.Tag) {
                $targetPath = $selectedItem.Tag.ToString()
                if ([System.IO.Directory]::Exists($targetPath)) {
                    Add-NavigationHistory -Path $script:CurrentPath
                    Invoke-Navigate -Path $targetPath
                }
            }
            $e.Handled = $true
            return
        }
    }
    # Ctrl+C → Copy path to clipboard (when not in address bar)
    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::C) {
        if (-not $script:txtAddress.Focused) {
            if ($script:btnSelect.Enabled) { $script:btnSelect.PerformClick() }
            $e.Handled = $true
            return
        }
    }
    # F5 → Refresh
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        if ($script:CurrentPath -ne '') {
            Update-ListView -Path $script:CurrentPath
        }
        $e.Handled = $true
        return
    }
    # F4 or Ctrl+L → focus address bar
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F4 -or
        ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::L)) {
        $script:txtAddress.Focus() | Out-Null
        $script:txtAddress.SelectAll()
        $e.Handled = $true
        return
    }
})

# ── Form Load: build the TreeView and navigate to initial location ─────────────
$form.add_Load({
    # Set split-pane sizing here — the form now has its real width, so
    # the Panel1MinSize / Panel2MinSize / SplitterDistance constraints are satisfied.
    $splitContainer.Panel1MinSize    = [int](150 * $dpiScale)
    $splitContainer.Panel2MinSize    = [int](200 * $dpiScale)
    $splitContainer.SplitterDistance = [int](260 * $dpiScale)

    $script:treeView.BeginUpdate()

    # Root node "My Computer"
    $computerNode         = [System.Windows.Forms.TreeNode]::new('My Computer')
    $computerNode.Tag     = 'MyComputer'
    $computerNode.ImageIndex         = $script:IconComputer
    $computerNode.SelectedImageIndex = $script:IconComputer
    $script:treeView.Nodes.Add($computerNode) | Out-Null

    $drives = Get-AvailableDrives
    $firstDrivePath = ''

    foreach ($drive in $drives) {
        $driveNode = New-TreeDriveNode -Drive $drive
        $computerNode.Nodes.Add($driveNode) | Out-Null
        if ($firstDrivePath -eq '') {
            $firstDrivePath = $drive.RootDirectory.FullName
        }
    }

    $computerNode.Expand()
    $script:treeView.EndUpdate()

    # Auto-select start path:
    #   WinPE boot drive is always X:\ — use it when present
    #   Otherwise fall back to the first available drive
    if (Test-Path -LiteralPath 'X:\') {
        $startPath = 'X:\'
    }
    elseif ($firstDrivePath -ne '') {
        $startPath = $firstDrivePath
    }
    else {
        $script:statusLabel.Text = 'No drives found.'
        return
    }

    Invoke-Navigate -Path $startPath
})

    [System.Windows.Forms.Application]::Run($form)
}
