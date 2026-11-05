$script:OSDCloudBootMenuModulePath = Join-Path $PSScriptRoot 'OSDCloudBootMenu.psd1'
$script:OSDCloudBootMenuDefaultsPath = Join-Path $PSScriptRoot 'core\PSDefaultParameterValues.json'
$moduleFiles = (Import-PowerShellDataFile -LiteralPath $script:OSDCloudBootMenuModulePath -ErrorAction Stop).FileList

foreach ($directory in @('private', 'public')) {
    foreach ($source in @($moduleFiles | Where-Object { $_ -like "$directory\*.ps1" -and $_ -notlike '*.Tests.ps1' } | Sort-Object)) {
        . (Join-Path $PSScriptRoot $source)
    }
}

Export-ModuleMember -Function Invoke-OSDCloudBootMenu, Test-OSDCloudBootMenu
