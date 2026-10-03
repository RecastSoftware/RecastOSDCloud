function Set-OSDCloudModelDriversCacheObject {
    <#
    .SYNOPSIS
        Refreshes the preferred ModelDrivers source in the current deployment.
    .DESCRIPTION
        CLI always prefers eligible ModelDrivers. Other workflows honor driver-pack
        selections of None and Microsoft Update Catalog. OEM metadata remains separate
        and is used when no eligible ModelDrivers source is available.
    .EXAMPLE
        Set-OSDCloudModelDriversCacheObject
        Refreshes the source after driver selection and before the workflow snapshot.
    .OUTPUTS
        None. Updates $global:OSDCloudDeploy.ModelDriversCacheObject.
    .NOTES
        ModelDriversCacheObject is a cache inventory entry, never an OEM archive object.
    #>
    [CmdletBinding()]
    param ()

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $deployment = $global:OSDCloudDeploy
    if (-not $deployment) {
        throw 'OSDCloudDeploy must be initialized before selecting ModelDrivers.'
    }

    $deployment.ModelDriversCacheObject = $null
    if ($deployment.WorkflowName -eq 'cli' -or $deployment.DriverPackName -notin 'None', 'Microsoft Update Catalog') {
        $deployment.ModelDriversCacheObject = Get-OSDCoreModelDriversCacheObject -OSArchitecture $deployment.OSArchitecture
    }
    if ($deployment.ModelDriversCacheObject) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] ModelDrivers takes precedence over the OEM driver pack: $($deployment.ModelDriversCacheObject.FullName)"
    }
    elseif ($deployment.DriverPackName -eq 'ModelDrivers') {
        $deployment.DriverPackName = $deployment.DriverPackCloudObject.Name
        Write-Warning "[$(Get-Date -format s)] No eligible ModelDrivers source remains. Using the configured OEM fallback when available."
    }
}
