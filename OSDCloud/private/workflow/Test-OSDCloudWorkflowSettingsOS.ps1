function Test-OSDCloudWorkflowSettingsOS {
    <#
    .SYNOPSIS
        Validates workflow operating system settings.

    .DESCRIPTION
        Validates the parsed os-amd64.json or os-arm64.json settings object for required
        sections, non-empty allowed values, unique values, valid defaults, and edition to
        activation requirements.

    .PARAMETER Settings
        The parsed workflow OS settings object from ConvertFrom-Json.

    .PARAMETER WorkflowName
        The workflow name being validated.

    .PARAMETER Path
        The settings file path being validated.

    .EXAMPLE
        Test-OSDCloudWorkflowSettingsOS -Settings $osSettings -WorkflowName 'default' -Path $osJsonPath

        Validates parsed OS settings and returns True when valid.

    .OUTPUTS
        System.Boolean

    .NOTES
        Private helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Object]
        $Settings,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $WorkflowName = 'default',

        [Parameter(Mandatory = $false)]
        [System.String]
        $Path
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] WorkflowName: $WorkflowName"

    $settingsSource = if ([string]::IsNullOrWhiteSpace($Path)) { "workflow '$WorkflowName' OS settings" } else { $Path }
    $requiredSettingNames = @('OperatingSystem', 'OSActivation', 'OSEdition', 'OSLanguageCode')

    foreach ($settingName in $requiredSettingNames) {
        if ($Settings.PSObject.Properties.Match($settingName).Count -eq 0) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource is missing required '$settingName' settings."
        }

        $setting = $Settings.$settingName
        if ($null -eq $setting) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource '$settingName' settings are null."
        }
        if ($setting.PSObject.Properties.Match('default').Count -eq 0) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource '$settingName' is missing a default value."
        }
        if ($setting.PSObject.Properties.Match('values').Count -eq 0) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource '$settingName' is missing allowed values."
        }
        if ([string]::IsNullOrWhiteSpace([string]$setting.default)) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource '$settingName' default value is empty."
        }
        if (@($setting.values).Count -eq 0) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource '$settingName' allowed values are empty."
        }
    }

    foreach ($settingName in @('OperatingSystem', 'OSActivation', 'OSLanguageCode')) {
        $setting = $Settings.$settingName
        $allowedValues = @($setting.values | ForEach-Object { [string]$_ })
        $emptyValues = @($allowedValues | Where-Object { [string]::IsNullOrWhiteSpace($_) })
        if ($emptyValues.Count -gt 0) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource '$settingName' contains empty allowed values."
        }

        $duplicateValues = @($allowedValues | Group-Object | Where-Object { $_.Count -gt 1 })
        if ($duplicateValues.Count -gt 0) {
            $duplicateNames = [string[]]($duplicateValues | ForEach-Object { $_.Name })
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource '$settingName' contains duplicate values: $($duplicateNames -join ', ')"
        }

        if ([string]$setting.default -notin $allowedValues) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource '$settingName' default '$($setting.default)' is not in allowed values: $($allowedValues -join ', ')"
        }
    }

    $editionValues = @($Settings.OSEdition.values)
    $editionNames = @()
    foreach ($editionValue in $editionValues) {
        if ($null -eq $editionValue) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource 'OSEdition' contains a null edition entry."
        }
        if ($editionValue.PSObject.Properties.Match('Edition').Count -eq 0) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource 'OSEdition' contains an entry without an Edition value."
        }
        if ($editionValue.PSObject.Properties.Match('EditionId').Count -eq 0) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource 'OSEdition' contains an entry without an EditionId value."
        }
        if ([string]::IsNullOrWhiteSpace([string]$editionValue.Edition)) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource 'OSEdition' contains an empty Edition value."
        }
        if ([string]::IsNullOrWhiteSpace([string]$editionValue.EditionId)) {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource 'OSEdition' contains an empty EditionId value for Edition '$($editionValue.Edition)'."
        }
        $editionNames += [string]$editionValue.Edition
    }

    $duplicateEditions = @($editionNames | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($duplicateEditions.Count -gt 0) {
        $duplicateEditionNames = [string[]]($duplicateEditions | ForEach-Object { $_.Name })
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource 'OSEdition' contains duplicate Edition values: $($duplicateEditionNames -join ', ')"
    }

    if ([string]$Settings.OSEdition.default -notin $editionNames) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource 'OSEdition' default '$($Settings.OSEdition.default)' is not in allowed values: $($editionNames -join ', ')"
    }

    $activationValues = @($Settings.OSActivation.values | ForEach-Object { [string]$_ })
    if (@($editionNames | Where-Object { $_ -like 'Enterprise*' }).Count -gt 0 -and 'Volume' -notin $activationValues) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource contains Enterprise* editions, but OSActivation values do not include Volume."
    }
    if (@($editionNames | Where-Object { $_ -like 'Home*' }).Count -gt 0 -and 'Retail' -notin $activationValues) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] $settingsSource contains Home* editions, but OSActivation values do not include Retail."
    }

    return $true
}
