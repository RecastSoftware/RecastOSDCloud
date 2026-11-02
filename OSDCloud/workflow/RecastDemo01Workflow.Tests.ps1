BeforeAll {
    $workflowRoot = $PSScriptRoot
    $workflowName = 'recast-demo-01'
    $path = Join-Path $workflowRoot $workflowName
    Add-Type -AssemblyName PresentationFramework
    function Get-WorkflowWindow {
        [xml]$xaml = Get-Content -Raw (Join-Path $path 'ui\MainWindow.xaml')
        [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
    }
}

Describe 'recast-demo-01 workflow' {
    It 'loads MainWindow.xaml with the required controls' {
        $window = Get-WorkflowWindow
        $controls = @(
            'RootGrid', 'VersionText', 'LogoImage', 'MinimizeButton', 'MaximizeButton', 'CloseButton', 'PrivacyButton',
            'TaskSequenceCombo', 'OperatingSystemCombo', 'OSLanguageCodeCombo', 'OSEditionCombo', 'OSActivationCombo',
            'DriverPackCombo', 'SummaryText', 'StatusText', 'CancelButton', 'StartButton'
        )
        foreach ($control in $controls) {
            $window.FindName($control) | Should -Not -BeNullOrEmpty -Because "$control is used by MainWindow.ps1"
        }
        $window.FindName('StartButton').IsDefault | Should -BeFalse
        $window.FindName('CancelButton').IsCancel | Should -BeTrue
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
}
