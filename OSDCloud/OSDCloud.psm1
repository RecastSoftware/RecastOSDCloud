<#
.SYNOPSIS
    OSDeploy root module loader.

.DESCRIPTION
    Dot-sources all Private and Public functions.
    Exports all Public functions.
#>

# Set-StrictMode -Version Latest

# Capture root path before any dot-sourcing (functions see a different $PSScriptRoot)
$script:OSDCloudModuleBase = $PSScriptRoot
$global:OSDCloudModule = Get-Content -Path (Join-Path $script:OSDCloudModuleBase 'core\module.json') -Raw | ConvertFrom-Json
$script:OSDCloudPSDefaultParameterValuesPath = Join-Path $script:OSDCloudModuleBase 'core\PSDefaultParameterValues.json'

# Get public and private function definition files.
$Classes = @(Get-ChildItem -Path "$PSScriptRoot\classes\*.ps1" -Exclude '*.Tests.ps1')
$Private = @( Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -Exclude '*.Tests.ps1' -ErrorAction SilentlyContinue -Recurse )
$PublicWinOS = @( Get-ChildItem -Path $PSScriptRoot\public\WinOS\*.ps1 -Exclude '*.Tests.ps1' -ErrorAction SilentlyContinue -Recurse )
$PublicWinPE = @( Get-ChildItem -Path $PSScriptRoot\public\WinPE\*.ps1 -Exclude '*.Tests.ps1' -ErrorAction SilentlyContinue -Recurse )

try {
    if (!([System.Management.Automation.PSTypeName]'HtmlAgilityPack.HtmlDocument').Type) {
        if ($PSVersionTable.PSEdition -eq "Desktop") {
            Add-Type -Path "$PSScriptRoot\types\Net45\HtmlAgilityPack.dll"
        } else {
            Add-Type -Path "$PSScriptRoot\types\netstandard2.0\HtmlAgilityPack.dll"
        }
    }
} catch {
    $Err = $_
    throw $Err
}

try {
    if (!([System.Management.Automation.PSTypeName]'Wpf.Ui.Controls.Button').Type) {
        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            Add-Type -Path "$PSScriptRoot\types\wpfui\net481\Wpf.Ui.dll"
        } else {
            Add-Type -Path "$PSScriptRoot\types\wpfui\net6.0-windows\Wpf.Ui.dll"
        }
    }
} catch {
    Write-Warning "[$($MyInvocation.MyCommand.Name)] Could not load Wpf.Ui.dll: $_"
}

$FoundErrors = @(
    if ($env:SystemDrive -eq 'X:') {
        foreach ($Import in @($Classes + $Private + $PublicWinOS + $PublicWinPE)) {
            try { . $Import.Fullname}
            catch {
                Write-Error -Message "Failed to import functions from $($Import.Fullname): $_"
                $true
            }
        }
    } else {
        foreach ($Import in @($Classes + $Private + $PublicWinOS)) {
            try { . $Import.Fullname}
            catch {
                Write-Error -Message "Failed to import functions from $($Import.Fullname): $_"
                $true
            }
        }
    }
)

if ($FoundErrors.Count -gt 0) {
    $ModuleName = (Get-ChildItem $PSScriptRoot\*.psd1).BaseName
    Write-Warning "Importing module $ModuleName failed. Fix errors before continuing."
    break
}

if ($env:SystemDrive -eq 'X:') {
    Set-Alias -Name OSDCloudExplorer -Value Start-OSDCloudExplorer -Scope Script
    New-Alias -Name Invoke-OSDCloudPEStartup -Value Invoke-WinPEStartupManager -Description 'Backward compatibility alias' -Force
    New-Alias -Name Show-PEStartupDeviceInfo -Value Show-OSDCloudDeviceInfo -Description 'Backward compatibility alias' -Force
    New-Alias -Name Show-PEStartupHardware -Value Show-WinPEStartupDevices -Description 'Backward compatibility alias' -Force
    New-Alias -Name Show-PEStartupErrors -Value Show-WinPEStartupDeviceErrors -Description 'Backward compatibility alias' -Force
    New-Alias -Name Show-PEStartupIpconfig -Value Show-WinPEStartupIpconfig -Description 'Backward compatibility alias' -Force
    New-Alias -Name Show-PEStartupWifi -Value Show-WinPEStartupWifi -Description 'Backward compatibility alias' -Force
    New-Alias -Name Use-PEStartupUpdateModule -Value Update-WinPEStartupModule -Description 'Backward compatibility alias' -Force
}

Export-ModuleMember -Function '*' -Alias '*' -Cmdlet '*'
Initialize-OSDCloudModule
