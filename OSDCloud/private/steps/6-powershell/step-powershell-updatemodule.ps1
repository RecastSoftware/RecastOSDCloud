function step-powershell-updatemodule {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Checking PowerShell Gallery availability'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $Step = $global:OSDCloudCurrentStep
        $GalleryUrl = 'https://www.powershellgallery.com'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Checking PowerShell Gallery availability:"
        Write-Host -ForegroundColor DarkGray "  $GalleryUrl"
        $WebRequest = Invoke-WebRequest -Uri $GalleryUrl -UseBasicParsing -Method Head -ErrorAction Stop
        if ($WebRequest.StatusCode -ne 200) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] PowerShell Gallery returned HTTP $($WebRequest.StatusCode). Skipping optional module updates."
            return
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] PowerShell Gallery is reachable (HTTP $($WebRequest.StatusCode))."

        $PowerShellSavePath = 'C:\Program Files\WindowsPowerShell'
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] PowerShellSavePath: $PowerShellSavePath"
        foreach ($DirectoryName in @('Configuration', 'Modules', 'Scripts')) {
            $DirectoryPath = Join-Path $PowerShellSavePath $DirectoryName
            $ProgressPhase = "Preparing PowerShell $DirectoryName directory"
            if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container -ErrorAction Stop)) {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Creating PowerShell $DirectoryName directory:"
                Write-Host -ForegroundColor DarkGray "  $DirectoryPath"
                New-Item -Path $DirectoryPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
        }

        $ModulesPath = Join-Path $PowerShellSavePath 'Modules'
        $ProgressPhase = 'Finding locally installed PowerShell modules'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Finding locally installed modules under:"
        Write-Host -ForegroundColor DarkGray "  $ModulesPath"
        $ExistingModules = @(Get-ChildItem -LiteralPath $ModulesPath -Directory -ErrorAction Stop | Select-Object -ExpandProperty Name)
        if ($ExistingModules.Count -eq 0) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] No locally installed modules were found to update."
            return
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Found $($ExistingModules.Count) locally installed module(s) to check."

        foreach ($Name in $ExistingModules) {
            $ProgressPhase = "Checking PowerShell Gallery for module '$Name'"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Checking whether module '$Name' is available in PowerShell Gallery."
            try {
                $FindModule = Find-Module -Name $Name -ErrorAction Stop
                if ($null -eq $FindModule) {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Module '$Name' was not found in PowerShell Gallery. Skipping."
                    continue
                }

                $ProgressPhase = "Saving PowerShell module '$Name'"
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Saving module '$Name' to:"
                Write-Host -ForegroundColor DarkGray "  $ModulesPath"
                Save-Module -Name $Name -Path $ModulesPath -Force -ErrorAction Stop
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Module '$Name' saved successfully."
            }
            catch {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Could not update module '$Name': $($_.Exception.Message)"
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing with the next module."
            }
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] PowerShell module update checks completed."
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional module-update step failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing OSDCloud without module updates."
    }
    #=================================================
}
