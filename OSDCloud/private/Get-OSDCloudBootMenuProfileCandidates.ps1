function Get-OSDCloudBootMenuProfileCandidates {
    <#
    .SYNOPSIS
        Finds OSDCloud Boot Menu profiles on attached drives.
    .DESCRIPTION
        Reads only OSDCloud\bootmenu-profiles\<name>\osdcloudbootmenu.json on drives C:
        through Z:. The RAM disk is searched first. Names and GUIDs come from
        info, not folder names. Duplicate IDs use the first discovered profile.
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
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Discovering Boot Menu profiles"
    $seen = [System.Collections.Generic.HashSet[guid]]::new()
    foreach ($driveLetter in @('X') + @([char[]](67..90) | Where-Object { $_ -ne 'X' })) {
        $root = '{0}:\OSDCloud\bootmenu-profiles' -f $driveLetter
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
                $profile = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if (-not $profile.info.name -or -not $profile.info.id) {
                    throw 'Boot Menu discovery requires info.name and info.id.'
                }
                if (-not $seen.Add([guid]$profile.info.id)) {
                    Write-Verbose "Invoke-OSDCloudBootMenu: Ignoring duplicate profile ID '$($profile.info.id)' at '$file'."
                    continue
                }
                [pscustomobject]@{
                    Index     = 0
                    Id        = $profile.info.id
                    Profile   = $profile.info.name
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
