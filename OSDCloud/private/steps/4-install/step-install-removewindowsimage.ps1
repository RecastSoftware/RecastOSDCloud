function step-install-removewindowsimage {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    if (Test-Path "C:\OSDCloud") {
        try {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Removing temporary Windows image directory: C:\OSDCloud"
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
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] C:\OSDCloud was not found. Nothing to remove."
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
