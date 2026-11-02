BeforeDiscovery {
    $workflowNames = @('refresh', 'refreshalt')
}

BeforeAll {
    $workflowRoot = $PSScriptRoot
    Add-Type -AssemblyName PresentationFramework
    $sharedControls = @(
        'RootGrid', 'VersionText', 'LogoImage', 'MinimizeButton', 'MaximizeButton', 'CloseButton', 'PrivacyButton',
        'TaskSequenceCombo', 'OperatingSystemCombo', 'OSLanguageCodeCombo', 'OSEditionCombo', 'OSActivationCombo',
        'DriverPackCombo', 'SummaryText', 'StatusText', 'CancelButton', 'StartButton'
    )
}

Describe 'Refresh workflow <_>' -ForEach $workflowNames {
    BeforeAll {
        $name = $_
        $path = Join-Path $workflowRoot $name
    }

    It 'loads MainWindow.xaml with the required controls' {
        [xml]$xaml = Get-Content -Raw (Join-Path $path 'ui\MainWindow.xaml')
        $window = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
        foreach ($control in $sharedControls) {
            $window.FindName($control) | Should -Not -BeNullOrEmpty -Because "$control is used by MainWindow.ps1"
        }
        $window.FindName('StartButton').IsDefault | Should -BeFalse
    }

    It 'parses MainWindow.ps1 without errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $path 'ui\MainWindow.ps1'), [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'references only controls defined in MainWindow.xaml' {
        $xamlText = Get-Content -Raw (Join-Path $path 'ui\MainWindow.xaml')
        $script = Get-Content -Raw (Join-Path $path 'ui\MainWindow.ps1')
        $names = [regex]::Matches($script, "FindName\('([^']+)'\)") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        foreach ($controlName in $names) {
            $xamlText | Should -Match "x:Name=`"$controlName`""
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
}

Describe 'Workflow task ids' {
    It 'are unique for the refresh workflows' {
        $tasks = Get-ChildItem $workflowRoot -Recurse -Filter *.json | Where-Object { $_.Directory.Name -eq 'tasks' } |
            ForEach-Object { [pscustomobject]@{ Workflow = $_.Directory.Parent.Name; Id = (Get-Content -Raw $_.FullName | ConvertFrom-Json).id } }
        $refreshIds = $tasks | Where-Object Workflow -In 'refresh', 'refreshalt' | ForEach-Object Id
        $duplicates = $tasks | Where-Object Id -In $refreshIds | Group-Object Id | Where-Object Count -GT 1 | ForEach-Object Name
        $duplicates | Should -BeNullOrEmpty
    }
}
