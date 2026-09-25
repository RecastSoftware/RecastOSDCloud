function Get-OSDCloudCoreOperatingSystems {
    <#
    .SYNOPSIS
    Gets parsed operating system records for OSDCloud selection workflows.

    .DESCRIPTION
    Converts raw module catalog records from Initialize-ModuleCoreOperatingSystems into
    normalized OSDCloud operating system objects. The function maps build numbers
    to known Windows releases, derives build versions, normalizes architecture,
    identifies activation channel, and emits sorted records with media metadata
    such as language, size, file name, path, and hashes.

    .EXAMPLE
    Get-OSDCloudCoreOperatingSystems

    Returns all available OSDCloud operating system records.

    .EXAMPLE
    Get-OSDCloudCoreOperatingSystems | Where-Object { $_.OSName -eq 'Windows 11' }

    Returns only Windows 11 operating system records.

    .EXAMPLE
    Get-OSDCloudCoreOperatingSystems | Group-Object OSArchitecture

    Groups results by normalized architecture.

    .INPUTS
    None
    You cannot pipe input to this function.

    .OUTPUTS
    PSCustomObject[]
    Parsed operating system records for OSDCloud catalog operations.

    .LINK
    https://www.osdeploy.com/

    .NOTES
    Author: OSDeploy
    2026-08-05 - Standardized and expanded comment-based help
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param ()

    $ErrorActionPreference = 'Stop'
    $records = @()
    $mctRecords = @()

    Initialize-ModuleCoreOperatingSystems
    if (-not ($global:ModuleCoreOperatingSystems)) {
        throw "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Unable to load Module Core Operating Systems."
    }
    $mctRecords = $global:ModuleCoreOperatingSystems

    if (-not $mctRecords) {
        return $records
    }

    foreach ($node in ($mctRecords | Sort-Object FileName, LanguageCode, Architecture)) {
        # Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Processing $($node.FileName)"

        if ([string]::IsNullOrWhiteSpace($node.OSBuild) -or [string]::IsNullOrWhiteSpace($node.OSBuildVersion)) {
            continue
        }
        #=================================================
        #   OperatingSystem / OSName / OSVersion
        $operatingSystemInfo = ConvertTo-OSDCoreOperatingSystemInfo -OSBuild $node.OSBuild
        if (-not $operatingSystemInfo) {
            continue
        }
        $OperatingSystem = $operatingSystemInfo.OperatingSystem
        $OSName = $operatingSystemInfo.OSName
        $OSVersion = $operatingSystemInfo.OSVersion
        #=================================================
        #   OSBuild / OSBuildVersion
        #=================================================
        $OSBuild = [string]$node.OSBuild
        $OSBuildVersion = [string]$node.OSBuildVersion
        #=================================================
        #   OSArchitecture
        #   Avoids confusion between x64 releases (amd64/arm64)
        #=================================================
        if ($node.Architecture -match 'x64') {
            $OSArchitecture = 'amd64'
        }
        elseif ($node.Architecture -match 'arm64') {
            $OSArchitecture = 'arm64'
        }
        else {
            $OSArchitecture = 'x86'
            continue
        }
        #=================================================
        #   OSActivation
        #=================================================
        if ($node.FileName -match 'clientconsumer_ret') {
            $OSActivation = 'Retail'
        }
        elseif ($node.FileName -match 'CLIENTBUSINESS_VOL') {
            $OSActivation = 'Volume'
        }
        else {
            $OSActivation = 'Unknown'
            continue
        }
        #=================================================
        #   Id
        #=================================================
        $Id = "$OperatingSystem $OSArchitecture $OSActivation $($node.LanguageCode) $OSBuildVersion"
        #=================================================
        #   ObjectProperties
        #=================================================
        $records += [pscustomobject]@{
            Id              = $Id
            OperatingSystem = $OperatingSystem
            OSName          = $OSName
            OSVersion       = $OSVersion
            OSArchitecture  = $OSArchitecture
            OSActivation    = $OSActivation
            OSLanguageCode  = $node.LanguageCode
            OSLanguage      = $node.Language
            OSBuild         = $OSBuild
            OSBuildVersion  = $OSBuildVersion
            # Architecture    = $node.Architecture
            Size            = $node.Size
            Sha1            = $node.Sha1
            Sha256          = $node.Sha256
            FileName        = $node.FileName
            FilePath        = $node.FilePath
            # IsRetailOnly    = $node.IsRetailOnly
        }
    }
    $records = $records | Sort-Object -Property FileName -Unique
    $records = $records | Sort-Object -Property @{Expression = { $_.OperatingSystem }; Descending = $true }, OSArchitecture, OSActivation, OSLanguageCode
    $records | Export-Clixml -Path (Join-Path -Path $env:TEMP -ChildPath 'OSDCloudCoreOperatingSystems.xml') -Force
    return $records
}
