function ConvertTo-OSDCloudBootStringEnvelope {
    <#
    .SYNOPSIS
        Validates and decodes a versioned encrypted string

    .DESCRIPTION
        Checks the prefix, size, version and block lengths without deriving keys.
        Version 1 contains a version byte, 32-byte salt, 16-byte IV, AES ciphertext,
        and 32-byte authentication tag. Tokens are limited to 1 MiB of plaintext.

    .PARAMETER Token
        Specifies an OSDBS1-prefixed Base64 token.

    .EXAMPLE
        PS> ConvertTo-OSDCloudBootStringEnvelope -Token $token

        Returns the decoded envelope, or terminates for an invalid token.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Byte[].

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-05
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$Token)

    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Validating encrypted string format"
    if ($Token.Length -gt 1398262 -or $Token -notmatch '^OSDBS1:[A-Za-z0-9+/]+={0,2}$') {
        throw [System.FormatException]::new('Invalid or unsupported encrypted string token.')
    }
    try { $bytes = [Convert]::FromBase64String($Token.Substring(7)) }
    catch { throw [System.FormatException]::new('Invalid encrypted string encoding.') }
    if ($bytes.Length -lt 97 -or $bytes.Length -gt 1048673 -or $bytes[0] -ne 1 -or ($bytes.Length - 81) % 16 -ne 0) {
        throw [System.FormatException]::new('Invalid or unsupported encrypted string envelope.')
    }
    return ,$bytes
}

function Invoke-OSDCloudBootStringCrypto {
    <#
    .SYNOPSIS
        Encrypts or authenticates and decrypts a portable string

    .DESCRIPTION
        Uses PBKDF2-HMAC-SHA256 (600000 iterations), independent AES-256-CBC and
        HMAC-SHA256 keys, and encrypt-then-MAC. Authentication covers the complete
        envelope preceding the tag. No sensitive arguments are logged.

    .PARAMETER Password
        Specifies a nonempty password as a SecureString.

    .PARAMETER InputString
        Specifies up to 1 MiB of UTF-8 plaintext to encrypt.

    .PARAMETER Token
        Specifies a token to authenticate before decrypting.

    .EXAMPLE
        PS> Invoke-OSDCloudBootStringCrypto -Token $token -Password $password

        Returns plaintext only after successful authentication.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-05
        Requires .NET support for the PBKDF2 SHA256 constructor.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Encrypt')]
    param (
        [Parameter(Mandatory)][System.Security.SecureString]$Password,
        [Parameter(Mandatory, ParameterSetName = 'Encrypt')][AllowEmptyString()][string]$InputString,
        [Parameter(Mandatory, ParameterSetName = 'Decrypt')][string]$Token
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Processing encrypted string"
    if ($Password.Length -eq 0) { throw 'An empty encryption password is not supported.' }
    if (-not [System.Security.Cryptography.Rfc2898DeriveBytes].GetConstructor(
            [type[]]@([byte[]], [byte[]], [int], [System.Security.Cryptography.HashAlgorithmName]))) {
        throw [System.PlatformNotSupportedException]::new('PBKDF2-HMAC-SHA256 requires .NET Framework 4.7.2 or newer in WinPE.')
    }
    $decrypt = $PSCmdlet.ParameterSetName -eq 'Decrypt'
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $pointer = [IntPtr]::Zero
    $passwordChars = $passwordBytes = $keys = $encryptionKey = $macKey = $plainBytes = $null
    $kdf = $aes = $hmac = $transform = $rng = $null
    try {
        $salt = New-Object byte[] 32
        $iv = New-Object byte[] 16
        if ($decrypt) {
            $envelope = ConvertTo-OSDCloudBootStringEnvelope -Token $Token
            [Array]::Copy($envelope, 1, $salt, 0, 32)
            [Array]::Copy($envelope, 33, $iv, 0, 16)
        }
        else {
            if ($utf8.GetByteCount($InputString) -gt 1048576) { throw 'The string exceeds the 1 MiB UTF-8 limit.' }
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($salt)
            $rng.GetBytes($iv)
        }

        $pointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $passwordChars = New-Object char[] $Password.Length
        [System.Runtime.InteropServices.Marshal]::Copy($pointer, $passwordChars, 0, $Password.Length)
        $passwordBytes = $utf8.GetBytes($passwordChars)
        $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
            $passwordBytes, $salt, 600000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        $keys = $kdf.GetBytes(64)
        $encryptionKey = New-Object byte[] 32
        $macKey = New-Object byte[] 32
        [Array]::Copy($keys, 0, $encryptionKey, 0, 32)
        [Array]::Copy($keys, 32, $macKey, 0, 32)
        $hmac = [System.Security.Cryptography.HMACSHA256]::new($macKey)
        if ($decrypt) {
            $authenticatedLength = $envelope.Length - 32
            $tag = $hmac.ComputeHash($envelope, 0, $authenticatedLength)
            $difference = 0
            for ($index = 0; $index -lt 32; $index++) {
                $difference = $difference -bor ($tag[$index] -bxor $envelope[$authenticatedLength + $index])
            }
            if ($difference -ne 0) {
                throw [System.Security.Cryptography.CryptographicException]::new('The password is incorrect or the encrypted string was modified.')
            }
        }

        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $encryptionKey
        $aes.IV = $iv
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        if ($decrypt) {
            $transform = $aes.CreateDecryptor()
            $plainBytes = $transform.TransformFinalBlock($envelope, 49, $envelope.Length - 81)
            return $utf8.GetString($plainBytes)
        }

        $plainBytes = $utf8.GetBytes($InputString)
        $transform = $aes.CreateEncryptor()
        $ciphertext = $transform.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        $envelope = New-Object byte[] (81 + $ciphertext.Length)
        $envelope[0] = 1
        [Array]::Copy($salt, 0, $envelope, 1, 32)
        [Array]::Copy($iv, 0, $envelope, 33, 16)
        [Array]::Copy($ciphertext, 0, $envelope, 49, $ciphertext.Length)
        $tag = $hmac.ComputeHash($envelope, 0, $envelope.Length - 32)
        [Array]::Copy($tag, 0, $envelope, $envelope.Length - 32, 32)
        return 'OSDBS1:' + [Convert]::ToBase64String($envelope)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        foreach ($buffer in @($passwordChars, $passwordBytes, $keys, $encryptionKey, $macKey, $plainBytes)) {
            if ($null -ne $buffer) { [Array]::Clear($buffer, 0, $buffer.Length) }
        }
        foreach ($resource in @($transform, $hmac, $aes, $kdf, $rng)) {
            if ($null -ne $resource) { $resource.Dispose() }
        }
    }
}
