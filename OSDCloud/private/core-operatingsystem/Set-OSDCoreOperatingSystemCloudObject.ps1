function Set-OSDCoreOperatingSystemCloudObject {
    <#
    .SYNOPSIS
    Selects and sets the global OSD core operating system object.

    .DESCRIPTION
    Filters the preloaded operating system catalog using activation, architecture,
    language, release ID, and version criteria, then sets
    $global:OSDCoreOperatingSystemCloudObject to the best match. If multiple matches
    are found, the highest build is selected.

    .PARAMETER OSActivation
    Operating system activation channel used for catalog selection.

    .PARAMETER OSArchitecture
    Operating system architecture used for catalog selection.

    .PARAMETER OSLanguageCode
    Operating system language code used for catalog selection.

    .PARAMETER OSReleaseID
    Operating system release identifier used for catalog selection.

    .PARAMETER OSVersion
    Operating system family/version label used for catalog selection.

    .PARAMETER RefreshCatalog
    Reloads $global:OSDCoreOperatingSystems from the current module's operating
    system catalog provider before filtering.

    .EXAMPLE
    Set-OSDCoreOperatingSystemCloudObject -OSArchitecture amd64 -OSReleaseID 25H2 -OSLanguageCode en-us
    Selects the latest Windows 11 Retail amd64 en-us 25H2 catalog entry and sets
    $global:OSDCoreOperatingSystemCloudObject.

    .EXAMPLE
    Set-OSDCoreOperatingSystemCloudObject -OSActivation Volume -OSArchitecture arm64 -OSLanguageCode en-us -OSReleaseID 24H2 -RefreshCatalog

    Refreshes the catalog cache and selects the latest matching Volume arm64 record.

    .INPUTS
    None
    You cannot pipe input to this function.

    .OUTPUTS
    PSCustomObject
    The selected operating system object assigned to
    $global:OSDCoreOperatingSystemCloudObject.

    .LINK
    https://github.com/OSDeploy/OSD/tree/master/docs

    .NOTES
    Author: David Segura - Recast Software
    2026-07-15 - Initial implementation to centralize OS catalog object selection.
    2026-08-05 - Expanded help content and examples
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Retail', 'Volume')]
        [string]$OSActivation = 'Retail',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('amd64', 'arm64', 'x64')]
        [string]$OSArchitecture = $env:PROCESSOR_ARCHITECTURE,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OSLanguageCode = 'en-us',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OSReleaseID = '25H2',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OSVersion = 'Windows 11',

        [Parameter(Mandatory = $false)]
        [switch]$RefreshCatalog
    )
    <# OSD PowerShell Module
        PS C:\Users\david> $OSDCoreOperatingSystemCloudObject

        Status       :
        ReleaseDate  :
        Name         : Windows 11 25H2 amd64 en-us Retail 26200.8873
        Version      : Windows 11
        ReleaseID    : 25H2
        Architecture : amd64
        Language     : en-us
        Activation   : Retail
        Build        : 26200.8873
        FileName     : 26200.8873.260710-2020.25h2_ge_release_svc_refresh_CLIENTCONSUMER_RET_x64FRE_en-us.esd
        ImageIndex   :
        ImageName    :
        Url          : http://dl.delivery.mp.microsoft.com/filestreamingservice/files/0f68e999-6e25-4ae7-92db-23cbb3a723a9/26200.8873.260710-2020.25h2_ge_release_svc_refresh_CLIENTCONSUMER_RET_x64FRE_en-us.esd
        SHA1         :
        SHA256       : e4c251a99eeade29aa5d462047bcb257d640cd2c98dfb7a2305f45876d1790c1
        UpdateID     :
        Win10        : False
        Win11        : True
    #>
    <# OSDCloud PowerShell Module
        PS C:\Users\david> $OSDCoreOperatingSystemCloudObject

        Id              : Windows 11 25H2 amd64 Retail en-us 26200.8873
        OperatingSystem : Windows 11 25H2
        OSName          : Windows 11
        OSVersion       : 25H2
        OSArchitecture  : amd64
        OSActivation    : Retail
        OSLanguageCode  : en-us
        OSLanguage      : English (United States)
        OSBuild         : 26200
        OSBuildVersion  : 26200.8873
        Size            : 6050059595
        Sha1            :
        Sha256          : e4c251a99eeade29aa5d462047bcb257d640cd2c98dfb7a2305f45876d1790c1
        FileName        : 26200.8873.260710-2020.25h2_ge_release_svc_refresh_CLIENTCONSUMER_RET_x64FRE_en-us.esd
        FilePath        : http://dl.delivery.mp.microsoft.com/filestreamingservice/files/0f68e999-6e25-4ae7-92db-23cbb3a723a9/26200.8873.260710-2020.25h2_ge_release_svc_refresh_CLIENTCONSUMER_RET_x64FRE_en-us.esd
    #>

    $Error.Clear()
    $ModuleName = $($MyInvocation.MyCommand.Module.Name)
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Starting operating system cloud object selection"
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Input filters: Activation='$OSActivation', Architecture='$OSArchitecture', Language='$OSLanguageCode', ReleaseID='$OSReleaseID', Version='$OSVersion', RefreshCatalog='$($RefreshCatalog.IsPresent)'"

    $normalizedArchitecture = switch ($OSArchitecture.ToLowerInvariant()) {
        'amd64' { 'amd64' }
        'x64' { 'amd64' }
        'arm64' { 'arm64' }
    }
    $normalizedLanguageCode = $OSLanguageCode.ToLowerInvariant()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Normalized filters: Architecture='$normalizedArchitecture', Language='$normalizedLanguageCode'"

    $catalogProvider = $null
    $catalogShape = $null
    if ($ModuleName -eq 'OSD') {
        $catalogProvider = 'Get-OSDCoreOperatingSystems'
        $catalogShape = 'OSD'
    }
    elseif ($ModuleName -eq 'OSDCloud') {
        $catalogProvider = 'Get-OSDCloudCoreOperatingSystems'
        $catalogShape = 'OSDCloud'
    }
    elseif (Get-Command -Name 'Get-OSDCloudCoreOperatingSystems' -ErrorAction Ignore) {
        $catalogProvider = 'Get-OSDCloudCoreOperatingSystems'
        $catalogShape = 'OSDCloud'
    }
    elseif (Get-Command -Name 'Get-OSDCoreOperatingSystems' -ErrorAction Ignore) {
        $catalogProvider = 'Get-OSDCoreOperatingSystems'
        $catalogShape = 'OSD'
    }
    else {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to load core operating systems provider command."
    }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Using operating systems provider '$catalogProvider' for '$catalogShape' object shape"

    $existingCatalogShape = $null
    if ($global:OSDCoreOperatingSystems) {
        $firstCachedOperatingSystem = @($global:OSDCoreOperatingSystems | Select-Object -First 1)[0]
        if ($firstCachedOperatingSystem.PSObject.Properties.Name -contains 'OSArchitecture') {
            $existingCatalogShape = 'OSDCloud'
        }
        elseif ($firstCachedOperatingSystem.PSObject.Properties.Name -contains 'Architecture') {
            $existingCatalogShape = 'OSD'
        }
    }
    $refreshOperatingSystems = $RefreshCatalog -or -not $global:OSDCoreOperatingSystems -or (($existingCatalogShape) -and ($existingCatalogShape -ne $catalogShape))

    if ($refreshOperatingSystems) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Refreshing cached operating systems from $catalogProvider"
        $global:OSDCoreOperatingSystems = & $catalogProvider |
        Where-Object { ($_.Architecture -eq $normalizedArchitecture) -or ($_.OSArchitecture -eq $normalizedArchitecture) }
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Cached operating systems after architecture prefilter: $(@($global:OSDCoreOperatingSystems).Count)"
    }
    else {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Using existing cached operating systems: $(@($global:OSDCoreOperatingSystems).Count)"
    }

    if (-not $global:OSDCoreOperatingSystems) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No operating systems are available after loading cache"
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to load Operating Systems"
    }

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Applying catalog filters to cached operating systems"
    $filteredOperatingSystems = $global:OSDCoreOperatingSystems |
    Where-Object { ($_.Activation -eq $OSActivation) -or ($_.OSActivation -eq $OSActivation) } |
    Where-Object { ($_.Architecture -eq $normalizedArchitecture) -or ($_.OSArchitecture -eq $normalizedArchitecture) } |
    Where-Object { ($_.Language -eq $normalizedLanguageCode) -or ($_.OSLanguageCode -eq $normalizedLanguageCode) } |
    Where-Object { ($_.ReleaseID -eq $OSReleaseID) -or ($_.OSVersion -eq $OSReleaseID) } |
    Where-Object { ($_.Version -eq $OSVersion) -or ($_.OSName -eq $OSVersion) }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Matching operating systems found: $(@($filteredOperatingSystems).Count)"

    $global:OSDCoreOperatingSystemCloudObject = $filteredOperatingSystems |
    Sort-Object -Property @{ Expression = {
            try {
                $buildVersion = if ($_.Build) { $_.Build } else { $_.OSBuildVersion }
                [version]([string]$buildVersion -replace '[^0-9\.]', '')
            }
            catch {
                [version]'0.0'
            }
        }; Descending                   = $true 
    } |
    Select-Object -First 1

    if (-not $global:OSDCoreOperatingSystemCloudObject) {
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No matching operating system object was selected after sorting"
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to find a matching operating system object for OSReleaseID '$OSReleaseID', OSArchitecture '$normalizedArchitecture', Activation '$OSActivation', Language '$normalizedLanguageCode', and OSVersion '$OSVersion'."
    }

    $selectedOperatingSystemName = if ($global:OSDCoreOperatingSystemCloudObject.Id) { $global:OSDCoreOperatingSystemCloudObject.Id } else { $global:OSDCoreOperatingSystemCloudObject.Name }
    $selectedOperatingSystemBuild = if ($global:OSDCoreOperatingSystemCloudObject.OSBuildVersion) { $global:OSDCoreOperatingSystemCloudObject.OSBuildVersion } else { $global:OSDCoreOperatingSystemCloudObject.Build }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Selected operating system object: Name='$selectedOperatingSystemName', Build='$selectedOperatingSystemBuild', FileName='$($global:OSDCoreOperatingSystemCloudObject.FileName)'"

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Operating system cloud object selection completed successfully"
    $global:OSDCoreOperatingSystemCloudObject | Export-Clixml -Path (Join-Path -Path $env:TEMP -ChildPath 'OSDCoreOperatingSystemCloudObject.xml') -Force
    return $global:OSDCoreOperatingSystemCloudObject
}
