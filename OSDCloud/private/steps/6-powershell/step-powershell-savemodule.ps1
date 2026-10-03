function step-powershell-savemodule {
    [CmdletBinding()]
    param (
        $Name
    )
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Preparing to save the requested PowerShell module'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $Step = $global:OSDCloudCurrentStep
        if (-not $PSBoundParameters.ContainsKey('Name')) {
            $Name = $Step.parameters.name
        }
        if ([string]::IsNullOrWhiteSpace([string]$Name)) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] No module name was specified. Skipping this optional step."
            return
        }

        $PowerShellSavePath = 'C:\Program Files\WindowsPowerShell'
        $ModulesPath = Join-Path $PowerShellSavePath 'Modules'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Preparing to save PowerShell module '$Name'."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Module destination:"
        Write-Host -ForegroundColor DarkGray "  $ModulesPath"

        foreach ($DirectoryName in @('Configuration', 'Modules', 'Scripts')) {
            $DirectoryPath = Join-Path $PowerShellSavePath $DirectoryName
            $ProgressPhase = "Preparing PowerShell $DirectoryName directory"
            if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container -ErrorAction Stop)) {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Creating PowerShell $DirectoryName directory:"
                Write-Host -ForegroundColor DarkGray "  $DirectoryPath"
                New-Item -Path $DirectoryPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            else {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] PowerShell $DirectoryName directory already exists:"
                Write-Host -ForegroundColor DarkGray "  $DirectoryPath"
            }
        }

        $ProgressPhase = "Saving PowerShell module '$Name'"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Saving module '$Name' to:"
        Write-Host -ForegroundColor DarkGray "  $ModulesPath"
        Save-Module -Name $Name -Path $ModulesPath -Force -ErrorAction Stop
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Module '$Name' saved successfully."
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional module-save step failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing OSDCloud without the requested module."
    }
    #=================================================
}
