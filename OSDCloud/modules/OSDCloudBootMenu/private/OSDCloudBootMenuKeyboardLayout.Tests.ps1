BeforeAll {
    . "$PSScriptRoot\Get-OSDCloudBootMenuKeyboardLayout.ps1"
    . "$PSScriptRoot\Set-OSDCloudBootMenuKeyboardLayout.ps1"
}

Describe 'Get-OSDCloudBootMenuKeyboardLayout' {
    BeforeAll {
        $script:layoutPath = 'TestRegistry:\Keyboard Layouts'
        New-Item -Path $script:layoutPath -Force | Out-Null
        foreach ($layout in @(
                @{ Id = '00000409'; Text = 'US' },
                @{ Id = '00020409'; Text = 'United States-International' },
                @{ Id = '0000040c'; Text = 'French' },
                @{ Id = 'E0010404'; Text = 'Chinese IME' },
                @{ Id = '00000807'; Text = '' },
                @{ Id = 'NotALayout'; Text = 'Invalid' }
            )) {
            $key = New-Item -Path (Join-Path $script:layoutPath $layout.Id) -Force
            if ($layout.Text) {
                New-ItemProperty -Path $key.PSPath -Name 'Layout Text' -Value $layout.Text | Out-Null
            }
        }
    }

    It 'returns sorted settable layouts with wpeutil input locales and the current layout' {
        Mock Get-CimInstance { [pscustomobject]@{ Layout = '00000409' } }

        $layouts = @(Get-OSDCloudBootMenuKeyboardLayout -Path $script:layoutPath)

        $layouts.Name | Should -Be @('French', 'United States-International', 'US')
        ($layouts | Where-Object Name -EQ 'French').InputLocale | Should -Be '040C:0000040C'
        ($layouts | Where-Object Name -EQ 'United States-International').InputLocale | Should -Be '0409:00020409'
        ($layouts | Where-Object IsCurrent).Id | Should -Be '00000409'
    }

    It 'still lists layouts when the current layout cannot be detected' {
        Mock Get-CimInstance { throw 'WMI unavailable' }

        $layouts = @(Get-OSDCloudBootMenuKeyboardLayout -Path $script:layoutPath)

        $layouts.Count | Should -Be 3
        @($layouts | Where-Object IsCurrent).Count | Should -Be 0
    }
}

Describe 'Set-OSDCloudBootMenuKeyboardLayout' {
    It 'runs wpeutil SetKeyboardLayout with the input locale' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

        Set-OSDCloudBootMenuKeyboardLayout -InputLocale '040C:0000040C'

        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'wpeutil.exe' -and ($ArgumentList -join ' ') -eq 'SetKeyboardLayout 040C:0000040C' -and $Wait
        }
    }

    It 'throws when wpeutil exits with a non-zero code' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 5 } }

        { Set-OSDCloudBootMenuKeyboardLayout -InputLocale '0409:00000409' } | Should -Throw '*exited with code 5*'
    }

    It 'rejects malformed input locales' {
        Mock Start-Process { }

        { Set-OSDCloudBootMenuKeyboardLayout -InputLocale '00000409' } | Should -Throw
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}
