BeforeAll {
    Add-Type -AssemblyName PresentationFramework
    . "$PSScriptRoot\OSDCloudBootString.ps1"
    . "$PSScriptRoot\Show-OSDCloudBootPasswordDialog.ps1"
    $script:password = ConvertTo-SecureString 'Synthetic dialog password' -AsPlainText -Force
    $script:token = Invoke-OSDCloudBootStringCrypto -InputString 'OSDCloudBootMenu profile access' -Password $password
    function Invoke-PasswordDialogTest {
        param ([scriptblock]$Action, [switch]$ConfirmPassword, [string]$Token)
        $owner = [System.Windows.Window]::new()
        $owner.Width = 100
        $owner.Height = 100
        $owner.Show()
        $state = @{ Error = $null }
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $tick = {
            $timer.Stop()
            $dialog = @($owner.OwnedWindows)[0]
            try { & $Action $dialog }
            catch { $state.Error = $_ }
            finally { if ($dialog.IsVisible) { $dialog.Close() } }
        }.GetNewClosure()
        $timer.Add_Tick($tick)
        try {
            $timer.Start()
            $result = Show-OSDCloudBootPasswordDialog -Owner $owner -ConfirmPassword:$ConfirmPassword -Token $Token
            if ($state.Error) { throw $state.Error }
            return $result
        }
        finally {
            $timer.Stop()
            $timer.Remove_Tick($tick)
            $owner.Close()
        }
    }
}
AfterAll { $script:password.Dispose() }

Describe 'Masked BootMenu profile password dialog' -Skip:([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    It 'requires nonempty matching confirmation and returns only a SecureString' {
        $result = Invoke-PasswordDialogTest -ConfirmPassword -Action {
            param ($dialog)
            $first = $dialog.FindName('Password')
            $second = $dialog.FindName('ConfirmPassword')
            $first | Should -BeOfType ([System.Windows.Controls.PasswordBox])
            $second | Should -BeOfType ([System.Windows.Controls.PasswordBox])
            $accept = $dialog.FindName('AcceptPassword')
            $event = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
            $accept.RaiseEvent($event)
            $dialog.FindName('PasswordError').Text | Should -Match 'nonempty'
            $first.Password = 'Synthetic dialog password'
            $second.Password = 'Different synthetic'
            $accept.RaiseEvent($event)
            $dialog.FindName('PasswordError').Text | Should -Match 'do not match'
            $dialog.IsVisible | Should -BeTrue
            $second.Password = 'Synthetic dialog password'
            $accept.RaiseEvent($event)
        }
        try { $result | Should -BeOfType ([Security.SecureString]); $result.Length | Should -Be 25 }
        finally { if ($result) { $result.Dispose() } }
    }

    It 'retries an incorrect password without closing and accepts a correct password' {
        $result = Invoke-PasswordDialogTest -Token $token -Action {
            param ($dialog)
            $dialog.FindName('Confirmation').Visibility | Should -Be 'Collapsed'
            $accept = $dialog.FindName('AcceptPassword')
            $event = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
            $dialog.FindName('Password').Password = 'Synthetic wrong'
            $accept.RaiseEvent($event)
            $dialog.FindName('PasswordError').Text | Should -Match 'Incorrect password'
            $dialog.IsVisible | Should -BeTrue
            $dialog.FindName('Password').Password = 'Synthetic dialog password'
            $accept.RaiseEvent($event)
        }
        try { $result | Should -BeOfType ([Security.SecureString]) }
        finally { if ($result) { $result.Dispose() } }
    }

    It 'returns no password on close' {
        Invoke-PasswordDialogTest -Token $token -Action {
            param ($dialog)
            $dialog.FindName('Password').Password = 'Synthetic dialog password'
            $dialog.Close()
        } | Should -BeNullOrEmpty
    }

    It 'allows cancellation after an incorrect password using <ButtonName>' -ForEach @(
        @{ ButtonName = 'TitleBarClose' }, @{ ButtonName = 'CancelPassword' }
    ) {
        Invoke-PasswordDialogTest -Token $token -Action {
            param ($dialog)
            [System.Windows.Shell.WindowChrome]::GetWindowChrome($dialog).CaptionHeight | Should -Be 48
            $dialog.FindName('WindowHeading').Text | Should -Be $dialog.Title
            $dialog.FindName('Password').Password = 'Synthetic wrong'
            $event = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
            $dialog.FindName('AcceptPassword').RaiseEvent($event)
            $dialog.FindName('PasswordError').Text | Should -Match 'Cancel to return to profiles'
            $dialog.FindName('Password').SecurePassword.Length | Should -Be 0
            $dialog.FindName('CancelPassword').IsCancel | Should -BeTrue
            $dialog.FindName($ButtonName).RaiseEvent($event)
            $dialog.IsVisible | Should -BeFalse
        } | Should -BeNullOrEmpty
    }
}
