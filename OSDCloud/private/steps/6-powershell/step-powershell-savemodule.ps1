function step-powershell-savemodule {
    [CmdletBinding()]
    param (
        $Name = $Step.parameters.name
    )
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    #region Main
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO]"
    $PowerShellSavePath = 'C:\Program Files\WindowsPowerShell'
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Module Name: $Name; PowerShellSavePath: $PowerShellSavePath"

    if (-not (Test-Path "$PowerShellSavePath\Configuration")) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating PowerShell configuration path."
        New-Item -Path "$PowerShellSavePath\Configuration" -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path "$PowerShellSavePath\Modules")) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating PowerShell modules path."
        New-Item -Path "$PowerShellSavePath\Modules" -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path "$PowerShellSavePath\Scripts")) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating PowerShell scripts path."
        New-Item -Path "$PowerShellSavePath\Scripts" -ItemType Directory -Force | Out-Null
    }

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Saving module $Name to $PowerShellSavePath\Modules."
        Save-Module -Name $Name -Path "$PowerShellSavePath\Modules" -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "[$(Get-Date -format s)] Unable to Save-Module $Name to $PowerShellSavePath\Modules"
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
