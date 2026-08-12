function Initialize-DeployOSDCloud {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false,
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        [Alias('Name')]
        [System.String]
        $WorkflowName = 'default',

        [Parameter(Mandatory = $false)]
        [System.Collections.IDictionary]
        $EnvParameters,

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

        [Parameter(Mandatory = $false, HelpMessage = 'Operating system architecture for deployment selection.')]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('amd64', 'arm64')]
        [System.String]
        $OSArchitecture = $env:PROCESSOR_ARCHITECTURE,

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
    if (Get-Command -Name 'Initialize-OSDCloudEnv' -ErrorAction SilentlyContinue) {
        Initialize-OSDCloudEnv -Parameters $EnvParameters -ProfileName $ProfileName | Out-Null
    }
    #>
    #=================================================
    # Dependencies
    # Make sure curl.exe is present and throw if not
    if (-not (Get-Command -Name 'curl.exe' -ErrorAction SilentlyContinue)) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSDCloud requires 'curl.exe' which is not available on this system. Please ensure curl.exe is available in the system PATH."
    }
    # Preserve caller-specified OS values so they can be applied after workflow defaults are loaded.
    $requestedOperatingSystem = if ($PSBoundParameters.ContainsKey('OperatingSystem')) {
        [System.String]$PSBoundParameters['OperatingSystem']
    }
    else {
        $null
    }
    $requestedOSEdition = if ($PSBoundParameters.ContainsKey('OSEdition')) {
        [System.String]$PSBoundParameters['OSEdition']
    }
    else {
        $null
    }
    $requestedOSActivation = if ($PSBoundParameters.ContainsKey('OSActivation')) {
        [System.String]$PSBoundParameters['OSActivation']
    }
    else {
        $null
    }
    $requestedOSLanguageCode = if ($PSBoundParameters.ContainsKey('OSLanguageCode')) {
        [System.String]$PSBoundParameters['OSLanguageCode']
    }
    else {
        $null
    }
    #=================================================
    # Initialize Architecture
    # Resolve the effective architecture once and normalize aliases.
    $processorArchitecture = if (-not [string]::IsNullOrWhiteSpace($OSArchitecture)) {
        $OSArchitecture
    }
    elseif (-not [string]::IsNullOrWhiteSpace($global:OSDCoreDevice.ProcessorArchitecture)) {
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
    # Keep the function parameter aligned to the effective value used downstream.
    $OSArchitecture = $processorArchitecture
    #=================================================
    # OSDCoreDevice
    if (-not ($global:OSDCoreDevice)) {
        Initialize-OSDCoreDevice
    }
    #=================================================
    # OSDCoreCache
    Initialize-OSDCoreCache
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
    #=================================================
    # Refactor variables for deployment workflow initialization
    $OSDManufacturer = $global:OSDCoreDevice.OSDManufacturer
    $OSDModel = $global:OSDCoreDevice.OSDModel
    $OSDProduct = $global:OSDCoreDevice.OSDProduct
    #=================================================
    # OSDCoreDriverPacks
    Initialize-ModuleCoreDriverPacks -OSDManufacturer $OSDManufacturer
    if ($global:ModuleCoreDriverPacks) {
        $global:OSDCoreDriverPackCloudObject = $global:ModuleCoreDriverPacks | Where-Object { $_.SystemId -match $OSDProduct } | Select-Object -First 1
    }

    if ($global:OSDCoreDriverPackCloudObject) {
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] OSDManufacturer: $OSDManufacturer"
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] OSDModel: $OSDModel"
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] OSDProduct: $OSDProduct"
        $DriverPackName = $global:OSDCoreDriverPackCloudObject.Name
        $DriverPackUrl = $global:OSDCoreDriverPackCloudObject.Url
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] DriverPack: $DriverPackName"
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] DriverPack Url: $DriverPackUrl"
    }
    else {
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] OSDManufacturer: $OSDManufacturer"
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] OSDModel: $OSDModel"
        Write-Host -ForegroundColor Gray "[$(Get-Date -format s)] [INFO] OSDProduct: $OSDProduct"
    }
    #=================================================
    # OSDCoreDriverPacks Verify
    if ($global:OSDCoreDriverPackCloudObject) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Verifying OSDCoreDriverPackCloudObject."
        $OSDCoreDriverPackCloudObjectUrlReachable = Test-OSDCoreDriverPackCloudObject -DriverPackCloudObject $global:OSDCoreDriverPackCloudObject
        if ($OSDCoreDriverPackCloudObjectUrlReachable) {
            Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] DriverPack is available online and ready to downloaded."
        }
        else {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] DriverPack URL is not reachable online and cannot be downloaded."
        }

        # Driver pack catalogs use either HashMD5 or MD5Hash depending on the source.
        $expectedDriverPackHashMD5 = $null
        if ($global:OSDCoreDriverPackCloudObject.PSObject.Properties.Match('HashMD5').Count -gt 0) {
            $expectedDriverPackHashMD5 = [string]$global:OSDCoreDriverPackCloudObject.HashMD5
        }
        elseif ($global:OSDCoreDriverPackCloudObject.PSObject.Properties.Match('MD5Hash').Count -gt 0) {
            $expectedDriverPackHashMD5 = [string]$global:OSDCoreDriverPackCloudObject.MD5Hash
        }

        # Check whether the selected driver pack is already present in the cache inventory.
        $OSDCoreDriverPackCacheObject = Get-OSDCoreDriverPackCacheObject -DriverPackCloudObject $global:OSDCoreDriverPackCloudObject
        if ($OSDCoreDriverPackCacheObject) {
            # Verify cached driver pack integrity when the catalog includes an MD5 hash.
            if (-not [string]::IsNullOrWhiteSpace($expectedDriverPackHashMD5)) {
                $actualDriverPackHashMD5 = (Get-FileHash -Path $OSDCoreDriverPackCacheObject.FullName -Algorithm MD5 -ErrorAction Stop).Hash
                if ($actualDriverPackHashMD5 -ne $expectedDriverPackHashMD5.Trim()) {
                    throw "[$(Get-Date -format s)] DriverPack MD5 hash mismatch for $($OSDCoreDriverPackCacheObject.FullName). Expected $($expectedDriverPackHashMD5.Trim()), found $actualDriverPackHashMD5."
                }
                Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] DriverPack is saved in cache and MD5 hash verified."
            }
            else {
                Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] DriverPack is saved in cache."
            }
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($OSDCoreDriverPackCacheObject.FullName)"
        }
        else {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] DriverPack is not available offline in cache."
            $OSDCoreDriverPackCacheObject = $null
        }
        $global:OSDCoreDriverPackCloudObject | Format-List | Out-Host
    }
    else {
        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OSDCoreDriverPackCloudObject is not set."
        Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OSDCloud will not apply a DriverPack for this deployment."
        $OSDCoreDriverPackCacheObject = $null
    }
    #=================================================
    # OSDCoreOperatingSystems
    $ModuleName = $($MyInvocation.MyCommand.Module.Name)
    if ($ModuleName -eq 'OSD') {
        $global:OSDCoreOperatingSystems = Get-OSDCoreOperatingSystems |
        Where-Object { $_.Architecture -match "$OSArchitecture" }
    }
    elseif ($ModuleName -eq 'OSDCloud') {
        $global:OSDCoreOperatingSystems = Get-OSDCloudCoreOperatingSystems |
        Where-Object { $_.OSArchitecture -match "$OSArchitecture" }
    }
    else {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to load core operating systems provider command."
    }
    #=================================================
    # OSDCloudWorkflowSettingsOS
    # This function will read a configuration file and store it in $OSDCloudWorkflowSettingsOS
    Initialize-OSDCloudWorkflowSettingsOS -WorkflowName $WorkflowName -Architecture $OSArchitecture

    # Example output of $OSDCloudWorkflowSettingsOS in JSON format for reference:
    <#
        PS C:\Users\david> $OSDCloudWorkflowSettingsOS | ConvertTo-Json
        {
            "OperatingSystem": {
                "default": "Windows 11 25H2",
                "values": [
                    "Windows 11 25H2",
                    "Windows 11 24H2",
                    "Windows 11 23H2"
                ]
            },
            "OSActivation": {
                "default": "Retail",
                "values": [
                    "Retail",
                    "Volume"
                ]
            },
            "OSLanguageCode": {
                "default": "en-us",
                "values": [
                    "ar-sa",
                    "bg-bg",
                    "cs-cz",
                    "da-dk",
                    "de-de",
                    "el-gr",
                    "en-gb",
                    "en-us",
                    "es-es",
                    "es-mx",
                    "et-ee",
                    "fi-fi",
                    "fr-ca",
                    "fr-fr",
                    "he-il",
                    "hr-hr",
                    "hu-hu",
                    "it-it",
                    "ja-jp",
                    "ko-kr",
                    "lt-lt",
                    "lv-lv",
                    "nb-no",
                    "nl-nl",
                    "pl-pl",
                    "pt-br",
                    "pt-pt",
                    "ro-ro",
                    "ru-ru",
                    "sk-sk",
                    "sl-si",
                    "sr-latn-rs",
                    "sv-se",
                    "th-th",
                    "tr-tr",
                    "uk-ua",
                    "zh-cn",
                    "zh-tw"
                ]
            }
        }
    #>

    # Apply workflow OS constraints to the loaded catalog for this architecture.
    $allowedOperatingSystems = @($global:OSDCloudWorkflowSettingsOS.OperatingSystem.values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $allowedOSActivations = @($global:OSDCloudWorkflowSettingsOS.OSActivation.values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $allowedOSEditionObjects = @($global:OSDCloudWorkflowSettingsOS.OSEdition.values)
    $allowedOSEditions = @($allowedOSEditionObjects | ForEach-Object { [string]$_.Edition } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $allowedOSLanguageCodes = @($global:OSDCloudWorkflowSettingsOS.OSLanguageCode.values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    $global:OSDCoreOperatingSystems = @(
        $global:OSDCoreOperatingSystems | Where-Object {
            ($allowedOperatingSystems.Count -eq 0 -or $allowedOperatingSystems -contains [string]$_.OperatingSystem) -and
            ($allowedOSActivations.Count -eq 0 -or $allowedOSActivations -contains [string]$_.OSActivation) -and
            ($allowedOSLanguageCodes.Count -eq 0 -or $allowedOSLanguageCodes -contains [string]$_.OSLanguageCode)
        }
    )

    if (-not $global:OSDCoreOperatingSystems) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No Operating Systems remain after applying workflow OS filters. Check workflow/$WorkflowName/ui/os.json values for OperatingSystem, OSActivation, and OSLanguageCode."
    }

    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Filtered OSDCoreOperatingSystems Count: $(@($global:OSDCoreOperatingSystems).Count)"
    #=================================================
    # $global:OSDCoreOperatingSystemCloudObject
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

    if (-not [string]::IsNullOrWhiteSpace($requestedOperatingSystem)) {
        $preferredOperatingSystem = $requestedOperatingSystem
    }
    if (-not [string]::IsNullOrWhiteSpace($requestedOSEdition)) {
        $preferredOSEdition = $requestedOSEdition
    }
    if (-not [string]::IsNullOrWhiteSpace($requestedOSActivation)) {
        $preferredOSActivation = $requestedOSActivation
    }
    if (-not [string]::IsNullOrWhiteSpace($requestedOSLanguageCode)) {
        $preferredOSLanguageCode = $requestedOSLanguageCode
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

    $global:OSDCoreOperatingSystemCloudObject = $global:OSDCoreOperatingSystems |
    Where-Object {
        ([string]$_.OperatingSystem -ieq $preferredOperatingSystem) -and
        ([string]$_.OSActivation -ieq $preferredOSActivation) -and
        ([string]$_.OSLanguageCode -ieq $preferredOSLanguageCode)
    } |
    Sort-Object -Property @{ Expression = {
            try {
                [version]([string]$_.OSBuildVersion -replace '[^0-9\.]', '')
            }
            catch {
                [version]'0.0'
            }
        }; Descending                   = $true
    } |
    Select-Object -First 1

    if (-not $global:OSDCoreOperatingSystemCloudObject) {
        Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No exact operating system match was found for OperatingSystem '$preferredOperatingSystem', OSActivation '$preferredOSActivation', and OSLanguageCode '$preferredOSLanguageCode'. Falling back to the first available filtered catalog entry."
        $global:OSDCoreOperatingSystemCloudObject = $global:OSDCoreOperatingSystems |
        Sort-Object -Property @{ Expression = {
                try {
                    [version]([string]$_.OSBuildVersion -replace '[^0-9\.]', '')
                }
                catch {
                    [version]'0.0'
                }
            }; Descending                   = $true
        } |
        Select-Object -First 1
    }

    if (-not $global:OSDCoreOperatingSystemCloudObject) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to set OSDCoreOperatingSystemCloudObject because no operating system entries are available in the filtered catalog."
    }
    # $null = Set-OSDCoreOperatingSystemCloudObject -OSArchitecture $OSArchitecture
    # $global:OSDCoreOperatingSystemCloudObject | Format-List | Out-Host
    #=================================================
    # OSDCoreOperatingSystems Verify
    if ($global:OSDCoreOperatingSystemCloudObject) {
        $global:OSDCoreOperatingSystemCloudObject | Export-Clixml -Path (Join-Path -Path $env:TEMP -ChildPath 'OSDCoreOperatingSystemCloudObject.xml') -Force
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Verifying cloud Operating System."
        # Confirm the selected operating system download URL before offering cache download work.
        $OSDCoreOperatingSystemCloudObjectUrlReachable = Test-OSDCoreOperatingSystemCloudObject -OperatingSystemCloudObject $global:OSDCoreOperatingSystemCloudObject
        if ($OSDCoreOperatingSystemCloudObjectUrlReachable) {
            Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] OperatingSystem is available online and ready to downloaded."
        }
        else {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OperatingSystem URL is not reachable online and cannot be downloaded."
        }

        # Prefer SHA256 when the catalog provides it, and fall back to SHA1 for older entries.
        $expectedOperatingSystemHash = $null
        $expectedOperatingSystemHashAlgorithm = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$global:OSDCoreOperatingSystemCloudObject.SHA256)) {
            $expectedOperatingSystemHash = [string]$global:OSDCoreOperatingSystemCloudObject.SHA256
            $expectedOperatingSystemHashAlgorithm = 'SHA256'
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$global:OSDCoreOperatingSystemCloudObject.SHA1)) {
            $expectedOperatingSystemHash = [string]$global:OSDCoreOperatingSystemCloudObject.SHA1
            $expectedOperatingSystemHashAlgorithm = 'SHA1'
        }

        # Check whether the selected OS payload is already present in the USB cache inventory.
        $OSDCoreOperatingSystemCacheObject = Get-OSDCoreOperatingSystemCacheObject -OperatingSystemCloudObject $global:OSDCoreOperatingSystemCloudObject
        if ($OSDCoreOperatingSystemCacheObject) {
            $OSDCoreOperatingSystemCacheObject | Export-Clixml -Path (Join-Path -Path $env:TEMP -ChildPath 'OSDCoreOperatingSystemCacheObject.xml') -Force
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Verifying cache Operating System."
            # Verify the cached payload before treating it as ready.
            if (-not [string]::IsNullOrWhiteSpace($expectedOperatingSystemHash)) {
                $actualOperatingSystemHash = (Get-FileHash -Path $OSDCoreOperatingSystemCacheObject.FullName -Algorithm $expectedOperatingSystemHashAlgorithm -ErrorAction Stop).Hash
                if ($actualOperatingSystemHash -ne $expectedOperatingSystemHash.Trim()) {
                    throw "[$(Get-Date -format s)] OSDCoreOperatingSystemCloudObject $expectedOperatingSystemHashAlgorithm hash mismatch for $($OSDCoreOperatingSystemCacheObject.FullName). Expected $($expectedOperatingSystemHash.Trim()), found $actualOperatingSystemHash."
                }
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem is saved in cache and $expectedOperatingSystemHashAlgorithm hash verified."
            }
            else {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem cached file hash was not verified because no hash property was available."
            }
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($OSDCoreOperatingSystemCacheObject.FullName)"
        }
        else {
            Write-Host -ForegroundColor DarkYellow "[$(Get-Date -format s)] [WARN] OperatingSystem is not available offline in cache."
        }
        # Build a display object that supports both OSD and OSDCloud property shapes.
        $selectedOperatingSystemName = if ($global:OSDCoreOperatingSystemCloudObject.Id) { $global:OSDCoreOperatingSystemCloudObject.Id } else { $global:OSDCoreOperatingSystemCloudObject.Name }
        $selectedOperatingSystemUrl = if ($global:OSDCoreOperatingSystemCloudObject.FilePath) { $global:OSDCoreOperatingSystemCloudObject.FilePath } else { $global:OSDCoreOperatingSystemCloudObject.Url }
        $selectedOperatingSystemSha1 = if ($global:OSDCoreOperatingSystemCloudObject.Sha1) { $global:OSDCoreOperatingSystemCloudObject.Sha1 } else { $global:OSDCoreOperatingSystemCloudObject.SHA1 }
        $selectedOperatingSystemSha256 = if ($global:OSDCoreOperatingSystemCloudObject.Sha256) { $global:OSDCoreOperatingSystemCloudObject.Sha256 } else { $global:OSDCoreOperatingSystemCloudObject.SHA256 }

        # Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] OSDCoreOperatingSystemCloudObject:"
        $tempOperatingSystemDisplay = [ordered]@{
            Name     = [string]$selectedOperatingSystemName
            FileName = [string]$global:OSDCoreOperatingSystemCloudObject.FileName
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
    # Update WorkflowTaskObject and WorkflowTaskName in the Init global variable
    $WorkflowTaskObject = $global:OSDCloudWorkflowTasks | Select-Object -First 1
    $WorkflowTaskName = $WorkflowTaskObject.name
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
    $OperatingSystemValues = [array]$allowedOperatingSystems
    $OSActivationValues = [array]$allowedOSActivations
    $OSArchitecture = $processorArchitecture
    $OSEdition = $preferredOSEdition
    $OSEditionValues = [array]$allowedOSEditionObjects
    $OSEditionId = $null
    $OSLanguageCodeValues = [array]$allowedOSLanguageCodes
    #=================================================
    # OperatingSystemObject
    $OperatingSystemObject = $global:OSDCoreOperatingSystemCloudObject
    if (-not $OperatingSystemObject) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to initialize deployment state because OSDCoreOperatingSystemCloudObject is not set."
    }

    $OperatingSystem = if ($OperatingSystemObject.OperatingSystem) {
        [string]$OperatingSystemObject.OperatingSystem
    }
    else {
        $preferredOperatingSystem
    }
    $OSActivation = if ($OperatingSystemObject.OSActivation) {
        [string]$OperatingSystemObject.OSActivation
    }
    elseif ($OperatingSystemObject.Activation) {
        [string]$OperatingSystemObject.Activation
    }
    else {
        $preferredOSActivation
    }
    $OSLanguageCode = if ($OperatingSystemObject.OSLanguageCode) {
        [string]$OperatingSystemObject.OSLanguageCode
    }
    elseif ($OperatingSystemObject.Language) {
        [string]$OperatingSystemObject.Language
    }
    else {
        $preferredOSLanguageCode
    }
    $OSVersion = if ($OperatingSystemObject.OSVersion) {
        [string]$OperatingSystemObject.OSVersion
    }
    elseif ($OperatingSystemObject.ReleaseID) {
        [string]$OperatingSystemObject.ReleaseID
    }
    else {
        ($OperatingSystem -split ' ')[2]
    }
    $OSEditionObject = $OSEditionValues | Where-Object { $_.Edition -eq $OSEdition } | Select-Object -First 1
    if (-not $OSEditionObject) {
        $validOSEditions = $OSEditionValues | ForEach-Object { $_.Edition }
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSEdition '$OSEdition' is not valid for workflow '$WorkflowName'. Valid values: $($validOSEditions -join ', ')"
    }
    if ([string]::IsNullOrWhiteSpace([string]$OSEditionObject.EditionId)) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSEdition '$OSEdition' does not have a valid EditionId in workflow '$WorkflowName'."
    }

    $OSEditionId = $OSEditionObject.EditionId
    $OSBuild = if ($OperatingSystemObject.OSBuild) {
        [string]$OperatingSystemObject.OSBuild
    }
    else {
        [string]$OperatingSystemObject.Build
    }
    $OSBuildVersion = if ($OperatingSystemObject.OSBuildVersion) {
        [string]$OperatingSystemObject.OSBuildVersion
    }
    else {
        [string]$OperatingSystemObject.Build
    }
    $ImageFileName = [string]$OperatingSystemObject.FileName
    $ImageFileUrl = if ($OperatingSystemObject.FilePath) {
        [string]$OperatingSystemObject.FilePath
    }
    else {
        [string]$OperatingSystemObject.Url
    }
    #=================================================
    # Get-DeploymentDiskObject
    $DeploymentDiskObject = Get-DeploymentDiskObject

    # Make sure Get-DeploymentDiskObject returns a single object
    if (-not $DeploymentDiskObject) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSDCloud requires at least one Local Disk, but no compatible Local Disk was found."
    }
    # Warn if multiple disks found and inform which disk will be used
    # Include the Friendly Name of the disk for clarity
    # Include the size in GB for clarity
    if (@($DeploymentDiskObject).Count -gt 1) {
        Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Multiple Local Disks were found. OSDCloud will default to DiskNumber: $($DeploymentDiskObject[0].DiskNumber)"
        $DeploymentDiskObject | ForEach-Object {
            Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DiskNumber: $($_.DiskNumber), FriendlyName: $($_.FriendlyName), Size(GB): $([math]::Round($_.Size / 1GB, 2))"
        }
    }
    # Limit to the first disk found
    $DeploymentDiskObject = $DeploymentDiskObject | Select-Object -First 1
    #=================================================
    # Main
    $global:OSDCloudDeploy = $null
    $global:OSDCloudDeploy = [ordered]@{
        DeploymentDiskObject   = $DeploymentDiskObject
        DriverFolderName       = $null
        DriverFolderNames      = @()
        DriverFolderPath       = $null
        DriverFolderPaths      = @()
        DriverFolderSelections = @()
        DriverPackName         = $DriverPackName
        DriverPackObject       = $global:OSDCoreDriverPackCloudObject
        DriverPackValues       = [array]$global:ModuleCoreDriverPacks
        Flows                  = [array]$global:OSDCloudWorkflowTasks
        Function               = $($MyInvocation.MyCommand.Name)
        ImageFileName          = $ImageFileName
        ImageFileUrl           = $ImageFileUrl
        LaunchMethod           = 'OSDCloudWorkflow'
        Module                 = $($MyInvocation.MyCommand.Module.Name)
        OperatingSystem        = $OperatingSystem
        OperatingSystemObject  = $OperatingSystemObject
        OperatingSystemValues  = $OperatingSystemValues
        OSActivation           = $OSActivation
        OSActivationValues     = $OSActivationValues
        OSArchitecture         = $OSArchitecture
        OSBuild                = $OSBuild
        OSBuildVersion         = $OSBuildVersion
        OSEdition              = $OSEdition
        OSEditionId            = $OSEditionId
        OSEditionValues        = $OSEditionValues
        OSLanguageCode         = $OSLanguageCode
        OSLanguageCodeValues   = $OSLanguageCodeValues
        OSVersion              = $OSVersion
        TimeStart              = $null
        WorkflowName           = $WorkflowName
        WorkflowTaskName       = $WorkflowTaskName
        WorkflowTaskObject     = $WorkflowTaskObject
    }
    #=================================================
    # OSDCloud Env override layer
    # Apply the pre-assembled overrides onto $global:OSDCloudDeploy so they take effect
    # everywhere.
    if (Get-Command -Name 'Set-OSDCloudEnvOverride' -ErrorAction SilentlyContinue) {
        Set-OSDCloudEnvOverride -Target $global:OSDCloudDeploy -ResolveOperatingSystem -AddMissingKeys
    }
    $global:OSDCloudDeploy | Export-Clixml -Path (Join-Path -Path $env:TEMP -ChildPath 'OSDCloudDeploy.xml') -Force
    #=================================================
}
