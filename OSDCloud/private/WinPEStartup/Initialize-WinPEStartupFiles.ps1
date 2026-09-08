#requires -Version 5.1

function Initialize-WinPEStartupFiles {
    <#
    .SYNOPSIS
        Copies content from $WinPE$ folders found on any attached drive into the WinPE RAM disk

    .DESCRIPTION
        Scans every available drive letter for a $WinPE$ folder. When found,
        uses robocopy to mirror the folder contents into the root of the
        SystemDrive (X:\ in WinPE). Existing files that are not in the source
        are preserved (extra files are not deleted). Multiple drives can
        contribute content; all matches are processed.

        This is the PowerShell equivalent of the $WinPE$ content-copy loop
        in startnet.cmd / ReStartnet.cmd.

    .PARAMETER SubfolderPath
        The relative subfolder path to search for on each drive. Defaults
        to 'WinPEStartup\Files'.

    .EXAMPLE
        Initialize-WinPEStartupFiles

        Scans all drive letters and copies content from every $WinPE$ folder.

    .EXAMPLE
        Initialize-WinPEStartupFiles -SubfolderPath 'MyContent'

        Scans all drive letters for a subfolder path MyContent instead of
        the default WinPEStartup\Files.

    .EXAMPLE
        Initialize-WinPEStartupFiles -Verbose

        Copies content with detailed progress showing each source drive.

    .NOTES
        Author:  David Segura
        Module:  OSDCloud
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$SubfolderPath = 'WinPEStartup\Files'
    )

    begin {
        $skipExecution = $false
        if ($env:SystemDrive -ne 'X:') {
            Write-Warning 'Initialize-WinPEStartupFiles: Not running in WinPE (SystemDrive is not X:). Exiting.'
            $skipExecution = $true
            return
        }

        Write-Verbose 'Initialize-WinPEStartupFiles: Starting content scan'
    }

    process {
        if ($skipExecution) { return }
        $driveLetters = [char[]](67..90)  # C through Z
        $destination = Join-Path -Path $env:SystemDrive -ChildPath '\'

        foreach ($letter in $driveLetters) {
            $contentFolder = '{0}:\{1}' -f $letter, $SubfolderPath

            if (Test-Path -Path $contentFolder -PathType Container) {
                Write-Verbose "Found content folder: $contentFolder"

                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Files: $contentFolder"
                # Write-Verbose "Copying content from $contentFolder to $destination"
                Invoke-Robocopy -Source $contentFolder -Destination $destination
            }
        }
    }

    end {
        if ($skipExecution) { return }
        Write-Verbose 'Initialize-WinPEStartupFiles: Complete'
    }
}
