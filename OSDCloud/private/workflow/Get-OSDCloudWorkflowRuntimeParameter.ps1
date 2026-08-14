function Get-OSDCloudWorkflowRuntimeParameter {
    <#
    .SYNOPSIS
        Builds the dynamic runtime parameters for an OSDCloud workflow.

    .DESCRIPTION
        Reads the operating system settings (os-amd64.json / os-arm64.json) and the task
        definitions for the specified workflow, then returns a
        RuntimeDefinedParameterDictionary containing the OperatingSystem, OSEdition,
        OSActivation, OSLanguageCode, and Task parameters. Each parameter is constrained to the
        values available for the workflow and the current processor architecture.

        This logic is shared by Deploy-OSDCloud and Deploy-OSDCloudCLI so the dynamic parameter
        surface is defined in exactly one place.

    .PARAMETER WorkflowName
        The workflow whose os-*.json and tasks define the available values, for example
        'default' or 'cli'.

    .PARAMETER ModuleBase
        The OSDCloud module base path. Typically $($MyInvocation.MyCommand.Module.ModuleBase) from
        the calling cmdlet.

    .PARAMETER ProcessorArchitecture
        Optional mock/testing processor architecture used to select architecture-specific workflow
        operating system settings before the deployment initializes OSDCoreDevice.

    .EXAMPLE
        Get-OSDCloudWorkflowRuntimeParameter -WorkflowName 'cli' -ModuleBase $moduleBase

        Returns the dynamic parameters for the 'cli' workflow.

    .OUTPUTS
        System.Management.Automation.RuntimeDefinedParameterDictionary

    .NOTES
        Private helper. Not exported. Intended for use inside a cmdlet dynamicparam block.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param (
        [Parameter(Mandatory = $true)]
        [System.String]
        $WorkflowName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ModuleBase,

        [Parameter(Mandatory = $false)]
        [ValidateSet('amd64', 'arm64')]
        [System.String]
        $ProcessorArchitecture
    )

    $workflowRootPath = Join-Path -Path $ModuleBase -ChildPath 'workflow'
    $workflowPath = Join-Path -Path $workflowRootPath -ChildPath $WorkflowName
    $tasksPath = Join-Path -Path $workflowPath -ChildPath 'tasks'

    $workflowProcessorArchitecture = if (-not [string]::IsNullOrWhiteSpace($ProcessorArchitecture)) {
        $ProcessorArchitecture
    }
    elseif ($global:OSDCoreDevice -and -not [string]::IsNullOrWhiteSpace($global:OSDCoreDevice.ProcessorArchitecture)) {
        $global:OSDCoreDevice.ProcessorArchitecture
    }
    else {
        $env:PROCESSOR_ARCHITECTURE
    }

    switch -Regex ($workflowProcessorArchitecture) {
        '^(amd64|x64)$' { $workflowProcessorArchitecture = 'amd64'; break }
        '^arm64$' { $workflowProcessorArchitecture = 'arm64'; break }
        default { $workflowProcessorArchitecture = 'amd64' }
    }

    $osSettingsFileObject = Get-OSDCloudWorkflowSettingsOSFile -WorkflowName $WorkflowName -Architecture $workflowProcessorArchitecture -Path $workflowRootPath
    $osJsonPath = $osSettingsFileObject.FullName

    $operatingSystemValues = @()
    $osActivationValues = @()
    $osLanguageCodeValues = @()
    $osEditionValues = @()
    $taskValues = @()

    $rawJsonContent = Get-Content -Path $osJsonPath -Raw
    $jsonContent = $rawJsonContent -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/'
    $osSettings = ConvertFrom-Json -InputObject $jsonContent
    $null = Test-OSDCloudWorkflowSettingsOS -Settings $osSettings -WorkflowName $WorkflowName -Path $osJsonPath
    $operatingSystemValues = [string[]]$osSettings.OperatingSystem.values
    $osActivationValues = [string[]]$osSettings.OSActivation.values
    $osLanguageCodeValues = [string[]]$osSettings.OSLanguageCode.values
    $osEditionValues = [string[]]($osSettings.OSEdition.values | ForEach-Object { $_.Edition })

    if (Test-Path -Path $tasksPath) {
        $taskJsonFiles = Get-ChildItem -Path $tasksPath -Filter '*.json' -File
        if ($osSettingsFileObject.Architecture -eq 'arm64') {
            $taskValues = [string[]]($taskJsonFiles |
                ForEach-Object { Get-Content -Path $_.FullName -Raw | ConvertFrom-Json } |
                Where-Object { $_.arm64 -eq $true } |
                Select-Object -ExpandProperty name)
        }
        else {
            $taskValues = [string[]]($taskJsonFiles |
                ForEach-Object { Get-Content -Path $_.FullName -Raw | ConvertFrom-Json } |
                Where-Object { $_.amd64 -eq $true } |
                Select-Object -ExpandProperty name)
        }
    }

    function New-OSDCloudRuntimeParameter {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Name,
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [string[]]$ValidateSetValues
        )

        $attributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
        $parameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
        $parameterAttribute.Mandatory = $false
        $attributeCollection.Add($parameterAttribute)
        $attributeCollection.Add([System.Management.Automation.ValidateNotNullOrEmptyAttribute]::new())

        if ($ValidateSetValues.Count -gt 0) {
            $validateSetAttribute = [System.Management.Automation.ValidateSetAttribute]::new($ValidateSetValues)
            $validateSetAttribute.IgnoreCase = $true
            $attributeCollection.Add($validateSetAttribute)
        }

        return [System.Management.Automation.RuntimeDefinedParameter]::new($Name, [System.String], $attributeCollection)
    }

    $dynamicParameters = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $dynamicParameters.Add('OperatingSystem', (New-OSDCloudRuntimeParameter -Name 'OperatingSystem' -ValidateSetValues $operatingSystemValues))
    $dynamicParameters.Add('OSEdition', (New-OSDCloudRuntimeParameter -Name 'OSEdition' -ValidateSetValues $osEditionValues))
    $dynamicParameters.Add('OSActivation', (New-OSDCloudRuntimeParameter -Name 'OSActivation' -ValidateSetValues $osActivationValues))
    $dynamicParameters.Add('OSLanguageCode', (New-OSDCloudRuntimeParameter -Name 'OSLanguageCode' -ValidateSetValues $osLanguageCodeValues))
    $dynamicParameters.Add('Task', (New-OSDCloudRuntimeParameter -Name 'Task' -ValidateSetValues $taskValues))

    return $dynamicParameters
}
