function step-Save-WindowsDriver-DriverPack {
    [CmdletBinding()]
    param (
        [System.String]
        $DriverPackName = $global:OSDCloudWorkflowInvoke.DriverPackName,

        $DriverPackCloudObject = $global:OSDCloudWorkflowInvoke.DriverPackCloudObject
    )
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Starting driver pack staging'

    try {
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackName: $DriverPackName"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackCloudObject.Url: $($DriverPackCloudObject.Url)"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Starting driver pack staging. DriverPackName: $DriverPackName"

    if ($global:OSDCloudWorkflowInvoke.ModelDriversCacheObject) {
        $ProgressPhase = 'Staging cached ModelDrivers'
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged = $false
        $modelDriversPath = Resolve-OSDCoreModelDriversPath -CacheObject $global:OSDCloudWorkflowInvoke.ModelDriversCacheObject
        if (-not $modelDriversPath) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [WARNING] The selected ModelDrivers source is no longer available. Cannot stage drivers."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] ModelDrivers staging stopped because the selected source could not be resolved."
            return
        }
        $expandPath = 'C:\Windows\Temp\osdcloud-driverpack-expand'
        if (Test-Path -LiteralPath $expandPath) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [WARNING] ModelDrivers staging destination already exists. Refusing to mix driver sources:"
            Write-Host -ForegroundColor DarkGray "  $expandPath"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] ModelDrivers staging stopped because the destination already exists."
            return
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Copying ModelDrivers from:"
        Write-Host -ForegroundColor DarkGray "  $modelDriversPath"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Staging drivers to:"
        Write-Host -ForegroundColor DarkGray "  $expandPath"
        New-Item -Path $expandPath -ItemType Directory -ErrorAction Stop | Out-Null
        Get-ChildItem -LiteralPath $modelDriversPath -Force -ErrorAction Stop |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $expandPath -Recurse -Force -ErrorAction Stop
            }
        $InfCount = @(Get-ChildItem -LiteralPath $expandPath -Recurse -File -Filter '*.inf' -ErrorAction Stop).Count
        if ($InfCount -eq 0) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [WARNING] No INF files were staged from ModelDrivers:"
            Write-Host -ForegroundColor DarkGray "  $modelDriversPath"
            Remove-Item -LiteralPath $expandPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] ModelDrivers staging stopped because the source contained no INF files."
            return
        }
        $global:OSDCloudWorkflowInvoke.ModelDriversStaged = $true
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] ModelDrivers staging complete. Found $InfCount INF file(s) in:"
        Write-Host -ForegroundColor DarkGray "  $expandPath"
        return
    }

    # Is DriverPackName set to None?
    if ($DriverPackName -eq 'None') {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackName bypass is None."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPackName is set to None. OK."
        return
    }
    #=================================================
    # Is DriverPackName set to Microsoft Update Catalog?
    if ($DriverPackName -eq 'Microsoft Update Catalog') {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackName bypass is Microsoft Update Catalog."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPackName is set to Microsoft Update Catalog. OK."
        return
    }
    #=================================================
    # Is there a DriverPack Object?
    if (-not ($DriverPackCloudObject)) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackCloudObject was not provided."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPackCloudObject is not set. OK."
        return
    }
    #=================================================
    # Is there a URL?
    if (-not $($DriverPackCloudObject.Url)) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [WARNING] DriverPackCloudObject does not have a URL to validate."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Skipping driver pack staging because no download URL was provided."
        return
    }
    if (-not $DriverPackCloudObject.FileName) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [WARNING] DriverPackCloudObject does not have a file name. Cannot locate or download the driver pack."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Skipping driver pack staging because no file name was provided."
        return
    }
    #=================================================
    # Is it reachable online?
    $IsOnline = $false
    $ProgressPhase = 'Checking driver pack URL availability'
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Checking driver pack URL availability:"
    Write-Host -ForegroundColor DarkGray "  $($DriverPackCloudObject.Url)"
    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing DriverPack URL with HEAD request."
        $WebRequest = Invoke-WebRequest -Uri $DriverPackCloudObject.Url -UseBasicParsing -Method Head -ErrorAction Stop
        if ($WebRequest.StatusCode -eq 200) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPack URL is reachable online."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack URL is reachable (HTTP $($WebRequest.StatusCode))."
            $IsOnline = $true
        }
        else {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack URL returned HTTP $($WebRequest.StatusCode); it will not be treated as available online."
        }
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] URL availability check failed: $($_.Exception.Message)"
    }
    #=================================================
    # Does the file exist on a Drive?
    $IsOffline = $false
    $FileName = $DriverPackCloudObject.FileName
    $ProgressPhase = 'Searching local driver pack caches'
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Searching local drives for cached driver pack:"
    Write-Host -ForegroundColor DarkGray "  OSDCloud\DriverPacks\$FileName"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Searching local drives for DriverPack file: $FileName"
    $MatchingFiles = @()
    $MatchingFiles = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        Get-ChildItem "$($_.Name):\OSDCloud\DriverPacks\" -Include "$FileName" -File -Recurse -Force -ErrorAction Ignore
    }

    if ($MatchingFiles) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Offline DriverPack matches found: $(@($MatchingFiles).Count)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Found $(@($MatchingFiles).Count) offline driver pack match(es)."
        $IsOffline = $true
    }
    else {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] No offline copy of the driver pack was found."
    }
    #=================================================
    # Nothing to do if it is unavailable online and offline
    if ($IsOnline -eq $false -and $IsOffline -eq $false) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPack unavailable online and offline. Skipping save."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [WARNING] Driver pack is not available online or offline. Continuing without it."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Skipping driver pack download because no online or offline source is available."
        return
    }
    #=================================================
    # Variables
    $LogPath = "C:\Windows\Temp\osdcloud-logs"
    $Manufacturer = $DriverPackCloudObject.Manufacturer
    $ScriptsPath = "C:\Windows\Setup\Scripts"
    $SetupCompleteCmd = "$ScriptsPath\SetupComplete.cmd"
    $SetupSpecializeCmd = "C:\Windows\Temp\osdcloud\SetupSpecialize.cmd"
    $Url = $DriverPackCloudObject.Url
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Manufacturer: $Manufacturer; Download URL: $Url; LogPath: $LogPath"
    #=================================================
    # Create Download Directory
    $DownloadPath = "C:\Windows\Temp\osdcloud-driverpack-download"
    $Params = @{
        ErrorAction = 'SilentlyContinue'
        Force       = $true
        ItemType    = 'Directory'
        Path        = $DownloadPath
    }
    if (!(Test-Path $Params.Path -ErrorAction SilentlyContinue)) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating driver pack download path: $($Params.Path)"
        $Params.ErrorAction = 'Stop'
        New-Item @Params | Out-Null
    }
    #=================================================
    $FileInfo = $null
    if (-not $IsOnline -and $MatchingFiles) {
        $ProgressPhase = 'Reusing an offline driver pack copy'
        $CachedFile = $MatchingFiles | Select-Object -First 1
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Reusing the offline driver pack:"
        Write-Host -ForegroundColor DarkGray "  $($CachedFile.FullName)"
        $null = Copy-Item -LiteralPath $CachedFile.FullName -Destination $DownloadPath -Force -ErrorAction Stop
        $FileInfo = Get-Item -LiteralPath (Join-Path $DownloadPath $CachedFile.Name) -ErrorAction Stop
    }
    #=================================================
    # Is there a USB drive available?
    $USBDrive = $null
    if (-not $FileInfo) {
        $USBDrive = Get-DeviceUSBVolume | Where-Object { ($_.FileSystemLabel -match "OSDCloud|USB-DATA") } | `
                    Where-Object { $_.SizeGB -ge 16 } | Where-Object { $_.SizeRemainingGB -ge 10 } | Select-Object -First 1
    }

    if ($FileInfo) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Offline driver pack copied to the local staging directory:"
        Write-Host -ForegroundColor DarkGray "  $($FileInfo.FullName)"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Using offline driver pack: $($FileInfo.FullName)"
    }
    elseif ($USBDrive) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack source URL:"
        Write-Host -ForegroundColor DarkGray "  $($DriverPackCloudObject.Url)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack file name: $FileName"
        $USBDownloadPath = "$($USBDrive.DriveLetter):\OSDCloud\DriverPacks\$Manufacturer"
        $ProgressPhase = "Using USB driver pack cache at $USBDownloadPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] USB cache drive selected: $($USBDrive.DriveLetter); USBDownloadPath: $USBDownloadPath"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] USB cache selected (drive $($USBDrive.DriveLetter)):"
        Write-Host -ForegroundColor DarkGray "  $USBDownloadPath"

        $FileInfo = $null
        try {
            if (-not (Test-Path -LiteralPath $USBDownloadPath -ErrorAction Stop)) {
                Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating USB driver pack download path: $USBDownloadPath"
                $null = New-Item -Path $USBDownloadPath -ItemType Directory -Force -ErrorAction Stop
            }
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Downloading DriverPack to USB cache."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Downloading or reusing the driver pack in the USB cache."
            $SaveWebFile = Invoke-RecastOSDDownloadFile -SourceUrl $DriverPackCloudObject.Url -DestinationDirectory $USBDownloadPath -DestinationName $FileName -ErrorAction Stop
            if ($SaveWebFile) {
                Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Copying cached DriverPack from $($SaveWebFile.FullName) to $DownloadPath."
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Copying cached driver pack from:"
                Write-Host -ForegroundColor DarkGray "  $($SaveWebFile.FullName)"
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Copying to the local staging directory:"
                Write-Host -ForegroundColor DarkGray "  $DownloadPath"
                $null = Copy-Item -LiteralPath $SaveWebFile.FullName -Destination $DownloadPath -Force -ErrorAction Stop
                $FileInfo = Get-Item -LiteralPath (Join-Path $DownloadPath $SaveWebFile.Name) -ErrorAction Stop
            }
        }
        catch {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] USB driver pack cache failed: $($_.Exception.Message)"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Falling back to the local download directory:"
            Write-Host -ForegroundColor DarkGray "  $DownloadPath"
        }
        if (-not $FileInfo) {
            $ProgressPhase = "Downloading driver pack to $DownloadPath"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] USB cache did not provide a usable file. Downloading directly to:"
            Write-Host -ForegroundColor DarkGray "  $DownloadPath"
            $SaveWebFile = Invoke-RecastOSDDownloadFile -SourceUrl $DriverPackCloudObject.Url -DestinationDirectory $DownloadPath -DestinationName $FileName -ErrorAction Stop
            $FileInfo = $SaveWebFile
        }
    }
    else {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack source URL:"
        Write-Host -ForegroundColor DarkGray "  $($DriverPackCloudObject.Url)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack file name: $FileName"
        $ProgressPhase = "Downloading driver pack to $DownloadPath"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Downloading driver pack directly to:"
        Write-Host -ForegroundColor DarkGray "  $DownloadPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Downloading DriverPack directly to $DownloadPath."
        $SaveWebFile = Invoke-RecastOSDDownloadFile -SourceUrl $DriverPackCloudObject.Url -DestinationDirectory $DownloadPath -ErrorAction Stop
        $FileInfo = $SaveWebFile
    }
    #=================================================
    # Verify download
    if (-not $FileInfo -or -not (Test-Path -LiteralPath $FileInfo.FullName -PathType Leaf)) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [WARNING] Unable to download or locate the driver pack file '$FileName'."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack staging stopped because the downloaded file is missing."
        return
    }
    $OutFileObject = Get-Item -LiteralPath $FileInfo.FullName -ErrorAction Stop
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Downloaded DriverPack file: $($OutFileObject.FullName); Extension: $($OutFileObject.Extension)"
    $ProgressPhase = 'Validating downloaded driver pack'
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack is ready ($($OutFileObject.Length) bytes; $($OutFileObject.Extension)):"
    Write-Host -ForegroundColor DarkGray "  $($OutFileObject.FullName)"
    # Store this as a FileInfo Object
    $MetadataPath = "$($OutFileObject.FullName).json"
    $DriverPackCloudObject | ConvertTo-Json | Out-File $MetadataPath -Encoding ascii -Width 2000 -Force -ErrorAction Stop
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Saved driver pack metadata to:"
    Write-Host -ForegroundColor DarkGray "  $MetadataPath"
    #=================================================
    # Expand the DriverPack
    $DownloadedFile = $OutFileObject.FullName
    $ExpandPath = 'C:\Windows\Temp\osdcloud-driverpack-expand'
    if (-not (Test-Path "$ExpandPath")) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating driver pack expand path: $ExpandPath"
        New-Item $ExpandPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $removeExistingPath = {
        param (
            [System.String]
            $Path
        )

        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Preparing to process driver pack:"
    Write-Host -ForegroundColor DarkGray "  $DownloadedFile"
    #=================================================
    #   Cab
    #=================================================
    if ($OutFileObject.Extension -eq '.cab') {
        $ProgressPhase = "Expanding CAB driver pack to $ExpandPath"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Expanding CAB driver pack to:"
        Write-Host -ForegroundColor DarkGray "  $ExpandPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding CAB DriverPack: $DownloadedFile"
        Expand -R "$DownloadedFile" -F:* "$ExpandPath" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] CAB driver pack extraction failed with exit code $LASTEXITCODE."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Skipping this driver pack and continuing OSDCloud."
            & $removeExistingPath -Path $ExpandPath
            return
        }

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] CAB extraction finished. Applying drivers from:"
        Write-Host -ForegroundColor DarkGray "  $ExpandPath"
        $ProgressPhase = 'Applying CAB driver pack'
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for CAB DriverPack."
        Add-WindowsDriver -Path "C:\" -Driver $ExpandPath -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction Stop | Out-Null

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing temporary driver pack download files."
        & $removeExistingPath -Path "C:\Windows\Temp\osdcloud-driverpack-download"

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing extracted driver files from:"
        Write-Host -ForegroundColor DarkGray "  $ExpandPath"
        & $removeExistingPath -Path $ExpandPath

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing temporary driver files from:"
        Write-Host -ForegroundColor DarkGray "  C:\Drivers"
        & $removeExistingPath -Path "C:\Drivers"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] CAB driver pack processing complete."
        return
    }
    #=================================================
    #   Zip
    #=================================================
    if ($OutFileObject.Extension -eq '.zip') {
        $ProgressPhase = "Expanding ZIP driver pack to $ExpandPath"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Expanding ZIP driver pack to:"
        Write-Host -ForegroundColor DarkGray "  $ExpandPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding ZIP DriverPack: $DownloadedFile"
        Expand-Archive -Path $DownloadedFile -DestinationPath $ExpandPath -Force

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] ZIP extraction finished. Applying drivers from:"
        Write-Host -ForegroundColor DarkGray "  $ExpandPath"
        $ProgressPhase = 'Applying ZIP driver pack'
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for ZIP DriverPack."
        Add-WindowsDriver -Path "C:\" -Driver $ExpandPath -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction Stop | Out-Null

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing temporary driver pack download files from:"
        Write-Host -ForegroundColor DarkGray "  C:\Windows\Temp\osdcloud-driverpack-download"
        & $removeExistingPath -Path "C:\Windows\Temp\osdcloud-driverpack-download"

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing extracted driver files from:"
        Write-Host -ForegroundColor DarkGray "  $ExpandPath"
        & $removeExistingPath -Path $ExpandPath

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing temporary driver files from:"
        Write-Host -ForegroundColor DarkGray "  C:\Drivers"
        & $removeExistingPath -Path "C:\Drivers"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] ZIP driver pack processing complete."
        return
    }
    #=================================================
    #   Dell
    #=================================================
    if (($OutFileObject.Extension -eq '.exe') -and ($OutFileObject.VersionInfo.FileDescription -match 'Dell')) {
        $ProgressPhase = "Expanding Dell driver pack to $ExpandPath"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] FileDescription: $($OutFileObject.VersionInfo.FileDescription)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] ProductVersion: $($OutFileObject.VersionInfo.ProductVersion)"

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Expanding Dell driver pack to:"
        Write-Host -ForegroundColor DarkGray "  $ExpandPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding Dell DriverPack with Start-Process: $DownloadedFile"
        $null = New-Item -Path $ExpandPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
        $ExpandProcess = Start-Process -FilePath $DownloadedFile -ArgumentList "/s /e=`"$ExpandPath`"" -Wait -PassThru
        if ($ExpandProcess.ExitCode -ne 0) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Dell driver pack extraction failed with exit code $($ExpandProcess.ExitCode)."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Skipping this driver pack and continuing OSDCloud."
            & $removeExistingPath -Path $ExpandPath
            return
        }

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Dell extraction finished. Applying drivers from:"
        Write-Host -ForegroundColor DarkGray "  $ExpandPath"
        $ProgressPhase = 'Applying Dell driver pack'
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for Dell DriverPack."
        Add-WindowsDriver -Path "C:\" -Driver $ExpandPath -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction Stop | Out-Null

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing temporary driver pack download files from:"
        Write-Host -ForegroundColor DarkGray "  C:\Windows\Temp\osdcloud-driverpack-download"
        & $removeExistingPath -Path "C:\Windows\Temp\osdcloud-driverpack-download"

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing extracted driver files from:"
        Write-Host -ForegroundColor DarkGray "  $ExpandPath"
        & $removeExistingPath -Path $ExpandPath

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing temporary driver files from:"
        Write-Host -ForegroundColor DarkGray "  C:\Drivers"
        & $removeExistingPath -Path "C:\Drivers"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Dell driver pack processing complete."
        return
    }
    #=================================================
    #   HP
    #=================================================
    if (($OutFileObject.Extension -eq '.exe') -and ($OutFileObject.VersionInfo.InternalName -match 'hpsoftpaqwrapper')) {
        $ProgressPhase = 'Expanding HP driver pack'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] FileDescription: $($OutFileObject.VersionInfo.FileDescription)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] InternalName: $($OutFileObject.VersionInfo.InternalName)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] ProductVersion: $($OutFileObject.VersionInfo.ProductVersion)"

        if (Test-Path -Path $env:windir\System32\7za.exe) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Expanding HP driver pack to:"
            Write-Host -ForegroundColor DarkGray "  $ExpandPath"
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding HP DriverPack with 7za.exe: $DownloadedFile"
            # Start-Process -FilePath $DownloadedFile -ArgumentList "/s /e /f `"$ExpandPath`"" -Wait
            & 7za x "$DownloadedFile" -o"C:\Windows\Temp\osdcloud-driverpack-expand"
            if ($LASTEXITCODE -ne 0) {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] HP driver pack extraction failed with exit code $LASTEXITCODE."
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Skipping this driver pack and continuing OSDCloud."
                & $removeExistingPath -Path $ExpandPath
                return
            }

            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] HP extraction finished. Applying drivers from:"
            Write-Host -ForegroundColor DarkGray "  $ExpandPath"
            $ProgressPhase = 'Applying HP driver pack'
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for HP DriverPack."
            Add-WindowsDriver -Path "C:\" -Driver $ExpandPath -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction Stop | Out-Null

            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing temporary driver pack download files from:"
            Write-Host -ForegroundColor DarkGray "  C:\Windows\Temp\osdcloud-driverpack-download"
            & $removeExistingPath -Path "C:\Windows\Temp\osdcloud-driverpack-download"

            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing extracted driver files from:"
            Write-Host -ForegroundColor DarkGray "  $ExpandPath"
            & $removeExistingPath -Path $ExpandPath

            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Removing temporary driver files from:"
            Write-Host -ForegroundColor DarkGray "  C:\Drivers"
            & $removeExistingPath -Path "C:\Drivers"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] HP driver pack processing complete."
        }
        else {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] 7za.exe was not found at $env:windir\System32\7za.exe."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [WARNING] 7zip 7za.exe needs to be added to WinPE to expand HP DriverPacks."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] HP driver pack was saved but could not be expanded. Saved file:"
            Write-Host -ForegroundColor DarkGray "  $DownloadedFile"

            & $removeExistingPath -Path $ExpandPath
            & $removeExistingPath -Path "C:\Drivers"
        }
        return
    }
    #=================================================
    #   Lenovo
    #=================================================
    if (($OutFileObject.Extension -eq '.exe') -and ($DriverPackCloudObject.Manufacturer -match 'Lenovo')) {
        $ProgressPhase = "Configuring Lenovo driver pack for installation during SetupComplete"
        if (-not (Test-Path $ScriptsPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating scripts path for Lenovo SetupComplete: $ScriptsPath"
            New-Item -Path $ScriptsPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Adding Lenovo driver installation commands to:"
        Write-Host -ForegroundColor DarkGray "  $SetupCompleteCmd"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Appending Lenovo DriverPack install commands to $SetupCompleteCmd."

$Content = @"
:: ========================================================
:: RecastOSDCloud DriverPack Installation for Lenovo
$DownloadedFile /SILENT /SUPPRESSMSGBOXES
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\UnattendSettings\PnPUnattend\DriverPaths\1" /v Path /t REG_SZ /d "C:\Drivers" /f
pnpunattend.exe AuditSystem /L
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\UnattendSettings\PnPUnattend\DriverPaths\1" /v Path /f
rd /s /q C:\Drivers
rd /s /q C:\Windows\Temp\osdcloud-driverpack-download
:: ========================================================
"@
        $Content | Out-File -FilePath $SetupCompleteCmd -Append -Encoding ascii -Width 2000 -Force
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Lenovo installation commands were added to:"
        Write-Host -ForegroundColor DarkGray "  $SetupCompleteCmd"
    & $removeExistingPath -Path $ExpandPath
        return

        <#
        # Write-Host -ForegroundColor DarkGray "FileDescription: $($OutFileObject.VersionInfo.FileDescription)"
        # Write-Host -ForegroundColor DarkGray "ProductVersion: $($OutFileObject.VersionInfo.ProductVersion)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Adding Lenovo SetupSpecialize commands to:"
        Write-Host -ForegroundColor DarkGray "  $SetupSpecializeCmd"

$Content = @"
:: ========================================================
:: RecastOSDCloud DriverPack Installation for Lenovo
$DownloadedFile /SILENT /SUPPRESSMSGBOXES
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\UnattendSettings\PnPUnattend\DriverPaths\1" /v Path /t REG_SZ /d "C:\Drivers" /f
pnpunattend.exe AuditSystem /L
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\UnattendSettings\PnPUnattend\DriverPaths\1" /v Path /f
rd /s /q C:\Drivers
rd /s /q C:\Windows\Temp\osdcloud-driverpack-download
:: ========================================================
"@

        $SetupSpecializePath = "C:\Windows\Temp\osdcloud"
        $Params = @{
            ErrorAction = 'SilentlyContinue'
            Force       = $true
            ItemType    = 'Directory'
            Path        = $SetupSpecializePath
        }
        if (!(Test-Path $Params.Path -ErrorAction SilentlyContinue)) {
            New-Item @Params | Out-Null
        }

        $Content | Out-File -FilePath $SetupSpecializeCmd -Append -Encoding ascii -Width 2000 -Force

        $ProvisioningPackage = Join-Path $$($MyInvocation.MyCommand.Module.ModuleBase) "core\setupspecialize\setupspecialize.ppkg"

        if (Test-Path $ProvisioningPackage) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Adding Provisioning Package for SetupSpecialize"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Adding the SetupSpecialize provisioning package from:"
            Write-Host -ForegroundColor DarkGray "  $ProvisioningPackage"
            $ArgumentList = "/Image=C:\ /Add-ProvisioningPackage /PackagePath:`"$ProvisioningPackage`""
            $null = Start-Process -FilePath 'dism.exe' -ArgumentList $ArgumentList -Wait -NoNewWindow
        }

        & $removeExistingPath -Path $ExpandPath
        return
        #>
    }
    #=================================================
    #   Surface
    #=================================================
    if (($OutFileObject.Extension -eq '.msi') -and ($OutFileObject.Name -match 'surface')) {
        $ProgressPhase = "Configuring Surface driver pack for installation during SetupComplete"
        if (-not (Test-Path $ScriptsPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating scripts path for Surface SetupComplete: $ScriptsPath"
            New-Item -Path $ScriptsPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Adding Surface driver installation commands to:"
        Write-Host -ForegroundColor DarkGray "  $SetupCompleteCmd"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Appending Surface MSI install commands to $SetupCompleteCmd."

$Content = @"
:: ========================================================
:: RecastOSDCloud DriverPack Installation for Microsoft Surface
msiexec /i $DownloadedFile /qn /norestart /l*v C:\Windows\Temp\osdcloud-logs\drivers-driverpack-microsoft.log
rd /s /q C:\Windows\Temp\osdcloud-driverpack-download
:: ========================================================
"@
        $Content | Out-File -FilePath $SetupCompleteCmd -Append -Encoding ascii -Width 2000 -Force
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Surface MSI installation commands were added to:"
        Write-Host -ForegroundColor DarkGray "  $SetupCompleteCmd"
    & $removeExistingPath -Path $ExpandPath
    & $removeExistingPath -Path "C:\Drivers"
        return
    }
    #=================================================
    # End the function
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No DriverPack expansion branch matched $($OutFileObject.FullName)."
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [WARNING] No driver pack processing branch supports '$($OutFileObject.Name)' ($($OutFileObject.Extension), manufacturer '$Manufacturer'). The file was downloaded but not applied."
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack was downloaded, but its format or manufacturer is not supported for processing."
    $Message = "[$(Get-Date -format s)] End"
    Write-Verbose -Message $Message; Write-Debug -Message $Message
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional driver pack step failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Driver pack step stopped during '$ProgressPhase'. See the warning above for details."
    }
    #=================================================
}
