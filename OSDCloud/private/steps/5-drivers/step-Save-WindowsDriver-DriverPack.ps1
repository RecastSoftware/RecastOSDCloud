function step-Save-WindowsDriver-DriverPack {
    [CmdletBinding()]
    param (
        [System.String]
        $DriverPackName = $global:OSDCloudWorkflowInvoke.DriverPackName,

        $DriverPackCloudObject = $global:OSDCloudWorkflowInvoke.DriverPackCloudObject
    )
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $Step = $global:OSDCloudCurrentStep
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackName: $DriverPackName"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPackCloudObject.Url: $($DriverPackCloudObject.Url)"

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
        Write-Warning "[$(Get-Date -format s)] DriverPackCloudObject does not have a Url to validate."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    # Is it reachable online?
    $IsOnline = $false
    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing DriverPack URL with HEAD request."
        $WebRequest = Invoke-WebRequest -Uri $DriverPackCloudObject.Url -UseBasicParsing -Method Head
        if ($WebRequest.StatusCode -eq 200) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPack URL is reachable online."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack URL returned a 200 status code. OK."
            $IsOnline = $true
        }
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack URL is not reachable online and cannot be downloaded."
    }
    #=================================================
    # Does the file exist on a Drive?
    $IsOffline = $false
    $FileName = $DriverPackCloudObject.FileName
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Searching local drives for DriverPack file: $FileName"
    $MatchingFiles = @()
    $MatchingFiles = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        Get-ChildItem "$($_.Name):\OSDCloud\DriverPacks\" -Include "$FileName" -File -Recurse -Force -ErrorAction Ignore
    }

    if ($MatchingFiles) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Offline DriverPack matches found: $(@($MatchingFiles).Count)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack is available offline. OK."
        $IsOffline = $true
    }
    else {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack is not available offline."
    }
    #=================================================
    # Nothing to do if it is unavailable online and offline
    if ($IsOnline -eq $false -and $IsOffline -eq $false) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPack unavailable online and offline. Skipping save."
        Write-Warning "[$(Get-Date -format s)] DriverPack is not available online or offline. Continue."
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
        New-Item @Params | Out-Null
    }
    #=================================================
    # Is there a USB drive available?
    $USBDrive = Get-DeviceUSBVolume | Where-Object { ($_.FileSystemLabel -match "OSDCloud|USB-DATA") } | `
                Where-Object { $_.SizeGB -ge 16 } | Where-Object { $_.SizeRemainingGB -ge 10 } | Select-Object -First 1

    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($DriverPackCloudObject.Url)"
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] FileName: $FileName"

    if ($USBDrive) {
        $USBDownloadPath = "$($USBDrive.DriveLetter):\OSDCloud\DriverPacks\$Manufacturer"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] USB cache drive selected: $($USBDrive.DriveLetter); USBDownloadPath: $USBDownloadPath"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DownloadPath: $USBDownloadPath"

        if (-not (Test-Path $USBDownloadPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating USB driver pack download path: $USBDownloadPath"
            $null = New-Item -Path $USBDownloadPath -ItemType Directory -Force
        }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Downloading DriverPack to USB cache."
        $SaveWebFile = Invoke-OSDCloudDownloadFile -SourceUrl $DriverPackCloudObject.Url -DestinationDirectory "$USBDownloadPath" -DestinationName $FileName

        if ($SaveWebFile) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Copying cached DriverPack from $($SaveWebFile.FullName) to $DownloadPath."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Copying Offline DriverPack to $DownloadPath"
            $null = Copy-Item -Path $SaveWebFile.FullName -Destination $DownloadPath -Force
            $FileInfo = Get-Item "$DownloadPath\$($SaveWebFile.Name)"
        }
    }
    else {
        # $SaveWebFile is a FileInfo Object, not a path
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DownloadPath: $DownloadPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Downloading DriverPack directly to $DownloadPath."
        $SaveWebFile = Invoke-OSDCloudDownloadFile -SourceUrl $DriverPackCloudObject.Url -DestinationDirectory $DownloadPath -ErrorAction Stop
        $FileInfo = $SaveWebFile
    }
    #=================================================
    # Verify download
    $OutFileObject = Get-Item $FileInfo.FullName
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Downloaded DriverPack file: $($OutFileObject.FullName); Extension: $($OutFileObject.Extension)"

    if (! (Test-Path $OutFileObject)) {
        Write-Warning "[$(Get-Date -format s)] Unable to download the DriverPack from the Internet."
        return
    }
    # Store this as a FileInfo Object
    $DriverPackCloudObject | ConvertTo-Json | Out-File "$($OutFileObject.FullName).json" -Encoding ascii -Width 2000 -Force
    #=================================================
    # Expand the DriverPack
    $DownloadedFile = $OutFileObject.FullName
    $ExpandPath = 'C:\Windows\Temp\osdcloud-driverpack-expand'
    if (-not (Test-Path "$ExpandPath")) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating driver pack expand path: $ExpandPath"
        New-Item $ExpandPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
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
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack: $DownloadedFile"
    #=================================================
    #   Cab
    #=================================================
    if ($OutFileObject.Extension -eq '.cab') {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Expand CAB DriverPack to $ExpandPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding CAB DriverPack: $DownloadedFile"
        Expand -R "$DownloadedFile" -F:* "$ExpandPath" | Out-Null

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Apply drivers in $ExpandPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for CAB DriverPack."
        Add-WindowsDriver -Path "C:\" -Driver $ExpandPath -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction SilentlyContinue | Out-Null

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing C:\Windows\Temp\osdcloud-driverpack-download"
        & $removeExistingPath -Path "C:\Windows\Temp\osdcloud-driverpack-download"

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing $ExpandPath"
        & $removeExistingPath -Path $ExpandPath

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing C:\Drivers"
        & $removeExistingPath -Path "C:\Drivers"
        return
    }
    #=================================================
    #   Zip
    #=================================================
    if ($OutFileObject.Extension -eq '.zip') {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Expand ZIP DriverPack to $ExpandPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding ZIP DriverPack: $DownloadedFile"
        Expand-Archive -Path $DownloadedFile -DestinationPath $ExpandPath -Force

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Apply drivers in $ExpandPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for ZIP DriverPack."
        Add-WindowsDriver -Path "C:\" -Driver $ExpandPath -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction SilentlyContinue | Out-Null

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing C:\Windows\Temp\osdcloud-driverpack-download"
        & $removeExistingPath -Path "C:\Windows\Temp\osdcloud-driverpack-download"

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing $ExpandPath"
        & $removeExistingPath -Path $ExpandPath

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing C:\Drivers"
        & $removeExistingPath -Path "C:\Drivers"
        return
    }
    #=================================================
    #   Dell
    #=================================================
    if (($OutFileObject.Extension -eq '.exe') -and ($OutFileObject.VersionInfo.FileDescription -match 'Dell')) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] FileDescription: $($OutFileObject.VersionInfo.FileDescription)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] ProductVersion: $($OutFileObject.VersionInfo.ProductVersion)"

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Expand Dell DriverPack to $ExpandPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding Dell DriverPack with Start-Process: $DownloadedFile"
        $null = New-Item -Path $ExpandPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
        Start-Process -FilePath $DownloadedFile -ArgumentList "/s /e=`"$ExpandPath`"" -Wait

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Apply drivers in $ExpandPath"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for Dell DriverPack."
        Add-WindowsDriver -Path "C:\" -Driver $ExpandPath -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction SilentlyContinue | Out-Null

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing C:\Windows\Temp\osdcloud-driverpack-download"
        & $removeExistingPath -Path "C:\Windows\Temp\osdcloud-driverpack-download"

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing $ExpandPath"
        & $removeExistingPath -Path $ExpandPath

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing C:\Drivers"
        & $removeExistingPath -Path "C:\Drivers"
        return
    }
    #=================================================
    #   HP
    #=================================================
    if (($OutFileObject.Extension -eq '.exe') -and ($OutFileObject.VersionInfo.InternalName -match 'hpsoftpaqwrapper')) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] FileDescription: $($OutFileObject.VersionInfo.FileDescription)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] InternalName: $($OutFileObject.VersionInfo.InternalName)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] ProductVersion: $($OutFileObject.VersionInfo.ProductVersion)"

        if (Test-Path -Path $env:windir\System32\7za.exe) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Expand HP DriverPack to $ExpandPath"
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding HP DriverPack with 7za.exe: $DownloadedFile"
            # Start-Process -FilePath $DownloadedFile -ArgumentList "/s /e /f `"$ExpandPath`"" -Wait
            & 7za x "$DownloadedFile" -o"C:\Windows\Temp\osdcloud-driverpack-expand"

            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Apply drivers in $ExpandPath"
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for HP DriverPack."
            Add-WindowsDriver -Path "C:\" -Driver $ExpandPath -Recurse -ForceUnsigned -LogPath "$LogPath\dism-add-windowsdriver-driverpack.log" -ErrorAction SilentlyContinue | Out-Null

            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing C:\Windows\Temp\osdcloud-driverpack-download"
            & $removeExistingPath -Path "C:\Windows\Temp\osdcloud-driverpack-download"

            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing $ExpandPath"
            & $removeExistingPath -Path $ExpandPath

            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Removing C:\Drivers"
            & $removeExistingPath -Path "C:\Drivers"
        }
        else {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] 7za.exe was not found at $env:windir\System32\7za.exe."
            Write-Warning "[$(Get-Date -format s)] 7zip 7za.exe needs to be added to WinPE to expand HP DriverPacks"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] HP DriverPack is saved at $DownloadedFile"

            & $removeExistingPath -Path $ExpandPath
            & $removeExistingPath -Path "C:\Drivers"
        }
        return
    }
    #=================================================
    #   Lenovo
    #=================================================
    if (($OutFileObject.Extension -eq '.exe') -and ($DriverPackCloudObject.Manufacturer -match 'Lenovo')) {
        if (-not (Test-Path $ScriptsPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating scripts path for Lenovo SetupComplete: $ScriptsPath"
            New-Item -Path $ScriptsPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Adding Lenovo DriverPack to $SetupCompleteCmd"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Appending Lenovo DriverPack install commands to $SetupCompleteCmd."

$Content = @"
:: ========================================================
:: OSDCloud DriverPack Installation for Lenovo
:: ========================================================
$DownloadedFile /SILENT /SUPPRESSMSGBOXES
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\UnattendSettings\PnPUnattend\DriverPaths\1" /v Path /t REG_SZ /d "C:\Drivers" /f
pnpunattend.exe AuditSystem /L
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\UnattendSettings\PnPUnattend\DriverPaths\1" /v Path /f
rd /s /q C:\Drivers
rd /s /q C:\Windows\Temp\osdcloud-driverpack-download
:: ========================================================
"@
        $Content | Out-File -FilePath $SetupCompleteCmd -Append -Encoding ascii -Width 2000 -Force
    & $removeExistingPath -Path $ExpandPath
        return

        <#
        # Write-Host -ForegroundColor DarkGray "FileDescription: $($OutFileObject.VersionInfo.FileDescription)"
        # Write-Host -ForegroundColor DarkGray "ProductVersion: $($OutFileObject.VersionInfo.ProductVersion)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Adding Lenovo DriverPack to $SetupSpecializeCmd"

$Content = @"
:: ========================================================
:: OSDCloud DriverPack Installation for Lenovo
:: ========================================================
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
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] dism.exe /Image=C:\ /Add-ProvisioningPackage /PackagePath:`"$ProvisioningPackage`""
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
        if (-not (Test-Path $ScriptsPath)) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating scripts path for Surface SetupComplete: $ScriptsPath"
            New-Item -Path $ScriptsPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
        }
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Adding Surface DriverPack to $SetupCompleteCmd"
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Appending Surface MSI install commands to $SetupCompleteCmd."

$Content = @"
:: ========================================================
:: OSDCloud DriverPack Installation for Microsoft Surface
:: ========================================================
msiexec /i $DownloadedFile /qn /norestart /l*v C:\Windows\Temp\osdcloud-logs\drivers-driverpack-microsoft.log
rd /s /q C:\Windows\Temp\osdcloud-driverpack-download
:: ========================================================
"@
        $Content | Out-File -FilePath $SetupCompleteCmd -Append -Encoding ascii -Width 2000 -Force
    & $removeExistingPath -Path $ExpandPath
    & $removeExistingPath -Path "C:\Drivers"
        return
    }
    #=================================================
    # End the function
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No DriverPack expansion branch matched $($OutFileObject.FullName)."
    $Message = "[$(Get-Date -format s)] End"
    Write-Verbose -Message $Message; Write-Debug -Message $Message
    #=================================================
}
