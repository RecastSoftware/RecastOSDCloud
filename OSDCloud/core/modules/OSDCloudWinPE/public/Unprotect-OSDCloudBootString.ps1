function Unprotect-OSDCloudBootString {
    <#
    .SYNOPSIS
        Decrypts a password-protected OSDCloud string token

    .DESCRIPTION
        Authenticates a token before decrypting it, independently of the creating
        computer or account. An omitted password prompts with masked entry.
        Empty passwords cancel. This command returns plaintext: assigning it to
        a variable is preferable to displaying it in a console or transcript.

    .PARAMETER Token
        Specifies the token returned by Protect-OSDCloudBootString.

    .PARAMETER Password
        Specifies a nonempty SecureString password. Omit it for masked entry.
        The caller owns and disposes a supplied SecureString.

    .EXAMPLE
        PS> $value = Unprotect-OSDCloudBootString -Token $token

        Prompts for the password and captures the decrypted string.

    .EXAMPLE
        PS> $value = Unprotect-OSDCloudBootString -Token $token -Password $password

        Decrypts using an existing SecureString without prompting.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String. Returns plaintext after authentication.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-05
        Requires PBKDF2-HMAC-SHA256 support (.NET Framework 4.7.2 or newer).
        Plaintext .NET strings cannot be reliably erased from memory.

    .LINK
        Protect-OSDCloudBootString
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][string]$Token,
        [System.Security.SecureString]$Password
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Decrypting string"
    $null = ConvertTo-OSDCloudBootStringEnvelope -Token $Token
    $ownsPassword = -not $PSBoundParameters.ContainsKey('Password')
    try {
        if ($ownsPassword) { $Password = Read-Host -Prompt 'Decryption password (empty cancels)' -AsSecureString }
        if ($null -eq $Password -or $Password.Length -eq 0) { throw [System.OperationCanceledException]::new('String decryption cancelled.') }
        return Invoke-OSDCloudBootStringCrypto -Token $Token -Password $Password
    }
    finally {
        if ($ownsPassword -and $Password) { $Password.Dispose() }
    }
}
