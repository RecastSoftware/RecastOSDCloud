function Confirm-OSDCloudBootMenuProfilePassword {
    <#
    .SYNOPSIS
        Verifies a profile selection password before profile execution

    .DESCRIPTION
        Verifies a versioned profile access token, using a masked WPF dialog or a
        console prompt. Incorrect console passwords retry; empty input cancels.
        Supplied passwords fail without interactive retries. No environment values
        are assigned and no profile commands are run.

    .PARAMETER Token
        Specifies the profile's password token.

    .PARAMETER Password
        Specifies an optional SecureString for unattended callers.

    .PARAMETER CLI
        Uses a masked console prompt rather than WPF.

    .EXAMPLE
        PS> Confirm-OSDCloudBootMenuProfilePassword -Token $token -CLI

        Returns true on successful verification, or false on cancellation.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Boolean.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-05
        Protects the ordinary selection flow, not against modified boot-media code.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)][string]$Token,
        [System.Security.SecureString]$Password,
        [switch]$CLI
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Verifying profile password"
    $null = ConvertTo-OSDCloudBootStringEnvelope -Token $Token
    $interactive = -not $PSBoundParameters.ContainsKey('Password')
    if ($interactive -and -not $CLI) {
        try { Add-Type -AssemblyName PresentationFramework -ErrorAction Stop }
        catch {
            Write-Warning 'The profile password dialog is unavailable. Using a masked console prompt.'
            $CLI = $true
        }
        if (-not $CLI) {
            try {
                $Password = Show-OSDCloudBootPasswordDialog -Token $Token
                if ($null -eq $Password) { return $false }
                return $true
            }
            finally { if ($Password) { $Password.Dispose() } }
        }
    }
    while ($true) {
        try {
            if ($interactive) { $Password = Read-Host -Prompt 'BootMenu profile password (empty cancels)' -AsSecureString }
            if ($null -eq $Password -or $Password.Length -eq 0) { return $false }
            $value = Invoke-OSDCloudBootStringCrypto -Token $Token -Password $Password
            if ($value -cne 'OSDCloudBootMenu profile access') { throw 'Invalid profile password token.' }
            return $true
        }
        catch [System.Security.Cryptography.CryptographicException] {
            if (-not $interactive) { throw }
            Write-Warning 'Incorrect password or modified profile token. Try again, or enter an empty password to cancel.'
        }
        finally {
            $value = $null
            if ($interactive -and $Password) { $Password.Dispose(); $Password = $null }
        }
    }
}
