$script:OSDCloudSetupCompleteVersion = [string](Import-PowerShellDataFile -LiteralPath (
    Join-Path $PSScriptRoot 'OSDCloudSetupComplete.psd1') -ErrorAction Stop).ModuleVersion

. (Join-Path $PSScriptRoot 'private\OSDCloudSetupComplete.ps1')
. (Join-Path $PSScriptRoot 'public\Invoke-OSDCloudSetupComplete.ps1')

Export-ModuleMember -Function Invoke-OSDCloudSetupComplete
