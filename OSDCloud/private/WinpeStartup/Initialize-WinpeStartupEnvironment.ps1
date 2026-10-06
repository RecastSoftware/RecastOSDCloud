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

        Core files, including hidden files named .env, are loaded from immediate
        Core subfolders in sorted full-path order. Later assignments overwrite
        earlier values. Shell profile variables and the selected startup profile
        are applied afterward and take precedence over Core values.

        Entries use literal, single-line NAME=VALUE syntax. Blank lines and
        full-line # comments are ignored. Surrounding whitespace and matching
        outer quotes are removed; embedded equals signs are preserved. Expressions,
        variable references, escape sequences, and inline comments are not expanded.
        Multiline values and export syntax are not supported. Empty values use
        the current runtime's process environment semantics (removal on PS 5.1).
        Invalid entries and file failures warn and continue without logging values.
        Missing Core content is allowed. Imported values are not persisted.

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
        try {
            if (Test-Path -LiteralPath $corePath -PathType Container -ErrorAction Stop) {
                $coreFolders = @(Get-ChildItem -LiteralPath $corePath -Directory -Force -ErrorAction Stop)
            }
        }
        catch {
            Write-Warning "Initialize-WinpeStartupEnvironment: Failed to discover Core folders in '$corePath'."
        }

        $environmentFiles = @(
            foreach ($coreFolder in $coreFolders) {
                try {
                    Get-ChildItem -LiteralPath $coreFolder.FullName -File -Filter '*.env' -Force -ErrorAction Stop |
                        Where-Object { $_.Name -like '*.env' }
                }
                catch {
                    Write-Warning "Initialize-WinpeStartupEnvironment: Failed to discover environment files in '$($coreFolder.FullName)'."
                }
            }
        )

        foreach ($environmentFile in ($environmentFiles | Sort-Object FullName)) {
            try {
                $environmentLines = @(Get-Content -LiteralPath $environmentFile.FullName -ErrorAction Stop)
            }
            catch {
                Write-Warning "Initialize-WinpeStartupEnvironment: Failed to read environment file '$($environmentFile.FullName)'."
                continue
            }

            $lineNumber = 0
            foreach ($environmentLine in $environmentLines) {
                $lineNumber++
                $line = $environmentLine.Trim()
                if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
                    continue
                }

                $separatorIndex = $line.IndexOf('=')
                if ($separatorIndex -le 0) {
                    Write-Warning "Initialize-WinpeStartupEnvironment: Invalid environment entry in '$($environmentFile.FullName)' at line $lineNumber. Expected NAME=VALUE."
                    continue
                }

                $name = $line.Substring(0, $separatorIndex).Trim()
                $value = $line.Substring($separatorIndex + 1).Trim()
                if ($name -match '[\s=\x00]' -or [string]::IsNullOrWhiteSpace($name) -or $value.Contains([char]0)) {
                    Write-Warning "Initialize-WinpeStartupEnvironment: Invalid environment name or value in '$($environmentFile.FullName)' at line $lineNumber."
                    continue
                }

                if ($value.StartsWith('"') -or $value.StartsWith("'")) {
                    if ($value.Length -lt 2 -or $value[$value.Length - 1] -ne $value[0]) {
                        Write-Warning "Initialize-WinpeStartupEnvironment: Unmatched environment value quotes in '$($environmentFile.FullName)' at line $lineNumber."
                        continue
                    }
                    $value = $value.Substring(1, $value.Length - 2)
                }

                try {
                    [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Process)
                    Write-Verbose "Initialize-WinpeStartupEnvironment: Loaded environment entry from '$($environmentFile.FullName)' at line $lineNumber."
                }
                catch {
                    Write-Warning "Initialize-WinpeStartupEnvironment: Failed to set environment entry from '$($environmentFile.FullName)' at line $lineNumber."
                }
            }
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
    }

    end {
        if ($skipExecution) { return }
        Write-Verbose 'Initialize-WinpeStartupEnvironment: Complete'
    }
}
