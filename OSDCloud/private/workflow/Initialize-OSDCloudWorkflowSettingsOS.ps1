function Initialize-OSDCloudWorkflowSettingsOS {
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

        [System.Management.Automation.SwitchParameter]
        $AsJson,

        [System.String]
        $Architecture = $env:PROCESSOR_ARCHITECTURE,

        $Path = "$($MyInvocation.MyCommand.Module.ModuleBase)\workflow"
    )
    #=================================================
    $Error.Clear()
    $ModuleName = $($MyInvocation.MyCommand.Module.Name)
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] ModuleName: $ModuleName"
    $ModuleBase = $($MyInvocation.MyCommand.Module.ModuleBase)
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] ModuleBase: $ModuleBase"
    $ModuleVersion = $($MyInvocation.MyCommand.Module.Version)
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] ModuleVersion: $ModuleVersion"
    #=================================================
    # Workflow Path must exist, there is no fallback
    $OSDCloudWorkflowSettingsOSFileObject = Get-OSDCloudWorkflowSettingsOSFile -WorkflowName $WorkflowName -Architecture $Architecture -Path $Path
    $OSDCloudWorkflowSettingsOSFile = $OSDCloudWorkflowSettingsOSFileObject.FullName
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($OSDCloudWorkflowSettingsOSFile.Replace((Split-Path $ModuleBase -Parent) + '\', ''))"

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Importing settings from $OSDCloudWorkflowSettingsOSFile"
    $rawJsonContent = Get-Content -Path $OSDCloudWorkflowSettingsOSFile -Raw

    if ($AsJson) {
        return $rawJsonContent
    }

    # https://stackoverflow.com/questions/51066978/convert-to-json-with-comments-from-powershell
    $JsonContent = $rawJsonContent -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*' -replace '(?ms)/\*.*?\*/'

    $OSDCloudWorkflowSettingsOSObject = ConvertFrom-Json $JsonContent
    $null = Test-OSDCloudWorkflowSettingsOS -Settings $OSDCloudWorkflowSettingsOSObject -WorkflowName $WorkflowName -Path $OSDCloudWorkflowSettingsOSFile

    $hashtable = [ordered]@{}
    $OSDCloudWorkflowSettingsOSObject.psobject.properties | ForEach-Object { $hashtable[$_.Name] = $_.Value }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSDCloud OS Settings are stored in `$global:OSDCloudWorkflowSettingsOS"
    $global:OSDCloudWorkflowSettingsOS = $hashtable
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
