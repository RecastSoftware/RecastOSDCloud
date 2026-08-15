function Update-OSDCoreDriverPackCatalogSurface {
    <#
    .SYNOPSIS
        Updates the Microsoft Surface driver pack catalog bundled with the module.

    .DESCRIPTION
        Reads the bundled Surface catalog JSON, resolves live Microsoft download pages for
        entries with UpdatePage values, enriches FileName, Url, and ReleaseDate where live
        values are found, and replaces the local module Surface catalog file.

    .PARAMETER LocalDriverPackCatalog
        Path to the local Surface catalog JSON file to update.

    .PARAMETER OSDProduct
        Limits live catalog updates to entries whose SystemId matches this device product value.

    .PARAMETER PassThru
        Returns Surface driver pack catalog objects after updating the local catalog.

    .EXAMPLE
        Update-OSDCoreDriverPackCatalogSurface

        Updates the Surface driver pack catalog bundled with the module.

    .EXAMPLE
        Update-OSDCoreDriverPackCatalogSurface -PassThru

        Updates the Surface catalog and returns catalog objects.

    .OUTPUTS
        None by default. PSCustomObject[] when PassThru is specified.

    .NOTES
        Base catalog: core\driverpacks\surface.json.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalDriverPackCatalog = (Join-Path $($MyInvocation.MyCommand.Module.ModuleBase) 'core\driverpacks\surface.json'),

        [Parameter(Mandatory = $false)]
        [string]$OSDProduct,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"

    $tempCatalogPath = Join-Path -Path $env:TEMP -ChildPath 'osdcloud-driverpack-surface.json'
    if (Test-Path -LiteralPath $tempCatalogPath) {
        Remove-Item -LiteralPath $tempCatalogPath -Force -ErrorAction SilentlyContinue
    }

    $userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
    $msiPattern = 'https://download\.microsoft\.com/download/[^"''<>\s]+\.msi'
    $datePatterns = @(
        '"detailsSection_file_date"\s*:\s*"(\d{1,2}/\d{1,2}/\d{4})"',
        '"datePublished"\s*:\s*"(\d{1,2}/\d{1,2}/\d{4})',
        '(?is)Date Published.{0,500}?(\d{1,2}/\d{1,2}/\d{4})'
    )
    $updatePageCache = @{}
    $networkCalls = 0
    $fallbackCalls = 0

    try {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Indexing $LocalDriverPackCatalog"
        $jsonCatalogContent = Get-Content -Path $LocalDriverPackCatalog -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        if (-not $jsonCatalogContent) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Failed to load Surface driver pack catalog content'),
                'CatalogLoadFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $LocalDriverPackCatalog
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $catalogVersion = Get-Date -Format yy.MM.dd
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Building Surface driver pack catalog (CatalogVersion: $catalogVersion)"

        $matchesOSDProduct = {
            param (
                [Parameter(Mandatory = $true)]
                $Item
            )

            if ([string]::IsNullOrWhiteSpace($OSDProduct)) {
                return $true
            }

            foreach ($systemId in @($Item.SystemId)) {
                if ([string]::Equals([string]$systemId, $OSDProduct, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }
            }

            return $false
        }

        $targetCatalogContent = @(if ([string]::IsNullOrWhiteSpace($OSDProduct)) {
                $jsonCatalogContent
            }
            else {
                $jsonCatalogContent | Where-Object { & $matchesOSDProduct -Item $_ }
            })

        if ([string]::IsNullOrWhiteSpace($OSDProduct)) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Updating all Surface driver pack entries."
        }
        else {
            Write-Host -ForegroundColor DarkGreen "[$(Get-Date -format s)] [INFO] Recast OSDCloud is updating the Surface DriverPack catalog for $OSDProduct."
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Updating Surface driver pack entries matching OSDProduct '$OSDProduct'. Matched $($targetCatalogContent.Count) entries."
            if ($targetCatalogContent.Count -eq 0) {
                # Write-Warning "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No Surface driver pack catalog entries match OSDProduct '$OSDProduct'. Skipping live update checks."
            }
        }

        $uniqueUpdatePages = @($targetCatalogContent.UpdatePage | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        if ($uniqueUpdatePages.Count -gt 0) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Resolving $($uniqueUpdatePages.Count) unique UpdatePage URLs"
        }

        foreach ($updatePage in $uniqueUpdatePages) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Refreshing DriverPacks at $updatePage"
            $networkCalls++
            try {
                $response = Invoke-WebRequest -Uri $updatePage -UseBasicParsing -UserAgent $userAgent -MaximumRedirection 5 -ErrorAction Stop
                $html = $response.Content

                $allMsi = @(
                    [regex]::Matches($html, $msiPattern) |
                    ForEach-Object { $_.Value } |
                    Select-Object -Unique
                )

                if ($allMsi.Count -eq 0 -and $updatePage -match '[?&]id=(\d+)') {
                    $confirmUri = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=$($Matches[1])"
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Downloading $confirmUri"
                    $fallbackCalls++
                    $networkCalls++
                    $response = Invoke-WebRequest -Uri $confirmUri -UseBasicParsing -UserAgent $userAgent -MaximumRedirection 5 -ErrorAction Stop
                    $html = $response.Content
                    $allMsi = @(
                        [regex]::Matches($html, $msiPattern) |
                        ForEach-Object { $_.Value } |
                        Select-Object -Unique
                    )
                }

                if ($allMsi.Count -gt 0) {
                    $win11Uris = @($allMsi | Where-Object { $_ -match 'Win11' })
                    $candidates = if ($win11Uris.Count -gt 0) { $win11Uris } else { $allMsi }
                    $bestUri = $candidates |
                        Sort-Object {
                            if ($_ -match '_(\d{5})_') { [int]$Matches[1] } else { 0 }
                        } -Descending |
                        Select-Object -First 1

                    $newDate = $null
                    $now = [datetime]::UtcNow
                    foreach ($datePattern in $datePatterns) {
                        foreach ($match in [regex]::Matches($html, $datePattern)) {
                            try {
                                $parsed = [datetime]::ParseExact($match.Groups[1].Value, 'M/d/yyyy', $null)
                                if ($parsed.Year -ge 2015 -and $parsed -le $now.AddMonths(3)) {
                                    $newDate = $parsed.ToString('yy.MM.dd')
                                    break
                                }
                            }
                            catch { }
                        }

                        if ($newDate) {
                            break
                        }
                    }

                    $updatePageCache[$updatePage] = @{
                        Error       = $null
                        FileName    = ($bestUri -replace '.+/', '')
                        Url         = $bestUri
                        ReleaseDate = $newDate
                    }
                }
                else {
                    $updatePageCache[$updatePage] = @{ Error = 'No MSI links found' }
                    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No MSI links found for $updatePage"
                }
            }
            catch {
                $updatePageCache[$updatePage] = @{ Error = $_.Exception.Message }
                Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Failed to resolve $updatePage`: $($_.Exception.Message)"
            }
        }

        $results = foreach ($item in $jsonCatalogContent) {
            $isUpdateTarget = & $matchesOSDProduct -Item $item
            $itemCatalogVersion = $item.CatalogVersion
            $releaseDate = $item.ReleaseDate
            $fileName = $item.FileName
            $url = $item.Url

            if ($isUpdateTarget) {
                $itemCatalogVersion = $catalogVersion
            }

            if ($isUpdateTarget -and $item.UpdatePage -and $updatePageCache.ContainsKey($item.UpdatePage)) {
                $cached = $updatePageCache[$item.UpdatePage]
                if (-not $cached.Error) {
                    $fileName = $cached.FileName
                    $url = $cached.Url
                    if ($cached.ReleaseDate) {
                        $releaseDate = $cached.ReleaseDate
                    }
                }
            }

            $displayName = $item.Name
            if ($isUpdateTarget) {
                $baseName = $item.Name -replace '\s*\[.*?\]$', ''
                $displayName = "$baseName [$releaseDate]"
            }

            $objectProperties = [Ordered]@{
                CatalogVersion  = $itemCatalogVersion
                ReleaseDate     = $releaseDate
                Name            = $displayName
                Manufacturer    = $item.Manufacturer
                Model           = $item.Model
                SystemId        = $item.SystemId
                FileName        = $fileName
                Url             = $url
                OperatingSystem = $item.OperatingSystem
                OSArchitecture  = $item.OSArchitecture
                HashMD5         = $item.HashMD5
                UpdatePage      = $item.UpdatePage
            }
            [PSCustomObject]$objectProperties
        }

        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $tempCatalogPath -Encoding utf8 -Force
        $updatedCatalogContent = Get-Content -Path $tempCatalogPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        if (-not $updatedCatalogContent) {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Generated Surface driver pack catalog JSON is invalid'),
                'CatalogValidationFailed',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $tempCatalogPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        if ($PSCmdlet.ShouldProcess($LocalDriverPackCatalog, 'Update Surface driver pack catalog')) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Updating $LocalDriverPackCatalog"
            Copy-Item -Path $tempCatalogPath -Destination $LocalDriverPackCatalog -Force
        }

        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Performance: UpdatePages=$($uniqueUpdatePages.Count), NetworkCalls=$networkCalls, FallbackCalls=$fallbackCalls"
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Found $($results.Count) Surface driver packs"

        if ($PassThru.IsPresent) {
            Get-OSDCoreDriverPackCatalogSurface -LocalDriverPackCatalog $LocalDriverPackCatalog
        }
    }
    finally {
        if (Test-Path $tempCatalogPath) {
            Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Removing temporary catalog file"
            Remove-Item -Path $tempCatalogPath -Force -ErrorAction SilentlyContinue
        }
        Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
}
