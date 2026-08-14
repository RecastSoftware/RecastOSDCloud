function Deploy-OSDCloud {
    <#
    .SYNOPSIS
        Starts an OSDCloud operating system deployment.

    .DESCRIPTION
        Initializes and runs an OSDCloud deployment workflow. By default, launches the
        graphical UI (UX) so the operator can configure deployment settings before
        starting. Use -CLI to skip the UI and immediately begin the workflow in the
        current console session.

        In addition to the static parameters documented here, workflow-specific runtime
        parameters are added dynamically from the selected workflow definition.

        OSDCloud collects anonymous analytic data about the deployment environment and
        system configuration to help improve the product. No personally identifiable
        information (PII) is collected. By using OSDCloud you consent to this collection
        as described in the privacy policy:
        https://github.com/OSDeploy/OSDCloud/blob/main/PRIVACY.md

    .PARAMETER WorkflowName
        The name of the OSDCloud workflow to run. Defaults to 'default'.
        Available workflows are located in the module's workflow folder.

    .PARAMETER CLI
        Skips the graphical UX and runs the deployment workflow immediately in the
        current console session.

    .PARAMETER Force
        Suppresses supported confirmation prompts for destructive workflow steps.

    .PARAMETER ProfileName
        The full OS profile name used to resolve the Env file path. Defaults to 'default'.
        Ignored in WinPE.

    .PARAMETER DiskNumber
        Specifies the local disk number to use for deployment. The disk number must
        exist in the local disk inventory detected by OSDCloud.

    .PARAMETER KeyboardLayout
        Overrides the detected keyboard layout value used to infer OSLanguageCode
        when OSLanguageCode is not explicitly provided.

    .PARAMETER ProcessorArchitecture
        Mock/testing processor architecture override used to validate ARM64 workflow
        behavior on AMD64 devices. When supplied, overrides
        OSDCoreDevice.ProcessorArchitecture before deployment OSArchitecture is
        derived.

    .PARAMETER SkipWorkflowVerification
        Skips the custom-workflow warning prompt and continues immediately.

    .EXAMPLE
        Deploy-OSDCloud

        Launches the OSDCloud graphical UX for the default workflow. The deployment
        starts only after the operator clicks Start in the UI.

    .EXAMPLE
        Deploy-OSDCloud -CLI

        Runs the default OSDCloud workflow immediately without the graphical UX.

    .EXAMPLE
        Deploy-OSDCloud -WorkflowName 'latest'

        Launches the graphical UX for the 'latest' workflow.

    .EXAMPLE
        Deploy-OSDCloud -CLI -OperatingSystem 'Windows 11 24H2' -OSEdition 'Enterprise'

        Runs in CLI mode using dynamic runtime overrides from the selected workflow.

    .EXAMPLE
        Deploy-OSDCloud -ProfileName 'Lab'

        Launches the OSDCloud graphical UX using the 'Lab' profile Env path.

    .EXAMPLE
        Deploy-OSDCloud -CLI -DiskNumber 1

        Runs the default OSDCloud workflow immediately and deploys to local disk 1.

    .EXAMPLE
        Deploy-OSDCloud -WorkflowName 'latest' -SkipWorkflowVerification

        Runs with a non-default workflow without showing the verification prompt.

    .OUTPUTS
        System.Void

    .NOTES
        This command writes deployment status to the host and starts workflow tasks.
        In GUI mode, workflow execution starts only after the operator clicks Start.
        Runtime parameters are provided by Get-OSDCloudWorkflowRuntimeParameter.

    .LINK
        https://github.com/OSDeploy/OSDCloud/blob/main/PRIVACY.md
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('Name')]
        [System.String]
        $WorkflowName = 'default',

        [System.Management.Automation.SwitchParameter]
        $CLI,

        [Parameter(Mandatory = $false, HelpMessage = 'Optional local disk number to use as the deployment target.')]
        [System.UInt32]
        $DiskNumber,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]
        $Force,

        [Parameter(Mandatory = $false)]
        [ArgumentCompleter({
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                $profileNames = @('default')
                if ($env:SystemDrive -ne 'X:' -and $env:ProgramData) {
                    $profileRoot = Join-Path -Path $env:ProgramData -ChildPath 'OSDeployCore\OSDCloud\Profiles'
                    if (Test-Path -Path $profileRoot -PathType Container) {
                        $directoryNames = Get-ChildItem -Path $profileRoot -Directory -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty Name
                        if ($directoryNames) {
                            $profileNames += $directoryNames
                        }
                    }
                }

                foreach ($profileName in ($profileNames | Sort-Object -Unique)) {
                    if ($profileName -like "$wordToComplete*") {
                        [System.Management.Automation.CompletionResult]::new($profileName, $profileName, 'ParameterValue', $profileName)
                    }
                }
            })]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ProfileName = 'default',

        [Parameter(Mandatory = $false, HelpMessage = 'Skips the custom workflow verification prompt.')]
        [System.Management.Automation.SwitchParameter]
        $SkipWorkflowVerification,

        [Parameter(Mandatory = $false, HelpMessage = 'Optional manufacturer override used for driver pack selection.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSDManufacturer,

        [Parameter(Mandatory = $false, HelpMessage = 'Optional model override used for driver pack selection.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSDModel,

        [Parameter(Mandatory = $false, HelpMessage = 'Optional product/system ID override used for driver pack selection.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSDProduct,

        [Parameter(Mandatory = $false, HelpMessage = 'Mock/testing processor architecture override used for deployment selection.')]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('amd64', 'arm64')]
        [System.String]
        $ProcessorArchitecture,

        [Parameter(Mandatory = $false, HelpMessage = 'Optional keyboard layout value used to infer OSLanguageCode.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $KeyboardLayout
    )

    dynamicparam {
        $moduleBase = $($MyInvocation.MyCommand.Module.ModuleBase)
        $resolvedWorkflowName = if ($PSBoundParameters.ContainsKey('WorkflowName')) { [System.String]$PSBoundParameters['WorkflowName'] } else { 'default' }
        $workflowRuntimeParameter = @{
            ModuleBase    = $moduleBase
            WorkflowName  = $resolvedWorkflowName
        }
        if ($PSBoundParameters.ContainsKey('ProcessorArchitecture')) {
            $workflowRuntimeParameter['ProcessorArchitecture'] = [System.String]$PSBoundParameters['ProcessorArchitecture']
        }
        return Get-OSDCloudWorkflowRuntimeParameter @workflowRuntimeParameter
    }

    end {
        #=================================================
        $ModuleVersion = $($MyInvocation.MyCommand.Module.Version)
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] [$($MyInvocation.MyCommand.Name)] $ModuleVersion"

        Write-Host -ForegroundColor DarkCyan 'OSDCloud collects analytic data during the deployment process to help improve the product and user experience.'
        Write-Host -ForegroundColor DarkCyan 'No personally identifiable information (PII) is collected, and all data is anonymized to protect user privacy.'
        Write-Host -ForegroundColor DarkCyan 'Collected data includes information about the deployment environment and system configuration.'
        Write-Host -ForegroundColor DarkCyan 'By using OSDCloud, you consent to the collection of analytic data as outlined in the privacy policy:'
        Write-Host -ForegroundColor DarkGray 'https://github.com/OSDeploy/OSDCloud/blob/main/PRIVACY.md'
        Write-Host
        #=================================================
        # Workflow Verification and Warning
        if ($WorkflowName -ne 'default' -and -not $SkipWorkflowVerification.IsPresent) {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OSDCloud Workflow: $WorkflowName"
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] This version of OSDCloud is designed to run the default workflow."
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Using a custom workflow may result in unexpected behavior or errors."
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Please contact OSDCloud support to report issues with custom workflows and to seek assistance."
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] Press any key to continue."
            if ($Host -and $Host.UI -and $Host.UI.RawUI) {
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            else {
                Write-Warning "Unable to read key input in this host. Continuing without key confirmation."
            }
        }
        elseif ($WorkflowName -ne 'default' -and $SkipWorkflowVerification.IsPresent) {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OSDCloud Workflow: $WorkflowName"
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] SkipWorkflowVerification is set; continuing without verification prompt."
        }
        else {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDCloud Workflow: default"
        }
        #=================================================
        # Populate variables from environment and profile settings, and apply any parameter overrides.
        $envParameters = @{}
        if (Get-Command -Name 'ConvertTo-OSDCloudEnvParameter' -ErrorAction SilentlyContinue) {
            $envParameters = ConvertTo-OSDCloudEnvParameter -BoundParameters $PSBoundParameters
        }
        #=================================================
        # Set the osdcloud-logs Path
        $LogsPath = "$env:TEMP\osdcloud-logs"
        if (-not (Test-Path -Path $LogsPath)) {
            New-Item -Path $LogsPath -ItemType Directory -Force | Out-Null
        }
        #=================================================
        # Initialize OSDCoreDevice
        Initialize-OSDCoreDevice
        #=================================================
        # OSDCoreDevice Manufacturer, Model, Product overrides
        if ($OSDManufacturer -and -not [string]::IsNullOrWhiteSpace($OSDManufacturer)) {
            $global:OSDCoreDevice.OSDManufacturer = $OSDManufacturer
        }
        if ($OSDModel -and -not [string]::IsNullOrWhiteSpace($OSDModel)) {
            $global:OSDCoreDevice.OSDModel = $OSDModel
        }
        if ($OSDProduct -and -not [string]::IsNullOrWhiteSpace($OSDProduct)) {
            $global:OSDCoreDevice.OSDProduct = $OSDProduct
        }
        if ($ProcessorArchitecture -and -not [string]::IsNullOrWhiteSpace($ProcessorArchitecture)) {
            $global:OSDCoreDevice.ProcessorArchitecture = $ProcessorArchitecture
        }
        #=================================================
        # Export OSDCoreDevice to XML and JSON for use in other scripts or workflows
        $OSDCoreDeviceClixmlPath = Join-Path -Path $LogsPath -ChildPath 'OSDCoreDevice.xml'
        Remove-Item -Path $OSDCoreDeviceClixmlPath -Force -ErrorAction SilentlyContinue
        $global:OSDCoreDevice | Export-Clixml -Path $OSDCoreDeviceClixmlPath -Force

        $OSDCoreDeviceJsonPath = Join-Path -Path $LogsPath -ChildPath 'OSDCoreDevice.json'
        Remove-Item -Path $OSDCoreDeviceJsonPath -Force -ErrorAction SilentlyContinue
        $global:OSDCoreDevice | ConvertTo-Json -Depth 10 | Out-File $OSDCoreDeviceJsonPath -Force -Encoding utf8
        #=================================================
        # Automatically determine default OSLanguageCode from the detected keyboard layout if not explicitly provided.
        $resolvedOSLanguageCode = if ($PSBoundParameters.ContainsKey('OSLanguageCode')) {
            [System.String]$PSBoundParameters['OSLanguageCode']
        }
        else {
            $null
        }

        if (-not $PSBoundParameters.ContainsKey('OSLanguageCode')) {
            $languageKeyboardLayout = if ($PSBoundParameters.ContainsKey('KeyboardLayout')) { $KeyboardLayout } else { $global:OSDCoreDevice.KeyboardLayout }
            $osdRegistered = $false
            if ($global:OSDCoreDevice -is [System.Collections.IDictionary] -and $global:OSDCoreDevice.Contains('OSDRegistered')) {
                $osdRegistered = $global:OSDCoreDevice['OSDRegistered'] -eq $true
            }
            elseif ($global:OSDCoreDevice -and $global:OSDCoreDevice.PSObject.Properties.Match('OSDRegistered').Count -gt 0) {
                $osdRegistered = $global:OSDCoreDevice.OSDRegistered -eq $true
            }

            if ($osdRegistered -and $languageKeyboardLayout -and -not [string]::IsNullOrWhiteSpace($languageKeyboardLayout)) {
                $resolvedOSLanguageCode = Convert-KeyboardLayoutToLanguageCode -KeyboardLayout $languageKeyboardLayout -FallbackLanguageCode 'en-US'
                Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] Recast OSDCloud has set the OSLanguageCode to $resolvedOSLanguageCode based on the KeyboardLayout [$languageKeyboardLayout]."
            }
            else {
                $resolvedOSLanguageCode = 'en-US'
                if (-not $osdRegistered) {
                    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Skipping OSLanguageCode keyboard conversion because OSDCloud is not registered."
                }
            }
        }
        #=================================================
        # Start Initialization of OSDCloud Deployment
        $initializeOSDCloudDeployParameters = @{
            EnvParameters         = $envParameters
            OSLanguageCode        = $resolvedOSLanguageCode
            OSDManufacturer       = $global:OSDCoreDevice.OSDManufacturer
            OSDModel              = $global:OSDCoreDevice.OSDModel
            OSDProduct            = $global:OSDCoreDevice.OSDProduct
            ProcessorArchitecture = $global:OSDCoreDevice.ProcessorArchitecture
            ProfileName           = $ProfileName
            WorkflowName          = $WorkflowName
        }
        $initializeOSDCloudDeployCommand = Get-Command -Name 'Initialize-DeployOSDCloud' -ErrorAction SilentlyContinue
        if ($initializeOSDCloudDeployCommand) {
            $excludedCommonParameterNames = @(
                'Verbose',
                'Debug',
                'ErrorAction',
                'WarningAction',
                'InformationAction',
                'ErrorVariable',
                'WarningVariable',
                'InformationVariable',
                'OutVariable',
                'OutBuffer',
                'PipelineVariable',
                'WhatIf',
                'Confirm'
            )

            $initializeEligibleParameterNames = @(
                $initializeOSDCloudDeployCommand.Parameters.Keys |
                Where-Object {
                    (-not $initializeOSDCloudDeployParameters.ContainsKey($_)) -and
                    ($_ -notin $excludedCommonParameterNames)
                }
            )

            foreach ($parameterName in $initializeEligibleParameterNames) {
                if (-not $PSBoundParameters.ContainsKey($parameterName)) {
                    continue
                }
                $parameterValue = $PSBoundParameters[$parameterName]
                if ($null -eq $parameterValue) {
                    continue
                }
                if ($parameterValue -is [System.String] -and [string]::IsNullOrWhiteSpace($parameterValue)) {
                    continue
                }

                $initializeOSDCloudDeployParameters[$parameterName] = $parameterValue
            }
        }
        Initialize-DeployOSDCloud @initializeOSDCloudDeployParameters
        #=================================================
        # Start Deployment Workflow
        if ($CLI.IsPresent) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Invoke-OSDCloudWorkflowTask"
            $global:OSDCloudDeploy.TimeStart = Get-Date
            $global:OSDCloudDeploy | Out-Host
            Invoke-OSDCloudWorkflowTask
        }
        else {
            # Prevents the workflow from starting unless the Start button is clicked in the GUI
            $global:OSDCloudDeploy.TimeStart = $null

            Invoke-OSDCloudWorkflowUI -WorkflowName $WorkflowName

            if ($null -ne $global:OSDCloudDeploy.TimeStart) {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Invoke-OSDCloudWorkflowTask $WorkflowName"
                $global:OSDCloudDeploy | Out-Host
                try {
                    Invoke-OSDCloudWorkflowTask
                }
                catch {
                    Write-Warning "Failed to invoke OSDCloud Workflow '$WorkflowName': $_"
                }
            }
            else {
                Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OSDCloud Workflow '$WorkflowName' was not started."
            }
        }
    }
}
