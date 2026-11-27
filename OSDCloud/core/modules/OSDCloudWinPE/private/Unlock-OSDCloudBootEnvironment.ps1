function Unlock-OSDCloudBootEnvironment {
    <#
    .SYNOPSIS
        Unlocks all encrypted environment values without assigning them

    .DESCRIPTION
        Prompts once per attempt for a shared password and retries authentication
        failures. Empty input cancels. Invalid tokens and unrepresentable environment
        values terminate without retry. A supplied password never triggers a prompt.
        No values are returned until every entry has decrypted successfully.

    .PARAMETER Environment
        Specifies the validated encryptedEnv dictionary.

    .PARAMETER Password
        Specifies an optional nonempty SecureString password for unattended use.

    .EXAMPLE
        PS> $values = Unlock-OSDCloudBootEnvironment -Environment $encryptedEnvironment

        Prompts and returns all unlocked values, without modifying the environment.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-05
        All entries must have been encrypted using the same password.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][System.Collections.IDictionary]$Environment,
        [System.Security.SecureString]$Password
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Unlocking profile environment"
    foreach ($name in $Environment.Keys) {
        $null = ConvertTo-OSDCloudBootStringEnvelope -Token $Environment[$name]
    }
    $interactive = -not $PSBoundParameters.ContainsKey('Password')
    while ($true) {
        $values = [ordered]@{}
        $complete = $false
        try {
            if ($interactive) {
                $Password = Read-Host -Prompt 'Unlock profile environment: password (empty cancels)' -AsSecureString
            }
            if ($null -eq $Password -or $Password.Length -eq 0) {
                throw [System.OperationCanceledException]::new('Profile environment unlock cancelled.')
            }
            foreach ($name in $Environment.Keys) {
                $value = Invoke-OSDCloudBootStringCrypto -Token $Environment[$name] -Password $Password
                if ($value.Length -eq 0 -or $value.Length -gt 32766 -or $value.Contains([char]0)) {
                    throw [System.InvalidOperationException]::new('An unlocked value cannot be represented as a nonempty Windows environment variable.')
                }
                $values[$name] = $value
                $value = $null
            }
            $complete = $true
            return $values
        }
        catch [System.Security.Cryptography.CryptographicException] {
            if (-not $interactive) { throw }
            Write-Warning 'Unable to unlock the profile: the password is incorrect or encrypted content was modified. Retry, or submit an empty password to cancel.'
        }
        finally {
            if (-not $complete) { $values.Clear() }
            $value = $null
            if ($interactive -and $Password) { $Password.Dispose(); $Password = $null }
        }
    }
}
