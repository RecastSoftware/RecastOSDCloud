function Initialize-DeployOSDCloud {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false,
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('Name')]
        [System.String]
        $WorkflowName = 'default',

        [Parameter(Mandatory = $false, HelpMessage = 'Optional local disk number to use as the deployment target.')]
        [System.UInt32]
        $DiskNumber,

        [Parameter(Mandatory = $false)]
        [System.Collections.IDictionary]
        $EnvParameters,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.SwitchParameter]
        $Force,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ProfileName = 'default',

        [Parameter(Mandatory = $false, HelpMessage = 'Optional manufacturer override used for driver pack selection.')]
        [System.String]
        $OSDManufacturer,

        [Parameter(Mandatory = $false, HelpMessage = 'Optional model override used for driver pack selection.')]
        [System.String]
        $OSDModel,

        [Parameter(Mandatory = $false, HelpMessage = 'Optional product/system ID override used for driver pack selection.')]
        [System.String]
        $OSDProduct,

        [Parameter(Mandatory = $false, HelpMessage = 'Mock/testing processor architecture override used for deployment selection.')]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('amd64', 'arm64')]
        [System.String]
        $ProcessorArchitecture,

        [Parameter(Mandatory = $false, HelpMessage = 'Operating system name for deployment selection.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OperatingSystem,

        [Parameter(Mandatory = $false, HelpMessage = 'Operating system edition for deployment selection.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSEdition,

        [Parameter(Mandatory = $false, HelpMessage = 'Operating system activation channel for deployment selection.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OSActivation,

        [Parameter(Mandatory = $false, HelpMessage = 'Operating system language code for deployment selection.')]
        [ValidateNotNullOrEmpty()]
        [ValidateSet(
            'ar-sa', 'bg-bg', 'cs-cz', 'da-dk', 'de-de', 'el-gr',
            'en-gb', 'en-us', 'es-es', 'es-mx', 'et-ee', 'fi-fi',
            'fr-ca', 'fr-fr', 'he-il', 'hr-hr', 'hu-hu', 'it-it',
            'ja-jp', 'ko-kr', 'lt-lt', 'lv-lv', 'nb-no', 'nl-nl',
            'pl-pl', 'pt-br', 'pt-pt', 'ro-ro', 'ru-ru', 'sk-sk',
            'sl-si', 'sr-latn-rs', 'sv-se', 'th-th', 'tr-tr',
            'uk-ua', 'zh-cn', 'zh-tw'
        )]
        [System.String]
        $OSLanguageCode
    )
    $ErrorActionPreference = 'Stop'
    #=================================================
    # Get module details
    # $ModuleVersion = $($MyInvocation.MyCommand.Module.Version)
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] [$($MyInvocation.MyCommand.Name)]"
    #=================================================
    # OSDCloud Env override layer
    # Assemble $global:OSDCloudEnv early so initial property resolution can consume
    # values from the selected profile and parameter overrides.
    <#
    if (Get-Command -Name 'Initialize-OSDCloudEnv' -ErrorAction Ignore) {
        Initialize-OSDCloudEnv -Parameters $EnvParameters -ProfileName $ProfileName | Out-Null
    }
    #>
    #=================================================
    # Dependencies
    # Make sure curl.exe is present and throw if not
    if (-not (Get-Command -Name 'curl.exe' -ErrorAction Ignore)) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSDCloud requires 'curl.exe' which is not available on this system. Please ensure curl.exe is available in the system PATH."
    }
    # Preserve caller-specified OS values so they can be applied after workflow defaults are loaded.
    $requestedOSValues = @{}
    foreach ($requestedOSParameterName in 'OperatingSystem', 'OSEdition', 'OSActivation', 'OSLanguageCode') {
        if ($PSBoundParameters.ContainsKey($requestedOSParameterName)) {
            $requestedOSValues[$requestedOSParameterName] = [System.String]$PSBoundParameters[$requestedOSParameterName]
        }
    }
    #=================================================
    # Initialize
    if (-not ($global:OSDCoreDevice)) {
        Initialize-OSDCoreDevice
    }
    Initialize-OSDCoreCache
    #=================================================
    #region OSArchitecture
    if ($ProcessorArchitecture -and -not [string]::IsNullOrWhiteSpace($ProcessorArchitecture)) {
        $global:OSDCoreDevice.ProcessorArchitecture = $ProcessorArchitecture
    }

    # Resolve the effective architecture from OSDCoreDevice and normalize aliases.
    $processorArchitecture = if (-not [string]::IsNullOrWhiteSpace($global:OSDCoreDevice.ProcessorArchitecture)) {
        $global:OSDCoreDevice.ProcessorArchitecture
    }
    else {
        $env:PROCESSOR_ARCHITECTURE
    }

    switch -Regex ($processorArchitecture) {
        '^(amd64|x64)$' { $processorArchitecture = 'amd64'; break }
        '^arm64$' { $processorArchitecture = 'arm64'; break }
        default {
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unsupported processor architecture '$processorArchitecture'. Expected amd64 or arm64."
        }
    }
    #endregion
    #=================================================
    # CoreDriverPacks
    Initialize-ModuleCoreDriverPacks -OSDManufacturer $OSDManufacturer -ProcessorArchitecture $processorArchitecture
    #=================================================
    # CoreOperatingSystems
    $ModuleName = $($MyInvocation.MyCommand.Module.Name)
    if ($ModuleName -eq 'OSD') {
        $global:OSDCoreOperatingSystems = Get-OSDCoreOperatingSystems |
        Where-Object { $_.Architecture -match $processorArchitecture }
    }
    elseif ($ModuleName -eq 'OSDCloud') {
        $global:OSDCoreOperatingSystems = Get-OSDCloudCoreOperatingSystems |
        Where-Object { $_.OSArchitecture -match $processorArchitecture }
    }
    else {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to load core operating systems provider command."
    }
    #=================================================
    # OSDCloudDeploy
    $global:OSDCloudDeploy = $null
    $global:OSDCloudDeploy = [pscustomobject][ordered]@{
        CoreDriverPacks            = [array]$global:ModuleCoreDriverPacks
        CoreOperatingSystems       = $global:OSDCoreOperatingSystems
        DeploymentDisk             = $null
        DeploymentDiskNumber       = $null
        DriverPackName             = $null
        DriverPackCacheObject      = $null
        DriverPackCloudObject      = $null
        DriverPackCloudTest        = $false
        Force                      = $Force.IsPresent
        Function                   = $($MyInvocation.MyCommand.Name)
        LaunchMethod               = 'OSDCloudWorkflow'
        Module                     = $($MyInvocation.MyCommand.Module.Name)
        OperatingSystemCacheObject = $null
        OperatingSystemCloudObject = $null
        OperatingSystemCloudTest   = $false
        OperatingSystem            = $null
        OperatingSystemValues      = $null
        OSArchitecture             = $processorArchitecture
        OSActivation               = $OSActivation
        OSActivationValues         = $null
        OSBuild                    = $null
        OSBuildVersion             = $null
        OSEdition                  = $null
        OSEditionId                = $null
        OSEditionValues            = $null
        OSLanguageCode             = $null
        OSLanguageCodeValues       = $null
        OSVersion                  = $OSVersion
        SkipFirmwareUpdate         = $false
        TimeStart                  = $null
        WorkflowName               = $WorkflowName
        WorkflowTaskName           = $null
        WorkflowTaskObject         = $null
        WorkflowTasks              = $null
        # DriverFolderName       = $null
        # DriverFolderNames      = @()
        # DriverFolderPath       = $null
        # DriverFolderPaths      = @()
        # DriverFolderSelections = @()
        # ImageFileName         = $ImageFileName
        # ImageFileUrl          = $ImageFileUrl
        # LocalImageFileInfo    = $null
        # LocalImageFilePath    = $null
        # LocalImageName        = $null
        # OperatingSystemObject = $OperatingSystemObject
    }
    #=================================================
    #region OSDCoreDevice Manufacturer, Model, Product overrides
    if ($OSDManufacturer -and -not [string]::IsNullOrWhiteSpace($OSDManufacturer)) {
        $global:OSDCoreDevice.OSDManufacturer = $OSDManufacturer
    }
    if ($OSDModel -and -not [string]::IsNullOrWhiteSpace($OSDModel)) {
        $global:OSDCoreDevice.OSDModel = $OSDModel
    }
    if ($OSDProduct -and -not [string]::IsNullOrWhiteSpace($OSDProduct)) {
        $global:OSDCoreDevice.OSDProduct = $OSDProduct
    }
    #=================================================
    # Refactor variables for deployment workflow initialization
    $OSDManufacturer = $global:OSDCoreDevice.OSDManufacturer
    $OSDModel = $global:OSDCoreDevice.OSDModel
    $OSDProduct = $global:OSDCoreDevice.OSDProduct
    #endregion
    #=================================================
    #region OSDCloudDeploy.DeploymentDisk
    $getDiskNumber = {
        param ($Disk)

        if ($Disk.PSObject.Properties.Match('Number').Count -gt 0) {
            $Disk.Number
        }
        elseif ($Disk.PSObject.Properties.Match('DiskNumber').Count -gt 0) {
            $Disk.DiskNumber
        }
    }
    $getDiskName = {
        param ($Disk)

        if ($Disk.PSObject.Properties.Match('FriendlyName').Count -gt 0) {
            $Disk.FriendlyName
        }
        else {
            'Unknown'
        }
    }
    $getDiskSize = {
        param ($Disk)

        if ($Disk.PSObject.Properties.Match('Size').Count -gt 0) {
            "$([math]::Round($Disk.Size / 1GB, 2)) GB"
        }
        else {
            'Unknown size'
        }
    }

    $localDisks = @($global:OSDCoreDevice.LocalDisk)
    if ($PSBoundParameters.ContainsKey('DiskNumber')) {
        $selectedDeploymentDisk = $localDisks |
        Where-Object {
            $localDiskNumber = & $getDiskNumber $_
            $null -ne $localDiskNumber -and [System.UInt32]$localDiskNumber -eq $DiskNumber
        } |
        Select-Object -First 1

        if (-not $selectedDeploymentDisk) {
            $availableLocalDiskDetails = @(
                $localDisks | ForEach-Object {
                    $availableDiskNumber = & $getDiskNumber $_
                    $availableDiskName = & $getDiskName $_
                    $availableDiskSize = & $getDiskSize $_
                    "$availableDiskNumber ($availableDiskName, $availableDiskSize)"
                }
            )
            $availableLocalDiskMessage = if ($availableLocalDiskDetails.Count -gt 0) { $availableLocalDiskDetails -join ', ' } else { 'None' }
            throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DiskNumber '$DiskNumber' is not a valid local deployment disk. Valid DiskNumber values: $availableLocalDiskMessage"
        }

        $tempDeploymentDisk = $selectedDeploymentDisk
    }
    else {
        $selectedDeploymentDisk = $localDisks | Select-Object -First 1
        if ($selectedDeploymentDisk) {
            $tempDeploymentDisk = $selectedDeploymentDisk
        }
    }

    if ($tempDeploymentDisk) {
        $tempDeploymentDiskNumber = & $getDiskNumber $tempDeploymentDisk
    }
    if ($tempDeploymentDisk) {
        $deploymentDiskName = & $getDiskName $tempDeploymentDisk
        $deploymentDiskSize = & $getDiskSize $tempDeploymentDisk
        Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] DiskNumber is automatically set to $tempDeploymentDiskNumber [$deploymentDiskName] with size $deploymentDiskSize."

        $otherLocalDisks = @($global:OSDCoreDevice.LocalDisk | Where-Object {
                $localDiskNumber = & $getDiskNumber $_
                $localDiskNumber -ne $tempDeploymentDiskNumber
            })
        foreach ($localDisk in $otherLocalDisks) {
            $localDiskNumber = & $getDiskNumber $localDisk
            $localDiskName = & $getDiskName $localDisk
            $localDiskSize = & $getDiskSize $localDisk
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DiskNumber $localDiskNumber [$localDiskName] with size $localDiskSize was not selected for deployment."
        }
    }
    else {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to determine Deployment Disk. Please check your system configuration."
    }
    $global:OSDCloudDeploy.DeploymentDisk = $tempDeploymentDisk
    $global:OSDCloudDeploy.DeploymentDiskNumber = [System.UInt32]$tempDeploymentDiskNumber
    #endregion
    #=================================================
    #region DriverPacks
    if ($global:ModuleCoreDriverPacks) {
        $DriverPackCloudObject = $global:ModuleCoreDriverPacks | Where-Object { $_.SystemId -match $OSDProduct } | Select-Object -First 1
    }
    Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] OSDManufacturer: $OSDManufacturer"
    Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] OSDModel: $OSDModel"
    Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] OSDProduct: $OSDProduct"

    if ($DriverPackCloudObject) {
        $global:OSDCloudDeploy.DriverPackCloudObject = $DriverPackCloudObject
        $global:OSDCloudDeploy.DriverPackName = $DriverPackCloudObject.Name
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] DriverPack: $($global:OSDCloudDeploy.DriverPackName)"
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] DriverPack Url: $($DriverPackCloudObject.Url)"
    }
    #=================================================
    # DriverPackCloudTest
    if ($DriverPackCloudObject) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Test DriverPack CloudObject."
        $global:OSDCloudDeploy.DriverPackCloudTest = Test-OSDCoreDriverPackCloudObject -DriverPackCloudObject $DriverPackCloudObject
        if ($global:OSDCloudDeploy.DriverPackCloudTest) {
            Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] DriverPack is available online and ready to downloaded."
        }
        else {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] DriverPack URL is not reachable online and cannot be downloaded."
        }

        # Driver pack catalogs use either HashMD5 or MD5Hash depending on the source.
        $expectedDriverPackHashMD5 = $null
        if ($DriverPackCloudObject.PSObject.Properties.Match('HashMD5').Count -gt 0) {
            $expectedDriverPackHashMD5 = [string]$DriverPackCloudObject.HashMD5
        }
        elseif ($DriverPackCloudObject.PSObject.Properties.Match('MD5Hash').Count -gt 0) {
            $expectedDriverPackHashMD5 = [string]$DriverPackCloudObject.MD5Hash
        }

        # Check whether the selected driver pack is already present in the cache inventory.
        $DriverPackCacheObject = Get-OSDCoreDriverPackCacheObject -DriverPackCloudObject $DriverPackCloudObject
        if ($DriverPackCacheObject) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Test DriverPack CacheObject."
            # Verify cached driver pack integrity when the catalog includes an MD5 hash.
            if (-not [string]::IsNullOrWhiteSpace($expectedDriverPackHashMD5)) {
                $actualDriverPackHashMD5 = (Get-FileHash -Path $DriverPackCacheObject.FullName -Algorithm MD5 -ErrorAction Stop).Hash
                if ($actualDriverPackHashMD5 -ne $expectedDriverPackHashMD5.Trim()) {
                    throw "[$(Get-Date -format s)] DriverPack MD5 hash mismatch for $($DriverPackCacheObject.FullName). Expected $($expectedDriverPackHashMD5.Trim()), found $actualDriverPackHashMD5."
                }
                Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] DriverPack is saved in cache and MD5 hash verified."
            }
            else {
                Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] DriverPack is saved in cache."
            }
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($DriverPackCacheObject.FullName)"
            $global:OSDCloudDeploy.DriverPackCacheObject = $DriverPackCacheObject
            $global:OSDCloudDeploy.DriverPackCloudTest = $true
        }
        else {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] DriverPack is not available in the offline cache."
            $DriverPackCacheObject = $null
        }
        # $DriverPackCloudObject | Format-List | Out-Host
    }
    else {
        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OSDCoreDriverPackCloudObject is not set."
        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OSDCloud will not apply a DriverPack for this deployment."
        $global:OSDCloudDeploy.DriverPackCacheObject = $null
        $global:OSDCloudDeploy.DriverPackCloudObject = $null
        $global:OSDCloudDeploy.DriverPackCloudTest = $false
        $global:OSDCloudDeploy.DriverPackName = $null
    }
    #endregion
    #=================================================
    # OSDCloudWorkflowSettingsOS
    # This function will read a configuration file and store it in $OSDCloudWorkflowSettingsOS
    Initialize-OSDCloudWorkflowSettingsOS -WorkflowName $WorkflowName -Architecture $global:OSDCloudDeploy.OSArchitecture

    # Apply workflow OS constraints to the loaded catalog for this architecture.
    $allowedOperatingSystems = @($global:OSDCloudWorkflowSettingsOS.OperatingSystem.values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $allowedOSActivations = @($global:OSDCloudWorkflowSettingsOS.OSActivation.values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $allowedOSEditionObjects = @($global:OSDCloudWorkflowSettingsOS.OSEdition.values)
    $allowedOSEditions = @($allowedOSEditionObjects | ForEach-Object { [string]$_.Edition } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $allowedOSLanguageCodes = @($global:OSDCloudWorkflowSettingsOS.OSLanguageCode.values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    $global:OSDCloudDeploy.CoreOperatingSystems = @(
        $global:OSDCloudDeploy.CoreOperatingSystems | Where-Object {
            ($allowedOperatingSystems.Count -eq 0 -or $allowedOperatingSystems -contains [string]$_.OperatingSystem) -and
            ($allowedOSActivations.Count -eq 0 -or $allowedOSActivations -contains [string]$_.OSActivation) -and
            ($allowedOSLanguageCodes.Count -eq 0 -or $allowedOSLanguageCodes -contains [string]$_.OSLanguageCode)
        }
    )

    if (-not $global:OSDCloudDeploy.CoreOperatingSystems) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No Operating Systems remain after applying workflow OS filters. Check workflow/$WorkflowName/ui/os.json values for OperatingSystem, OSActivation, and OSLanguageCode."
    }

    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Filtered CoreOperatingSystems Count: $(@($global:OSDCloudDeploy.CoreOperatingSystems).Count)"
    #=================================================
    # $OperatingSystemCloudObject
    <#
        This global variable is used to store the selected operating system object from the catalog for use in deployment.
        A default should be selected based on this order of preference:
            1. Parameter.
            2. OSDCloudEnv override
            3. Workflow default
            4. First available in the filtered catalog

    #>
    # Solution:
    $preferredOperatingSystem = [string]$global:OSDCloudWorkflowSettingsOS.OperatingSystem.default
    $preferredOSEdition = [string]$global:OSDCloudWorkflowSettingsOS.OSEdition.default
    $preferredOSActivation = [string]$global:OSDCloudWorkflowSettingsOS.OSActivation.default
    $preferredOSLanguageCode = [string]$global:OSDCloudWorkflowSettingsOS.OSLanguageCode.default

    if ($global:OSDCloudEnv) {
        if (-not [string]::IsNullOrWhiteSpace([string]$global:OSDCloudEnv.OperatingSystem)) {
            $preferredOperatingSystem = [string]$global:OSDCloudEnv.OperatingSystem
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$global:OSDCloudEnv.OSEdition)) {
            $preferredOSEdition = [string]$global:OSDCloudEnv.OSEdition
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$global:OSDCloudEnv.OSActivation)) {
            $preferredOSActivation = [string]$global:OSDCloudEnv.OSActivation
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$global:OSDCloudEnv.OSLanguageCode)) {
            $preferredOSLanguageCode = [string]$global:OSDCloudEnv.OSLanguageCode
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($requestedOSValues['OperatingSystem'])) {
        $preferredOperatingSystem = $requestedOSValues['OperatingSystem']
    }
    if (-not [string]::IsNullOrWhiteSpace($requestedOSValues['OSEdition'])) {
        $preferredOSEdition = $requestedOSValues['OSEdition']
    }
    if (-not [string]::IsNullOrWhiteSpace($requestedOSValues['OSActivation'])) {
        $preferredOSActivation = $requestedOSValues['OSActivation']
    }
    if (-not [string]::IsNullOrWhiteSpace($requestedOSValues['OSLanguageCode'])) {
        $preferredOSLanguageCode = $requestedOSValues['OSLanguageCode']
    }

    if ($preferredOperatingSystem -notin $allowedOperatingSystems) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OperatingSystem '$preferredOperatingSystem' is not valid for workflow '$WorkflowName'. Valid values: $($allowedOperatingSystems -join ', ')"
    }
    if ($preferredOSEdition -notin $allowedOSEditions) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSEdition '$preferredOSEdition' is not valid for workflow '$WorkflowName'. Valid values: $($allowedOSEditions -join ', ')"
    }
    if ($preferredOSLanguageCode -notin $allowedOSLanguageCodes) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSLanguageCode '$preferredOSLanguageCode' is not valid for workflow '$WorkflowName'. Valid values: $($allowedOSLanguageCodes -join ', ')"
    }

    $resolvedPreferredOSActivation = Resolve-OSDCloudWorkflowOSActivation -OSEdition $preferredOSEdition -OSActivation $preferredOSActivation
    if ($resolvedPreferredOSActivation -ne $preferredOSActivation) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSEdition '$preferredOSEdition' requires OSActivation '$resolvedPreferredOSActivation'."
        $preferredOSActivation = $resolvedPreferredOSActivation
    }
    if ($preferredOSActivation -notin $allowedOSActivations) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSEdition '$preferredOSEdition' requires OSActivation '$preferredOSActivation', which is not valid for workflow '$WorkflowName'. Valid values: $($allowedOSActivations -join ', ')"
    }

    $operatingSystemBuildVersionSort = @{ Expression = {
            try {
                [version]([string]$_.OSBuildVersion -replace '[^0-9\.]', '')
            }
            catch {
                [version]'0.0'
            }
        }; Descending                   = $true
    }

    $OperatingSystemCloudObject = $global:OSDCloudDeploy.CoreOperatingSystems |
    Where-Object {
        ([string]$_.OperatingSystem -ieq $preferredOperatingSystem) -and
        ([string]$_.OSActivation -ieq $preferredOSActivation) -and
        ([string]$_.OSLanguageCode -ieq $preferredOSLanguageCode)
    } |
    Sort-Object -Property $operatingSystemBuildVersionSort |
    Select-Object -First 1

    if (-not $OperatingSystemCloudObject) {
        Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No exact operating system match was found for OperatingSystem '$preferredOperatingSystem', OSActivation '$preferredOSActivation', and OSLanguageCode '$preferredOSLanguageCode'. Falling back to the first available filtered catalog entry."
        $OperatingSystemCloudObject = $global:OSDCloudDeploy.CoreOperatingSystems |
        Sort-Object -Property $operatingSystemBuildVersionSort |
        Select-Object -First 1
    }

    if (-not $OperatingSystemCloudObject) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to set OperatingSystemCloudObject because no operating system entries are available in the filtered catalog."
    }
    #=================================================
    # OSDCoreOperatingSystems Verify
    if ($OperatingSystemCloudObject) {
        $OperatingSystemCloudObject | Export-Clixml -Path (Join-Path -Path $env:TEMP -ChildPath 'OperatingSystemCloudObject.xml') -Force
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Test OperatingSystem CloudObject."
        # Confirm the selected operating system download URL before offering cache download work.
        $global:OSDCloudDeploy.OperatingSystemCloudTest = Test-OperatingSystemCloudObject -OperatingSystemCloudObject $OperatingSystemCloudObject
        if ($global:OSDCloudDeploy.OperatingSystemCloudTest) {
            Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] OperatingSystem is available online and ready to downloaded."
        }
        else {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OperatingSystem URL is not reachable online and cannot be downloaded."
        }

        # Prefer SHA256 when the catalog provides it, and fall back to SHA1 for older entries.
        $expectedOperatingSystemHash = $null
        $expectedOperatingSystemHashAlgorithm = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$OperatingSystemCloudObject.SHA256)) {
            $expectedOperatingSystemHash = [string]$OperatingSystemCloudObject.SHA256
            $expectedOperatingSystemHashAlgorithm = 'SHA256'
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$OperatingSystemCloudObject.SHA1)) {
            $expectedOperatingSystemHash = [string]$OperatingSystemCloudObject.SHA1
            $expectedOperatingSystemHashAlgorithm = 'SHA1'
        }

        # Check whether the selected OS payload is already present in the USB cache inventory.
        $OperatingSystemCacheObject = Get-OSDCoreOperatingSystemCacheObject -OperatingSystemCloudObject $OperatingSystemCloudObject
        if ($OperatingSystemCacheObject) {
            $OperatingSystemCacheObject | Export-Clixml -Path (Join-Path -Path $env:TEMP -ChildPath 'OSDCoreOperatingSystemCacheObject.xml') -Force
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Test OperatingSystem CacheObject."
            # Verify the cached payload before treating it as ready.
            if (-not [string]::IsNullOrWhiteSpace($expectedOperatingSystemHash)) {
                $actualOperatingSystemHash = (Get-FileHash -Path $OperatingSystemCacheObject.FullName -Algorithm $expectedOperatingSystemHashAlgorithm -ErrorAction Stop).Hash
                if ($actualOperatingSystemHash -ne $expectedOperatingSystemHash.Trim()) {
                    throw "[$(Get-Date -format s)] OSDCoreOperatingSystemCloudObject $expectedOperatingSystemHashAlgorithm hash mismatch for $($OperatingSystemCacheObject.FullName). Expected $($expectedOperatingSystemHash.Trim()), found $actualOperatingSystemHash."
                }
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem is saved in cache and $expectedOperatingSystemHashAlgorithm hash verified."
            }
            else {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem cached file hash was not verified because no hash property was available."
            }
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($OperatingSystemCacheObject.FullName)"
            $global:OSDCloudDeploy.OperatingSystemCacheObject = $OperatingSystemCacheObject
        }
        else {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OperatingSystem is not available in the offline cache."
            $global:OSDCloudDeploy.OperatingSystemCacheObject = $null
        }

        # Build a display object that supports both OSD and OSDCloud property shapes.
        $selectedOperatingSystemName = if ($OperatingSystemCloudObject.Id) { $OperatingSystemCloudObject.Id } else { $OperatingSystemCloudObject.Name }
        $selectedOperatingSystemUrl = if ($OperatingSystemCloudObject.FilePath) { $OperatingSystemCloudObject.FilePath } else { $OperatingSystemCloudObject.Url }
        $selectedOperatingSystemSha1 = if ($OperatingSystemCloudObject.Sha1) { $OperatingSystemCloudObject.Sha1 } else { $OperatingSystemCloudObject.SHA1 }
        $selectedOperatingSystemSha256 = if ($OperatingSystemCloudObject.Sha256) { $OperatingSystemCloudObject.Sha256 } else { $OperatingSystemCloudObject.SHA256 }

        # Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] OSDCoreOperatingSystemCloudObject:"
        $tempOperatingSystemDisplay = [ordered]@{
            Name     = [string]$selectedOperatingSystemName
            FileName = [string]$OperatingSystemCloudObject.FileName
            Url      = [string]$selectedOperatingSystemUrl
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$selectedOperatingSystemSha256)) {
            $tempOperatingSystemDisplay['SHA256'] = [string]$selectedOperatingSystemSha256
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$selectedOperatingSystemSha1)) {
            $tempOperatingSystemDisplay['SHA1'] = [string]$selectedOperatingSystemSha1
        }
        $tempOSDCoreOperatingSystemCloudObject = [pscustomobject]$tempOperatingSystemDisplay
        $tempOSDCoreOperatingSystemCloudObject | Format-List | Out-Host
        $global:OSDCloudDeploy.OperatingSystemCloudObject = $OperatingSystemCloudObject
    }
    #=================================================
    # OSDCloudWorkflowTasks
    # If $WorkflowName is not default, display a message that this Workflow is for Beta or Testing purposes only
    if ($WorkflowName -ne 'default') {
        Write-Warning "[$(Get-Date -format s)] The workflow '$WorkflowName' is for Beta testing purposes only."
    }

    Initialize-OSDCloudWorkflowTasks -WorkflowName $WorkflowName
    # Make sure at least one workflow task is defined
    if (-not $global:OSDCloudWorkflowTasks) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Initialize-DeployOSDCloud requires at least one valid workflow task. Please check your OSDCloud Workflow Tasks."
    }
    $global:OSDCloudDeploy.WorkflowTasks = [array]$global:OSDCloudWorkflowTasks
    $global:OSDCloudDeploy.WorkflowTaskObject = $global:OSDCloudDeploy.WorkflowTasks | Select-Object -First 1
    $global:OSDCloudDeploy.WorkflowTaskName = $global:OSDCloudDeploy.WorkflowTaskObject.name
    #=================================================
    # Set initial Operating System
    <#
        Id              : Windows 11 25H2 amd64 Retail en-gb 26200.7462
        OperatingSystem : Windows 11 25H2
        OSVersion       : 25H2
        OSArchitecture  : amd64
        OSActivation    : Retail
        LanguageCode    : en-gb
        Language        : English (United Kingdom)
        OSBuild         : 26200
        OSBuildVersion  : 26200.7462
        Size            : 5626355066
        Sha1            :
        Sha256          : 566a518dc46ba5ea401381810751a8abcfe7d012b2f81c9709b787358c606926
        FileName        : 26200.7462.251207-0044.25h2_ge_release_svc_refresh_CLIENTCONSUMER_RET_x64FRE_en-gb.esd
        FilePath        : http://dl.delivery.mp.microsoft.com/filestreamingservice/files/79a3f5e0-d04d-4689-a5d4-3ea35f8b189a/26200.7462.251207-0044.25h2_ge_release_svc_refresh_CLIENTCONSUMER_RET_x64FRE_en-gb.esd
    #>
    #=================================================
    # OperatingSystemObject
    $OperatingSystemObject = $global:OSDCloudDeploy.OperatingSystemCloudObject
    if (-not $OperatingSystemObject) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to initialize deployment state because OperatingSystemCloudObject is not set."
    }
    #=================================================
    # OperatingSystem
    $OperatingSystem = if ($OperatingSystemObject.OperatingSystem) {
        [string]$OperatingSystemObject.OperatingSystem
    }
    else {
        $preferredOperatingSystem
    }
    $global:OSDCloudDeploy.OperatingSystem = $OperatingSystem
    $global:OSDCloudDeploy.OperatingSystemValues = [array]$allowedOperatingSystems
    #=================================================
    # OSActivation
    $OSActivation = if ($OperatingSystemObject.OSActivation) {
        [string]$OperatingSystemObject.OSActivation
    }
    elseif ($OperatingSystemObject.Activation) {
        [string]$OperatingSystemObject.Activation
    }
    else {
        $preferredOSActivation
    }
    $global:OSDCloudDeploy.OSActivation = $OSActivation
    $global:OSDCloudDeploy.OSActivationValues = [array]$allowedOSActivations
    #=================================================
    # OSBuild
    $global:OSDCloudDeploy.OSBuild = if ($OperatingSystemObject.OSBuild) {
        [string]$OperatingSystemObject.OSBuild
    }
    else {
        [string]$OperatingSystemObject.Build
    }
    #=================================================
    # OSBuildVersion
    $global:OSDCloudDeploy.OSBuildVersion = if ($OperatingSystemObject.OSBuildVersion) {
        [string]$OperatingSystemObject.OSBuildVersion
    }
    else {
        [string]$OperatingSystemObject.Build
    }
    #=================================================
    # OSEdition
    $OSEdition = $preferredOSEdition
    $OSEditionValues = [array]$allowedOSEditionObjects
    $OSEditionObject = $OSEditionValues | Where-Object { $_.Edition -eq $OSEdition } | Select-Object -First 1
    if (-not $OSEditionObject) {
        $validOSEditions = $OSEditionValues | ForEach-Object { $_.Edition }
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSEdition '$OSEdition' is not valid for workflow '$WorkflowName'. Valid values: $($validOSEditions -join ', ')"
    }
    if ([string]::IsNullOrWhiteSpace([string]$OSEditionObject.EditionId)) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSEdition '$OSEdition' does not have a valid EditionId in workflow '$WorkflowName'."
    }
    $global:OSDCloudDeploy.OSEdition = $OSEdition
    $global:OSDCloudDeploy.OSEditionValues = $OSEditionValues
    $global:OSDCloudDeploy.OSEditionId = $OSEditionObject.EditionId
    #=================================================
    # OSLanguageCode
    $OSLanguageCode = if ($OperatingSystemObject.OSLanguageCode) {
        [string]$OperatingSystemObject.OSLanguageCode
    }
    elseif ($OperatingSystemObject.Language) {
        [string]$OperatingSystemObject.Language
    }
    else {
        $preferredOSLanguageCode
    }
    $global:OSDCloudDeploy.OSLanguageCode = $OSLanguageCode
    $global:OSDCloudDeploy.OSLanguageCodeValues = [array]$allowedOSLanguageCodes
    #=================================================
    # OSVersion
    $OSVersion = if ($OperatingSystemObject.OSVersion) {
        [string]$OperatingSystemObject.OSVersion
    }
    elseif ($OperatingSystemObject.ReleaseID) {
        [string]$OperatingSystemObject.ReleaseID
    }
    else {
        ($OperatingSystem -split ' ')[2]
    }
    $global:OSDCloudDeploy.OSVersion = $OSVersion
    #=================================================
    # OSDCloud Env override layer
    # Apply the pre-assembled overrides onto $global:OSDCloudDeploy so they take effect
    # everywhere.
    <#
    if (Get-Command -Name 'Set-OSDCloudEnvOverride' -ErrorAction Ignore) {
        Set-OSDCloudEnvOverride -Target $global:OSDCloudDeploy -ResolveOperatingSystem -AddMissingKeys
    }
    #>
    $global:OSDCloudDeploy | Export-Clixml -Path (Join-Path -Path $env:TEMP -ChildPath 'OSDCloudDeploy.xml') -Force
    #=================================================
}
