BeforeAll {
    $workflowRoot = $PSScriptRoot
    $workflowName = 'recast-winui-dark'
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
    $uiAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $path 'ui\MainWindow.ps1'), [ref]$null, [ref]$null)
    $initialFocusStatement = $uiAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $node.Member.Value -eq 'Add_ContentRendered'
        }, $true).Extent.Text
    $hardwareSummaryStatement = $uiAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -eq '$SummaryText.Text'
        }, $true).Extent.Text
}

Describe 'recast-winui-dark workflow' {
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
        $window.FindName('StartButton').IsDefault | Should -BeTrue
        $window.FindName('StartButton').IsEnabled | Should -BeFalse
        $window.FindName('CancelButton').IsCancel | Should -BeTrue
    }

    It 'uses the dark OSDCloud Boot palette' {
        $window = Get-WorkflowWindow
        $window.Background.Color.ToString() | Should -Be '#FF161F5B'
        $window.Foreground.Color.ToString() | Should -Be '#FFF5F5F5'
        $window.FindResource('AccentBrush').Color.ToString() | Should -Be '#FF31D1FF'
        $window.FindResource('SurfaceBrush').Color.ToString() | Should -Be '#FF1C2868'
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

    It 'uses the shared Recast logo for dark surfaces' {
        Join-Path $workflowRoot '..\core\recast-logo.png' | Should -Exist
        Get-Content -Raw (Join-Path $path 'ui\MainWindow.ps1') | Should -Match ([regex]::Escape("'..\..\..\core\recast-logo.png'"))
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

Describe 'recast-winui-dark keyboard navigation and hardware summary' {
    BeforeEach {
        $window = Get-WorkflowWindow
        $StartButton = $window.FindName('StartButton')
        foreach ($name in @(
                'TaskSequenceCombo', 'OperatingSystemCombo', 'OSLanguageCodeCombo',
                'OSEditionCombo', 'OSActivationCombo', 'DriverPackCombo'
            )) {
            $combo = $window.FindName($name)
            $null = $combo.Items.Add('Synthetic selection')
            $combo.SelectedIndex = 0
        }
        . ([scriptblock]::Create($initialFocusStatement))
    }

    AfterEach {
        $window.Close()
    }

    It 'focuses the text-only Start action when a valid selection enables deployment' {
        $StartButton.IsEnabled = $true
        $window.Show()
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

        $StartButton.IsKeyboardFocused | Should -BeTrue
        $StartButton.Content | Should -BeExactly 'Start'
        $window.FindName('TaskSequenceCombo').IsKeyboardFocusWithin | Should -BeFalse
        $window.IsVisible | Should -BeTrue -Because 'initial focus must not confirm deployment'
    }

    It 'focuses Cancel instead of enabling Start when deployment is unavailable' {
        $window.Show()
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

        $StartButton.IsEnabled | Should -BeFalse
        $window.FindName('CancelButton').IsKeyboardFocused | Should -BeTrue
    }

    It 'tabs forward and backward through all settings and both actions' {
        $StartButton.IsEnabled = $true
        $window.Show()
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        $names = @(
            'TaskSequenceCombo', 'OperatingSystemCombo', 'OSLanguageCodeCombo', 'OSEditionCombo',
            'OSActivationCombo', 'DriverPackCombo', 'CancelButton', 'StartButton'
        )
        $null = $window.FindName($names[0]).Focus()
        foreach ($name in $names | Select-Object -Skip 1) {
            $focused = [System.Windows.Input.Keyboard]::FocusedElement
            $focused.MoveFocus([System.Windows.Input.TraversalRequest]::new(
                    [System.Windows.Input.FocusNavigationDirection]::Next)) | Should -BeTrue
            [System.Windows.Input.Keyboard]::FocusedElement.Name | Should -Be $name
        }
        for ($index = $names.Count - 2; $index -ge 0; $index--) {
            $focused = [System.Windows.Input.Keyboard]::FocusedElement
            $focused.MoveFocus([System.Windows.Input.TraversalRequest]::new(
                    [System.Windows.Input.FocusNavigationDirection]::Previous)) | Should -BeTrue
            [System.Windows.Input.Keyboard]::FocusedElement.Name | Should -Be $names[$index]
        }
    }

    It 'skips disabled activation and keeps the actions reachable' {
        $StartButton.IsEnabled = $true
        $window.FindName('OSActivationCombo').IsEnabled = $false
        $window.Show()
        $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        $null = $window.FindName('OSEditionCombo').Focus()
        foreach ($name in 'DriverPackCombo', 'CancelButton', 'StartButton') {
            [System.Windows.Input.Keyboard]::FocusedElement.MoveFocus(
                [System.Windows.Input.TraversalRequest]::new(
                    [System.Windows.Input.FocusNavigationDirection]::Next)) | Should -BeTrue
            [System.Windows.Input.Keyboard]::FocusedElement.Name | Should -Be $name
        }
    }

    It 'shows manufacturer, model and product in that order with the full text in its tooltip' {
        $originalDevice = $global:OSDCoreDevice
        try {
            $global:OSDCoreDevice = [pscustomobject]@{
                OSDManufacturer = 'Microsoft'
                OSDModel = 'Virtual Machine'
                OSDProduct = 'Hyper-V UEFI Release v4.1'
            }
            $SummaryText = $window.FindName('SummaryText')
            . ([scriptblock]::Create($hardwareSummaryStatement))
            $SummaryText.Text | Should -BeExactly 'Microsoft | Virtual Machine | Hyper-V UEFI Release v4.1'
            $SummaryText.ToolTip | Should -BeExactly $SummaryText.Text
        }
        finally {
            $global:OSDCoreDevice = $originalDevice
        }
    }
}

Describe 'recast-winui-dark device and identity bar' {
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

    It 'keeps the header and device values readable on the dark surface' {
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
