function Invoke-OSDCloudWorkflowUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Name')]
        [System.String]
        $WorkflowName = 'default',

        [System.String]
        $WorkflowsRootPath = "$($MyInvocation.MyCommand.Module.ModuleBase)\workflow"
    )
    #=================================================
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    $ModuleName = $($MyInvocation.MyCommand.Module.Name)
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] ModuleName: $ModuleName"
    $ModuleBase = $($MyInvocation.MyCommand.Module.ModuleBase)
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] ModuleBase: $ModuleBase"
    $ModuleVersion = $($MyInvocation.MyCommand.Module.Version)
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] ModuleVersion: $ModuleVersion"
    #=================================================
    # Workflows Root Path must exist, there is no fallback
    if (-not (Test-Path $WorkflowsRootPath)) {
        Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to find OSDCloud Workflows Root Path"
        Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $WorkflowsRootPath"
        throw
    }
    #=================================================
    $defaultWorkflowUiFolder = 'ui'
    $workflowUiFolder = 'ui'

    if (-not (Test-Path -Path (Join-Path $WorkflowsRootPath (Join-Path 'default' 'ui')) -PathType Container)) {
        $defaultWorkflowUiFolder = 'ux'
    }
    if (-not (Test-Path -Path (Join-Path $WorkflowsRootPath (Join-Path $WorkflowName 'ui')) -PathType Container)) {
        $workflowUiFolder = 'ux'
    }

    $workflowDefaultUiPath = Join-Path $WorkflowsRootPath (Join-Path 'default' $defaultWorkflowUiFolder)
    $workflowUiPath = Join-Path $WorkflowsRootPath (Join-Path $WorkflowName $workflowUiFolder)

    $currentUiPath = $null
    if (Test-Path "$workflowDefaultUiPath\MainWindow.ps1") {
        $currentUiPath = Join-Path -Path $workflowDefaultUiPath -ChildPath "MainWindow.ps1"
    }
    if (Test-Path "$workflowUiPath\MainWindow.ps1") {
        $currentUiPath = Join-Path -Path $workflowUiPath -ChildPath "MainWindow.ps1"
    }

    if (-not $currentUiPath) {
        Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to locate a valid Workflow UI MainWindow.ps1"
        Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Checked $workflowUiPath and $workflowDefaultUiPath (preferred ui, fallback ux when ui folder is missing)"
        throw
    }

    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($currentUiPath.Replace((Split-Path $ModuleBase -Parent) + '\', ''))"
    . $currentUiPath
    #=================================================
}
