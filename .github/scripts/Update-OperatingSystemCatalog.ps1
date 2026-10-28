$Error.Clear()
$ErrorActionPreference = 'Stop'

$metadataUri = 'https://fe3.delivery.mp.microsoft.com/UpdateMetadataService/updates/search/v1/bydeviceinfo'
$requestBody = [ordered]@{
    Products         = 'PN=Windows.Products.Cab.amd64&V=0.0.0.0'
    DeviceAttributes = 'DUScan=1;OSVersion=10.0.26100.1'
} | ConvertTo-Json -Compress
$catalogDirectory = Join-Path $PSScriptRoot '..\..\OSDCloud\core\operatingsystems'
$catalogDirectory = [System.IO.Path]::GetFullPath($catalogDirectory)
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('os-catalog-' + [guid]::NewGuid().ToString())
$changed = $false
$destinationName = $null

if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
    throw 'GITHUB_OUTPUT is not set; this script must run from GitHub Actions.'
}
if (-not (Test-Path -LiteralPath $catalogDirectory -PathType Container)) {
    throw "Operating system catalog directory was not found at '$catalogDirectory'."
}

try {
    $null = New-Item -Path $temporaryDirectory -ItemType Directory
    $response = Invoke-RestMethod `
        -Uri $metadataUri `
        -Method Post `
        -ContentType 'application/json' `
        -Headers @{ Accept = '*/*' } `
        -Body $requestBody `
        -ErrorAction Stop

    if ($response -is [array]) {
        if ($response.Count -ne 1) {
            throw "Microsoft metadata returned $($response.Count) response records; expected one."
        }
        $response = $response[0]
    }

    $cabRecords = @($response.FileLocations | Where-Object { $_.FileName -eq 'products.cab' })
    if ($cabRecords.Count -ne 1) {
        throw "Microsoft metadata returned $($cabRecords.Count) products.cab records; expected one."
    }

    $cabRecord = $cabRecords[0]
    $cabUri = [uri]$cabRecord.Url
    if (-not $cabUri.IsAbsoluteUri -or $cabUri.Scheme -notin @('http', 'https')) {
        throw "Microsoft metadata returned an invalid products.cab URL: $($cabRecord.Url)"
    }

    [long]$expectedCabSize = 0
    if (-not [long]::TryParse([string]$cabRecord.Size, [ref]$expectedCabSize) -or $expectedCabSize -le 0) {
        throw "Microsoft metadata returned an invalid products.cab size: $($cabRecord.Size)"
    }

    try {
        $expectedDigest = [Convert]::FromBase64String([string]$cabRecord.Digest)
    }
    catch {
        throw 'Microsoft metadata returned an invalid products.cab SHA256 digest.'
    }
    if ($expectedDigest.Length -ne 32) {
        throw "Microsoft metadata returned a $($expectedDigest.Length)-byte digest; expected SHA256."
    }

    $cabPath = Join-Path $temporaryDirectory 'products.cab'
    Invoke-WebRequest -Uri $cabUri -OutFile $cabPath -Headers @{ Accept = '*/*' } -ErrorAction Stop
    $actualCabSize = (Get-Item -LiteralPath $cabPath).Length
    if ($actualCabSize -ne $expectedCabSize) {
        throw "Downloaded products.cab size mismatch. Expected $expectedCabSize bytes, got $actualCabSize bytes."
    }

    $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    $cabStream = [System.IO.File]::OpenRead($cabPath)
    try {
        $actualDigest = $hashAlgorithm.ComputeHash($cabStream)
    }
    finally {
        $cabStream.Dispose()
        $hashAlgorithm.Dispose()
    }
    if ([Convert]::ToBase64String($actualDigest) -cne [Convert]::ToBase64String($expectedDigest)) {
        throw 'Downloaded products.cab SHA256 digest does not match Microsoft metadata.'
    }

    $expandPath = Join-Path $env:SystemRoot 'System32\expand.exe'
    if (-not (Test-Path -LiteralPath $expandPath -PathType Leaf)) {
        throw "Windows expand.exe was not found at '$expandPath'."
    }

    $sourceXmlPath = Join-Path $temporaryDirectory 'products.xml'
    $expandResult = & $expandPath $cabPath $sourceXmlPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "expand.exe failed with exit code ${LASTEXITCODE}: $expandResult"
    }
    if (-not (Test-Path -LiteralPath $sourceXmlPath -PathType Leaf)) {
        throw 'expand.exe did not produce products.xml.'
    }

    [xml]$catalog = Get-Content -LiteralPath $sourceXmlPath -Raw
    $fileNodes = @($catalog.MCT.Catalogs.Catalog.PublishedMedia.Files.File)
    $esdNodes = @($fileNodes | Where-Object { [string]$_.FileName -like '*.esd' })
    if ($esdNodes.Count -lt 50) {
        throw "Catalog contains $($esdNodes.Count) ESD records; expected at least 50."
    }

    $requiredProperties = @('FileName', 'LanguageCode', 'Edition', 'Architecture', 'Size', 'Sha256', 'FilePath')
    $catalogIdentities = @()
    foreach ($node in $esdNodes) {
        foreach ($property in $requiredProperties) {
            if ([string]::IsNullOrWhiteSpace([string]$node.$property)) {
                throw "Catalog record '$($node.FileName)' is missing required property '$property'."
            }
        }

        if ([string]$node.Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
            throw "Catalog record '$($node.FileName)' has an invalid SHA256 value."
        }

        [long]$fileSize = 0
        if (-not [long]::TryParse([string]$node.Size, [ref]$fileSize) -or $fileSize -le 0) {
            throw "Catalog record '$($node.FileName)' has an invalid size."
        }

        $identityMatch = [regex]::Match(
            [string]$node.FileName,
            '^(?<Identity>\d{5}\.(?:0|[1-9]\d*)\.\d{6}-\d{4})\..+\.esd$',
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        if (-not $identityMatch.Success) {
            throw "Catalog record '$($node.FileName)' does not contain a supported build identity."
        }
        $catalogIdentities += $identityMatch.Groups['Identity'].Value
    }

    $catalogIdentities = @($catalogIdentities | Sort-Object -Unique)
    if ($catalogIdentities.Count -ne 1) {
        throw "Catalog contains $($catalogIdentities.Count) build and release identities; expected one."
    }

    $catalogIdentity = $catalogIdentities[0]
    $identityMatch = [regex]::Match(
        $catalogIdentity,
        '^(?<Major>\d{5})\.(?<Ubr>0|[1-9]\d*)\.(?<Timestamp>\d{6}-\d{4})$',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    $releaseDateTime = [datetime]::MinValue
    if (-not $identityMatch.Success -or -not [datetime]::TryParseExact(
        $identityMatch.Groups['Timestamp'].Value,
        'yyMMdd-HHmm',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$releaseDateTime
    )) {
        throw "Catalog identity '$catalogIdentity' is not valid."
    }

    $build = $null
    if (-not [version]::TryParse(
        "$($identityMatch.Groups['Major'].Value).$($identityMatch.Groups['Ubr'].Value)",
        [ref]$build
    )) {
        throw "Catalog build '$catalogIdentity' is not valid."
    }

    foreach ($architecture in @('x64', 'ARM64')) {
        $target = @(
            $esdNodes | Where-Object {
                [string]$_.LanguageCode -eq 'en-us' -and
                [string]$_.Edition -eq 'Enterprise' -and
                [string]$_.Architecture -eq $architecture
            }
        )
        if ($target.Count -lt 1) {
            throw "Catalog does not contain an en-us Enterprise $architecture ESD record."
        }
    }

    $destinationName = "$catalogIdentity.xml"
    $destinationPath = Join-Path $catalogDirectory $destinationName
    $sourceHash = (Get-FileHash -LiteralPath $sourceXmlPath -Algorithm SHA256).Hash
    $destinationExists = Test-Path -LiteralPath $destinationPath -PathType Leaf

    if ($destinationExists) {
        $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
        if ($sourceHash -cne $destinationHash) {
            throw "Catalog '$destinationName' already exists with different content."
        }
        Write-Host "Catalog is already up to date: $destinationName"
    }
    else {
        foreach ($existingCatalog in Get-ChildItem -LiteralPath $catalogDirectory -Filter '*.xml' -File) {
            $existingMatch = [regex]::Match(
                $existingCatalog.Name,
                '^(?<Major>\d{5})\.(?<Ubr>0|[1-9]\d*)\.(?<Timestamp>\d{6}-\d{4})\.xml$',
                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
            )
            if (-not $existingMatch.Success) {
                continue
            }

            $existingBuild = $null
            $existingReleaseDateTime = [datetime]::MinValue
            if (-not [version]::TryParse(
                "$($existingMatch.Groups['Major'].Value).$($existingMatch.Groups['Ubr'].Value)",
                [ref]$existingBuild
            ) -or -not [datetime]::TryParseExact(
                $existingMatch.Groups['Timestamp'].Value,
                'yyMMdd-HHmm',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$existingReleaseDateTime
            )) {
                continue
            }

            $isNewerBuild = $existingBuild -gt $build
            $isNewerRelease = $existingBuild -eq $build -and $existingReleaseDateTime -gt $releaseDateTime
            if ($isNewerBuild -or $isNewerRelease) {
                throw "Existing catalog '$($existingCatalog.Name)' is newer than downloaded catalog '$destinationName'."
            }
        }

        $stagedPath = Join-Path $catalogDirectory ('.' + $destinationName + '.' + [guid]::NewGuid().ToString() + '.tmp')
        [System.IO.File]::Copy($sourceXmlPath, $stagedPath, $false)
        try {
            [System.IO.File]::Move($stagedPath, $destinationPath)
        }
        finally {
            if (Test-Path -LiteralPath $stagedPath -PathType Leaf) {
                Remove-Item -LiteralPath $stagedPath -Force
            }
        }

        $changed = $true
        Write-Host "Saved OS catalog: $destinationPath"
    }

    "changed=$($changed.ToString().ToLowerInvariant())" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    "catalog_name=$destinationName" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory -PathType Container) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
