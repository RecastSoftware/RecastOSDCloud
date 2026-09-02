function Test-OSDeployLicenseGate {
    <#
    .SYNOPSIS
        Tests whether an Update-OSDeploy command should proceed under license gating.

    .DESCRIPTION
        Returns $true when the caller should continue execution and $false when the
        command should stop because no valid OSDeploy license is available.

        The gate bypasses license validation only when the immediate caller of the
        Update-OSDeploy function is Invoke-OSDeployHydration. This supports the
        hydration workflow exception.

        On license failure, the function invokes Show-OSDeployLicense so the user
        receives registration and installation guidance, then returns $false.

    .PARAMETER CommandName
        Name of the command currently being gated.

    .EXAMPLE
        if (-not (Test-OSDeployLicenseGate -CommandName $MyInvocation.MyCommand.Name)) {
            return
        }

    .OUTPUTS
        System.Boolean. Returns $true when command execution may continue; otherwise
        returns $false.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-09-01
    #>
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$CommandName
    )

    $callStack = Get-PSCallStack
    $immediateCaller = $callStack | Select-Object -Skip 2 -First 1
    if ($immediateCaller -and $immediateCaller.Command -eq 'Invoke-OSDeployHydration') {
        Write-Verbose "[$(Get-Date -Format s)] [$CommandName] License gate bypassed: immediate caller is Invoke-OSDeployHydration."
        return $true
    }

    $license = Get-OSDCoreLicense
    if ($license -and $license.IsValid) {
        return $true
    }

    Write-Warning "[$(Get-Date -Format s)] [$CommandName] A valid Recast Software Community License is required for this command."
    Show-OSDeployLicense | Out-Null
    return $false
}
