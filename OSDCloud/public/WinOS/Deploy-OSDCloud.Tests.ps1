BeforeAll {
    $moduleRoot = Join-Path $PSScriptRoot '..\..'
    $testModule = New-Module -Name DiskParameterDeploymentTests -ArgumentList $moduleRoot -ScriptBlock {
        param ($ModuleRoot)
        . "$ModuleRoot\public\WinOS\Deploy-OSDCloud.ps1"
        . "$ModuleRoot\private\Initialize-OSDCloudResults.ps1"
        . "$ModuleRoot\private\Update-OSDCloudResults.ps1"
        . "$ModuleRoot\private\Export-OSDCloudResults.ps1"
        . "$ModuleRoot\private\Send-OSDCloudResults.ps1"
        . "$ModuleRoot\private\Initialize-DeployOSDCloud.ps1"
        . "$ModuleRoot\private\Update-OSDCloudCoreCatalogOS.ps1"
        . "$ModuleRoot\private\core-license\Get-OSDCoreLicense.ps1"
        . "$ModuleRoot\private\core-license\Test-OSDCoreLicense.ps1"
        . "$ModuleRoot\private\core\Convert-KeyboardLayoutToLanguageCode.ps1"
        function Get-OSDCloudWorkflowRuntimeParameter {
            [CmdletBinding()]
            param ($ModuleBase, $WorkflowName, $ProcessorArchitecture)
            $parameters = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
            $attributes = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $attributes.Add([System.Management.Automation.ParameterAttribute]::new())
            $parameters.Add('OSLanguageCode', [System.Management.Automation.RuntimeDefinedParameter]::new('OSLanguageCode', [string], $attributes))
            return $parameters
        }
        function Initialize-OSDCoreLicense { [CmdletBinding()] param () }
        function Initialize-OSDCoreDevice { [CmdletBinding()] param () }
        function Invoke-OSDCloudWorkflowTask { [CmdletBinding()] param () }
        function Invoke-OSDCloudWorkflowUI { [CmdletBinding()] param ($WorkflowName) }
    }
    Import-Module $testModule
    $originalDevice = $global:OSDCoreDevice
    $originalDeploy = $global:OSDCloudDeploy
    $originalLicense = $global:OSDCoreLicense
    $originalResults = Get-Variable -Name OSDCloudResults -Scope Global -ErrorAction SilentlyContinue
    $originalWorkflowInvoke = Get-Variable -Name OSDCloudWorkflowInvoke -Scope Global -ErrorAction SilentlyContinue
}

AfterAll {
    Remove-Module DiskParameterDeploymentTests
    $global:OSDCoreDevice = $originalDevice
    $global:OSDCloudDeploy = $originalDeploy
    $global:OSDCoreLicense = $originalLicense
    if ($originalResults) { $global:OSDCloudResults = $originalResults.Value }
    else { Remove-Variable -Name OSDCloudResults -Scope Global -ErrorAction SilentlyContinue }
    if ($originalWorkflowInvoke) { $global:OSDCloudWorkflowInvoke = $originalWorkflowInvoke.Value }
    else { Remove-Variable -Name OSDCloudWorkflowInvoke -Scope Global -ErrorAction SilentlyContinue }
}

Describe 'Deploy-OSDCloud disk parameters' {
    BeforeEach {
        Mock Get-CimInstance { @() } -ModuleName DiskParameterDeploymentTests
        $global:OSDCoreDevice = [pscustomobject]@{
            OSDManufacturer = 'HP'; OSDModel = 'Test'; OSDProduct = 'Test'
            ProcessorArchitecture = 'amd64'; KeyboardLayout = $null
        }
        $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $true }
        $global:OSDCloudDeploy = [pscustomobject]@{ TimeStart = $null }
        Mock Get-OSDCoreLicense {
            if ($global:OSDCoreLicense.IsIncognito -ne $true) { [pscustomobject]@{ IsValid = $true } }
        } -ModuleName DiskParameterDeploymentTests
        Mock Convert-KeyboardLayoutToLanguageCode { 'fr-FR' } -ModuleName DiskParameterDeploymentTests
        Mock Initialize-OSDCoreLicense {} -ModuleName DiskParameterDeploymentTests
        Mock Initialize-OSDCoreDevice {} -ModuleName DiskParameterDeploymentTests
        Mock Initialize-DeployOSDCloud {} -ModuleName DiskParameterDeploymentTests
        Mock Invoke-OSDCloudWorkflowTask {} -ModuleName DiskParameterDeploymentTests
        Mock Invoke-OSDCloudWorkflowUI {} -ModuleName DiskParameterDeploymentTests
        Mock Export-OSDCloudResults {} -ModuleName DiskParameterDeploymentTests
        Mock Send-OSDCloudResults {} -ModuleName DiskParameterDeploymentTests
        Mock Export-Clixml {} -ModuleName DiskParameterDeploymentTests
        Mock Out-File {} -ModuleName DiskParameterDeploymentTests
        Mock Test-Path { $true } -ModuleName DiskParameterDeploymentTests
        Mock Remove-Item {} -ModuleName DiskParameterDeploymentTests
        Mock Write-Host {} -ModuleName DiskParameterDeploymentTests
        Mock Out-Host {} -ModuleName DiskParameterDeploymentTests
        Mock Format-List { $InputObject } -ModuleName DiskParameterDeploymentTests
    }

    It 'records completed results for CLI=<CLI> before terminal reporting' -TestCases @(
        @{ CLI = $true }
        @{ CLI = $false }
    ) {
        param ($CLI)
        Mock Invoke-OSDCloudWorkflowUI { $global:OSDCloudDeploy.TimeStart = Get-Date } -ModuleName DiskParameterDeploymentTests
        Mock Invoke-OSDCloudWorkflowTask {
            $global:OSDCloudResults.Status | Should -Be 'Running'
            $global:OSDCloudResults.IsComplete | Should -BeFalse
            $global:OSDCloudResults.StartTimeUtc.Kind | Should -Be 'Utc'
            $global:OSDCloudResults.EndTimeUtc | Should -BeNullOrEmpty
            $global:OSDCloudWorkflowInvoke | Should -BeNullOrEmpty
            [System.Threading.Thread]::Sleep(30)
        } -ModuleName DiskParameterDeploymentTests
        Mock Send-OSDCloudResults {
            $global:OSDCloudResults.Status | Should -Be 'Completed'
            $global:OSDCloudResults.IsComplete | Should -BeTrue
            $global:OSDCloudResults.totalDurationRAW | Should -BeOfType ([long])
            $global:OSDCloudResults.totalDuration | Should -Be $global:OSDCloudResults.totalDurationRAW
            $global:OSDCloudResults.totalDurationRAW | Should -BeGreaterOrEqual 0
            $global:OSDCloudResults.EndTimeUtc.Kind | Should -Be 'Utc'
        } -ModuleName DiskParameterDeploymentTests
        $global:OSDCloudWorkflowInvoke = @{ ParamsExpandWindowsImage = @{ ApplyPath = 'Z:\stale' } }
        Deploy-OSDCloud -CLI:$CLI
        Should -Invoke Send-OSDCloudResults -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly
        Should -Invoke Out-Host -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter {
            $expectedProperties = @(
                'DeploymentId', 'ModuleVersion', 'WorkflowName', 'WorkflowTaskName',
                'LaunchMethod', 'DeploymentPhase', 'OSDManufacturer', 'OSDModel',
                'OSDProduct', 'IsComplete', 'Status', 'StartTimeUtc', 'EndTimeUtc',
                'totalDuration', 'ContentSource', 'ContentInternet', 'ContentLocal'
            )
            $InputObject.DeploymentId -eq $global:OSDCloudResults.DeploymentId -and
            $InputObject.IsComplete -and
            (@($InputObject.PSObject.Properties.Name) -join ',') -ceq ($expectedProperties -join ',')
        }
        Should -Invoke Export-OSDCloudResults -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter { -not $IncludeTarget }
        Should -Invoke Export-OSDCloudResults -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter { $IncludeTarget }
    }

    It 'records GUI cancellation without timing, a target export, or terminal analytics' {
        Deploy-OSDCloud
        $global:OSDCloudResults.Status | Should -Be 'Cancelled'
        Should -Invoke Format-List -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        $global:OSDCloudResults.IsComplete | Should -BeFalse
        $global:OSDCloudResults.StartTimeUtc | Should -BeNullOrEmpty
        $global:OSDCloudResults.EndTimeUtc | Should -BeNullOrEmpty
        $global:OSDCloudResults.totalDurationRAW | Should -BeNullOrEmpty
        $global:OSDCloudResults.totalDuration | Should -BeNullOrEmpty
        Should -Invoke Invoke-OSDCloudWorkflowTask -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Send-OSDCloudResults -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Export-OSDCloudResults -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter { -not $IncludeTarget }
    }

    It 'records terminating workflow failure and preserves CLI=<CLI> error behavior' -TestCases @(
        @{ CLI = $true }
        @{ CLI = $false }
    ) {
        param ($CLI)
        Mock Invoke-OSDCloudWorkflowUI { $global:OSDCloudDeploy.TimeStart = Get-Date } -ModuleName DiskParameterDeploymentTests
        Mock Invoke-OSDCloudWorkflowTask { throw 'Synthetic workflow failure' } -ModuleName DiskParameterDeploymentTests
        if ($CLI) {
            { Deploy-OSDCloud -CLI } | Should -Throw '*Synthetic workflow failure*'
        }
        else {
            Deploy-OSDCloud -WarningVariable warnings
            "$warnings" | Should -Match 'Synthetic workflow failure'
        }
        $global:OSDCloudResults.Status | Should -Be 'Failed'
        $global:OSDCloudResults.IsComplete | Should -BeFalse
        $global:OSDCloudResults.EndTimeUtc | Should -Not -BeNullOrEmpty
        Should -Invoke Format-List -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        $global:OSDCloudResults.totalDurationRAW | Should -BeOfType ([long])
        Should -Invoke Send-OSDCloudResults -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly
    }

    It 'resets results and records initialization failure without timing or terminal analytics' {
        Deploy-OSDCloud -CLI
        $previousId = $global:OSDCloudResults.DeploymentId
        Mock Initialize-DeployOSDCloud { throw 'Synthetic initialization failure' } -ModuleName DiskParameterDeploymentTests
        { Deploy-OSDCloud -CLI } | Should -Throw '*Synthetic initialization failure*'
        $global:OSDCloudResults.DeploymentId | Should -Not -Be $previousId
        $global:OSDCloudResults.Status | Should -Be 'Failed'
        $global:OSDCloudResults.IsComplete | Should -BeFalse
        $global:OSDCloudResults.totalDurationRAW | Should -BeNullOrEmpty
        Should -Invoke Send-OSDCloudResults -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly
    }

    It 'excludes initialization, UI selection, and results export time from the stopwatch' {
        Mock Initialize-DeployOSDCloud { [System.Threading.Thread]::Sleep(300) } -ModuleName DiskParameterDeploymentTests
        Mock Invoke-OSDCloudWorkflowUI {
            [System.Threading.Thread]::Sleep(300)
            $global:OSDCloudDeploy.TimeStart = Get-Date
        } -ModuleName DiskParameterDeploymentTests
        Mock Export-OSDCloudResults { [System.Threading.Thread]::Sleep(300) } -ModuleName DiskParameterDeploymentTests
        Mock Invoke-OSDCloudWorkflowTask { [System.Threading.Thread]::Sleep(40) } -ModuleName DiskParameterDeploymentTests
        Deploy-OSDCloud
        $global:OSDCloudResults.totalDurationRAW | Should -BeOfType ([long])
        $global:OSDCloudResults.totalDurationRAW | Should -Be 0
    }

    It 'finalizes and reports results before the PostAction <PostAction> countdown' -TestCases @(
        @{ PostAction = 'Restart' }
        @{ PostAction = 'Shutdown' }
        @{ PostAction = 'Exit' }
    ) {
        param ($PostAction)
        $originalSystemDrive = $env:SystemDrive
        try {
            $env:SystemDrive = 'X:'
            Mock Start-Sleep {
                $global:OSDCloudResults.IsComplete | Should -BeTrue
                $global:OSDCloudResults.Status | Should -Be 'Completed'
                $global:OSDCloudResults.totalDurationRAW | Should -BeOfType ([long])
                Should -Invoke Send-OSDCloudResults -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly
                Should -Invoke Out-Host -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter {
                    $InputObject.DeploymentId -eq $global:OSDCloudResults.DeploymentId -and $InputObject.IsComplete -and @($InputObject.PSObject.Properties.Name | Where-Object { $_ -match '^(step|rate)' }).Count -eq 0
                }
                Should -Invoke Export-OSDCloudResults -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter { $IncludeTarget }
                throw 'Stop before host exit or restart'
            } -ModuleName DiskParameterDeploymentTests
            { Deploy-OSDCloud -CLI -PostAction $PostAction } | Should -Throw '*Stop before host exit or restart*'
        }
        finally {
            $env:SystemDrive = $originalSystemDrive
        }
    }

    It 'forwards all explicit disk parameters for CLI and GUI launches: CLI=<CLI>' -TestCases @(
        @{ CLI = $true }
        @{ CLI = $false }
    ) {
        param ($CLI)
        Deploy-OSDCloud -CLI:$CLI -DiskNumber 0 -DiskLabelOS Windows -DiskLabelRecovery WinRE `
            -DiskSizeSystem 1GB -DiskSizeOS 32GB -DiskSizeRecovery 3GB
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter {
            $DiskNumber -eq 0 -and $DiskLabelOS -eq 'Windows' -and $DiskLabelRecovery -eq 'WinRE' -and
            $DiskSizeSystem -eq 1GB -and $DiskSizeOS -eq 32GB -and $DiskSizeRecovery -eq 3GB
        }
    }

    It 'does not bind omitted disk parameters in the initializer' {
        Deploy-OSDCloud -CLI
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter {
            -not $PesterBoundParameters.ContainsKey('DiskSizeOS') -and
            -not $PesterBoundParameters.ContainsKey('DiskLabelOS') -and
            -not $PesterBoundParameters.ContainsKey('DiskSizeSystem') -and
            -not $PesterBoundParameters.ContainsKey('DiskSizeRecovery')
        }
    }

    It 'forces unregistered state before device and deployment initialization: CLI=<CLI>' -TestCases @(
        @{ CLI = $true }
        @{ CLI = $false }
    ) {
        param ($CLI)
        $savedLicense = [pscustomobject]@{ Email = 'test@example.invalid'; LicenseGuid = 'test-license' }
        Mock Initialize-OSDCoreLicense {
            $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $true; License = $savedLicense }
        } -ModuleName DiskParameterDeploymentTests
        Mock Initialize-OSDCoreDevice {
            $global:OSDCoreLicense.IsRegistered | Should -BeFalse
            $global:OSDCoreLicense.IsRegistered = $true
        } -ModuleName DiskParameterDeploymentTests
        Mock Initialize-DeployOSDCloud {
            $global:OSDCoreLicense.IsRegistered | Should -BeFalse
        } -ModuleName DiskParameterDeploymentTests
        Deploy-OSDCloud -CLI:$CLI -Incognito
        $global:OSDCoreLicense.IsRegistered | Should -BeFalse
        $global:OSDCoreLicense.License | Should -Be $savedLicense
        Should -Invoke Initialize-OSDCoreLicense -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly
    }

    It 'reloads normal registration on the next launch without Incognito' {
        Mock Initialize-OSDCoreLicense {
            $global:OSDCoreLicense = [pscustomobject]@{ IsRegistered = $true }
        } -ModuleName DiskParameterDeploymentTests
        Deploy-OSDCloud -CLI -Incognito
        $global:OSDCoreLicense.IsRegistered | Should -BeFalse
        $global:OSDCoreLicense.IsIncognito | Should -BeTrue
        Deploy-OSDCloud -CLI
        $global:OSDCoreLicense.IsRegistered | Should -BeTrue
        $global:OSDCoreLicense.IsIncognito | Should -BeFalse
        Should -Invoke Initialize-OSDCoreLicense -ModuleName DiskParameterDeploymentTests -Times 2 -Exactly
    }

    It 'does not override normal registration when Incognito is explicitly false' {
        Deploy-OSDCloud -CLI -Incognito:$false
        $global:OSDCoreLicense.IsRegistered | Should -BeTrue
        $global:OSDCoreLicense.IsIncognito | Should -BeFalse
    }

    It 'skips real OS catalog updates with no discovery during Incognito: CLI=<CLI>' -TestCases @(
        @{ CLI = $true }
        @{ CLI = $false }
    ) {
        param ($CLI)
        Mock Invoke-RestMethod { throw 'Unexpected catalog request' } -ModuleName DiskParameterDeploymentTests
        Mock Invoke-WebRequest { throw 'Unexpected catalog download' } -ModuleName DiskParameterDeploymentTests
        Mock Get-Volume { throw 'Unexpected USB discovery' } -ModuleName DiskParameterDeploymentTests
        Mock Get-ChildItem { throw 'Unexpected license/catalog discovery' } -ModuleName DiskParameterDeploymentTests
        Mock Initialize-DeployOSDCloud {
            $global:OSDCoreLicense.IsIncognito | Should -BeTrue
            Get-OSDCoreLicense | Should -BeNullOrEmpty
            Update-OSDCloudCoreCatalogOS | Should -BeNullOrEmpty
        } -ModuleName DiskParameterDeploymentTests
        Deploy-OSDCloud -CLI:$CLI -Incognito -WarningVariable warnings
        @($warnings).Count | Should -Be 0
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly
        Should -Invoke Invoke-RestMethod -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Invoke-WebRequest -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Get-Volume -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Get-ChildItem -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Write-Host -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly -ParameterFilter {
            $Object -like '*updating the OS catalog*' -or $Object -like '*OS catalog saved to*'
        }
    }

    It 'skips registered keyboard language conversion in Incognito mode' {
        $global:OSDCoreDevice.KeyboardLayout = '00000409'
        Deploy-OSDCloud -CLI -Incognito
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter { $OSLanguageCode -eq 'en-US' }
        Should -Invoke Convert-KeyboardLayoutToLanguageCode -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
    }

    It 'infers language with a valid unregistered license: CLI=<CLI>, override=<Override>' -TestCases @(
        @{ CLI = $true; Override = $false }
        @{ CLI = $false; Override = $false }
        @{ CLI = $true; Override = $true }
        @{ CLI = $false; Override = $true }
    ) {
        param ($CLI, $Override)
        $global:OSDCoreLicense.IsRegistered = $false
        $global:OSDCoreDevice.KeyboardLayout = '0000040C'
        $parameters = @{ CLI = $CLI }
        if ($Override) { $parameters.KeyboardLayout = '0000040C' }
        Deploy-OSDCloud @parameters -WarningVariable warnings
        @($warnings).Count | Should -Be 0
        Should -Invoke Convert-KeyboardLayoutToLanguageCode -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter {
            $KeyboardLayout -eq '0000040C' -and $FallbackLanguageCode -eq 'en-US'
        }
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter { $OSLanguageCode -eq 'fr-FR' }
        Should -Invoke Write-Host -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter {
            $Object -like '*has set the OSLanguageCode to fr-FR*'
        }
    }

    It 'quietly skips registered language inference for <Case>: CLI=<CLI>' -TestCases @(
        @{ CLI = $true; Case = 'missing' }
        @{ CLI = $false; Case = 'missing' }
        @{ CLI = $true; Case = 'invalid' }
        @{ CLI = $false; Case = 'invalid' }
        @{ CLI = $true; Case = 'registration only' }
        @{ CLI = $false; Case = 'registration only' }
        @{ CLI = $true; Case = 'failed lookup' }
        @{ CLI = $false; Case = 'failed lookup' }
    ) {
        param ($CLI, $Case)
        $global:OSDCoreDevice.KeyboardLayout = '0000040C'
        Mock Get-OSDCoreLicense {
            switch ($Case) {
                'missing' { $null }
                'invalid' { [pscustomobject]@{ IsValid = $false } }
                'registration only' { [pscustomobject]@{ IsRegistered = $true } }
                'failed lookup' { throw 'synthetic-private-license-data' }
            }
        } -ModuleName DiskParameterDeploymentTests
        $output = @(Deploy-OSDCloud -CLI:$CLI -KeyboardLayout '0000040C' -Verbose -WarningVariable warnings 4>&1 3>&1 2>&1)
        @($warnings).Count | Should -Be 0
        @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
        "$output" | Should -Not -Match 'synthetic-private-license-data'
        Should -Invoke Convert-KeyboardLayoutToLanguageCode -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter { $OSLanguageCode -eq 'en-US' }
        Should -Invoke Write-Host -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly -ParameterFilter {
            $Object -like '*has set the OSLanguageCode*'
        }
    }

    It 'preserves explicit language selection without checking a license: CLI=<CLI>' -TestCases @(
        @{ CLI = $true }
        @{ CLI = $false }
    ) {
        param ($CLI)
        $global:OSDCoreDevice.KeyboardLayout = '0000040C'
        Mock Get-OSDCoreLicense { throw 'Unexpected license lookup' } -ModuleName DiskParameterDeploymentTests
        Deploy-OSDCloud -CLI:$CLI -OSLanguageCode 'de-de' -KeyboardLayout '0000040C'
        Should -Invoke Get-OSDCoreLicense -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Convert-KeyboardLayoutToLanguageCode -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter { $OSLanguageCode -eq 'de-de' }
    }

    It 'keeps en-US when the keyboard layout is unavailable with a valid license' {
        Deploy-OSDCloud -CLI
        Should -Invoke Convert-KeyboardLayoutToLanguageCode -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 1 -Exactly -ParameterFilter { $OSLanguageCode -eq 'en-US' }
    }

    It 'surfaces licensed conversion failures instead of silently using a fallback' {
        $global:OSDCoreDevice.KeyboardLayout = '0000040C'
        Mock Convert-KeyboardLayoutToLanguageCode { throw 'Synthetic conversion failure' } -ModuleName DiskParameterDeploymentTests
        { Deploy-OSDCloud -CLI } | Should -Throw '*Synthetic conversion failure*'
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
    }

    It 'documents every new parameter in the bundled external help' {
        [xml]$helpXml = Get-Content -LiteralPath "$moduleRoot\en-US\OSDCloud-help.xml" -Raw
        $namespaces = [System.Xml.XmlNamespaceManager]::new($helpXml.NameTable)
        $namespaces.AddNamespace('command', 'http://schemas.microsoft.com/maml/dev/command/2004/10')
        $namespaces.AddNamespace('maml', 'http://schemas.microsoft.com/maml/2004/10')
        $deployHelp = $helpXml.SelectSingleNode("//command:command[command:details/command:name='Deploy-OSDCloud']", $namespaces)
        $description = $deployHelp.SelectSingleNode('maml:description', $namespaces).InnerText
        $description | Should -Match 'valid Recast license.*Test-OSDCoreLicense.*IsValid = true'
        $description | Should -Not -Match 'require Initialize-OSDCoreLicense to report IsRegistered'
        foreach ($name in 'Incognito', 'DiskLabelOS', 'DiskLabelRecovery', 'DiskSizeSystem', 'DiskSizeOS', 'DiskSizeRecovery') {
            $deployHelp.SelectNodes("command:parameters/command:parameter[maml:name='$name']", $namespaces).Count | Should -Be 1
            $deployHelp.SelectNodes("command:syntax/command:syntaxItem/command:parameter[maml:name='$name']", $namespaces).Count | Should -Be 1
        }
    }

    It 'rejects invalid public input before initialization: <Name>' -TestCases @(
        @{ Name = 'DiskLabelOS'; Value = ' ' }
        @{ Name = 'DiskLabelRecovery'; Value = "bad`nlabel" }
        @{ Name = 'DiskSizeSystem'; Value = 99MB }
        @{ Name = 'DiskSizeOS'; Value = 0 }
        @{ Name = 'DiskSizeOS'; Value = 32GB - 1 }
        @{ Name = 'DiskSizeRecovery'; Value = 349MB }
    ) {
        param ($Name, $Value)
        $parameters = @{ $Name = $Value }
        { Deploy-OSDCloud -CLI @parameters } | Should -Throw
        Should -Invoke Initialize-DeployOSDCloud -ModuleName DiskParameterDeploymentTests -Times 0 -Exactly
    }
}
