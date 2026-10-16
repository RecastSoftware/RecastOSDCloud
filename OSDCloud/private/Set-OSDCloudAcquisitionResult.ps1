function Set-OSDCloudAcquisitionResult {
    <#
    .SYNOPSIS
        Records the size of acquired deployment content.
    .DESCRIPTION
        Stores unrounded bytes in the current workflow snapshot. Results
        aggregation rounds these values for local results and analytics. Cache and
        download paths use the same measurements. CompletedTransfers identifies
        whether the content was downloaded locally, downloaded to USB cache,
        or copied/reused. Multiple completed transfer categories can apply.
    .PARAMETER Content
        OS or DriverPack content acquired by the current workflow.
    .PARAMETER Bytes
        Actual acquired file size, or total staged ModelDrivers file size, in bytes.
    .EXAMPLE
        Set-OSDCloudAcquisitionResult -Content OS -Bytes 5GB
    .NOTES
        Updates global OSDCloudWorkflowInvoke, not results belonging to a previous run.
        Recording failures warn without interrupting deployment.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('OS', 'DriverPack')]
        [string]$Content,
        [Parameter(Mandatory)]
        [ValidateRange(0, [long]::MaxValue)]
        [long]$Bytes
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Recording $Content acquisition"
    try {
        $global:OSDCloudWorkflowInvoke."${Content}Acquisition" = [pscustomobject]@{
            Bytes = $Bytes
            Downloaded = $null -ne $global:OSDCloudWorkflowInvoke.CompletedTransfers -and
                $global:OSDCloudWorkflowInvoke.CompletedTransfers["step${Content}Download"] -eq $true
            Copied = $null -ne $global:OSDCloudWorkflowInvoke.CompletedTransfers -and
                $global:OSDCloudWorkflowInvoke.CompletedTransfers["step${Content}Copy"] -eq $true
            Cached = $null -ne $global:OSDCloudWorkflowInvoke.CompletedTransfers -and
                $global:OSDCloudWorkflowInvoke.CompletedTransfers["step${Content}Cache"] -eq $true
        }
    }
    catch {
        Write-Warning "Could not record $Content acquisition metrics: $($_.Exception.Message)"
    }
}
