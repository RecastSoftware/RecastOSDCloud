function step-install-downloadwindowsimage {
    [CmdletBinding()]
    param (
        $OperatingSystemCloudObject = $global:OSDCloudWorkflowInvoke.OperatingSystemCloudObject
    )
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    # Is there an OperatingSystem Object?
    if (-not ($OperatingSystemCloudObject)) {
        Write-Warning "[$(Get-Date -format s)] OperatingSystemCloudObject is not set."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    $OperatingSystemFilePath = [string]$OperatingSystemCloudObject.FilePath
    if ([string]::IsNullOrWhiteSpace($OperatingSystemFilePath)) {
        $OperatingSystemFilePath = [string]$OperatingSystemCloudObject.Url
    }
    $OperatingSystemFileName = if ($OperatingSystemCloudObject.FileName) { [string]$OperatingSystemCloudObject.FileName } else { Split-Path $OperatingSystemFilePath -Leaf }
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OperatingSystemFilePath: $OperatingSystemFilePath"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OperatingSystemFileName: $OperatingSystemFileName"
    #=================================================
    # Is there a FilePath?
    if ([string]::IsNullOrWhiteSpace($OperatingSystemFilePath)) {
        Write-Warning "[$(Get-Date -format s)] OperatingSystemCloudObject does not have a FilePath or Url to validate."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    # Use the selected cache object when initialization found an offline image.
    if ($global:OSDCloudWorkflowInvoke.OperatingSystemCacheObject) {
        $OperatingSystemCachePath = if ($global:OSDCloudWorkflowInvoke.OperatingSystemCacheObject.FullName) { $global:OSDCloudWorkflowInvoke.OperatingSystemCacheObject.FullName } else { [string]$global:OSDCloudWorkflowInvoke.OperatingSystemCacheObject }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing selected OperatingSystem cache path: $OperatingSystemCachePath"
        if (Test-Path -LiteralPath $OperatingSystemCachePath) {
            $global:OSDCloudWorkflowInvoke.FileInfoWindowsImage = Get-Item -LiteralPath $OperatingSystemCachePath
            $global:OSDCloudWorkflowInvoke.WindowsImagePath = $global:OSDCloudWorkflowInvoke.FileInfoWindowsImage.FullName
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Using cached Windows image: $($global:OSDCloudWorkflowInvoke.WindowsImagePath)"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] WindowsImagePath:  $($global:OSDCloudWorkflowInvoke.WindowsImagePath)"
            return
        }
    }
    #=================================================
    # Is it reachable online?
    $IsOnline = $false
    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing OperatingSystem download URL with HEAD request."
        $WebRequest = Invoke-WebRequest -Uri $OperatingSystemFilePath -UseBasicParsing -Method Head
        if ($WebRequest.StatusCode -eq 200) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OperatingSystem download URL is reachable online."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystemCloudObject FilePath returned a 200 status code. OK."
            $IsOnline = $true
        }
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystemCloudObject FilePath is not reachable."
    }
    #=================================================
    # Does the file exist on a Drive?
    $IsOffline = $false
    $FileName = $OperatingSystemFileName
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Searching local drives for OperatingSystem file: $FileName"
    $MatchingFiles = @()
    $MatchingFiles = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        Get-ChildItem "$($_.Name):\OSDCloud\OS\" -Include "$FileName" -File -Recurse -Force -ErrorAction Ignore
    }

    if ($MatchingFiles) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Offline OperatingSystem matches found: $(@($MatchingFiles).Count)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystemCloudObject is available offline. OK."
        $FileInfo = $MatchingFiles | Select-Object -First 1
        $IsOffline = $true
    }
    else {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystemCloudObject is not available offline."
    }
    #=================================================
    # Nothing to do if it is unavailable online and offline
    if ($IsOnline -eq $false -and $IsOffline -eq $false) {
        Write-Warning "[$(Get-Date -format s)] OperatingSystemCloudObject is not available online or offline."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    if ($FileInfo) {
        $global:OSDCloudWorkflowInvoke.FileInfoWindowsImage = $FileInfo
        $global:OSDCloudWorkflowInvoke.WindowsImagePath = $global:OSDCloudWorkflowInvoke.FileInfoWindowsImage.FullName
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Using offline Windows image: $($global:OSDCloudWorkflowInvoke.WindowsImagePath)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] WindowsImagePath:  $($global:OSDCloudWorkflowInvoke.WindowsImagePath)"
        return
    }
    #=================================================
    # Create Download Directory
    $DownloadPath = "C:\OSDCloud\OS"
    $ItemParams = @{
        ErrorAction = 'SilentlyContinue'
        Force       = $true
        ItemType    = 'Directory'
        Path        = $DownloadPath
    }
    if (!(Test-Path $ItemParams.Path -ErrorAction SilentlyContinue)) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating download path: $($ItemParams.Path)"
        New-Item @ItemParams | Out-Null
    }
    #=================================================
    # Is there a USB drive available?
    $USBDrive = Get-DeviceUSBVolume | Where-Object { ($_.FileSystemLabel -match "OSDCloud|USB-DATA") } | `
                Where-Object { $_.SizeGB -ge 16 } | Where-Object { $_.SizeRemainingGB -ge 10 } | Select-Object -First 1

    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $OperatingSystemFilePath"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] FileName: $FileName"

    if ($USBDrive) {
        $USBDownloadPath = "$($USBDrive.DriveLetter):\OSDCloud\OS\$($OperatingSystemCloudObject.OperatingSystem)"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] USB cache drive selected: $($USBDrive.DriveLetter); USBDownloadPath: $USBDownloadPath"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DownloadPath: $USBDownloadPath"

        if (-not (Test-Path $USBDownloadPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating USB download path: $USBDownloadPath"
            $null = New-Item -Path $USBDownloadPath -ItemType Directory -Force
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Downloading Windows image to USB cache."
        $SaveWebFile = Invoke-OSDCloudDownloadFile -SourceUrl $OperatingSystemFilePath -DestinationDirectory "$USBDownloadPath" -DestinationName $FileName

        if ($SaveWebFile) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Copying cached Windows image from $($SaveWebFile.FullName) to $DownloadPath."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Copy Offline OS to $DownloadPath"
            $null = Copy-Item -Path $SaveWebFile.FullName -Destination $DownloadPath -Force
            $FileInfo = Get-Item "$DownloadPath\$($SaveWebFile.Name)"
        }
    }
    else {
        # $SaveWebFile is a FileInfo Object, not a path
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DownloadPath: $DownloadPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Downloading Windows image directly to $DownloadPath."
        $SaveWebFile = Invoke-OSDCloudDownloadFile -SourceUrl $OperatingSystemFilePath -DestinationDirectory $DownloadPath -ErrorAction Stop
        $FileInfo = $SaveWebFile
    }
    #=================================================
    # Do we have FileInfo for the downloaded file?
    if (-not ($FileInfo)) {
        Write-Warning "[$(Get-Date -format s)] Unable to download the WindowsImage from the Internet."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    # Store this as a FileInfo Object
    $global:OSDCloudWorkflowInvoke.FileInfoWindowsImage = $FileInfo
    $global:OSDCloudWorkflowInvoke.WindowsImagePath = $global:OSDCloudWorkflowInvoke.FileInfoWindowsImage.FullName
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Downloaded Windows image path: $($global:OSDCloudWorkflowInvoke.WindowsImagePath)"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] WindowsImagePath:  $($global:OSDCloudWorkflowInvoke.WindowsImagePath)"
    #=================================================
    # Check the File Hash
    if ($OperatingSystemCloudObject.Sha1) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Validating SHA1 hash for $($FileInfo.FullName)."
        $FileHash = (Get-FileHash -Path $FileInfo.FullName -Algorithm SHA1).Hash
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Verified ESD SHA1: $($OperatingSystemCloudObject.Sha1)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Downloaded ESD SHA1: $FileHash"

        if ($OperatingSystemCloudObject.Sha1 -notmatch $FileHash) {
            Write-Warning "[$(Get-Date -format s)] Unable to deploy this Operating System."
            Write-Warning "[$(Get-Date -format s)] Downloaded ESD SHA1 does not match the verified Microsoft ESD SHA1."
            Write-Warning 'Press Ctrl+C to exit OSDCloud'
            Start-Sleep -Seconds 86400
        }
        else {
            Write-Host -ForegroundColor Green "[$(Get-Date -format s)] Downloaded ESD SHA1 matches the verified Microsoft ESD SHA1. OK."
        }
    }
    if ($OperatingSystemCloudObject.Sha256) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Validating SHA256 hash for $($FileInfo.FullName)."
        $FileHash = (Get-FileHash -Path $FileInfo.FullName -Algorithm SHA256).Hash
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Microsoft Verified ESD SHA256: $($OperatingSystemCloudObject.Sha256)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Downloaded ESD SHA256: $FileHash"

        if ($OperatingSystemCloudObject.Sha256 -notmatch $FileHash) {
            Write-Warning "[$(Get-Date -format s)] Unable to deploy this Operating System."
            Write-Warning "[$(Get-Date -format s)] Downloaded ESD SHA256 does not match the verified Microsoft ESD SHA256."
            Write-Warning 'Press Ctrl+C to exit OSDCloud'
            Start-Sleep -Seconds 86400
        }
        else {
            Write-Host -ForegroundColor Green "[$(Get-Date -format s)] Downloaded ESD SHA256 matches the verified Microsoft ESD SHA256. OK."
        }
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
