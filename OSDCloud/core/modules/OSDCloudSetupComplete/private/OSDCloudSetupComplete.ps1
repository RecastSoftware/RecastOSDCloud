function Write-OSDCloudSetupCompleteLog {
    <#
    .SYNOPSIS
        Appends timestamped runtime diagnostics

    .DESCRIPTION
        Writes UTF-8 diagnostics under Windows Temp. Log failures terminate.

    .PARAMETER Message
        Diagnostic text without credentials or argument values.

    .EXAMPLE
        PS> Write-OSDCloudSetupCompleteLog -Message 'Run completed.'

        Appends a diagnostic line.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$Message)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] $Message"
    $root = Join-Path $env:SystemRoot 'Temp\osdcloud-logs'
    [void][IO.Directory]::CreateDirectory($root)
    [IO.File]::AppendAllText((Join-Path $root 'OSDCloudSetupComplete.log'),
        "[$(Get-Date -Format s)] [PID $PID] $Message`r`n", [Text.Encoding]::UTF8)
}

function Assert-OSDCloudSetupCompleteContext {
    <#
    .SYNOPSIS
        Checks the supported execution context

    .DESCRIPTION
        Requires SYSTEM, full Windows, and Windows PowerShell 5.1.

    .EXAMPLE
        PS> Assert-OSDCloudSetupCompleteContext

        Throws when the execution context is unsupported.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
    #>
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Validate context"
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
        $PSVersionTable.PSVersion.Minor -ne 1 -or $env:SystemDrive -eq 'X:' -or
        (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT' -ErrorAction Stop)) {
        throw 'SetupComplete requires inbox Windows PowerShell 5.1 in full Windows.'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        if ($identity.User.Value -ne 'S-1-5-18') { throw 'SetupComplete requires the SYSTEM account.' }
    }
    finally { $identity.Dispose() }
}

function Get-OSDCloudSetupCompleteRoot {
    <#
    .SYNOPSIS
        Lists package discovery roots in execution order

    .DESCRIPTION
        Returns the local Windows Setup root followed by drive roots A through Z.

    .EXAMPLE
        PS> Get-OSDCloudSetupCompleteRoot

        Lists paths without executing packages.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String. Ordered package roots.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
    #>
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Discover roots"
    Join-Path $env:SystemRoot 'Setup\SetupComplete'
    foreach ($letter in 65..90) { "$([char]$letter):\OSDCloud\core\SetupComplete" }
}

function Resolve-OSDCloudSetupCompleteScript {
    <#
    .SYNOPSIS
        Validates the package entry script

    .DESCRIPTION
        Requires a direct .ps1 child of an absolute package folder. Rejects
        alternate streams, escaping paths, and reparse points in the path.

    .PARAMETER Folder
        Absolute package directory.

    .PARAMETER Script
        Entry script filename without directory components.

    .EXAMPLE
        PS> Resolve-OSDCloudSetupCompleteScript -Folder 'C:\Packages\Agent' -Script 'Install.ps1'

        Returns the validated script path.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String. Full script path.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Script
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Validate script"
    if (-not [IO.Path]::IsPathRooted($Folder) -or $Script.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        [IO.Path]::GetExtension($Script) -ne '.ps1') {
        throw 'Script must name a .ps1 file directly inside an absolute package folder.'
    }
    $path = Join-Path ([IO.Path]::GetFullPath($Folder)) $Script
    if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction Stop)) {
        throw "SetupComplete script is missing: $path"
    }
    $checkPath = $path
    while ($checkPath) {
        $item = Get-Item -LiteralPath $checkPath -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "SetupComplete path contains a reparse point: $checkPath"
        }
        $checkPath = Split-Path -Path $checkPath -Parent
    }
    return $path
}

function Read-OSDCloudSetupCompleteManifest {
    <#
    .SYNOPSIS
        Validates and filters a package configuration

    .DESCRIPTION
        Reads OSDCloudSetupComplete.json. Conditions use AND across fields and
        OR within each field. Returns nothing for disabled or nonmatching items.
        Invalid configurations and unavailable required device facts throw.

    .PARAMETER Folder
        Absolute directory containing the configuration and entry script.

    .PARAMETER Context
        Per-run cache for CIM and native architecture facts.

    .EXAMPLE
        PS> Read-OSDCloudSetupCompleteManifest -Folder 'C:\Packages\Agent' -Context @{}

        Returns an eligible package or logs a skip.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject. Validated eligible package.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][hashtable]$Context
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Read configuration"
    $manifestPath = Join-Path $Folder 'OSDCloudSetupComplete.json'
    if ((Get-Item -LiteralPath $manifestPath -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Configuration is a reparse point: $manifestPath"
    }
    $json = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($json) -or -not $json.TrimStart().StartsWith('{')) {
        throw 'SetupComplete configuration must be a JSON object.'
    }
    try { $manifest = $json | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'SetupComplete configuration contains invalid JSON.' }
    if ($manifest -isnot [pscustomobject]) { throw 'SetupComplete configuration must be a JSON object.' }
    foreach ($property in $manifest.PSObject.Properties.Name) {
        if ($property -notin 'Version','Name','Script','Arguments','Enabled','CopyToLocal','Conditions') {
            throw "Unknown SetupComplete configuration field: $property"
        }
    }
    if (($manifest.Version -isnot [int] -and $manifest.Version -isnot [long]) -or $manifest.Version -ne 1) {
        throw 'SetupComplete Version must be the integer 1.'
    }
    if ($manifest.Script -isnot [string] -or [string]::IsNullOrWhiteSpace($manifest.Script)) {
        throw 'SetupComplete Script must be a nonempty string.'
    }
    $name = Split-Path -Path $Folder -Leaf
    $arguments = ''
    $enabled = $true
    $copyToLocal = $false
    if ($manifest.PSObject.Properties['Name']) {
        if ($manifest.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($manifest.Name)) {
            throw 'SetupComplete Name must be a nonempty string.'
        }
        $name = $manifest.Name
    }
    if ($manifest.PSObject.Properties['Arguments']) {
        if ($manifest.Arguments -isnot [string] -or $manifest.Arguments -match '[\r\n]') {
            throw 'SetupComplete Arguments must be a single-line string.'
        }
        $arguments = $manifest.Arguments
    }
    foreach ($field in 'Enabled','CopyToLocal') {
        if ($manifest.PSObject.Properties[$field] -and $manifest.$field -isnot [bool]) {
            throw "SetupComplete $field must be a boolean."
        }
    }
    if ($manifest.PSObject.Properties['Enabled']) { $enabled = $manifest.Enabled }
    if ($manifest.PSObject.Properties['CopyToLocal']) { $copyToLocal = $manifest.CopyToLocal }
    $conditions = $manifest.Conditions
    if ($manifest.PSObject.Properties['Conditions'] -and $conditions -isnot [pscustomobject]) {
        throw 'SetupComplete Conditions must be an object.'
    }
    foreach ($condition in $conditions.PSObject.Properties) {
        if ($condition.Name -notin 'ComputerManufacturer','ComputerModel','OSArchitecture') {
            throw "Unknown SetupComplete condition: $($condition.Name)"
        }
        if (($condition.Value -isnot [string] -and $condition.Value -isnot [array]) -or @($condition.Value).Count -eq 0) {
            throw "Condition $($condition.Name) requires a string or nonempty string array."
        }
        foreach ($pattern in $condition.Value) {
            if ($pattern -isnot [string] -or [string]::IsNullOrWhiteSpace($pattern)) {
                throw "Condition $($condition.Name) contains an invalid value."
            }
            if ($condition.Name -eq 'OSArchitecture') {
                if ($pattern -notin 'amd64','arm64') { throw 'OSArchitecture must be amd64 or arm64.' }
            }
            else { [void][Management.Automation.WildcardPattern]::new($pattern, 'IgnoreCase') }
        }
    }
    $path = Resolve-OSDCloudSetupCompleteScript -Folder $Folder -Script $manifest.Script
    if (-not $enabled) {
        Write-OSDCloudSetupCompleteLog -Message "Skipped disabled package: $Folder"
        return
    }
    foreach ($condition in $conditions.PSObject.Properties) {
        if ($condition.Name -eq 'OSArchitecture') {
            if (-not $Context.ContainsKey('OSArchitecture')) {
                $Context.OSArchitecture = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
                    -Name PROCESSOR_ARCHITECTURE -ErrorAction Stop
            }
            $actual = $Context.OSArchitecture
            if ($actual -notin 'AMD64','ARM64') { throw 'Native OS architecture is missing or unsupported.' }
        }
        else {
            if (-not $Context.ContainsKey('ComputerSystem')) {
                $Context.ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -Property Manufacturer,Model -ErrorAction Stop
            }
            $actual = if ($condition.Name -eq 'ComputerManufacturer') { $Context.ComputerSystem.Manufacturer } else { $Context.ComputerSystem.Model }
            if ([string]::IsNullOrWhiteSpace($actual)) { throw "Device fact unavailable: $($condition.Name)" }
        }
        $matched = $false
        foreach ($pattern in $condition.Value) {
            if ($actual -ilike $pattern) { $matched = $true; break }
        }
        if (-not $matched) {
            Write-OSDCloudSetupCompleteLog -Message "Skipped package $Folder`: $($condition.Name) did not match."
            return
        }
    }
    [pscustomobject]@{
        Name = $name; Folder = $Folder; Script = $manifest.Script; Path = $path
        Arguments = $arguments; CopyToLocal = $copyToLocal
    }
}

function Invoke-OSDCloudSetupCompletePackage {
    <#
    .SYNOPSIS
        Runs a validated script in a separate noninteractive process

    .DESCRIPTION
        Optionally copies the complete package locally, then launches its script
        with Windows PowerShell -File. Retains copied content and stdout/stderr.
        Exit 3010 records reboot required without restarting Windows.

    .PARAMETER Package
        Package returned by the manifest reader.

    .EXAMPLE
        PS> Invoke-OSDCloudSetupCompletePackage -Package $package

        Waits for the package and returns its exit code.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Int32. Child exit code.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-04
        Scripts must throw on errors or explicitly exit nonzero to signal failure.
        Native tool failures must be checked by the script.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param ([Parameter(Mandatory)][pscustomobject]$Package)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Execute package"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $folder = $Package.Folder
    $path = Resolve-OSDCloudSetupCompleteScript -Folder $folder -Script $Package.Script
    if ($Package.CopyToLocal) {
        foreach ($item in Get-ChildItem -LiteralPath $folder -Recurse -Force -ErrorAction Stop) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Package contains a reparse point: $($item.FullName)"
            }
        }
        $copyRoot = Join-Path $env:SystemRoot "Temp\OSDCloudSetupComplete\$(Split-Path -Path $folder -Leaf)"
        $destination = $copyRoot
        $number = 1
        while (Test-Path -LiteralPath $destination -ErrorAction Stop) {
            $number++
            $destination = "$copyRoot-$number"
        }
        [void][IO.Directory]::CreateDirectory($destination)
        Write-OSDCloudSetupCompleteLog -Message "Copying $folder to $destination"
        foreach ($item in Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop) {
            Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
        }
        foreach ($item in @(Get-Item -LiteralPath $destination -Force -ErrorAction Stop) +
            @(Get-ChildItem -LiteralPath $destination -Recurse -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReadOnly) {
                $item.Attributes = $item.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
            }
        }
        $folder = $destination
        $path = Resolve-OSDCloudSetupCompleteScript -Folder $folder -Script $Package.Script
    }
    $logs = Join-Path $env:SystemRoot 'Temp\osdcloud-logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $id = [guid]::NewGuid().ToString('N')
    $output = Join-Path $logs "SetupComplete-$id.stdout.log"
    $errors = Join-Path $logs "SetupComplete-$id.stderr.log"
    $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe') -PathType Leaf) {
        $powerShell = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }
    Write-OSDCloudSetupCompleteLog -Message "Starting $($Package.Name): $path; stdout=$output; stderr=$errors"
    $process = $null
    try {
        $process = Start-Process -FilePath $powerShell -ArgumentList (
            "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$path`" " + $Package.Arguments
        ) -WorkingDirectory $folder -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $output -RedirectStandardError $errors -ErrorAction Stop
        if ($null -eq $process.ExitCode) { throw 'The child process did not return an exit code.' }
        $code = [int]$process.ExitCode
        $outcome = if ($code -eq 3010) { 'Succeeded; reboot required (not initiated)' }
            elseif ($code -eq 0) { 'Succeeded' } else { 'Failed' }
        Write-OSDCloudSetupCompleteLog -Message (
            "$outcome`: $($Package.Name); exit=$code; elapsed=$($watch.Elapsed); stdout=$output; stderr=$errors")
        return $code
    }
    finally { if ($process) { $process.Dispose() } }
}
