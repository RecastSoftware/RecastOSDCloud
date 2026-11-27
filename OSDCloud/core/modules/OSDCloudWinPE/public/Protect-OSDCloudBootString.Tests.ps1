BeforeAll {
    . "$PSScriptRoot\..\private\OSDCloudBootString.ps1"
    . "$PSScriptRoot\..\private\Unlock-OSDCloudBootEnvironment.ps1"
    . "$PSScriptRoot\..\private\Confirm-OSDCloudBootMenuProfilePassword.ps1"
    . "$PSScriptRoot\Protect-OSDCloudBootString.ps1"
    . "$PSScriptRoot\Unprotect-OSDCloudBootString.ps1"
    $script:password = ConvertTo-SecureString 'Synthetic-vector-password' -AsPlainText -Force
    $script:otherPassword = ConvertTo-SecureString 'Synthetic-wrong-password' -AsPlainText -Force
    $script:vector = 'OSDBS1:AQABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uL00Jov5YKptB383uAzXnSOzlsQ2erM/w1XLKP2t2tFHLND5fbXvbAT4oWekHfwIRdQ=='
}

AfterAll {
    $script:password.Dispose()
    $script:otherPassword.Dispose()
}

Describe 'Portable encrypted strings' {
    It 'decrypts the fixed version 1 vector' {
        Unprotect-OSDCloudBootString -Token $vector -Password $password | Should -BeExactly 'Known vector'
    }

    It 'round trips Unicode, quotes, and newlines with fresh salt and IV' {
        $text = "Synthetic '$([char]0x00e9)'`r`n$([char]0x4e2d)$([char]0x6587)"
        $first = Protect-OSDCloudBootString -InputString $text -Password $password
        $second = Protect-OSDCloudBootString -InputString $text -Password $password
        $second | Should -Not -Be $first
        Unprotect-OSDCloudBootString -Token $first -Password $password | Should -BeExactly $text
        $firstBytes = [Convert]::FromBase64String($first.Substring(7))
        $secondBytes = [Convert]::FromBase64String($second.Substring(7))
        [Convert]::ToBase64String($firstBytes[1..32]) | Should -Not -Be ([Convert]::ToBase64String($secondBytes[1..32]))
        [Convert]::ToBase64String($firstBytes[33..48]) | Should -Not -Be ([Convert]::ToBase64String($secondBytes[33..48]))
    }

    It 'supports an empty string but rejects an empty password' {
        $token = Protect-OSDCloudBootString -InputString '' -Password $password
        (Unprotect-OSDCloudBootString -Token $token -Password $password).Length | Should -Be 0
        $empty = [Security.SecureString]::new()
        try { { Protect-OSDCloudBootString -InputString 'Synthetic' -Password $empty } | Should -Throw '*empty*' }
        finally { $empty.Dispose() }
    }

    It 'authenticates the salt, IV, ciphertext, and tag before decryption' -ForEach @(
        @{ Offset = 1 }, @{ Offset = 33 }, @{ Offset = 49 }, @{ Offset = 96 }
    ) {
        $bytes = [Convert]::FromBase64String($vector.Substring(7))
        $bytes[$Offset] = $bytes[$Offset] -bxor 1
        $modified = 'OSDBS1:' + [Convert]::ToBase64String($bytes)
        { Unprotect-OSDCloudBootString -Token $modified -Password $password } |
            Should -Throw '*password is incorrect or the encrypted string was modified*'
    }

    It 'uses the same authentication failure for an incorrect password' {
        { Unprotect-OSDCloudBootString -Token $vector -Password $otherPassword } |
            Should -Throw '*password is incorrect or the encrypted string was modified*'
    }

    It 'rejects malformed, truncated and unsupported tokens before prompting' -ForEach @(
        @{ Value = 'OSDBS2:AAAA' }, @{ Value = 'OSDBS1:====' }, @{ Value = 'OSDBS1:AQ==' }
    ) {
        Mock Read-Host { throw 'Unexpected password prompt' }
        { Unprotect-OSDCloudBootString -Token $Value } | Should -Throw '*Invalid*'
        Should -Invoke Read-Host -Times 0 -Exactly
    }

    It 'enforces the exact UTF-8 input limit' {
        $text = 'a' * 1048576
        $token = Protect-OSDCloudBootString -InputString $text -Password $password
        (Unprotect-OSDCloudBootString -Token $token -Password $password).Length | Should -Be 1048576
        { Protect-OSDCloudBootString -InputString ($text + 'a') -Password $password } | Should -Throw '*1 MiB*'
    }

    It 'rejects mismatched interactive confirmation and emits no token' {
        $script:promptCount = 0
        Mock Read-Host {
            $script:promptCount++
            ConvertTo-SecureString $(if ($script:promptCount -eq 1) { 'Synthetic-one' } else { 'Synthetic-two' }) -AsPlainText -Force
        }
        { Protect-OSDCloudBootString -InputString 'Synthetic' } | Should -Throw '*do not match*'
        Should -Invoke Read-Host -Times 2 -Exactly -ParameterFilter { $AsSecureString }
    }

    It 'does not write passwords or plaintext to operation streams or a transcript' {
        $path = Join-Path $TestDrive 'synthetic-transcript.txt'
        $plain = 'SYNTHETIC-PLAINTEXT-MARKER'
        $null = Start-Transcript -Path $path
        try {
            $records = @(Protect-OSDCloudBootString -InputString $plain -Password $password -Verbose -Debug *>&1)
            $token = @($records | Where-Object { $_ -is [string] -and $_ -like 'OSDBS1:*' })[0]
            $result = Unprotect-OSDCloudBootString -Token $token -Password $password
            $result | Should -BeExactly $plain
        }
        finally { $null = Stop-Transcript }
        ($records | Out-String) | Should -Not -Match 'SYNTHETIC-PLAINTEXT-MARKER|Synthetic-vector-password'
        (Get-Content -LiteralPath $path -Raw) | Should -Not -Match 'SYNTHETIC-PLAINTEXT-MARKER|Synthetic-vector-password'
    }

    It 'encrypts and decrypts across Windows PowerShell 5.1 and the current runtime' {
        $modulePath = Join-Path $PSScriptRoot '..\OSDCloudBootMenu.psd1'
        $inputPath = Join-Path $TestDrive 'portable-token.txt'
        Protect-OSDCloudBootString -InputString 'Synthetic portable' -Password $password | Set-Content -LiteralPath $inputPath
        $child = @'
param($ModulePath, $TokenPath)
$ErrorActionPreference = 'Stop'
Import-Module -Name $ModulePath -Force
$password = ConvertTo-SecureString 'Synthetic-vector-password' -AsPlainText -Force
try {
    $token = Get-Content -LiteralPath $TokenPath -Raw
    if ((Unprotect-OSDCloudBootString -Token $token.Trim() -Password $password) -cne 'Synthetic portable') { throw 'Cross-runtime decryption failed' }
    Protect-OSDCloudBootString -InputString 'Synthetic child' -Password $password
}
finally { $password.Dispose() }
'@
        $scriptPath = Join-Path $TestDrive 'portable.ps1'
        $child | Set-Content -LiteralPath $scriptPath
        $token = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File $scriptPath $modulePath $inputPath
        $LASTEXITCODE | Should -Be 0
        Unprotect-OSDCloudBootString -Token $token -Password $password | Should -BeExactly 'Synthetic child'
    }
}

Describe 'Atomic environment unlock' {
    It 'retries the shared password without returning partially decrypted values' {
        $script:attempt = 0
        Mock Read-Host {
            $script:attempt++
            ConvertTo-SecureString "Synthetic-attempt-$script:attempt" -AsPlainText -Force
        }

        Mock Invoke-OSDCloudBootStringCrypto {
            if ($script:attempt -eq 1 -and $Token -eq $script:secondToken) {
                throw [Security.Cryptography.CryptographicException]::new('Synthetic authentication failure')
            }
            if ($Token -eq $script:secondToken) { 'Synthetic second' } else { 'Synthetic first' }
        }
        Mock Write-Warning { }
        $bytes = [Convert]::FromBase64String($vector.Substring(7))
        $bytes[1] = 50
        $script:secondToken = 'OSDBS1:' + [Convert]::ToBase64String($bytes)
        $result = Unlock-OSDCloudBootEnvironment -Environment ([ordered]@{ FIRST = $vector; SECOND = $secondToken })
        $result.Count | Should -Be 2
        $result['FIRST'] | Should -BeExactly 'Synthetic first'
        $result['SECOND'] | Should -BeExactly 'Synthetic second'
        Should -Invoke Read-Host -Times 2 -Exactly -ParameterFilter { $AsSecureString }
        Should -Invoke Write-Warning -Times 1 -Exactly
    }

    It 'cancels empty interactive input without decrypting' {
        Mock Read-Host { [Security.SecureString]::new() }
        Mock Invoke-OSDCloudBootStringCrypto { throw 'Unexpected decryption' }
        { Unlock-OSDCloudBootEnvironment -Environment @{ FIRST = $vector } } | Should -Throw '*cancelled*'
        Should -Invoke Invoke-OSDCloudBootStringCrypto -Times 0 -Exactly
    }

    It 'does not prompt after a supplied incorrect password' {
        Mock Read-Host { throw 'Unexpected password prompt' }
        { Unlock-OSDCloudBootEnvironment -Environment @{ FIRST = $vector } -Password $otherPassword } | Should -Throw '*password is incorrect*'
        Should -Invoke Read-Host -Times 0 -Exactly
    }

    It 'rejects unrepresentable environment values without retrying' -ForEach @(
        @{ Value = '' }, @{ Value = "before$([char]0)after" }, @{ Value = ('x' * 32767) }
    ) {
        Mock Invoke-OSDCloudBootStringCrypto { $Value }
        Mock Read-Host { throw 'Unexpected retry' }
        { Unlock-OSDCloudBootEnvironment -Environment @{ FIRST = $vector } -Password $password } | Should -Throw '*cannot be represented*'
        Should -Invoke Read-Host -Times 0 -Exactly
    }

    It 'accepts the exact Windows environment value length limit' {
        Mock Invoke-OSDCloudBootStringCrypto { 'x' * 32766 }
        $result = Unlock-OSDCloudBootEnvironment -Environment @{ FIRST = $vector } -Password $password
        $result['FIRST'].Length | Should -Be 32766
    }
}

Describe 'Profile password verification' {
    BeforeAll {
        $script:accessToken = Protect-OSDCloudBootString -InputString 'OSDCloudBootMenu profile access' -Password $password
    }

    It 'accepts the correct supplied password and rejects a different token purpose' {
        Confirm-OSDCloudBootMenuProfilePassword -Token $accessToken -Password $password | Should -BeTrue
        { Confirm-OSDCloudBootMenuProfilePassword -Token $vector -Password $password } | Should -Throw '*Invalid profile password token*'
        $password.Length | Should -BeGreaterThan 0
    }

    It 'does not silently retry or prompt for an incorrect supplied password' {
        Mock Read-Host { throw 'Unexpected prompt' }
        { Confirm-OSDCloudBootMenuProfilePassword -Token $accessToken -Password $otherPassword } | Should -Throw '*password is incorrect*'
        Should -Invoke Read-Host -Times 0 -Exactly
    }

    It 'retries incorrect console input until success' {
        $script:attempt = 0
        Mock Read-Host {
            $script:attempt++
            ConvertTo-SecureString $(if ($script:attempt -eq 1) { 'Synthetic wrong' } else { 'Synthetic-vector-password' }) -AsPlainText -Force
        }
        Mock Write-Warning { }
        Confirm-OSDCloudBootMenuProfilePassword -Token $accessToken -CLI | Should -BeTrue
        Should -Invoke Read-Host -Times 2 -Exactly -ParameterFilter { $AsSecureString }
        Should -Invoke Write-Warning -Times 1 -Exactly
    }

    It 'cancels empty console input' {
        Mock Read-Host { [Security.SecureString]::new() }
        Confirm-OSDCloudBootMenuProfilePassword -Token $accessToken -CLI | Should -BeFalse
    }
}
