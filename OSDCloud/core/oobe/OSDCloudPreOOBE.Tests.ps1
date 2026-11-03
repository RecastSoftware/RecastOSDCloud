BeforeAll {
    . "$PSScriptRoot\OSDCloudPreOOBE.ps1" -Preview
    Initialize-OOBEMenuNative
    $menuScriptPath = "$PSScriptRoot\OSDCloudPreOOBE.ps1"
}

Describe 'Standalone OOBE menu startup' {
    BeforeEach {
        $Preview = $false
        $Phase = 'OOBE'
        $InteractiveChild = $false
        $ReadyEvent = $null
        Mock Write-OOBEMenuLog {}
        Mock Write-Error {}
        Mock Show-OOBEMenuWindow { 0 }
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{
                IsSystem = $true
                Identity = 'NT AUTHORITY\SYSTEM'
                SessionId = 1
                Station = 'WinSta0'
                Desktop = 'Default'
                ConsoleSession = 1
                IsInputDesktop = $true
            }
        }
    }

    It 'returns zero after a normal visible menu closure without launching a bridge' {
        Mock Invoke-OOBEMenuChild { throw 'Unexpected child launch' }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath | Should -Be 0
        Should -Invoke Show-OOBEMenuWindow -Times 1 -Exactly
        Should -Invoke Invoke-OOBEMenuChild -Times 0 -Exactly
    }

    It 'propagates the session child exit code without showing a hidden parent menu' {
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{ IsSystem = $true; IsInputDesktop = $false; SessionId = 0 }
        }
        Mock Invoke-OOBEMenuChild { 7 }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath | Should -Be 7
        Should -Invoke Invoke-OOBEMenuChild -Times 1 -Exactly -ParameterFilter {
            $ScriptPath -eq $menuScriptPath
        }
        Should -Invoke Show-OOBEMenuWindow -Times 0 -Exactly
    }

    It 'logs menu creation failure and returns nonzero' {
        Mock Show-OOBEMenuWindow { throw 'WPF unavailable' }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Write-OOBEMenuLog -Times 1 -ParameterFilter {
            $Message -like '*startup failed*WPF unavailable*'
        }
    }

    It 'returns nonzero if the native session launcher fails' {
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{ IsSystem = $true; IsInputDesktop = $false }
        }
        Mock Invoke-OOBEMenuChild { throw 'No console session is available' }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Show-OOBEMenuWindow -Times 0 -Exactly
    }

    It 'rejects non-SYSTEM execution outside preview' {
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{ IsSystem = $false; IsInputDesktop = $true }
        }
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Show-OOBEMenuWindow -Times 0 -Exactly
    }

    It 'does not cross sessions in preview' {
        $Preview = $true
        Mock Get-OOBEMenuContext {
            [pscustomobject]@{ IsSystem = $false; IsInputDesktop = $false }
        }
        Mock Invoke-OOBEMenuChild {}
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Invoke-OOBEMenuChild -Times 0 -Exactly
    }

    It 'rejects internal child mode without its readiness event' {
        $InteractiveChild = $true
        Invoke-OOBEMenu -ScriptPath $menuScriptPath -ErrorAction SilentlyContinue | Should -Be 1
        Should -Invoke Show-OOBEMenuWindow -Times 0 -Exactly
    }

    It 'resolves native PowerShell and cmd paths to existing inbox executables' {
        Get-OOBEMenuNativePath -PowerShell | Should -BeLike '*\WindowsPowerShell\v1.0\powershell.exe'
        Get-OOBEMenuNativePath | Should -BeLike '*\cmd.exe'
        Test-Path -LiteralPath (Get-OOBEMenuNativePath -PowerShell) | Should -BeTrue
    }

    It 'reports a missing inbox executable instead of returning an invalid path' {
        Mock Test-Path { $false }
        { Get-OOBEMenuNativePath -PowerShell } | Should -Throw '*Inbox executable is missing*'
    }
}

Describe 'SetupComplete clock validation' {
    BeforeEach {
        Mock Write-OOBEMenuLog {}
        Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $true } }
        Mock Set-TimeZone {}
        Mock Set-Date {}
    }

    It 'previews all clock settings without changing anything' {
        Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId 'UTC' -PreviewOnly |
            Should -Be 'Preview: would set 2030-06-15 14:30:00 (UTC).'
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'applies the chosen local time as the correct UTC instant after setting the selected time zone' {
        Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId 'Eastern Standard Time' |
            Should -BeLike 'Date, time, and time zone set to *'
        Should -Invoke Set-TimeZone -Times 1 -Exactly -ParameterFilter { $Id -eq 'Eastern Standard Time' -and $ErrorAction -eq 'Stop' }
        Should -Invoke Set-Date -Times 1 -Exactly -ParameterFilter {
            $Date.ToString('yyyy-MM-dd HH:mm:ss') -eq '2030-06-15 18:30:00' -and
            $Date.Kind -eq [DateTimeKind]::Utc -and $ErrorAction -eq 'Stop'
        }
    }

    It 'rejects invalid time format before changing time or zone' {
        foreach ($time in '25:00:00', '2:30 PM', '14:30', 'invalid') {
            { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time $time -TimeZoneId UTC } |
                Should -Throw '*HH:mm:ss*'
        }
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'rejects invalid zones before changing the clock' {
        { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId 'Invalid Zone' } | Should -Throw
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'rejects daylight-saving gaps and repeated hours' {
        { Set-OOBEMenuClock -Date ([datetime]'2030-03-10') -Time '02:30:00' -TimeZoneId 'Eastern Standard Time' } |
            Should -Throw '*daylight-saving*'
        { Set-OOBEMenuClock -Date ([datetime]'2030-11-03') -Time '01:30:00' -TimeZoneId 'Eastern Standard Time' } |
            Should -Throw '*daylight-saving*'
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'does not attempt to set the clock after a time-zone failure' {
        Mock Set-TimeZone { throw 'Time zone update failed' }
        { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId UTC } |
            Should -Throw '*Time zone update failed*'
        Should -Invoke Set-Date -Times 0 -Exactly
    }

    It 'surfaces a date failure explicitly after a successful zone change' {
        Mock Set-Date { throw 'Clock update failed' }
        { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId UTC } |
            Should -Throw '*Clock update failed*'
        Should -Invoke Write-OOBEMenuLog -Times 1 -ParameterFilter { $Message -like 'Time zone set*' }
    }

    It 'rejects non-SYSTEM clock changes' {
        Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $false } }
        { Set-OOBEMenuClock -Date ([datetime]'2030-06-15') -Time '14:30:00' -TimeZoneId UTC } |
            Should -Throw '*require SYSTEM*'
        Should -Invoke Set-TimeZone -Times 0 -Exactly
    }

    It 'rejects dates outside the Windows system clock range before changing the time zone' {
        { Set-OOBEMenuClock -Date ([datetime]'1500-06-15') -Time '14:30:00' -TimeZoneId UTC } |
            Should -Throw '*1601*'
        Should -Invoke Set-TimeZone -Times 0 -Exactly
        Should -Invoke Set-Date -Times 0 -Exactly
    }
}


