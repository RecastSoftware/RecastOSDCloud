function Get-OSDCloudBootMenuProfileCandidates {
    <#
    .SYNOPSIS
        Finds standalone OSDCloud BootMenu profiles on attached drives.
    .DESCRIPTION
        Reads only OSDCloud\core\bootmenu-profiles\<id>\osdcloudbootmenu.json on drives C:
        through Z:. The RAM disk is searched first. Each folder name matches
        info.id; info.name is the display name. Duplicate IDs use the first
        discovered profile.
        Invalid profiles throw to prevent an unintended default deployment. Legacy WinpeStartup profiles are
        not read or modified.
    .EXAMPLE
        Get-OSDCloudBootMenuProfileCandidates
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Used by Invoke-OSDCloudBootMenu.
    #>
    [CmdletBinding()]
    param ()

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Discovering BootMenu Profiles"
    $seen = [System.Collections.Generic.HashSet[guid]]::new()
    foreach ($driveLetter in @('X') + @([char[]](67..90) | Where-Object { $_ -ne 'X' })) {
        $root = '{0}:\OSDCloud\core\bootmenu-profiles' -f $driveLetter
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        try {
            $folders = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop | Sort-Object FullName)
        }
        catch {
            Write-Warning "Invoke-OSDCloudBootMenu: Cannot enumerate '$root': $($_.Exception.Message)"
            continue
        }
        foreach ($folder in $folders) {
            $file = Join-Path $folder.FullName 'osdcloudbootmenu.json'
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            try {
                Assert-OSDCloudBootMenuProfile -Path $file
                $profileData = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if (-not $profileData.info.name -or -not $profileData.info.id) {
                    throw 'BootMenu discovery requires info.name and info.id.'
                }
                if (-not $seen.Add([guid]$profileData.info.id)) {
                    Write-Verbose "Invoke-OSDCloudBootMenu: Ignoring duplicate profile ID '$($profileData.info.id)' at '$file'."
                    continue
                }
                [pscustomobject]@{
                    Index     = 0
                    Id        = $profileData.info.id
                    Profile   = $profileData.info.name
                    Path      = $file
                    AssetPath = $folder.FullName
                }
            }
            catch {
                throw "Invoke-OSDCloudBootMenu: Invalid profile '$file': $($_.Exception.Message)"
            }
        }
    }
}
