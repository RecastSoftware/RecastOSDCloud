function Get-OSDCloudWorkflowSettingsOSFile {
    <#
    .SYNOPSIS
        Resolves the workflow operating system settings file for an architecture.

    .DESCRIPTION
        Resolves workflow/<WorkflowName>/os-<architecture>.json and preserves the
        existing fallback behavior to workflow/default/os-<architecture>.json when a
        workflow-specific file is not present.

    .PARAMETER WorkflowName
        The workflow name whose OS settings file should be resolved.

    .PARAMETER Architecture
        The processor architecture used to choose os-amd64.json or os-arm64.json.

    .PARAMETER Path
        The root workflow path that contains workflow folders.

    .EXAMPLE
        Get-OSDCloudWorkflowSettingsOSFile -WorkflowName 'default' -Architecture 'amd64' -Path $workflowRootPath

        Resolves the default workflow amd64 OS settings file.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $WorkflowName = 'default',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Architecture = $env:PROCESSOR_ARCHITECTURE,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] WorkflowName: $WorkflowName"
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Architecture: $Architecture"

    if (-not (Test-Path -Path $Path -PathType Container)) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] The specified workflow Path does not exist: $Path"
    }

    switch -Regex ($Architecture) {
        '^(AMD64|amd64|x64|X64)$' {
            $normalizedArchitecture = 'amd64'
            $fileName = 'os-amd64.json'
            break
        }
        '^(ARM64|arm64)$' {
            $normalizedArchitecture = 'arm64'
            $fileName = 'os-arm64.json'
            break
        }
        default {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Invalid Architecture '$Architecture'. Expected amd64 or arm64."
        }
    }

    $workflowNamedPath = Join-Path -Path $Path -ChildPath $WorkflowName
    $workflowDefaultPath = Join-Path -Path $Path -ChildPath 'default'
    $settingsPath = Join-Path -Path $workflowNamedPath -ChildPath $fileName
    $isFallback = $false

    if ($workflowNamedPath -ne $workflowDefaultPath -and -not (Test-Path -Path $settingsPath -PathType Leaf)) {
        $settingsPath = Join-Path -Path $workflowDefaultPath -ChildPath $fileName
        $isFallback = $true
    }

    if (-not (Test-Path -Path $settingsPath -PathType Leaf)) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to find workflow OS settings file: $settingsPath"
    }

    [PSCustomObject]@{
        Architecture = $normalizedArchitecture
        FileName     = $fileName
        FullName     = $settingsPath
        IsFallback   = $isFallback
        WorkflowName = $WorkflowName
    }
}
