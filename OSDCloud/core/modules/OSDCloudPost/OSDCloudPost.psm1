$script:OSDCloudPostModulePath = Join-Path $PSScriptRoot 'OSDCloudPost.psd1'
$script:OSDCloudPostVersion = [string](Import-PowerShellDataFile -LiteralPath $script:OSDCloudPostModulePath -ErrorAction Stop).ModuleVersion
$script:OSDCloudPreOOBEModulePath = $script:OSDCloudPostModulePath
$script:OSDCloudPreOOBEVersion = $script:OSDCloudPostVersion
$script:OSDCloudSetupCompleteVersion = $script:OSDCloudPostVersion
$script:Preview = $false
$script:InteractiveChild = $false
$script:ReadyEvent = $null
$script:OSDCloudPreOOBERunning = $false

. (Join-Path $PSScriptRoot 'private\OSDCloudPreOOBE.ps1')
. (Join-Path $PSScriptRoot 'private\Get-OSDCloudPostSetting.ps1')
. (Join-Path $PSScriptRoot 'private\Invoke-OSDCloudPreOOBEDriverPack.ps1')
. (Join-Path $PSScriptRoot 'private\Show-OSDCloudPreOOBEWireless.ps1')
. (Join-Path $PSScriptRoot 'private\Show-OSDCloudPreOOBEWindow.ps1')
. (Join-Path $PSScriptRoot 'private\OSDCloudSetupComplete.ps1')
. (Join-Path $PSScriptRoot 'public\Invoke-OSDCloudPreOOBE.ps1')
. (Join-Path $PSScriptRoot 'public\Invoke-OSDCloudSetupComplete.ps1')

Set-Alias -Name OSDCloudPreOOBE -Value Invoke-OSDCloudPreOOBE -Scope Script
Export-ModuleMember -Function Invoke-OSDCloudPreOOBE, Invoke-OSDCloudSetupComplete -Alias OSDCloudPreOOBE
