function step-install-getwindowsedition {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    try {
        $WindowsEdition = (Get-WindowsEdition -Path 'C:\' -ErrorAction Stop | Out-String).Trim()
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $WindowsEdition"
        $global:OSDCloudWorkflowInvoke.WindowsEdition = $WindowsEdition
    }
    catch {
        Write-Warning "[$(Get-Date -format s)] Unable to get Windows Edition. OK."
        Write-Warning "[$(Get-Date -format s)] $_"
    }
    finally {
        $Error.Clear()
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
