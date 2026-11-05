function Protect-OSDCloudBootString {
    <#
    .SYNOPSIS
        Encrypts a string into a portable password-protected token

    .DESCRIPTION
        Returns an authenticated OSDBS1 token using .NET cryptography, without
        machine-bound DPAPI or external tools. An omitted password prompts twice
        with masked entry. Empty passwords cancel. Tokens support up to 1 MiB of
        UTF-8 text. Use the same password for every encryptedEnv entry in a profile.
        Do not enter real plaintext secrets as literals in saved scripts or history.

    .PARAMETER InputString
        Specifies the string to encrypt. Empty strings are supported.

    .PARAMETER Password
        Specifies a nonempty SecureString password. Omit it for masked entry and
        confirmation. The caller owns and disposes a supplied SecureString.

    .EXAMPLE
        PS> $token = Protect-OSDCloudBootString -InputString 'Synthetic example'

        Prompts for a password and returns a token suitable for encryptedEnv JSON.

    .EXAMPLE
        PS> $token = Protect-OSDCloudBootString -InputString $value -Password $password

        Encrypts a value using an existing SecureString without prompting.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String. Returns a versioned encrypted token.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-05
        Password strength matters: copied tokens permit offline password guessing.
        Requires PBKDF2-HMAC-SHA256 support (.NET Framework 4.7.2 or newer).

    .LINK
        Unprotect-OSDCloudBootString
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][AllowEmptyString()][string]$InputString,
        [System.Security.SecureString]$Password
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Encrypting string"
    $ownsPassword = -not $PSBoundParameters.ContainsKey('Password')
    $confirmation = $null
    try {
        if ($ownsPassword) {
            $Password = Read-Host -Prompt 'Encryption password (empty cancels)' -AsSecureString
            if ($null -eq $Password -or $Password.Length -eq 0) { throw [System.OperationCanceledException]::new('String encryption cancelled.') }
            $confirmation = Read-Host -Prompt 'Confirm encryption password' -AsSecureString
            if ($null -eq $confirmation -or $confirmation.Length -eq 0) { throw [System.OperationCanceledException]::new('String encryption cancelled.') }
        }
        if ($null -eq $Password) { throw 'A nonempty encryption password is required.' }
        $token = Invoke-OSDCloudBootStringCrypto -InputString $InputString -Password $Password
        if ($confirmation) {
            try { $null = Invoke-OSDCloudBootStringCrypto -Token $token -Password $confirmation }
            catch [System.Security.Cryptography.CryptographicException] { throw 'Encryption passwords do not match.' }
        }
        return $token
    }
    finally {
        if ($confirmation) { $confirmation.Dispose() }
        if ($ownsPassword -and $Password) { $Password.Dispose() }
    }
}
