function Export-OSDCloudResults {
    <#
    .SYNOPSIS
        Saves deployment results as CLIXML.
    .DESCRIPTION
        Writes OSDCloudResults.clixml to current TEMP and, when requested, the
        deployed Windows Temp directory. Each destination is attempted independently.
    .PARAMETER IncludeTarget
        Also saves to the Windows image application root from the current workflow.
        An unavailable target generates a warning rather than guessing a drive.
    .EXAMPLE
        Export-OSDCloudResults -IncludeTarget
    .NOTES
        Reads global OSDCloudResults and OSDCloudWorkflowInvoke. Write failures warn
        and do not prevent deployment or PostAction.
    #>
    [CmdletBinding()]
    param ([switch]$IncludeTarget)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Saving deployment results"

    $destinations = @($env:TEMP)
    if ($IncludeTarget) {
        try {
            $applyPath = [string]$global:OSDCloudWorkflowInvoke.ParamsExpandWindowsImage.ApplyPath
            if ([string]::IsNullOrWhiteSpace($applyPath) -or -not [System.IO.Path]::IsPathRooted($applyPath)) {
                throw 'The current workflow has no Windows image application root.'
            }
            $windowsPath = Join-Path -Path $applyPath -ChildPath 'Windows'
            if (-not (Test-Path -LiteralPath $windowsPath -PathType Container -ErrorAction Stop)) {
                throw "The deployed Windows directory is unavailable: $windowsPath"
            }
            $destinations += Join-Path -Path $windowsPath -ChildPath 'Temp'
        }
        catch {
            Write-Warning "Could not resolve the deployed Windows TEMP for OSDCloudResults: $($_.Exception.Message)"
        }
    }

    $savedPaths = @()
    foreach ($destination in $destinations) {
        try {
            if ([string]::IsNullOrWhiteSpace($destination)) {
                throw 'The results TEMP directory is not configured.'
            }
            $directory = [System.IO.Path]::GetFullPath($destination)
            if ($directory.Length -gt [System.IO.Path]::GetPathRoot($directory).Length) {
                $directory = $directory.TrimEnd('\')
            }
            if ($directory -in $savedPaths) {
                continue
            }
            $savedPaths += $directory
            $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
            $path = Join-Path -Path $directory -ChildPath 'OSDCloudResults.clixml'
            $global:OSDCloudResults | Export-Clixml -LiteralPath $path -Depth 4 -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not export OSDCloudResults to '$destination': $($_.Exception.Message)"
        }
    }
}
