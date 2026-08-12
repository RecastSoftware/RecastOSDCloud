function step-powershell-savemodule {
    [CmdletBinding()]
    param (
        $Name = $Step.parameters.name
    )
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    #=================================================
    #region Main
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO]"
    $PowerShellSavePath = 'C:\Program Files\WindowsPowerShell'

    if (-not (Test-Path "$PowerShellSavePath\Configuration")) {
        New-Item -Path "$PowerShellSavePath\Configuration" -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path "$PowerShellSavePath\Modules")) {
        New-Item -Path "$PowerShellSavePath\Modules" -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path "$PowerShellSavePath\Scripts")) {
        New-Item -Path "$PowerShellSavePath\Scripts" -ItemType Directory -Force | Out-Null
    }

    try {
        Save-Module -Name $Name -Path "$PowerShellSavePath\Modules" -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "[$(Get-Date -format s)] Unable to Save-Module $Name to $PowerShellSavePath\Modules"
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
