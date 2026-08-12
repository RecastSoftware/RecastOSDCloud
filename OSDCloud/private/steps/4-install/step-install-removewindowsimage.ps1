function step-install-removewindowsimage {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $Step = $global:OSDCloudCurrentStep
    #=================================================
    #region Main
    if (Test-Path "C:\OSDCloud") {
        try {
            Remove-Item -Path "C:\OSDCloud" -Recurse -Force -ErrorAction Stop | Out-Null
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removed C:\OSDCloud"
        }
        catch {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] Unable to remove C:\OSDCloud"
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] $_"
        }
        finally {
            $Error.Clear()
        }
    }
    #endregion
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
