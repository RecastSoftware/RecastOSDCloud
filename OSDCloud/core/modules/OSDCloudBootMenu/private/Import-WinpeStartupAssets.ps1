#requires -Version 5.1

function Import-WinpeStartupAssets {
    <#
    .SYNOPSIS
        Imports WinpeStartup environment, registry, and root-certificate files.

    .DESCRIPTION
        Imports immediate *.env files, winpe-reg\*.reg files, and
        winpe-root-cer\*.cer files from explicit source folders in WinPE.
        Includes hidden files and sorts full paths within each asset type.
        Environment entries are literal process-scoped NAME=VALUE assignments.
        Invalid entries, discovery failures, and import failures warn and continue.
        Values and native tool output are not logged.
        Requires a valid Recast license (Get-OSDCoreLicense IsValid). Without one,
        skips all asset discovery and imports quietly.

    .PARAMETER Path
        Source folders containing assets. An empty list is allowed.

    .PARAMETER AssetType
        Asset types to import, in environment, registry, certificate order.

    .PARAMETER DiscoverySucceeded
        Whether upstream folder discovery succeeded. A failed discovery marks
        each requested asset-type summary as failed while importing known files.

    .PARAMETER SystemDrive
        System drive captured by the caller before applying environment overrides.
        Defaults to the current SystemDrive for direct calls.

    .EXAMPLE
        Import-WinpeStartupAssets -Path 'H:\WinpeStartup\profiles\BranchOffice'

        Imports assets from the selected profile folder.

    .NOTES
        Requires WinPE, reg.exe, certutil.exe, and permission to modify the
        WinPE registry and local machine Root certificate store.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Path,

        [Parameter()]
        [ValidateSet('Environment', 'Registry', 'Certificate')]
        [string[]]$AssetType = @('Environment', 'Registry', 'Certificate'),

        [Parameter()]
        [bool]$DiscoverySucceeded = $true,

        [Parameter()]
        [string]$SystemDrive = $env:SystemDrive
    )

    $Error.Clear()
    if (-not (Test-WinpeStartupAssetLicense)) {
        return
    }
    if ($SystemDrive -ne 'X:') {
        Write-Warning 'Import-WinpeStartupAssets: Not running in WinPE (SystemDrive is not X:). Exiting.'
        return
    }
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Importing startup assets"

    if ($AssetType -contains 'Environment') {
        $allEnvironmentImportsSucceeded = $DiscoverySucceeded
        $environmentFiles = @(
            foreach ($folderPath in $Path) {
                try {
                    if (Test-Path -LiteralPath $folderPath -PathType Container -ErrorAction Stop) {
                        Get-ChildItem -LiteralPath $folderPath -File -Filter '*.env' -Force -ErrorAction Stop |
                            Where-Object { $_.Name -like '*.env' }
                    }
                }
                catch {
                    $allEnvironmentImportsSucceeded = $false
                    Write-Warning "Import-WinpeStartupAssets: Failed to discover environment files in '$folderPath'."
                }
            }
        )

        foreach ($environmentFile in ($environmentFiles | Sort-Object FullName)) {
            try {
                $environmentLines = @(Get-Content -LiteralPath $environmentFile.FullName -ErrorAction Stop)
            }
            catch {
                $allEnvironmentImportsSucceeded = $false
                Write-Warning "Import-WinpeStartupAssets: Failed to read environment file '$($environmentFile.FullName)'."
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
                    $allEnvironmentImportsSucceeded = $false
                    Write-Warning "Import-WinpeStartupAssets: Invalid environment entry in '$($environmentFile.FullName)' at line $lineNumber. Expected NAME=VALUE."
                    continue
                }

                $name = $line.Substring(0, $separatorIndex).Trim()
                $value = $line.Substring($separatorIndex + 1).Trim()
                if ($name -match '[\s=\x00]' -or [string]::IsNullOrWhiteSpace($name) -or $value.Contains([char]0)) {
                    $allEnvironmentImportsSucceeded = $false
                    Write-Warning "Import-WinpeStartupAssets: Invalid environment name or value in '$($environmentFile.FullName)' at line $lineNumber."
                    continue
                }

                if ($value.StartsWith('"') -or $value.StartsWith("'")) {
                    if ($value.Length -lt 2 -or $value[$value.Length - 1] -ne $value[0]) {
                        $allEnvironmentImportsSucceeded = $false
                        Write-Warning "Import-WinpeStartupAssets: Unmatched environment value quotes in '$($environmentFile.FullName)' at line $lineNumber."
                        continue
                    }
                    $value = $value.Substring(1, $value.Length - 2)
                }

                try {
                    [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Process)
                    Write-Verbose "Import-WinpeStartupAssets: Loaded environment entry from '$($environmentFile.FullName)' at line $lineNumber."
                }
                catch {
                    $allEnvironmentImportsSucceeded = $false
                    Write-Warning "Import-WinpeStartupAssets: Failed to set environment entry from '$($environmentFile.FullName)' at line $lineNumber."
                }
            }
        }

        if ($environmentFiles.Count -gt 0 -or -not $allEnvironmentImportsSucceeded) {
            $environmentStatus = if ($allEnvironmentImportsSucceeded) { 'PASS' } else { 'FAIL' }
            Write-Host "[$(Get-Date -format s)] [$environmentStatus] Initialize env"
        }
    }

    $nativeImports = @(
        @{
            Type       = 'Registry'
            Folder     = 'winpe-reg'
            Filter     = '*.reg'
            Executable = 'reg.exe'
            Arguments  = @('import')
            Status     = 'Initialize registry'
        }
        @{
            Type       = 'Certificate'
            Folder     = 'winpe-root-cer'
            Filter     = '*.cer'
            Executable = 'certutil.exe'
            Arguments  = @('-addstore', 'root')
            Status     = 'Initialize certificates'
        }
    )

    foreach ($nativeImport in $nativeImports) {
        if ($AssetType -notcontains $nativeImport.Type) {
            continue
        }
        $allImportsSucceeded = $DiscoverySucceeded
        $importFiles = @(
            foreach ($folderPath in $Path) {
                $importPath = Join-Path -Path $folderPath -ChildPath $nativeImport.Folder
                try {
                    if (Test-Path -LiteralPath $importPath -PathType Container -ErrorAction Stop) {
                        Get-ChildItem -LiteralPath $importPath -File -Filter $nativeImport.Filter -Force -ErrorAction Stop |
                            Where-Object { $_.Name -like $nativeImport.Filter }
                    }
                }
                catch {
                    $allImportsSucceeded = $false
                    Write-Warning "Import-WinpeStartupAssets: Failed to discover '$($nativeImport.Filter)' files in '$importPath'."
                }
            }
        )

        foreach ($importFile in ($importFiles | Sort-Object FullName)) {
            $standardOutputPath = $null
            $standardErrorPath = $null
            try {
                # Start-Process joins arguments, so retain quotes around paths with spaces.
                $importArguments = @($nativeImport.Arguments) + @("`"$($importFile.FullName)`"")
                $startProcessParameters = @{
                    FilePath     = $nativeImport.Executable
                    ArgumentList = $importArguments
                    NoNewWindow  = $true
                    Wait         = $true
                    PassThru     = $true
                    ErrorAction  = 'Stop'
                }
                $standardOutputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "$([System.IO.Path]::GetRandomFileName()).stdout"
                $standardErrorPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "$([System.IO.Path]::GetRandomFileName()).stderr"
                $startProcessParameters.RedirectStandardOutput = $standardOutputPath
                $startProcessParameters.RedirectStandardError = $standardErrorPath

                $importProcess = Start-Process @startProcessParameters
                if ($importProcess.ExitCode -ne 0) {
                    $allImportsSucceeded = $false
                    Write-Warning "Import-WinpeStartupAssets: '$($nativeImport.Executable)' failed for '$($importFile.FullName)' with exit code $($importProcess.ExitCode)."
                    continue
                }
                Write-Verbose "Import-WinpeStartupAssets: Imported '$($importFile.FullName)' using '$($nativeImport.Executable)'."
            }
            catch {
                $allImportsSucceeded = $false
                Write-Warning "Import-WinpeStartupAssets: Failed to import '$($importFile.FullName)' using '$($nativeImport.Executable)': $($_.Exception.Message)"
            }
            finally {
                @($standardOutputPath, $standardErrorPath) |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
            }
        }

        if ($importFiles.Count -gt 0 -or -not $allImportsSucceeded) {
            $importStatus = if ($allImportsSucceeded) { 'PASS' } else { 'FAIL' }
            Write-Host "[$(Get-Date -format s)] [$importStatus] $($nativeImport.Status)"
        }
    }
}
