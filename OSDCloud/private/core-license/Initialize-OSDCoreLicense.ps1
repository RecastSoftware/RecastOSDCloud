function Initialize-OSDCoreLicense {
    <#
    .SYNOPSIS
    Initializes the OSDCore license state.

    .DESCRIPTION
    Retrieves the selected Recast Core license and stores it in
    $global:OSDCoreLicense. The IsRegistered property is true when the
    selected license has an email address; otherwise it is false.

    .OUTPUTS
    None. This function updates $global:OSDCoreLicense.

    .EXAMPLE
    Initialize-OSDCoreLicense

    Retrieves the current license and updates $global:OSDCoreLicense.

    .NOTES
    Depends on Get-OSDCoreLicense being available in the session.
    #>
    [CmdletBinding()]
    param ()

    $Error.Clear()
    $license = Get-OSDCoreLicense
    $classWin32ComputerSystemProduct = Get-CimInstance -ClassName Win32_ComputerSystemProduct
    $deviceUUID = [System.String]$classWin32ComputerSystemProduct.UUID
    $EndpointSHA = $null
    if (-not [string]::IsNullOrWhiteSpace($deviceUUID)) {
        $EndpointSHA = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($deviceUUID))).Replace("-", "")
    }

    $global:OSDCoreLicense = [pscustomobject]@{
        EndpointSHA  = [System.String]$EndpointSHA
        IsRegistered = -not [string]::IsNullOrWhiteSpace([string]$license.Email)
        License      = $license
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Ready: OSDCoreLicense (IsRegistered: $($global:OSDCoreLicense.IsRegistered))"
}
