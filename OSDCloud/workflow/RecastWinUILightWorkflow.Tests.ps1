BeforeAll {
    $workflowRoot = $PSScriptRoot
    $workflowName = 'recast-winui-light'
    $path = Join-Path $workflowRoot $workflowName
    Add-Type -AssemblyName PresentationFramework
    function Get-WorkflowWindow {
        [xml]$xaml = Get-Content -Raw (Join-Path $path 'ui\MainWindow.xaml')
        [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
    }
    function Update-WorkflowLayout {
        param($Window, [double]$Width, [double]$Height)
        $root = $Window.FindName('RootGrid')
        $root.Measure([System.Windows.Size]::new($Width, $Height))
        $root.Arrange([System.Windows.Rect]::new(0, 0, $Width, $Height))
        $root.UpdateLayout()
    }
}

Describe 'recast-winui-light workflow' {
    It 'loads MainWindow.xaml with the required controls' {
        $window = Get-WorkflowWindow
        $controls = @(
            'RootGrid', 'VersionText', 'LogoImage', 'MinimizeButton', 'MaximizeButton', 'CloseButton',
            'LogsMenuButton', 'WmiMenuButton', 'ShellMenuButton', 'PrivacyButton',
            'TaskSequenceCombo', 'OperatingSystemCombo', 'OSLanguageCodeCombo', 'OSEditionCombo', 'OSActivationCombo',
            'DriverPackCombo', 'SummaryText', 'StatusText', 'CancelButton', 'StartButton'
        )
        foreach ($control in $controls) {
            $window.FindName($control) | Should -Not -BeNullOrEmpty -Because "$control is used by MainWindow.ps1"
        }
        $window.FindName('StartButton').IsDefault | Should -BeFalse
        $window.FindName('StartButton').IsEnabled | Should -BeFalse
        $window.FindName('CancelButton').IsCancel | Should -BeTrue
    }

    It 'uses the Recast light palette' {
        $window = Get-WorkflowWindow
        $window.Background.Color.ToString() | Should -Be '#FFF4F6FB'
        $window.Foreground.Color.ToString() | Should -Be '#FF161F5B'
        $window.FindResource('AccentBrush').Color.ToString() | Should -Be '#FF0062DB'
        $window.FindResource('SurfaceBrush').Color.ToString() | Should -Be '#FFFFFFFF'
    }

    It 'keeps text readable with at least 4.5:1 contrast' {
        $window = Get-WorkflowWindow
        function Get-Luminance([System.Windows.Media.Color]$Color) {
            $channels = foreach ($channel in $Color.R, $Color.G, $Color.B) {
                $value = $channel / 255
                if ($value -le 0.03928) { $value / 12.92 } else { [math]::Pow(($value + 0.055) / 1.055, 2.4) }
            }
            0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2]
        }
        function Get-Contrast([System.Windows.Media.Color]$Foreground, [System.Windows.Media.Color]$Background) {
            $a = Get-Luminance $Foreground
            $b = Get-Luminance $Background
            ([math]::Max($a, $b) + 0.05) / ([math]::Min($a, $b) + 0.05)
        }
        $surface = $window.FindResource('SurfaceBrush').Color
        $accent = $window.FindResource('AccentBrush').Color
        Get-Contrast $window.Foreground.Color $window.Background.Color | Should -BeGreaterOrEqual 4.5
        Get-Contrast $window.Foreground.Color $window.FindResource('SelectionBrush').Color | Should -BeGreaterOrEqual 4.5
        Get-Contrast $window.FindResource('SecondaryTextBrush').Color $surface | Should -BeGreaterOrEqual 4.5
        Get-Contrast $accent $surface | Should -BeGreaterOrEqual 4.5
        $startForeground = $window.FindName('StartButton').Foreground.Color
        Get-Contrast $startForeground $accent | Should -BeGreaterOrEqual 4.5
    }

    It 'parses MainWindow.ps1 without errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $path 'ui\MainWindow.ps1'), [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'references only controls and resources defined in MainWindow.xaml' {
        $xamlText = Get-Content -Raw (Join-Path $path 'ui\MainWindow.xaml')
        $script = Get-Content -Raw (Join-Path $path 'ui\MainWindow.ps1')
        $names = [regex]::Matches($script, "FindName\('([^']+)'\)") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        foreach ($controlName in $names) {
            $xamlText | Should -Match "x:Name=`"$controlName`""
        }
        $resources = [regex]::Matches($script, "FindResource\('([^']+)'\)") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        foreach ($resourceName in $resources) {
            $xamlText | Should -Match "x:Key=`"$resourceName`""
        }
    }

    It 'ships the OSDCloud by Recast logo for light surfaces' {
        $logoPath = Join-Path $path 'ui\logo.png'
        $logoPath | Should -Exist
        $logo = [System.Windows.Media.Imaging.BitmapFrame]::Create([uri]$logoPath)
        $logo.PixelWidth | Should -BeGreaterThan $logo.PixelHeight
        Get-Content -Raw (Join-Path $path 'ui\MainWindow.ps1') | Should -Match ([regex]::Escape("Join-Path `$PSScriptRoot 'logo.png'"))
    }

    It 'provides valid OS settings for both architectures' {
        foreach ($arch in 'amd64', 'arm64') {
            $os = Get-Content -Raw (Join-Path $path "os-$arch.json") | ConvertFrom-Json
            $os.OperatingSystem.values | Should -Contain $os.OperatingSystem.default
            $os.OSActivation.values | Should -Contain $os.OSActivation.default
        }
    }

    It 'has tasks with bookend steps and exactly one default' {
        $tasks = Get-ChildItem (Join-Path $path 'tasks') -Filter *.json | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json }
        $tasks | Should -Not -BeNullOrEmpty
        @($tasks | Where-Object default).Count | Should -Be 1
        foreach ($task in $tasks) {
            $task.steps[0].command | Should -Be 'step-initialize-osdcloudworkflowtask'
            $task.steps[0].parameters.WorkflowTaskName | Should -Be $task.name
            $task.steps[-1].command | Should -Be 'step-finalize-stoposdcloudworkflow'
        }
    }

    It 'has task ids that are unique across all workflows' {
        $tasks = Get-ChildItem $workflowRoot -Recurse -Filter *.json | Where-Object { $_.Directory.Name -eq 'tasks' } |
            ForEach-Object { [pscustomobject]@{ Workflow = $_.Directory.Parent.Name; Id = (Get-Content -Raw $_.FullName | ConvertFrom-Json).id } }
        $workflowIds = $tasks | Where-Object Workflow -EQ $workflowName | ForEach-Object Id
        $workflowIds | Should -Not -BeNullOrEmpty
        $tasks | Where-Object Id -In $workflowIds | Group-Object Id | Where-Object Count -GT 1 | Should -BeNullOrEmpty
    }

    It 'keeps the Start button reachable at minimum size' {
        $window = Get-WorkflowWindow
        Update-WorkflowLayout -Window $window -Width 760 -Height 560
        $root = $window.FindName('RootGrid')
        $start = $window.FindName('StartButton')
        $origin = $start.TranslatePoint([System.Windows.Point]::new(0, 0), $root)
        ($origin.X + $start.ActualWidth) | Should -BeLessOrEqual 760
        ($origin.Y + $start.ActualHeight) | Should -BeLessOrEqual 560
    }
}

Describe 'recast-winui-light device and identity bar' {
    BeforeEach {
        $window = Get-WorkflowWindow
        $expander = $window.FindName('DeviceIdentityExpander')
        $null = $expander.ApplyTemplate()
        $header = $expander.Template.FindName('HeaderToggle', $expander)
        $presenter = $expander.Template.FindName('DetailsPresenter', $expander)
    }

    It 'starts collapsed with an accessible, focusable header' {
        $expander | Should -BeOfType [System.Windows.Controls.Expander]
        $expander.IsExpanded | Should -BeFalse
        $presenter.Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $header.Focusable | Should -BeTrue
        [System.Windows.Automation.AutomationProperties]::GetName($expander) | Should -Be 'Device and Identity'
        [System.Windows.Automation.AutomationProperties]::GetName($header) | Should -Be 'Device and Identity'
    }

    It 'expands and collapses through the header toggle' {
        $null = $header.ApplyTemplate()
        $chevron = $header.Template.FindName('HeaderChevron', $header)
        $collapsedChevron = $chevron.Data.ToString()
        $peer = [System.Windows.Automation.Peers.ToggleButtonAutomationPeer]::new($header)
        $toggle = $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Toggle)

        $toggle.Toggle()
        $expander.IsExpanded | Should -BeTrue
        $presenter.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $chevron.Data.ToString() | Should -Not -Be $collapsedChevron

        $toggle.Toggle()
        $expander.IsExpanded | Should -BeFalse
        $presenter.Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        $chevron.Data.ToString() | Should -Be $collapsedChevron
    }

    It 'exposes expand and collapse to accessibility clients' {
        $peer = [System.Windows.Automation.Peers.ExpanderAutomationPeer]::new($expander)
        $provider = $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::ExpandCollapse)

        $provider.Expand()
        $expander.IsExpanded | Should -BeTrue

        $provider.Collapse()
        $expander.IsExpanded | Should -BeFalse
    }

    It 'keeps every device field and identity copy control in the same bar' {
        $controls = @(
            'deviceOSDManufacturerText', 'deviceOSDModelText', 'deviceOSDProductText',
            'deviceComputerSystemSKUText', 'deviceBiosVersionText', 'deviceBiosReleaseDateText',
            'deviceIsTpmSpecText', 'deviceIsAutopilotSpecText', 'deviceSerialNumberText',
            'deviceUUIDText', 'deviceHardwareHashLabelText', 'deviceHardwareHashText',
            'CopySerialNumberButton', 'CopyUUIDButton', 'CopyHardwareHashButton'
        )
        foreach ($controlName in $controls) {
            $control = $window.FindName($controlName)
            $control | Should -Not -BeNullOrEmpty -Because "$controlName is populated or handled by MainWindow.ps1"
            $ancestor = $control
            while ($ancestor -and -not [object]::ReferenceEquals($ancestor, $expander)) {
                $ancestor = [System.Windows.LogicalTreeHelper]::GetParent($ancestor)
            }
            [object]::ReferenceEquals($ancestor, $expander) | Should -BeTrue -Because "$controlName belongs in the combined bar"
        }

        foreach ($controlName in 'deviceHardwareHashLabelText', 'deviceHardwareHashText', 'CopyHardwareHashButton') {
            $window.FindName($controlName).Visibility | Should -Be ([System.Windows.Visibility]::Collapsed)
        }
    }

    It 'retains identity values and optional hardware hash visibility when toggled' {
        $serial = $window.FindName('deviceSerialNumberText')
        $hash = $window.FindName('deviceHardwareHashText')
        $hashButton = $window.FindName('CopyHardwareHashButton')
        $serial.Text = 'SERIAL-TEST'
        $hash.Visibility = [System.Windows.Visibility]::Visible
        $hashButton.Visibility = [System.Windows.Visibility]::Visible

        $expander.IsExpanded = $true
        $expander.IsExpanded = $false
        $expander.IsExpanded = $true

        $serial.Text | Should -Be 'SERIAL-TEST'
        $hash.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
        $hashButton.Visibility | Should -Be ([System.Windows.Visibility]::Visible)
    }

    It 'keeps the header and device values readable on the light surface' {
        $expander.IsExpanded = $true
        Update-WorkflowLayout -Window $window -Width 1000 -Height 760

        $expectedForeground = $window.Foreground.Color.ToString()
        $expander.Header.Children[1].Foreground.Color.ToString() | Should -Be $expectedForeground
        $window.FindName('deviceOSDModelText').Foreground.Color.ToString() | Should -Be $expectedForeground
    }

    It 'keeps long identity values separate from their copy buttons at minimum width' {
        $serial = $window.FindName('deviceSerialNumberText')
        $serial.Text = 'SYNTHETIC-SERIAL-NUMBER-WITH-LONG-CONTENT'
        $uuid = $window.FindName('deviceUUIDText')
        $uuid.Text = '048A2C6B-A1D9-488C-8BF0-18D0F9A82D91'
        $expander.IsExpanded = $true
        Update-WorkflowLayout -Window $window -Width 760 -Height 560

        $details = $window.FindName('DeviceIdentityDetails')
        foreach ($pair in @(
                @{ Value = $serial; Button = $window.FindName('CopySerialNumberButton') }
                @{ Value = $uuid; Button = $window.FindName('CopyUUIDButton') }
            )) {
            $valueLeft = $pair.Value.TranslatePoint([System.Windows.Point]::new(0, 0), $details).X
            $buttonLeft = $pair.Button.TranslatePoint([System.Windows.Point]::new(0, 0), $details).X
            ($valueLeft + $pair.Value.ActualWidth) | Should -BeLessOrEqual $buttonLeft
            $pair.Button.ActualWidth | Should -BeGreaterThan 0
        }
    }

    It 'uses a compact header and reserves space for the expanded details' {
        Update-WorkflowLayout -Window $window -Width 1000 -Height 760
        $collapsedHeight = $expander.ActualHeight

        $expander.IsExpanded = $true
        $window.FindName('RootGrid').UpdateLayout()

        $collapsedHeight | Should -BeLessThan 72
        $expander.ActualHeight | Should -BeGreaterThan ($collapsedHeight + 100)

        $expander.IsExpanded = $false
        $window.FindName('RootGrid').UpdateLayout()
        $expander.ActualHeight | Should -Be $collapsedHeight
    }
}
