function Deploy-OSDCloudCLI {
    <#
    .SYNOPSIS
        Starts an OSDCloud operating system deployment in CLI mode.

    .DESCRIPTION
        Initializes and runs an OSDCloud deployment workflow directly in the current
        console session without launching the graphical UX. This function is a CLI-only
        entry point and immediately invokes workflow tasks after initialization.

        In addition to the static parameters documented here, workflow-specific runtime
        parameters are added dynamically from the CLI workflow definition.

    .PARAMETER OperatingSystem
        Overrides the CLI workflow OS default from workflow/cli/os-amd64.json
        or workflow/cli/os-arm64.json.
        The value must exist in the workflow's OperatingSystem values list
        (for example, 'Windows 11 24H2').

    .PARAMETER OSEdition
        Overrides the CLI workflow OS edition.

    .PARAMETER OSActivation
        Overrides the CLI workflow OS activation channel.

    .PARAMETER OSLanguageCode
        Overrides the CLI workflow OS language code.

    .PARAMETER Task
        Selects the CLI workflow task by name from workflow/cli/tasks/*.json.

    .PARAMETER SkipFirmwareUpdate
        Skips firmware update download and apply steps in the workflow.

    .PARAMETER Force
        Skips confirmation prompts for destructive workflow steps that support force behavior.

    .PARAMETER ProfileName
        The full OS profile name used to resolve the Env file path. Defaults to 'default'.
        Ignored in WinPE.

    .EXAMPLE
        Deploy-OSDCloudCLI

        Runs the default OSDCloud workflow immediately in the current console session.

    .EXAMPLE
        Deploy-OSDCloudCLI -OperatingSystem 'Windows 11 24H2'

        Runs the CLI workflow and overrides the OperatingSystem default.

    .EXAMPLE
        Deploy-OSDCloudCLI -OSEdition 'Enterprise' -OSLanguageCode 'en-gb'

        Runs the CLI workflow with Enterprise edition and en-gb language.

    .EXAMPLE
        Deploy-OSDCloudCLI -Task 'OSDCloud SkipFirmwareUpdate'

        Runs the selected CLI workflow task.

    .EXAMPLE
        Deploy-OSDCloudCLI -SkipFirmwareUpdate

        Runs the default workflow and skips firmware update steps.

    .EXAMPLE
        Deploy-OSDCloudCLI -Force

        Runs the default workflow and suppresses supported confirmation prompts.

    .EXAMPLE
        Deploy-OSDCloudCLI -ProfileName 'Lab'

        Runs the CLI workflow using the 'Lab' profile Env path.

    .OUTPUTS
        System.Void

    .NOTES
        This function does not display the graphical UX. Workflow execution begins
        immediately after initialization. Runtime parameters are provided by
        Get-OSDCloudWorkflowRuntimeParameter for the 'cli' workflow.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]
        $SkipFirmwareUpdate,

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
        $ProfileName = 'default'
    )

    dynamicparam {
        $moduleBase = $($MyInvocation.MyCommand.Module.ModuleBase)
        return Get-OSDCloudWorkflowRuntimeParameter -WorkflowName 'cli' -ModuleBase $moduleBase
    }

    begin {
        $OperatingSystem = if ($PSBoundParameters.ContainsKey('OperatingSystem')) { [System.String]$PSBoundParameters['OperatingSystem'] } else { $null }
        $OSEdition = if ($PSBoundParameters.ContainsKey('OSEdition')) { [System.String]$PSBoundParameters['OSEdition'] } else { $null }
        $OSActivation = if ($PSBoundParameters.ContainsKey('OSActivation')) { [System.String]$PSBoundParameters['OSActivation'] } else { $null }
        $OSLanguageCode = if ($PSBoundParameters.ContainsKey('OSLanguageCode')) { [System.String]$PSBoundParameters['OSLanguageCode'] } else { $null }
        $Task = if ($PSBoundParameters.ContainsKey('Task')) { [System.String]$PSBoundParameters['Task'] } else { $null }

        Write-Host -ForegroundColor Yellow "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Preview Release: This function is for feedback only. Expect frequent changes before the official release."

        #=================================================
        # Initialize OSDCloudWorkflow
        # Override values (Parameters > ENV) are assembled into $global:OSDCloudEnv
        # and applied to $global:OSDCloudDeploy - including operating system resolution - inside
        # Initialize-DeployOSDCloud.
        $WorkflowName = 'cli'
        $envParameters = @{}
        if (Get-Command -Name 'ConvertTo-OSDCloudEnvParameter' -ErrorAction Ignore) {
            $envParameters = ConvertTo-OSDCloudEnvParameter -BoundParameters $PSBoundParameters
        }
        Initialize-DeployOSDCloud -WorkflowName $WorkflowName -EnvParameters $envParameters -Force:$Force.IsPresent -ProfileName $ProfileName

        $selectedTask = if ($null -ne $Task) { $Task } else { [System.String]$global:OSDCloudDeploy.WorkflowTaskName }
        $selectedOperatingSystem = if ($null -ne $OperatingSystem) { $OperatingSystem } else { [System.String]$global:OSDCloudDeploy.OperatingSystem }
        $selectedOSEdition = if ($null -ne $OSEdition) { $OSEdition } else { [System.String]$global:OSDCloudDeploy.OSEdition }
        $selectedOSActivation = if ($null -ne $OSActivation) { $OSActivation } else { [System.String]$global:OSDCloudDeploy.OSActivation }
        $selectedOSLanguageCode = if ($null -ne $OSLanguageCode) { $OSLanguageCode } else { [System.String]$global:OSDCloudDeploy.OSLanguageCode }

        $resolvedOSActivation = Resolve-OSDCloudWorkflowOSActivation -OSEdition $selectedOSEdition -OSActivation $selectedOSActivation
        if ($resolvedOSActivation -ne $selectedOSActivation) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSEdition '$selectedOSEdition' requires OSActivation '$resolvedOSActivation'."
            $selectedOSActivation = $resolvedOSActivation
        }

        $operatingSystemValues = [array]$global:OSDCloudDeploy.OperatingSystemValues
        if ($selectedOperatingSystem -notin $operatingSystemValues) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OperatingSystem '$selectedOperatingSystem' is not valid for workflow '$WorkflowName'. Valid values: $($operatingSystemValues -join ', ')"
        }

        $osActivationValues = [array]$global:OSDCloudDeploy.OSActivationValues
        if ($selectedOSActivation -notin $osActivationValues) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSActivation '$selectedOSActivation' is not valid for workflow '$WorkflowName'. Valid values: $($osActivationValues -join ', ')"
        }

        $osLanguageCodeValues = [array]$global:OSDCloudDeploy.OSLanguageCodeValues
        if ($selectedOSLanguageCode -notin $osLanguageCodeValues) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSLanguageCode '$selectedOSLanguageCode' is not valid for workflow '$WorkflowName'. Valid values: $($osLanguageCodeValues -join ', ')"
        }

        $osEditionValues = [array]$global:OSDCloudDeploy.OSEditionValues
        $selectedOSEditionObject = $osEditionValues | Where-Object { $_.Edition -eq $selectedOSEdition } | Select-Object -First 1
        if (-not $selectedOSEditionObject) {
            $validOSEditions = $osEditionValues | ForEach-Object { $_.Edition }
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSEdition '$selectedOSEdition' is not valid for workflow '$WorkflowName'. Valid values: $($validOSEditions -join ', ')"
        }

        $workflowTaskValues = [array]($global:OSDCloudDeploy.WorkflowTasks | Select-Object -ExpandProperty Name)
        if ($selectedTask -notin $workflowTaskValues) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Task '$selectedTask' is not valid for workflow '$WorkflowName'. Valid values: $($workflowTaskValues -join ', ')"
        }

        $workflowTaskObject = $global:OSDCloudDeploy.WorkflowTasks | Where-Object { $_.Name -eq $selectedTask } | Select-Object -First 1

        $operatingSystemCloudObject = $global:OSDCloudDeploy.CoreOperatingSystems |
        Where-Object { $_.OperatingSystem -eq $selectedOperatingSystem } |
        Where-Object { $_.OSActivation -eq $selectedOSActivation } |
        Where-Object { $_.OSLanguageCode -eq $selectedOSLanguageCode } |
        Select-Object -First 1

        if (-not $operatingSystemCloudObject) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No Operating System object found for OperatingSystem '$selectedOperatingSystem' with OSActivation '$selectedOSActivation' and OSLanguageCode '$selectedOSLanguageCode'."
        }

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem: $selectedOperatingSystem"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSEdition: $selectedOSEdition"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSActivation: $selectedOSActivation"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSLanguageCode: $selectedOSLanguageCode"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Task: $selectedTask"

        $global:OSDCloudDeploy.OperatingSystem = $operatingSystemCloudObject.OperatingSystem
        $global:OSDCloudDeploy.OperatingSystemCloudObject = $operatingSystemCloudObject
        $global:OSDCloudDeploy.OperatingSystemCacheObject = Get-OSDCoreOperatingSystemCacheObject -OperatingSystemCloudObject $operatingSystemCloudObject
        $global:OSDCloudDeploy.OSBuild = $operatingSystemCloudObject.OSBuild
        $global:OSDCloudDeploy.OSBuildVersion = $operatingSystemCloudObject.OSBuildVersion
        $global:OSDCloudDeploy.OSVersion = $operatingSystemCloudObject.OSVersion
        $global:OSDCloudDeploy.OSEdition = $selectedOSEdition
        $global:OSDCloudDeploy.OSEditionId = $selectedOSEditionObject.EditionId
        $global:OSDCloudDeploy.OSActivation = $selectedOSActivation
        $global:OSDCloudDeploy.OSLanguageCode = $selectedOSLanguageCode
        $global:OSDCloudDeploy.WorkflowTaskName = $selectedTask
        $global:OSDCloudDeploy.WorkflowTaskObject = $workflowTaskObject

        $global:OSDCloudDeploy.SkipFirmwareUpdate = $SkipFirmwareUpdate.IsPresent
        $global:OSDCloudDeploy.Force = $Force.IsPresent

        #=================================================
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Invoke-OSDCloudWorkflowTask"
        $global:OSDCloudDeploy.TimeStart = Get-Date
        $global:OSDCloudDeploy | Out-Host
        Invoke-OSDCloudWorkflowTask
        #=================================================
    }
}
