<#!
.SYNOPSIS
	Interactive picker for OSDCloud operating system catalog entries.
#>
[CmdletBinding()]
param()
#================================================
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
#================================================
# XAML
# Load the WPF layout from the companion XAML file so this script can wire data
# and event handlers without embedding UI markup in PowerShell.
$xamlfile = Get-Item -Path "$PSScriptRoot\MainWindow.xaml"
$xaml = Get-Content $xamlfile.FullName
$stringReader = [System.IO.StringReader]::new($xaml)
$xmlReader = [System.Xml.XmlReader]::Create($stringReader)
$window = [Windows.Markup.XamlReader]::Load($xmlReader)
#================================================
# XAML - Window Title
$deviceTitleParts = @()
$OSDCloudModuleVersion = Get-OSDCloudModuleVersion
if (-not [string]::IsNullOrWhiteSpace($OSDCloudModuleVersion)) {
	$deviceTitleParts += $OSDCloudModuleVersion
}
if ($deviceTitleParts.Count -gt 0) {
	$window.Title = "OSDCloud version $($deviceTitleParts -join ' - ')"
}
#================================================
# Logo
$logoImage = $window.FindName('LogoImage')
if ($logoImage) {
	$logoImage.Source = "$PSScriptRoot\logo.png"
}
#================================================
# Menu Items
# Resolve named controls once and attach event handlers for tools that are useful
# during WinPE deployment troubleshooting.
$RunCmdPrompt = $window.FindName("RunCmdPrompt")
$RunPowerShell = $window.FindName("RunPowerShell")
$RunPwsh = $window.FindName("RunPwsh")
$PrivacyMenuItem = $window.FindName("PrivacyMenuItem")
$LogsMenuItem = $window.FindName("LogsMenuItem")
$WMIMenuItem = $window.FindName("WMIMenuItem")

$RunCmdPrompt.Add_Click({
		try {
			Start-Process -FilePath "cmd.exe"
		}
		catch {
			[System.Windows.MessageBox]::Show("Failed to open CMD Prompt: $($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
		}
	})

$RunPowerShell.Add_Click({
		try {
			Start-Process -FilePath "powershell.exe"
		}
		catch {
			[System.Windows.MessageBox]::Show("Failed to open PowerShell: $($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
		}
	})

if ($RunPwsh) {
	# PowerShell 7 is optional in the environment, so only show the menu item when
	# pwsh.exe can be resolved on the current path.
	$pwshCommand = Get-Command -Name 'pwsh.exe' -ErrorAction Ignore
	if ($pwshCommand) {
		$script:PwshPath = $pwshCommand.Source
		$RunPwsh.Visibility = [System.Windows.Visibility]::Visible
		$RunPwsh.Add_Click({
				try {
					Start-Process -FilePath $script:PwshPath
				}
				catch {
					[System.Windows.MessageBox]::Show("Failed to open PowerShell 7: $($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
				}
			})
	}
 else {
		$RunPwsh.Visibility = [System.Windows.Visibility]::Collapsed
	}
}

$PrivacyMenuItem.Add_Click({
		$privacyMessage = @"
OSDCloud collects analytic data during the deployment process to help improve the product and user experience.
No personally identifiable information (PII) is collected, and all data is anonymized to protect user privacy.

Collected data includes information about the deployment environment and system configuration.
By using OSDCloud, you consent to the collection of analytic data as outlined in the privacy policy

https://github.com/OSDeploy/OSDCloud/blob/main/PRIVACY.md
"@
		[System.Windows.MessageBox]::Show($privacyMessage, "OSDCloud Privacy Statement", "OK", "Information") | Out-Null
	})

function Add-NoLogsMenuEntry {
	param(
		[Parameter(Mandatory)]
		[System.Windows.Controls.MenuItem]$MenuItem
	)

	$noLogsItem = [System.Windows.Controls.MenuItem]::new()
	$noLogsItem.Header = 'No logs found'
	$noLogsItem.IsEnabled = $false
	$MenuItem.Items.Add($noLogsItem) | Out-Null
}
function Set-ClipboardText {
	param([string]$Text)
	# Clipboard access can be temporarily locked by another process; retry briefly
	# so click-to-copy still works in most interactive sessions.
	$maxRetries = 5
	for ($i = 0; $i -lt $maxRetries; $i++) {
		try {
			[System.Windows.Clipboard]::SetText($Text)
			return
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
}
function Set-LogsMenuItems {
	# Rebuild the log menu from the temp log folder, excluding WMI captures that
	# have their own menu.
	$LogsMenuItem.Items.Clear()

	$logsRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'osdcloud-logs'
	if (-not (Test-Path -LiteralPath $logsRoot)) {
		Add-NoLogsMenuEntry -MenuItem $LogsMenuItem
		return
	}

	$logFiles = Get-ChildItem -LiteralPath $logsRoot -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
	$logFiles = $logFiles | Where-Object { $_.Name -NotLike "Win32_*.txt" }
	if (-not $logFiles) {
		Add-NoLogsMenuEntry -MenuItem $LogsMenuItem
		return
	}

	foreach ($logFile in $logFiles) {
		$logMenuItem = [System.Windows.Controls.MenuItem]::new()
		# Double underscores so WPF renders underscores literally instead of mnemonics
		$logMenuItem.Header = $logFile.Name -replace '_', '__'
		$logMenuItem.Tag = $logFile.FullName

		$logMenuItem.Add_Click({
				$eventSender = $args[0]
				$logPath = [string]$eventSender.Tag
				if (-not (Test-Path -LiteralPath $logPath)) {
					[System.Windows.MessageBox]::Show('Log file not found.', 'Open Log', 'OK', 'Warning') | Out-Null
					return
				}

				try {
					Start-Process -FilePath 'notepad.exe' -ArgumentList @("`"$logPath`"") -ErrorAction Stop
				}
				catch {
					[System.Windows.MessageBox]::Show("Failed to open log: $($_.Exception.Message)", 'Open Log', 'OK', 'Error') | Out-Null
				}
			})

		$LogsMenuItem.Items.Add($logMenuItem) | Out-Null
	}
}
Set-LogsMenuItems
function Set-WMIMenuItems {
	# WMI inventory files are separated from deployment logs to keep hardware data
	# easy to inspect during troubleshooting.
	$WMIMenuItem.Items.Clear()

	$logsRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'osdcloud-logs'
	if (-not (Test-Path -LiteralPath $logsRoot)) {
		Add-NoLogsMenuEntry -MenuItem $WMIMenuItem
		return
	}

	$logFiles = Get-ChildItem -LiteralPath $logsRoot -File -ErrorAction SilentlyContinue | Sort-Object -Property Name
	$logFiles = $logFiles | Where-Object { $_.Name -Like "Win32_*.txt" }
	if (-not $logFiles) {
		Add-NoLogsMenuEntry -MenuItem $WMIMenuItem
		return
	}

	foreach ($logFile in $logFiles) {
		$logMenuItem = [System.Windows.Controls.MenuItem]::new()
		# Double underscores so WPF renders underscores literally instead of mnemonics
		$logMenuItem.Header = $logFile.Name -replace '_', '__'
		$logMenuItem.Tag = $logFile.FullName

		$logMenuItem.Add_Click({
				$eventSender = $args[0]
				$logPath = [string]$eventSender.Tag
				if (-not (Test-Path -LiteralPath $logPath)) {
					[System.Windows.MessageBox]::Show('Log file not found.', 'Open Log', 'OK', 'Warning') | Out-Null
					return
				}

				try {
					Start-Process -FilePath 'notepad.exe' -ArgumentList @("`"$logPath`"") -ErrorAction Stop
				}
				catch {
					[System.Windows.MessageBox]::Show("Failed to open log: $($_.Exception.Message)", 'Open Log', 'OK', 'Error') | Out-Null
				}
			})

		$WMIMenuItem.Items.Add($logMenuItem) | Out-Null
	}
}
Set-WMIMenuItems
#================================================
# TaskSequence
$TaskSequenceCombo = $window.FindName("TaskSequenceCombo")
$taskSequenceFlows = $global:OSDCloudDeploy.WorkflowTasks.Name
if ($null -eq $taskSequenceFlows) { $taskSequenceFlows = @() }
$TaskSequenceCombo.ItemsSource = $taskSequenceFlows
$TaskSequenceCombo.SelectedIndex = 0
$TaskSequenceCombo.Add_SelectionChanged({
		if ($SummaryTaskSequenceText) {
			$value = [string]$TaskSequenceCombo.SelectedItem
			$SummaryTaskSequenceText.Text = if (-not [string]::IsNullOrWhiteSpace($value)) { $value } else { 'Not selected' }
		}
	})
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
$OperatingSystemCombo = $window.FindName("OperatingSystemCombo")
$OperatingSystemCombo.ItemsSource = $OperatingSystemValues
#================================================
# OperatingSystemDefault
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
# GlobalVariable Configuration
# Environment Configuration
# Workflow Configuration
if ($global:OSDCloudDeploy.OSEditionValues.Edition) {
	$OSEditionValues = $global:OSDCloudDeploy.OSEditionValues.Edition
	Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OSEditionValues = $OSEditionValues"
}
else {
	@()
}
$OSEditionCombo = $window.FindName("OSEditionCombo")
$OSEditionCombo.ItemsSource = $OSEditionValues
#================================================
# OSEditionDefault
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
# GlobalVariable Configuration
# Environment Configuration
# Workflow Configuration
if ($global:OSDCloudDeploy.OSActivationValues) {
	$OSActivationValues = $global:OSDCloudDeploy.OSActivationValues
	Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OSActivationValues = $OSActivationValues"
}
else {
	@()
}
$OSActivationCombo = $window.FindName("OSActivationCombo")
$OSActivationCombo.ItemsSource = $OSActivationValues
#================================================
# OSActivationDefault
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
# GlobalVariable Configuration
# Environment Configuration
# Workflow Configuration
if ($global:OSDCloudDeploy.OSLanguageCodeValues) {
	$OSLanguageCodeValues = $global:OSDCloudDeploy.OSLanguageCodeValues
	Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] OSLanguageCodeValues = $OSLanguageCodeValues"
}
# Catalog Configuration
else {
	$OSLanguageCodeValues = $global:OSDCoreOperatingSystems.OSLanguageCode | Sort-Object -Unique | Sort-Object -Descending
	Write-Verbose "[$(Get-Date -format s)] [MainWindow.ps1] Catalog OSLanguageCodeValues = $OSLanguageCodeValues"
}
$OSLanguageCodeCombo = $window.FindName("OSLanguageCodeCombo")
$OSLanguageCodeCombo.ItemsSource = $OSLanguageCodeValues
#================================================
# OSLanguageCodeDefault
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
# GlobalVariable Configuration
# Environment Configuration
# Workflow Configuration
#================================================
# Import the DriverPack Catalog
# Build the driver pack picker from the module catalog, while keeping explicit
# fallback choices for no driver pack or Microsoft Update Catalog lookup.
$DriverPackCatalog = @('None', 'Microsoft Update Catalog')
if ($global:OSDCoreDriverPacks) {
	$DriverPackCatalog += $global:OSDCoreDriverPacks | ForEach-Object { $_.Name }
}
$DriverPackCombo = $window.FindName("DriverPackCombo")
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

function Add-ClipboardTextBlockHandler {
	param(
		[Parameter(Mandatory)]
		[System.Windows.Controls.TextBlock]$TextBlock
	)

	$TextBlock.Add_MouseLeftButtonUp({
			$eventSender = $args[0]
			$text = [string]$eventSender.Text
			if ([string]::IsNullOrWhiteSpace($text)) {
				return
			}

			Set-ClipboardText -Text $text
		})
}
#================================================
# deviceSerialNumber
Add-ClipboardTextBlockHandler -TextBlock $window.FindName("deviceSerialNumberText")
#================================================
# deviceHardwareHash
$deviceHardwareHash = $global:OSDCoreDevice.HardwareHash
$deviceHardwareHashLabelText = $window.FindName("deviceHardwareHashLabelText")
$deviceHardwareHashText = $window.FindName("deviceHardwareHashText")
if (-not [string]::IsNullOrWhiteSpace([string]$deviceHardwareHash)) {
	$deviceHardwareHashLabelText.Visibility = [System.Windows.Visibility]::Visible
	$deviceHardwareHashText.Text = 'Copy to Clipboard'
	$deviceHardwareHashText.Visibility = [System.Windows.Visibility]::Visible
	$deviceHardwareHashText.Add_MouseLeftButtonUp({
			Set-ClipboardText -Text ([string]$deviceHardwareHash)
		})
}
#================================================
# deviceUUID
Add-ClipboardTextBlockHandler -TextBlock $window.FindName("deviceUUIDText")
#================================================
$SelectedOSLanguageText = $window.FindName("SelectedOSLanguageText")
$SelectedIdText = $window.FindName("SelectedIdText")
$SelectedFileNameText = $window.FindName("SelectedFileNameText")
$DriverPackUrlText = $window.FindName("DriverPackUrlText")
$DriverPackUrlText.Text = [string]$global:OSDCloudDeploy.DriverPackCloudObject.Url
$StartButton = $window.FindName("StartButton")
$StartButton.IsEnabled = $false

function Get-ComboValue {
	# Normalize ComboBox selections so downstream filters can treat empty UI values
	# as missing input instead of empty strings.
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
	# Deployment can only proceed after the current picker state resolves to an OS
	# catalog object.
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
	# Keep catalog filtering centralized so every picker change refreshes the same
	# selected OS object and detail summary.
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

	Update-SelectedDetails -Item $script:SelectedImage

	Set-StartButtonState
}
function Update-DriverPackResults {
	# Persist the selected driver pack name and matching catalog object immediately
	# so the final deployment state reflects the latest UI selection.
	$selectedDriverPackName = Get-ComboValue -ComboBox $DriverPackCombo
	$global:OSDCloudDeploy.DriverPackName = $selectedDriverPackName
	$global:OSDCloudDeploy.DriverPackCloudObject = $global:OSDCoreDriverPacks | Where-Object { $_.Name -eq $selectedDriverPackName }
	$global:OSDCloudDeploy.DriverPackCacheObject = Get-OSDCoreDriverPackCacheObject -DriverPackCloudObject $global:OSDCloudDeploy.DriverPackCloudObject
	$DriverPackUrlText.Text = [string]$global:OSDCloudDeploy.DriverPackCloudObject.Url
}
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

# Initialize Configuration summary with current values
if ($SummaryTaskSequenceText) {
	$value = [string]$TaskSequenceCombo.SelectedItem
	$SummaryTaskSequenceText.Text = if (-not [string]::IsNullOrWhiteSpace($value)) { $value } else { 'Not selected' }
}

$null = $window.ShowDialog()

if ($script:SelectionConfirmed) {
	#================================================
	# Local Variables
	# Convert the selected UI values into workflow and catalog objects that the
	# deployment engine expects after the dialog closes.
	$OSDCloudWorkflowTaskName = $TaskSequenceCombo.SelectedValue
	$OSDCloudWorkflowTaskObject = $global:OSDCloudDeploy.WorkflowTasks | Where-Object { $_.Name -eq $OSDCloudWorkflowTaskName } | Select-Object -First 1
	$OperatingSystemCloudObject = $global:OSDCloudDeploy.OperatingSystemCloudObject
	$OSEditionId = $global:OSDCloudDeploy.OSEditionValues | Where-Object { $_.Edition -eq $OSEditionCombo.SelectedValue } | Select-Object -ExpandProperty EditionId
	#================================================
	# Global Variables
	# Write the confirmed selection back to OSDCloudDeploy so the next deployment
	# phase can download the image and run the selected workflow task.
	# $global:OSDCloudDeploy.DriverPackName = $DriverPackName
	# $global:OSDCloudDeploy.DriverPackCloudObject = $DriverPackCloudObject
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
	$global:OSDCloudDeploy.TimeStart = (Get-Date)

	$LogsPath = "$env:TEMP\osdcloud-logs"
	if (-not (Test-Path -Path $LogsPath)) {
		New-Item -Path $LogsPath -ItemType Directory -Force | Out-Null
	}
	# Persist the resolved deployment state for post-run troubleshooting.
	$global:OSDCloudDeploy | ConvertTo-Json | Out-File -FilePath "$LogsPath\OSDCloudDeploy.json" -Encoding utf8 -Width 2000 -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}
