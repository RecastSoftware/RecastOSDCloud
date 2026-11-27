function Get-OSDCloudBootMenuProfileCandidates {
    <#
    .SYNOPSIS
        Finds standalone OSDCloud BootMenu profiles on attached drives.
    .DESCRIPTION
        Reads only OSDCloud\core\bootmenu-profiles\<id>\osdcloudbootmenu.json on drives C:
        through Z:. The RAM disk is searched first. Each folder name matches
        info.id; info.name is the display name. Duplicate IDs use the first
        discovered profile. An optional order.json in a profile root lists info.id
        values in menu order; RootIndex and OrderIndex expose that order, and
        unlisted profiles use [int]::MaxValue so callers sort them by name.
        A malformed order.json writes a warning and is ignored.
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
    $rootIndex = -1
    foreach ($driveLetter in @('X') + @([char[]](67..90) | Where-Object { $_ -ne 'X' })) {
        $root = '{0}:\OSDCloud\core\bootmenu-profiles' -f $driveLetter
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $rootIndex++
        try {
            $folders = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop | Sort-Object FullName)
        }
        catch {
            Write-Warning "Invoke-OSDCloudBootMenu: Cannot enumerate '$root': $($_.Exception.Message)"
            continue
        }
        # Optional order.json written by OSDCloud Boot: { "schemaVersion": 1, "profiles": ["<info.id>", ...] }
        $order = @{}
        $orderFile = Join-Path $root 'order.json'
        if (Test-Path -LiteralPath $orderFile -PathType Leaf) {
            try {
                $orderData = Get-Content -LiteralPath $orderFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($orderData.schemaVersion -ne 1 -or $null -eq $orderData.PSObject.Properties['profiles']) {
                    throw 'Expected schemaVersion 1 and a profiles array.'
                }
                foreach ($orderId in @($orderData.profiles)) {
                    $key = ([guid][string]$orderId).ToString()
                    if (-not $order.ContainsKey($key)) { $order[$key] = $order.Count }
                }
            }
            catch {
                Write-Warning "Invoke-OSDCloudBootMenu: Ignoring profile order '$orderFile': $($_.Exception.Message)"
                $order = @{}
            }
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
                $orderKey = ([guid]$profileData.info.id).ToString()
                [pscustomobject]@{
                    Index      = 0
                    Id         = $profileData.info.id
                    Profile    = $profileData.info.name
                    Path       = $file
                    AssetPath  = $folder.FullName
                    RootIndex  = $rootIndex
                    OrderIndex = if ($order.ContainsKey($orderKey)) { [int]$order[$orderKey] } else { [int]::MaxValue }
                }
            }
            catch {
                throw "Invoke-OSDCloudBootMenu: Invalid profile '$file': $($_.Exception.Message)"
            }
        }
    }
}
