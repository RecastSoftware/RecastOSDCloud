function Get-WinpeStartupProfileCandidates {
    <#
    .SYNOPSIS
        Finds WinpeStartup profiles on attached drives.

    .DESCRIPTION
        Discovers folder-based startup profiles and legacy root-level JSON
        profiles from WinpeStartup\profiles directories on attached drives.

    .EXAMPLE
        Get-WinpeStartupProfileCandidates

        Returns the discovered profile names and paths.

    .NOTES
        Used by Invoke-WinpeStartup to locate startup profiles.
    #>
    [CmdletBinding()]
    param ()

    $Error.Clear()
    $candidateProfiles = [System.Collections.Generic.List[object]]::new()

    foreach ($driveLetter in [char[]](67..90)) {
        $profileRoot = '{0}:\WinpeStartup\profiles' -f $driveLetter

        if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) {
            continue
        }

        try {
            $profileFiles = Get-ChildItem -LiteralPath $profileRoot -Filter '*.json' -File -ErrorAction Stop
            $profileFolders = Get-ChildItem -LiteralPath $profileRoot -Directory -ErrorAction Stop

            foreach ($profileFolder in $profileFolders) {
                $profileFilePath = Join-Path $profileFolder.FullName 'winpestartup.json'
                if (Test-Path -LiteralPath $profileFilePath -PathType Leaf) {
                    [void]$candidateProfiles.Add([pscustomobject]@{
                        Index   = 0
                        Profile = $profileFolder.Name
                        Path    = $profileFilePath
                    })
                }
            }

            foreach ($profileFile in ($profileFiles | Sort-Object FullName)) {
                [void]$candidateProfiles.Add([pscustomobject]@{
                    Index   = 0
                    Profile = $profileFile.BaseName
                    Path    = $profileFile.FullName
                })
            }
        }
        catch {
            Write-Verbose "Invoke-WinpeStartup: Unable to enumerate '$profileRoot': $($_.Exception.Message)"
        }
    }

    return $candidateProfiles.ToArray()
}
