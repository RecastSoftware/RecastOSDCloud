function Get-OSDCloudPostSetting {
    <#
    .SYNOPSIS
        Reads the PreOOBE choices staged by the OSDCloud deployment.
    .DESCRIPTION
        Reads Setup\Scripts\OSDCloudPost.json, written in WinPE from the
        OSDCloud Post section of the deployment window. Returns whether the
        Windows Update - OS and Windows Update - Drivers tasks start checked.
        A missing, unreadable, or invalid file leaves both tasks checked and is
        logged; it never stops PreOOBE. Preview ignores the default path.
    .PARAMETER Path
        Settings file. Defaults to Windows\Setup\Scripts\OSDCloudPost.json.
    .EXAMPLE
        Get-OSDCloudPostSetting
    .NOTES
        Does not decide whether staged drivers install; that always runs when a
        staged driver pack exists.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param ([string]$Path)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Read settings"
    $result = [pscustomobject]@{ WindowsUpdateOS = $true; WindowsUpdateDrivers = $true; Messages = @() }
    if (-not $Path) {
        if ($Preview) { return $result }
        $Path = Join-Path $env:WINDIR 'Setup\Scripts\OSDCloudPost.json'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    try {
        $json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $preOOBE = $json.PreOOBE
        if ($json.Version -isnot [int] -or $json.Version -ne 1 -or $null -eq $preOOBE -or
            $preOOBE.WindowsUpdateOS -isnot [bool] -or $preOOBE.WindowsUpdateDrivers -isnot [bool]) {
            throw 'Invalid OSDCloudPost settings schema.'
        }
        $result.WindowsUpdateOS = $preOOBE.WindowsUpdateOS
        $result.WindowsUpdateDrivers = $preOOBE.WindowsUpdateDrivers
        $result.Messages = @(
            "OSDCloud Post settings: Windows Update - OS $(if ($result.WindowsUpdateOS) { 'checked' } else { 'unchecked' }); Windows Update - Drivers $(if ($result.WindowsUpdateDrivers) { 'checked' } else { 'unchecked' })."
        )
    }
    catch {
        $result.WindowsUpdateOS = $true
        $result.WindowsUpdateDrivers = $true
        $result.Messages = @("Ignored OSDCloud Post settings in $Path`: $($_.Exception.Message) Windows Update tasks remain checked.")
    }
    Write-OOBEMenuLog -Message $result.Messages
    return $result
}
