#requires -Version 5.1

function Initialize-WinpeStartupEnvironment {
    <#
    .SYNOPSIS
        Initializes the WinPE shell environment for OS deployment

    .DESCRIPTION
        Creates required shell profile folders, sets process-level environment
        variables, and writes registry keys needed by Windows PE before any
        PowerShell modules or deployment scripts run.

        This function is the PowerShell equivalent of the environment-setup
        section in startnet.cmd / ReStartnet.cmd and should be called early
        in the WinPE boot sequence.

        Actions performed:
          - Imports X:\WinpeStartup\core\*\*.env into the process environment
          - Creates shell profile directories under SystemDrive
          - Sets APPDATA, HOMEDRIVE, HOMEPATH, LOCALAPPDATA, USERPROFILE
          - Writes the USERDATA registry value to the Session Manager Environment key
          - Sets the PowerShell execution policy to Bypass via registry
          - Imports X:\WinpeStartup\core\*\winpe-reg\*.reg using reg.exe import
          - Adds X:\WinpeStartup\core\*\winpe-root-cer\*.cer to the machine Root store

        Core files, including hidden files named .env, are loaded from immediate
        Core subfolders in sorted full-path order. Later assignments overwrite
        earlier values. Shell profile variables, selected-profile JSON environment
        values, and then selected-profile environment files are applied afterward
        and take precedence over Core values.

        Entries use literal, single-line NAME=VALUE syntax. Blank lines and
        full-line # comments are ignored. Surrounding whitespace and matching
        outer quotes are removed; embedded equals signs are preserved. Expressions,
        variable references, escape sequences, and inline comments are not expanded.
        Multiline values and export syntax are not supported. Empty values use
        the current runtime's process environment semantics (removal on PS 5.1).
        Invalid entries and file failures warn and continue without logging values.
        Missing Core content is allowed. Imported values are not persisted.
        Environment import output is summarized by one pass or fail message when
        files are discovered or discovery fails.

        After built-in registry setup, Core registry files are imported, followed
        by root certificates using certutil.exe -addstore root. Each file type is
        processed in sorted full-path order, including hidden files, without
        searching deeper folders. Missing import folders are allowed. Discovery,
        process launch, and nonzero exit-code failures warn and continue with
        remaining files. Registry imports may overwrite existing keys; certificates
        are trusted in the local machine Root store for the current WinPE instance.
        Registry and certificate tool output is suppressed and summarized by one
        pass or fail message for each file type.

        Core asset discovery and imports require a valid Recast license
        (Get-OSDCoreLicense IsValid). Missing or invalid licenses skip assets
        without errors, warnings, or asset summaries. Built-in shell setup
        remains available regardless of license state.

    .EXAMPLE
        PS> Initialize-WinpeStartupEnvironment

        Imports Core environment files, creates shell folders, sets environment
        variables, and writes registry keys for the current WinPE session.

    .EXAMPLE
        PS> Initialize-WinpeStartupEnvironment -Verbose

        Runs the full environment initialization with detailed progress output.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-10-06
        Module:  OSDCloud
        Runs only when SystemDrive is X:.
        Core imports require reg.exe and certutil.exe and permission to modify
        the WinPE registry and local machine certificate store.

    .LINK
        https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-import

    .LINK
        https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    begin {
        $skipExecution = $false
        if ($env:SystemDrive -ne 'X:') {
            Write-Warning 'Initialize-WinpeStartupEnvironment: Not running in WinPE (SystemDrive is not X:). Exiting.'
            $skipExecution = $true
            return
        }

        Write-Verbose 'Initialize-WinpeStartupEnvironment: Starting WinPE environment initialization'

        $systemDrive = $env:SystemDrive
        $profileRoot = Join-Path -Path $systemDrive -ChildPath 'windows\system32\config\systemprofile'
    }

    process {
        if ($skipExecution) { return }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Initialize WinpeStartup"

        $corePath = Join-Path -Path $systemDrive -ChildPath 'WinpeStartup\core'
        $coreFolders = @()
        $coreDiscoverySucceeded = $true
        $canImportAssets = Test-WinpeStartupAssetLicense
        if ($canImportAssets) {
            try {
                if (Test-Path -LiteralPath $corePath -PathType Container -ErrorAction Stop) {
                    $coreFolders = @(Get-ChildItem -LiteralPath $corePath -Directory -Force -ErrorAction Stop)
                }
            }
            catch {
                $coreDiscoverySucceeded = $false
                Write-Warning "Initialize-WinpeStartupEnvironment: Failed to discover Core folders in '$corePath'."
            }

            $assetPaths = @($coreFolders | ForEach-Object { $_.FullName })
            Import-WinpeStartupAssets -Path $assetPaths -AssetType Environment -DiscoverySucceeded $coreDiscoverySucceeded -SystemDrive $systemDrive
        }

        # ── Shell Folders ───────────────────────────────────────────────
        $shellFolders = @(
            Join-Path -Path $systemDrive -ChildPath 'Program Files\WindowsPowerShell\Scripts'
            Join-Path -Path $profileRoot -ChildPath 'AppData\Local'
            Join-Path -Path $profileRoot -ChildPath 'AppData\Roaming'
            Join-Path -Path $profileRoot -ChildPath 'Desktop'
            Join-Path -Path $profileRoot -ChildPath 'Documents\WindowsPowerShell'
            Join-Path -Path $systemDrive -ChildPath 'windows\system32\WindowsPowerShell\v1.0\Scripts'
        )

        foreach ($folder in $shellFolders) {
            New-Item -Path $folder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            # Write-Verbose "Created folder: $folder"
        }

        # ── Environment Variables (process scope) ───────────────────────
        $env:APPDATA      = Join-Path -Path $profileRoot -ChildPath 'AppData\Roaming'
        $env:HOMEDRIVE    = $systemDrive
        $env:HOMEPATH     = '\windows\system32\config\systemprofile'
        $env:LOCALAPPDATA = Join-Path -Path $profileRoot -ChildPath 'AppData\Local'
        $env:USERPROFILE  = $profileRoot

        Write-Verbose "Set APPDATA      = $env:APPDATA"
        Write-Verbose "Set HOMEDRIVE    = $env:HOMEDRIVE"
        Write-Verbose "Set HOMEPATH     = $env:HOMEPATH"
        Write-Verbose "Set LOCALAPPDATA = $env:LOCALAPPDATA"
        Write-Verbose "Set USERPROFILE  = $env:USERPROFILE"

        # ── Registry: USERDATA environment variable ─────────────────────
        $userDataPath  = Join-Path -Path $systemDrive -ChildPath 'Windows\System32\Config\SystemProfile'
        $envRegKeyPath = 'HKLM:\SYSTEM\ControlSet001\Control\Session Manager\Environment'

        Set-ItemProperty -Path $envRegKeyPath -Name 'USERDATA' -Value $userDataPath -Type String -Force
        Write-Verbose "Set registry USERDATA = $userDataPath"

        # ── Registry: PowerShell execution policy ───────────────────────
        $psRegKeyPath = 'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'

        Set-ItemProperty -Path $psRegKeyPath -Name 'ExecutionPolicy' -Value 'Bypass' -Type String -Force
        Write-Verbose 'Set registry ExecutionPolicy = Bypass'

        if ($canImportAssets) {
            Import-WinpeStartupAssets -Path $assetPaths -AssetType Registry, Certificate -DiscoverySucceeded $coreDiscoverySucceeded -SystemDrive $systemDrive
        }
    }

    end {
        if ($skipExecution) { return }
        Write-Verbose 'Initialize-WinpeStartupEnvironment: Complete'
    }
}
