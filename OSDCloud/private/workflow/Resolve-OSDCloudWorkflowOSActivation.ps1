function Resolve-OSDCloudWorkflowOSActivation {
    <#
    .SYNOPSIS
        Resolves OS activation based on Windows edition requirements.

    .DESCRIPTION
        Returns Volume for Enterprise* editions and Retail for Home* editions. Other
        editions preserve the requested OSActivation value.

    .PARAMETER OSEdition
        The selected Windows edition display name.

    .PARAMETER OSActivation
        The requested or default OS activation value.

    .EXAMPLE
        Resolve-OSDCloudWorkflowOSActivation -OSEdition 'Enterprise' -OSActivation 'Retail'

        Returns Volume.

    .OUTPUTS
        System.String

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSEdition,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSActivation
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSEdition: $OSEdition"
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSActivation: $OSActivation"

    if ($OSEdition -like 'Enterprise*') {
        return 'Volume'
    }
    if ($OSEdition -like 'Home*') {
        return 'Retail'
    }

    return $OSActivation
}
