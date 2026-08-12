function step-powershell-updatemodule {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    # Is it reachable online?
    try {
        $WebRequest = Invoke-WebRequest -Uri 'https://www.powershellgallery.com' -UseBasicParsing -Method Head
        if ($WebRequest.StatusCode -eq 200) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] PowerShell Gallery returned a 200 status code. OK."
        }
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] PowerShell Gallery is not reachable."
        return
    }
    #=================================================
    #region Main
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

    $ExistingModules = Get-ChildItem -Path "$PowerShellSavePath\Modules" -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -eq $true } | Select-Object -ExpandProperty Name

    foreach ($Name in $ExistingModules) {
        $FindModule = Find-Module -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $FindModule) {
            # Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Unable to update $Name"
            continue
        }

        try {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $Name"
            Save-Module -Name $Name -Path "$PowerShellSavePath\Modules" -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "[$(Get-Date -format s)] Save-Module failed: $Name"
        }
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
