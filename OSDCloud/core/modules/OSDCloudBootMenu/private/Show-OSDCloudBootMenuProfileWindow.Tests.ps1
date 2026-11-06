BeforeAll {
    Add-Type -AssemblyName PresentationFramework
    . "$PSScriptRoot\Show-OSDCloudBootMenuProfileWindow.ps1"
    function Invoke-ProfileWindowTest {
        param ([scriptblock]$Action, [switch]$TestMode)
        $state = @{ Error = $null }
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(100)
        $tick = {
            $timer.Stop()
            $window = @([System.Windows.PresentationSource]::CurrentSources |
                ForEach-Object { $_.RootVisual } |
                Where-Object { $_ -is [System.Windows.Window] -and $_.Title -like 'Recast Software - OSDCloud BootMenu*' })[0]
            try { & $Action $window }
            catch { $state.Error = $_ }
            finally {
                if ($window.IsVisible) {
                    $event = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
                    $window.FindName('StartButton').RaiseEvent($event)
                }
            }
        }.GetNewClosure()
        $timer.Add_Tick($tick)
        $candidate = [pscustomobject]@{ Profile = 'Synthetic profile'; Path = 'X:\Synthetic\osdcloudbootmenu.json'; AssetPath = $null }
        try {
            $timer.Start()
            $result = Show-OSDCloudBootMenuProfileWindow -Profiles @($candidate) -TestMode:$TestMode
            if ($state.Error) { throw $state.Error }
            $result
        }
        finally {
            $timer.Stop()
            $timer.Remove_Tick($tick)
        }
    }
}

Describe 'BootMenu required profile selection' -Skip:([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    It 'blocks closing and Escape until Start selects a profile' {
        $result = Invoke-ProfileWindowTest -Action {
            param ($window)
            $window.FindName('CancelButton') | Should -BeNullOrEmpty
            $window.FindName('TitleBarClose').Visibility | Should -Be 'Collapsed'
            $window.Close()
            $window.IsVisible | Should -BeTrue
            $source = [System.Windows.PresentationSource]::FromVisual($window)
            $key = [System.Windows.Input.KeyEventArgs]::new(
                [System.Windows.Input.Keyboard]::PrimaryDevice, $source, 0, [System.Windows.Input.Key]::Escape)
            $key.RoutedEvent = [System.Windows.Input.Keyboard]::PreviewKeyDownEvent
            $window.RaiseEvent($key)
            $key.Handled | Should -BeTrue
            $window.IsVisible | Should -BeTrue
            $window.FindName('StartButton').RaiseEvent(
                [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            $window.IsVisible | Should -BeFalse
        }
        $result.Profile | Should -Be 'Synthetic profile'
    }

    It 'still allows the inert test preview to close without selecting a profile' {
        Invoke-ProfileWindowTest -TestMode -Action {
            param ($window)
            $window.FindName('TitleBarClose').Visibility | Should -Be 'Visible'
            $window.Close()
            $window.IsVisible | Should -BeFalse
        } | Should -BeNullOrEmpty
    }
}
