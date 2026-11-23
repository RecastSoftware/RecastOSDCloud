<#!
.SYNOPSIS
    OSDCloud deployment settings window for the recast workflow.
.DESCRIPTION
    Dark single-page card layout that matches OSDCloud Boot and OSDCloud BootMenu.
    Provides the same selections and deployment write-back as the default workflow UI.
#>
[CmdletBinding()]
param()
#================================================
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
#================================================
# XAML
$xamlfile = Get-Item -Path "$PSScriptRoot\MainWindow.xaml"
$xaml = Get-Content $xamlfile.FullName -Raw
$stringReader = [System.IO.StringReader]::new($xaml)
$xmlReader = [System.Xml.XmlReader]::Create($stringReader)
$window = [Windows.Markup.XamlReader]::Load($xmlReader)
#================================================
# Window Title
$OSDCloudModuleVersion = Get-OSDCloudModuleVersion
$VersionText = $window.FindName('VersionText')
if (-not [string]::IsNullOrWhiteSpace($OSDCloudModuleVersion)) {
    $VersionText.Text = $OSDCloudModuleVersion
    $window.Title = "Recast Software - OSDCloud $OSDCloudModuleVersion"
}
#================================================
# Logo
$logoImage = $window.FindName('LogoImage')
try {
    $logo = [System.Windows.Media.Imaging.BitmapImage]::new()
    $logo.BeginInit()
    $logo.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $logo.UriSource = [uri][System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\core\recast-logo.png'))
    $logo.EndInit()
    $logo.Freeze()
    $logoImage.Source = $logo
}
catch {
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] Recast logo unavailable: $($_.Exception.Message)"
    $logoImage.Visibility = [System.Windows.Visibility]::Collapsed
}
#================================================
# Work area
$workArea = [System.Windows.SystemParameters]::WorkArea
$window.MinWidth = [Math]::Min($window.MinWidth, $workArea.Width)
$window.MinHeight = [Math]::Min($window.MinHeight, $workArea.Height)
$window.Width = [Math]::Min($window.Width, $workArea.Width)
$window.Height = [Math]::Min($window.Height, $workArea.Height)
#================================================
# Title bar
$RootGrid = $window.FindName('RootGrid')
$MinimizeButton = $window.FindName('MinimizeButton')
$MaximizeButton = $window.FindName('MaximizeButton')
$MaximizeIcon = $window.FindName('MaximizeIcon')
$CloseButton = $window.FindName('CloseButton')
$updateWindowState = {
    $maximized = $window.WindowState -eq [System.Windows.WindowState]::Maximized
    $MaximizeIcon.Text = [string][char]$(if ($maximized) { 0xE923 } else { 0xE922 })
    $action = if ($maximized) { 'Restore' } else { 'Maximize' }
    $MaximizeButton.ToolTip = $action
    [System.Windows.Automation.AutomationProperties]::SetName($MaximizeButton, $action)
    $RootGrid.Margin = [System.Windows.Thickness]::new(0)
    $presentationSource = [System.Windows.PresentationSource]::FromVisual($window)
    if ($maximized -and $presentationSource) {
        # A maximized custom-chrome window extends past the monitor work area; inset the layout to keep it visible.
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
            $area = [System.Windows.Forms.Screen]::FromHandle($handle).WorkingArea
            $origin = $window.PointToScreen([System.Windows.Point]::new(0, 0))
            $end = $window.PointToScreen([System.Windows.Point]::new($window.ActualWidth, $window.ActualHeight))
            $transform = $presentationSource.CompositionTarget.TransformFromDevice
            $inset = $transform.Transform([System.Windows.Vector]::new(
                    [Math]::Max(0, $area.Left - $origin.X), [Math]::Max(0, $area.Top - $origin.Y)))
            $outset = $transform.Transform([System.Windows.Vector]::new(
                    [Math]::Max(0, $end.X - $area.Right), [Math]::Max(0, $end.Y - $area.Bottom)))
            $RootGrid.Margin = [System.Windows.Thickness]::new($inset.X, $inset.Y, $outset.X, $outset.Y)
        }
        catch {
            $RootGrid.Margin = [System.Windows.SystemParameters]::WindowResizeBorderThickness
        }
    }
    $window.BorderThickness = [System.Windows.Thickness]::new($(if ($maximized) { 0 } else { 1 }))
}
$window.Add_StateChanged($updateWindowState)
$window.Add_SizeChanged($updateWindowState)
$MinimizeButton.Add_Click({ [System.Windows.SystemCommands]::MinimizeWindow($window) })
$MaximizeButton.Add_Click({
        if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) {
            [System.Windows.SystemCommands]::RestoreWindow($window)
        }
        else {
            [System.Windows.SystemCommands]::MaximizeWindow($window)
        }
    })
$CloseButton.Add_Click({ [System.Windows.SystemCommands]::CloseWindow($window) })
$window.FindName('CancelButton').Add_Click({ $window.Close() })
#================================================
# Helpers
$StatusText = $window.FindName('StatusText')
$SummaryText = $window.FindName('SummaryText')
function Show-MainWindowMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [Parameter(Mandatory)]
        [string]$Caption,
        [Parameter(Mandatory)]
        [System.Windows.MessageBoxImage]$Image
    )
    [System.Windows.MessageBox]::Show($window, $Message, $Caption, [System.Windows.MessageBoxButton]::OK, $Image) | Out-Null
}
function Set-ClipboardText {
    param([string]$Text)
    # Clipboard access can be temporarily locked by another process; retry briefly.
    $maxRetries = 5
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            [System.Windows.Clipboard]::SetText($Text)
            return $true
        }
        catch {
            if ($i -lt ($maxRetries - 1)) {
                Start-Sleep -Milliseconds 100
            }
            else {
                Write-Warning "Failed to copy to clipboard: $_"
            }
        }
    }
    return $false
}
function Copy-MainWindowValue {
    param(
        [string]$Text,
        [Parameter(Mandatory)]
        [string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }
    $StatusText.Text = if (Set-ClipboardText -Text $Text) { "$Label copied to the clipboard." } else { "$Label could not be copied to the clipboard." }
}
function Open-MainWindowLogFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        Show-MainWindowMessage -Message 'Log file not found.' -Caption 'Open Log' -Image Warning
        return
    }
    try {
        Start-Process -FilePath 'notepad.exe' -ArgumentList @("`"$Path`"") -ErrorAction Stop
    }
    catch {
        Show-MainWindowMessage -Message "Failed to open log: $($_.Exception.Message)" -Caption 'Open Log' -Image Error
    }
}
#================================================
# Title bar menus
# Dynamic menu items need explicit styles because implicit styles may not reach ContextMenus.
$script:ToolMenuStyle = $window.FindResource('ToolMenuStyle')
$script:ToolMenuItemStyle = $window.FindResource('ToolMenuItemStyle')
function New-ToolMenuItem {
    param(
        [Parameter(Mandatory)]
        [string]$Header,
        [string]$Tag,
        [switch]$Disabled
    )
    $menuItem = [System.Windows.Controls.MenuItem]::new()
    $menuItem.Style = $script:ToolMenuItemStyle
    # Double underscores so WPF renders underscores literally instead of mnemonics
    $menuItem.Header = $Header -replace '_', '__'
    $menuItem.Tag = $Tag
    $menuItem.IsEnabled = -not $Disabled
    [System.Windows.Automation.AutomationProperties]::SetName($menuItem, $Header)
    return $menuItem
}
function Show-ToolMenu {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Button]$Button,
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContextMenu]$Menu
    )
    $Menu.PlacementTarget = $Button
    $Menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $Menu.IsOpen = $true
}
function Update-LogsMenu {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ContextMenu]$Menu,
        [switch]$Wmi
    )
    # WMI inventory files (Win32_*.txt) are listed separately from deployment logs.
    $Menu.Items.Clear()
    $logsRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'osdcloud-logs'
    $logFiles = $null
    if (Test-Path -LiteralPath $logsRoot) {
        $logFiles = Get-ChildItem -LiteralPath $logsRoot -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
        $logFiles = if ($Wmi) {
            $logFiles | Where-Object { $_.Name -Like 'Win32_*.txt' }
        }
        else {
            $logFiles | Where-Object { $_.Name -NotLike 'Win32_*.txt' }
        }
    }
    if (-not $logFiles) {
        $Menu.Items.Add((New-ToolMenuItem -Header 'No logs found' -Disabled)) | Out-Null
        return
    }
    foreach ($logFile in $logFiles) {
        $logMenuItem = New-ToolMenuItem -Header $logFile.Name -Tag $logFile.FullName
        $logMenuItem.ToolTip = $logFile.FullName
        $logMenuItem.Add_Click({ Open-MainWindowLogFile -Path ([string]$args[0].Tag) })
        $Menu.Items.Add($logMenuItem) | Out-Null
    }
}
$LogsMenuButton = $window.FindName('LogsMenuButton')
$WmiMenuButton = $window.FindName('WmiMenuButton')
$ShellMenuButton = $window.FindName('ShellMenuButton')
$LogsMenu = [System.Windows.Controls.ContextMenu]::new()
$LogsMenu.Style = $script:ToolMenuStyle
$WmiMenu = [System.Windows.Controls.ContextMenu]::new()
$WmiMenu.Style = $script:ToolMenuStyle
$ShellMenu = [System.Windows.Controls.ContextMenu]::new()
$ShellMenu.Style = $script:ToolMenuStyle
$LogsMenuButton.Add_Click({
        Update-LogsMenu -Menu $LogsMenu
        Show-ToolMenu -Button $LogsMenuButton -Menu $LogsMenu
    })
$WmiMenuButton.Add_Click({
        Update-LogsMenu -Menu $WmiMenu -Wmi
        Show-ToolMenu -Button $WmiMenuButton -Menu $WmiMenu
    })
#================================================
# Shell
$RunCmdPrompt = New-ToolMenuItem -Header 'CMD Prompt'
$RunCmdPrompt.Add_Click({
        try {
            Start-Process -FilePath 'cmd.exe'
        }
        catch {
            Show-MainWindowMessage -Message "Failed to open CMD Prompt: $($_.Exception.Message)" -Caption 'Error' -Image Error
        }
    })
$ShellMenu.Items.Add($RunCmdPrompt) | Out-Null
$RunPowerShell = New-ToolMenuItem -Header 'Windows PowerShell'
$RunPowerShell.Add_Click({
        try {
            Start-Process -FilePath 'powershell.exe'
        }
        catch {
            Show-MainWindowMessage -Message "Failed to open PowerShell: $($_.Exception.Message)" -Caption 'Error' -Image Error
        }
    })
$ShellMenu.Items.Add($RunPowerShell) | Out-Null
# PowerShell 7 is optional in WinPE, so only show it when pwsh.exe resolves.
$pwshCommand = Get-Command -Name 'pwsh.exe' -ErrorAction Ignore
if ($pwshCommand) {
    $script:PwshPath = $pwshCommand.Source
    $RunPwsh = New-ToolMenuItem -Header 'PowerShell 7'
    $RunPwsh.ToolTip = $script:PwshPath
    $RunPwsh.Add_Click({
            try {
                Start-Process -FilePath $script:PwshPath
            }
            catch {
                Show-MainWindowMessage -Message "Failed to open PowerShell 7: $($_.Exception.Message)" -Caption 'Error' -Image Error
            }
        })
    $ShellMenu.Items.Add($RunPwsh) | Out-Null
}
$ShellMenuButton.Add_Click({ Show-ToolMenu -Button $ShellMenuButton -Menu $ShellMenu })
#================================================
# Privacy
$window.FindName('PrivacyButton').Add_Click({
        $privacyMessage = @"
OSDCloud collects analytic data during the deployment process to help improve the product and user experience.
No personally identifiable information (PII) is collected, and all data is anonymized to protect user privacy.

Collected data includes information about the deployment environment and system configuration.
By using OSDCloud, you consent to the collection of analytic data as outlined in the privacy policy

https://github.com/OSDeploy/OSDCloud/blob/main/PRIVACY.md
"@
        Show-MainWindowMessage -Message $privacyMessage -Caption 'OSDCloud Privacy Statement' -Image Information
    })
#================================================
# TaskSequence
$TaskSequenceCombo = $window.FindName('TaskSequenceCombo')
$taskSequenceFlows = $global:OSDCloudDeploy.WorkflowTasks.Name
if ($null -eq $taskSequenceFlows) { $taskSequenceFlows = @() }
$TaskSequenceCombo.ItemsSource = @($taskSequenceFlows)
$TaskSequenceCombo.SelectedIndex = 0
#================================================
# OperatingSystemValues
# Prefer workflow-provided choices when present; otherwise derive selectable OS
# names from the loaded operating system catalog.
if ($global:OSDCloudDeploy.OperatingSystemValues) {
    $OperatingSystemValues = $global:OSDCloudDeploy.OperatingSystemValues
}
else {
    $OperatingSystemValues = $global:OSDCoreOperatingSystems.OperatingSystem | Sort-Object -Unique | Sort-Object -Descending
}
$OperatingSystemCombo = $window.FindName('OperatingSystemCombo')
$OperatingSystemCombo.ItemsSource = $OperatingSystemValues
if ($global:OSDCloudDeploy.OperatingSystem) {
    $OperatingSystemDefault = $global:OSDCloudDeploy.OperatingSystem
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OperatingSystem = $OperatingSystemDefault"
}
if ($OperatingSystemDefault -and ($OperatingSystemValues -contains $OperatingSystemDefault)) {
    $OperatingSystemCombo.SelectedItem = $OperatingSystemDefault
}
elseif ($OperatingSystemValues) {
    $OperatingSystemCombo.SelectedIndex = 0
}
else {
    $OperatingSystemCombo.SelectedIndex = -1
}
#================================================
# OSEditionValues
if ($global:OSDCloudDeploy.OSEditionValues.Edition) {
    $OSEditionValues = $global:OSDCloudDeploy.OSEditionValues.Edition
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OSEditionValues = $OSEditionValues"
}
$OSEditionCombo = $window.FindName('OSEditionCombo')
$OSEditionCombo.ItemsSource = $OSEditionValues
if ($global:OSDCloudDeploy.OSEdition) {
    $OSEditionDefault = $global:OSDCloudDeploy.OSEdition
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OSEdition = $OSEditionDefault"
}
if ($OSEditionDefault) {
    $OSEditionCombo.SelectedItem = $OSEditionDefault
}
elseif ($OperatingSystemValues) {
    $OSEditionCombo.SelectedIndex = 0
}
else {
    $OSEditionCombo.SelectedIndex = -1
}
#================================================
# OSActivationValues
if ($global:OSDCloudDeploy.OSActivationValues) {
    $OSActivationValues = $global:OSDCloudDeploy.OSActivationValues
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OSActivationValues = $OSActivationValues"
}
$OSActivationCombo = $window.FindName('OSActivationCombo')
$OSActivationCombo.ItemsSource = $OSActivationValues
if ($global:OSDCloudDeploy.OSActivation) {
    $OSActivationDefault = $global:OSDCloudDeploy.OSActivation
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OSActivation = $OSActivationDefault"
}
if ($OSActivationDefault -and ($OSActivationValues -contains $OSActivationDefault)) {
    $OSActivationCombo.SelectedItem = $OSActivationDefault
}
elseif ($OSActivationValues) {
    $OSActivationCombo.SelectedIndex = 0
}
else {
    $OSActivationCombo.SelectedIndex = -1
}
#================================================
# OSLanguageCodeValues
if ($global:OSDCloudDeploy.OSLanguageCodeValues) {
    $OSLanguageCodeValues = $global:OSDCloudDeploy.OSLanguageCodeValues
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OSLanguageCodeValues = $OSLanguageCodeValues"
}
else {
    $OSLanguageCodeValues = $global:OSDCoreOperatingSystems.OSLanguageCode | Sort-Object -Unique | Sort-Object -Descending
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] Catalog OSLanguageCodeValues = $OSLanguageCodeValues"
}
$OSLanguageCodeCombo = $window.FindName('OSLanguageCodeCombo')
$OSLanguageCodeCombo.ItemsSource = $OSLanguageCodeValues
if ($global:OSDCloudDeploy.OSLanguageCode) {
    $OSLanguageCodeDefault = $global:OSDCloudDeploy.OSLanguageCode
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OSLanguage = $OSLanguageCodeDefault"
}
if ($OSLanguageCodeDefault -and ($OSLanguageCodeValues -contains $OSLanguageCodeDefault)) {
    $OSLanguageCodeCombo.SelectedItem = $OSLanguageCodeDefault
}
elseif ($OSLanguageCodeValues) {
    $OSLanguageCodeCombo.SelectedIndex = 0
}
else {
    $OSLanguageCodeCombo.SelectedIndex = -1
}
#================================================
# DriverPackCombo
# Keep explicit fallback choices for no driver pack or Microsoft Update Catalog lookup.
$DriverPackCatalog = @('None', 'Microsoft Update Catalog')
$script:DefaultDriverPackCloudObject = $global:OSDCloudDeploy.DriverPackCloudObject
if ($global:OSDCloudDeploy.ModelDriversCacheObject) {
    $DriverPackCatalog += 'ModelDrivers'
}
if ($global:OSDCoreDriverPacks) {
    $DriverPackCatalog += $global:OSDCoreDriverPacks | ForEach-Object { $_.Name }
}
$DriverPackCombo = $window.FindName('DriverPackCombo')
$DriverPackCombo.ItemsSource = $DriverPackCatalog
if ($global:OSDCloudDeploy.DriverPackName) {
    $DriverPackCombo.SelectedValue = $global:OSDCloudDeploy.DriverPackName
}
else {
    $DriverPackCombo.SelectedIndex = 0
}
#================================================
# OSDCoreDevice
$deviceTextBindings = @{
    deviceBiosReleaseDateText   = 'BiosReleaseDate'
    deviceBiosVersionText       = 'BiosVersion'
    deviceComputerSystemSKUText = 'ComputerSystemSKU'
    deviceIsAutopilotSpecText   = 'IsAutopilotSpec'
    deviceIsTpmSpecText         = 'IsTpmSpec'
    deviceOSDManufacturerText   = 'OSDManufacturer'
    deviceOSDModelText          = 'OSDModel'
    deviceOSDProductText        = 'OSDProduct'
    deviceSerialNumberText      = 'SerialNumber'
    deviceUUIDText              = 'UUID'
}
foreach ($deviceTextBinding in $deviceTextBindings.GetEnumerator()) {
    $window.FindName($deviceTextBinding.Key).Text = $global:OSDCoreDevice.$($deviceTextBinding.Value)
}
$SummaryText.Text = '{0} | {1} | {2}' -f $global:OSDCoreDevice.OSDManufacturer,
    $global:OSDCoreDevice.OSDModel, $global:OSDCoreDevice.OSDProduct
$deviceSerialNumberText = $window.FindName('deviceSerialNumberText')
$deviceUUIDText = $window.FindName('deviceUUIDText')
$deviceSerialNumberText.Add_MouseLeftButtonUp({ Copy-MainWindowValue -Text ([string]$deviceSerialNumberText.Text) -Label 'Serial Number' })
$window.FindName('CopySerialNumberButton').Add_Click({ Copy-MainWindowValue -Text ([string]$deviceSerialNumberText.Text) -Label 'Serial Number' })
$deviceUUIDText.Add_MouseLeftButtonUp({ Copy-MainWindowValue -Text ([string]$deviceUUIDText.Text) -Label 'UUID' })
$window.FindName('CopyUUIDButton').Add_Click({ Copy-MainWindowValue -Text ([string]$deviceUUIDText.Text) -Label 'UUID' })
#================================================
# deviceHardwareHash
$deviceHardwareHash = $global:OSDCoreDevice.HardwareHash
$deviceHardwareHashLabelText = $window.FindName('deviceHardwareHashLabelText')
$deviceHardwareHashText = $window.FindName('deviceHardwareHashText')
$CopyHardwareHashButton = $window.FindName('CopyHardwareHashButton')
if (-not [string]::IsNullOrWhiteSpace([string]$deviceHardwareHash)) {
    $deviceHardwareHashLabelText.Visibility = [System.Windows.Visibility]::Visible
    $deviceHardwareHashText.Text = 'Copy to Clipboard'
    $deviceHardwareHashText.Visibility = [System.Windows.Visibility]::Visible
    $CopyHardwareHashButton.Visibility = [System.Windows.Visibility]::Visible
    $deviceHardwareHashText.Add_MouseLeftButtonUp({ Copy-MainWindowValue -Text ([string]$deviceHardwareHash) -Label 'Hardware Hash' })
    $CopyHardwareHashButton.Add_Click({ Copy-MainWindowValue -Text ([string]$deviceHardwareHash) -Label 'Hardware Hash' })
}
#================================================
$SelectedOSLanguageText = $window.FindName('SelectedOSLanguageText')
$SelectedIdText = $window.FindName('SelectedIdText')
$SelectedFileNameText = $window.FindName('SelectedFileNameText')
$OSActivationHintText = $window.FindName('OSActivationHintText')
$DriverPackUrlText = $window.FindName('DriverPackUrlText')
$DriverPackUrlText.Text = [string]$global:OSDCloudDeploy.DriverPackCloudObject.Url
$StartButton = $window.FindName('StartButton')
$StartButton.IsEnabled = $false

function Get-ComboValue {
    # Normalize ComboBox selections so downstream filters treat empty UI values as missing input.
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.ComboBox]$ComboBox
    )

    $value = $ComboBox.SelectedItem
    if ($null -eq $value) {
        return $null
    }

    $text = [string]$value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text
}
function Set-StartButtonState {
    # Deployment can only proceed after the current picker state resolves to an OS catalog object.
    $StartButton.IsEnabled = ($null -ne $global:OSDCloudDeploy.OperatingSystemCloudObject)
}
function Update-SelectedDetails {
    param(
        [Parameter()]
        $Item
    )

    if (-not $Item) {
        $SelectedIdText.Text = 'No matching catalog entry.'
        $SelectedOSLanguageText.Text = '-'
        $SelectedFileNameText.Text = '-'
        return
    }

    $SelectedIdText.Text = [string]$Item.Id
    $SelectedOSLanguageText.Text = if ($Item.OSLanguage) {
        [string]$Item.OSLanguage
    }
    elseif ($Item.OSLanguageCode) {
        [string]$Item.OSLanguageCode
    }
    else {
        '-'
    }
    $SelectedFileNameText.Text = [string]$Item.FileName
}
function Update-OsResults {
    # Keep catalog filtering centralized so every picker change refreshes the same selected OS object.
    $updateOperatingSystem = Get-ComboValue -ComboBox $OperatingSystemCombo
    $updateOSEdition = Get-ComboValue -ComboBox $OSEditionCombo
    $updateOSActivation = Get-ComboValue -ComboBox $OSActivationCombo
    $updateOSLanguageCode = Get-ComboValue -ComboBox $OSLanguageCodeCombo

    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] updateOperatingSystem = $updateOperatingSystem"
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] updateOSEdition = $updateOSEdition"
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] updateOSActivation = $updateOSActivation"
    Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] updateOSLanguageCode = $updateOSLanguageCode"

    $global:OSDCloudDeploy.OperatingSystemCloudObject = $global:OSDCoreOperatingSystems | `
        Where-Object { $_.OperatingSystem -match $updateOperatingSystem } | `
        Where-Object { $_.OSActivation -eq $updateOSActivation } | `
        Where-Object { $_.OSLanguageCode -eq $updateOSLanguageCode } | Select-Object -First 1

    if (-not $global:OSDCloudDeploy.OperatingSystemCloudObject) {
        throw "No Operating System found for OperatingSystem: $updateOperatingSystem, OSActivation: $updateOSActivation, OSLanguageCode: $updateOSLanguageCode. Please check your OSDCloud OperatingSystems."
    }

    $global:OSDCloudDeploy.OperatingSystemCacheObject = Get-OSDCoreOperatingSystemCacheObject -OperatingSystemCloudObject $global:OSDCloudDeploy.OperatingSystemCloudObject
    $script:SelectedImage = $global:OSDCloudDeploy.OperatingSystemCloudObject

    if ($updateOSEdition -match 'Home') {
        $OSActivationCombo.SelectedValue = 'Retail'
        $OSActivationCombo.IsEnabled = $false
    }
    if ($updateOSEdition -match 'Education') {
        $OSActivationCombo.IsEnabled = $true
    }
    if ($updateOSEdition -match 'Enterprise') {
        $OSActivationCombo.SelectedValue = 'Volume'
        $OSActivationCombo.IsEnabled = $false
    }
    if ($updateOSEdition -match 'Pro') {
        $OSActivationCombo.IsEnabled = $true
    }
    $OSActivationHintText.Text = if ($OSActivationCombo.IsEnabled) {
        'Retail or Volume license channel'
    }
    else {
        "Set to $(Get-ComboValue -ComboBox $OSActivationCombo) for $updateOSEdition editions"
    }

    Update-SelectedDetails -Item $script:SelectedImage

    Set-StartButtonState
}
function Update-DriverPackResults {
    # Persist the selected driver pack immediately so the final deployment state reflects the latest UI selection.
    $selectedDriverPackName = Get-ComboValue -ComboBox $DriverPackCombo
    $global:OSDCloudDeploy.DriverPackName = $selectedDriverPackName
    $global:OSDCloudDeploy.DriverPackCloudObject = if ($selectedDriverPackName -eq 'ModelDrivers') {
        $script:DefaultDriverPackCloudObject
    }
    else {
        $global:OSDCoreDriverPacks | Where-Object { $_.Name -eq $selectedDriverPackName }
    }
    $global:OSDCloudDeploy.DriverPackCacheObject = Get-OSDCoreDriverPackCacheObject -DriverPackCloudObject $global:OSDCloudDeploy.DriverPackCloudObject
    Set-OSDCloudModelDriversCacheObject
    $DriverPackUrlText.Text = if ($global:OSDCloudDeploy.ModelDriversCacheObject) {
        "ModelDrivers (preferred): $($global:OSDCloudDeploy.ModelDriversCacheObject.FullName)"
    }
    else {
        [string]$global:OSDCloudDeploy.DriverPackCloudObject.Url
    }
}
#================================================
# OSDCloud Post
$PostActionCombo = $window.FindName('PostActionCombo')
$PostActionHintText = $window.FindName('PostActionHintText')
$WindowsUpdateOSToggle = $window.FindName('WindowsUpdateOSToggle')
$WindowsUpdateDriversToggle = $window.FindName('WindowsUpdateDriversToggle')
$PreOOBEHintText = $window.FindName('PreOOBEHintText')
$script:PostActionDescriptions = @{
    Quit     = 'Stay in WinPE and return to the prompt'
    Restart  = 'Restart WinPE into Windows Setup (wpeutil reboot)'
    Shutdown = 'Shut down the device (wpeutil shutdown)'
    Exit     = 'Close the PowerShell session'
}
$PostActionValues = @($global:OSDCloudDeploy.PostActionValues | Where-Object { $_ })
if ($PostActionValues.Count -eq 0) { $PostActionValues = @('Quit', 'Restart', 'Shutdown', 'Exit') }
$PostActionCombo.ItemsSource = $PostActionValues
# This workflow restarts into Windows Setup unless -PostAction was passed explicitly.
$PostActionDefault = if ($global:OSDCloudDeploy.PostActionSpecified -eq $true) { [string]$global:OSDCloudDeploy.PostAction } else { 'Restart' }
$PostActionCombo.SelectedItem = if ($PostActionValues -contains $PostActionDefault) { $PostActionDefault } else { $PostActionValues[0] }
$OSDCloudPostExpander = $window.FindName('OSDCloudPostExpander')
$OSDCloudPostSummaryText = $window.FindName('OSDCloudPostSummaryText')
$InternetWarningPanel = $window.FindName('InternetWarningPanel')
$script:InternetAvailable = $null
function Update-OSDCloudPostSummary {
    $summary = @()
    $selectedPostAction = Get-ComboValue -ComboBox $PostActionCombo
    if ($selectedPostAction) { $summary += $selectedPostAction }
    if ($WindowsUpdateOSToggle.IsEnabled) {
        $updates = @(
            if ($WindowsUpdateOSToggle.IsChecked -eq $true) { $WindowsUpdateOSToggle.Content }
            if ($WindowsUpdateDriversToggle.IsChecked -eq $true) { $WindowsUpdateDriversToggle.Content }
        )
        $summary += if ($updates.Count -gt 0) { $updates } else { 'No Windows Update' }
    }
    if ($script:InternetAvailable -eq $false) {
        $summary += 'Warning: no internet access'
        $OSDCloudPostSummaryText.Foreground = $window.FindResource('WarningBrush')
    }
    else {
        $OSDCloudPostSummaryText.ClearValue([System.Windows.Controls.TextBlock]::ForegroundProperty)
    }
    $OSDCloudPostSummaryText.Text = $summary -join '  |  '
}
function Update-PostActionHint {
    $selectedPostAction = Get-ComboValue -ComboBox $PostActionCombo
    $PostActionHintText.Text = if ($selectedPostAction -and $script:PostActionDescriptions.ContainsKey($selectedPostAction)) {
        $script:PostActionDescriptions[$selectedPostAction]
    }
    else {
        '-'
    }
    Update-OSDCloudPostSummary
}
$PostActionCombo.Add_SelectionChanged({ Update-PostActionHint })
Update-PostActionHint

function Set-MainWindowInternetState {
    param ([bool]$Available)
    $script:InternetAvailable = $Available
    $InternetWarningPanel.Visibility = if ($Available) { 'Collapsed' } else { 'Visible' }
    if (-not $Available) { $OSDCloudPostExpander.IsExpanded = $true }
    Update-OSDCloudPostSummary
}
# Windows Update - OS and Drivers need internet on first boot. The probe runs
# asynchronously so the window never waits on the network; Start stays enabled.
if (-not $script:InternetProbeUri) { $script:InternetProbeUri = 'http://www.msftconnecttest.com/connecttest.txt' }
try {
    if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
        Set-MainWindowInternetState -Available $false
    }
    else {
        Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
        $script:InternetProbeClient = [System.Net.Http.HttpClient]::new()
        $script:InternetProbeClient.Timeout = [TimeSpan]::FromSeconds(5)
        $script:InternetProbe = $script:InternetProbeClient.GetStringAsync($script:InternetProbeUri)
        $script:InternetProbeTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:InternetProbeTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $script:InternetProbeTimer.Add_Tick({
                if (-not $script:InternetProbe.IsCompleted) { return }
                $script:InternetProbeTimer.Stop()
                $probeSucceeded = $script:InternetProbe.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion -and
                    ([string]$script:InternetProbe.Result).Trim() -eq 'Microsoft Connect Test'
                $script:InternetProbeClient.Dispose()
                Set-MainWindowInternetState -Available $probeSucceeded
            })
        $script:InternetProbeTimer.Start()
        $window.Add_Closed({ if ($script:InternetProbeTimer) { $script:InternetProbeTimer.Stop() } })
    }
}
catch {
    Write-Verbose "Internet check unavailable: $($_.Exception.Message)"
}

$WindowsUpdateOSToggle.IsChecked = ($global:OSDCloudDeploy.PreOOBEWindowsUpdateOS -ne $false)
$WindowsUpdateDriversToggle.IsChecked = ($global:OSDCloudDeploy.PreOOBEWindowsUpdateDrivers -ne $false)
function Update-OSDCloudPostState {
    # PreOOBE toggles only apply when the selected task stages OSDCloudPost.
    $selectedTaskName = Get-ComboValue -ComboBox $TaskSequenceCombo
    $selectedTask = $global:OSDCloudDeploy.WorkflowTasks | Where-Object { $_.Name -eq $selectedTaskName } | Select-Object -First 1
    $postStepEnabled = [bool](@($selectedTask.steps) | Where-Object { $_.command -eq 'step-update-osdcloudpost' -and $_.skip -ne $true })
    $WindowsUpdateOSToggle.IsEnabled = $postStepEnabled
    $WindowsUpdateDriversToggle.IsEnabled = $postStepEnabled
    $PreOOBEHintText.Text = if ($postStepEnabled) {
        'Cleared tasks start unchecked in the PreOOBE window; the technician can still select them.'
    }
    else {
        'Unavailable: the selected task sequence does not stage OSDCloudPost.'
    }
    Update-OSDCloudPostSummary
}
foreach ($postToggle in @($WindowsUpdateOSToggle, $WindowsUpdateDriversToggle)) {
    $postToggle.Add_Checked({ Update-OSDCloudPostSummary })
    $postToggle.Add_Unchecked({ Update-OSDCloudPostSummary })
}
$TaskSequenceCombo.Add_SelectionChanged({ Update-OSDCloudPostState })
Update-OSDCloudPostState
#================================================
$DeploymentSettingsSummaryText = $window.FindName('DeploymentSettingsSummaryText')
function Update-DeploymentSettingsSummary {
    $summary = foreach ($combo in @($TaskSequenceCombo, $OperatingSystemCombo, $OSLanguageCodeCombo, $OSEditionCombo, $OSActivationCombo)) {
        Get-ComboValue -ComboBox $combo
    }
    $DeploymentSettingsSummaryText.Text = @($summary | Where-Object { $_ }) -join '  |  '
}
foreach ($deploymentCombo in @($TaskSequenceCombo, $OperatingSystemCombo, $OSLanguageCodeCombo, $OSEditionCombo, $OSActivationCombo)) {
    $deploymentCombo.Add_SelectionChanged({ Update-DeploymentSettingsSummary })
}
Update-DeploymentSettingsSummary
#================================================
$DriverPackCombo.Add_SelectionChanged({ Update-DriverPackResults })
$OperatingSystemCombo.Add_SelectionChanged({ Update-OsResults })
$OSActivationCombo.Add_SelectionChanged({ Update-OsResults })
$OSEditionCombo.Add_SelectionChanged({ Update-OsResults })
$OSLanguageCodeCombo.Add_SelectionChanged({ Update-OsResults })
$script:SelectionConfirmed = $false

$StartButton.Add_Click({
        $script:SelectionConfirmed = $true
        $window.DialogResult = $true
        $window.Close()
    })

Update-OsResults
Update-DriverPackResults

$window.Add_ContentRendered({
        if ($StartButton.IsEnabled) {
            $StartButton.Focus() | Out-Null
        }
        else {
            $window.FindName('CancelButton').Focus() | Out-Null
        }
    })
$null = $window.ShowDialog()

if ($script:SelectionConfirmed) {
    #================================================
    # Convert the selected UI values into the workflow and catalog objects the deployment engine expects.
    $OSDCloudWorkflowTaskName = $TaskSequenceCombo.SelectedValue
    $OSDCloudWorkflowTaskObject = $global:OSDCloudDeploy.WorkflowTasks | Where-Object { $_.Name -eq $OSDCloudWorkflowTaskName } | Select-Object -First 1
    $OperatingSystemCloudObject = $global:OSDCloudDeploy.OperatingSystemCloudObject
    $OSEditionId = $global:OSDCloudDeploy.OSEditionValues | Where-Object { $_.Edition -eq $OSEditionCombo.SelectedValue } | Select-Object -ExpandProperty EditionId
    #================================================
    # Write the confirmed selection back to OSDCloudDeploy for the next deployment phase.
    $global:OSDCloudDeploy.WorkflowTaskName = $OSDCloudWorkflowTaskName
    $global:OSDCloudDeploy.WorkflowTaskObject = $OSDCloudWorkflowTaskObject
    $global:OSDCloudDeploy.OperatingSystemCloudObject = $OperatingSystemCloudObject
    $global:OSDCloudDeploy.OperatingSystemCacheObject = Get-OSDCoreOperatingSystemCacheObject -OperatingSystemCloudObject $OperatingSystemCloudObject
    $global:OSDCloudDeploy.DriverPackCacheObject = Get-OSDCoreDriverPackCacheObject -DriverPackCloudObject $global:OSDCloudDeploy.DriverPackCloudObject
    $global:OSDCloudDeploy.OperatingSystem = $OperatingSystemCloudObject.OperatingSystem
    $global:OSDCloudDeploy.OSActivation = $OperatingSystemCloudObject.OSActivation
    $global:OSDCloudDeploy.OSBuild = $OperatingSystemCloudObject.OSBuild
    $global:OSDCloudDeploy.OSBuildVersion = $OperatingSystemCloudObject.OSBuildVersion
    $global:OSDCloudDeploy.OSEdition = Get-ComboValue -ComboBox $OSEditionCombo
    $global:OSDCloudDeploy.OSEditionId = $OSEditionId
    $global:OSDCloudDeploy.OSLanguageCode = $OperatingSystemCloudObject.OSLanguageCode
    $global:OSDCloudDeploy.OSVersion = $OperatingSystemCloudObject.OSVersion
    $selectedPostAction = Get-ComboValue -ComboBox $PostActionCombo
    if ($selectedPostAction) {
        $global:OSDCloudDeploy | Add-Member -NotePropertyName PostAction -NotePropertyValue $selectedPostAction -Force
    }
    $global:OSDCloudDeploy | Add-Member -NotePropertyName PreOOBEWindowsUpdateOS -NotePropertyValue ([bool]$WindowsUpdateOSToggle.IsChecked) -Force
    $global:OSDCloudDeploy | Add-Member -NotePropertyName PreOOBEWindowsUpdateDrivers -NotePropertyValue ([bool]$WindowsUpdateDriversToggle.IsChecked) -Force
    $global:OSDCloudDeploy.TimeStart = (Get-Date)

    $LogsPath = "$env:TEMP\osdcloud-logs"
    if (-not (Test-Path -Path $LogsPath)) {
        New-Item -Path $LogsPath -ItemType Directory -Force | Out-Null
    }
    # Persist the resolved deployment state for post-run troubleshooting.
    $global:OSDCloudDeploy | ConvertTo-Json | Out-File -FilePath "$LogsPath\OSDCloudDeploy.json" -Encoding utf8 -Width 2000 -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}
