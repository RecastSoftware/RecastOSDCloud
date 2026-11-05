$script:OSDCloudPreOOBEModulePath = Join-Path $PSScriptRoot 'OSDCloudPreOOBE.psd1'
$script:OSDCloudPreOOBEVersion = [string](Import-PowerShellDataFile -LiteralPath $script:OSDCloudPreOOBEModulePath -ErrorAction Stop).ModuleVersion
$script:Preview = $false
$script:InteractiveChild = $false
$script:ReadyEvent = $null
$script:OSDCloudPreOOBERunning = $false

. (Join-Path $PSScriptRoot 'private\OSDCloudPreOOBE.ps1')
. (Join-Path $PSScriptRoot 'private\Invoke-OSDCloudPreOOBEDriverPack.ps1')
. (Join-Path $PSScriptRoot 'private\Show-OSDCloudPreOOBEWireless.ps1')
. (Join-Path $PSScriptRoot 'private\Show-OSDCloudPreOOBEWindow.ps1')
. (Join-Path $PSScriptRoot 'public\Invoke-OSDCloudPreOOBE.ps1')

Set-Alias -Name OSDCloudPreOOBE -Value Invoke-OSDCloudPreOOBE -Scope Script
Export-ModuleMember -Function Invoke-OSDCloudPreOOBE -Alias OSDCloudPreOOBE
