function step-Add-WindowsDriver-OSDFolder {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $LogPath = "C:\Windows\Temp\osdcloud-logs"
    $OfflinePath = "C:\"

    $osdManufacturer = $global:OSDCoreDevice.OSDManufacturer
    $osdModel        = $global:OSDCoreDevice.OSDModel
    $osdProduct      = $global:OSDCoreDevice.OSDProduct
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSDManufacturer: $osdManufacturer; OSDModel: $osdModel; OSDProduct: $osdProduct"

    if (-not (Test-Path -Path $LogPath)) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating log path: $LogPath"
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }

    $drives = Get-PSDrive -PSProvider FileSystem
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] File system drive count: $(@($drives).Count)"

    $expandRoot = "C:\Windows\Temp\osdcloud-osdfolder-expand"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] ExpandRoot: $expandRoot"

    foreach ($drive in $drives) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Searching drive $($drive.Name): for OSD folder driver matches."
        #region OSDManufacturer — name starts with OSDManufacturer value
        if (-not [string]::IsNullOrWhiteSpace($osdManufacturer)) {
            $parentPath = "$($drive.Name):\OSDCloud\DriverPacks\OSDManufacturer"
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Checking OSDManufacturer parent path: $parentPath"
            if (Test-Path -Path $parentPath) {
                # Folder
                $matchedDirs = Get-ChildItem -Path $parentPath -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "$osdManufacturer*" }
                foreach ($dir in $matchedDirs) {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDManufacturer folder match: $($dir.FullName)"
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for OSDManufacturer folder match."
                    Add-WindowsDriver -Path $OfflinePath -Driver $dir.FullName -Recurse -ForceUnsigned `
                        -LogPath "$LogPath\dism-add-windowsdriver-osdfolder.log" `
                        -ErrorAction SilentlyContinue | Out-Null
                }
                # Zip
                $matchedZips = Get-ChildItem -Path $parentPath -File -Filter "*.zip" -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -like "$osdManufacturer*" }
                foreach ($zip in $matchedZips) {
                    $expandPath = Join-Path -Path $expandRoot -ChildPath $zip.BaseName
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDManufacturer zip match: $($zip.FullName)"
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding OSDManufacturer zip to $expandPath"
                    Expand-Archive -Path $zip.FullName -DestinationPath $expandPath -Force
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for expanded OSDManufacturer zip."
                    Add-WindowsDriver -Path $OfflinePath -Driver $expandPath -Recurse -ForceUnsigned `
                        -LogPath "$LogPath\dism-add-windowsdriver-osdfolder.log" `
                        -ErrorAction SilentlyContinue | Out-Null
                    if (Test-Path -LiteralPath $expandPath) {
                        Remove-Item -LiteralPath $expandPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                # PS1
                $matchedScripts = Get-ChildItem -Path $parentPath -File -Filter "*.ps1" -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -like "$osdManufacturer*" }
                foreach ($script in $matchedScripts) {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDManufacturer ps1 match: $($script.FullName)"
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Invoking OSDManufacturer script match: $($script.FullName)"
                    & $script.FullName
                }
            }
        }
        #endregion

        #region OSDModel — name contains OSDModel value
        if (-not [string]::IsNullOrWhiteSpace($osdModel)) {
            $parentPath = "$($drive.Name):\OSDCloud\DriverPacks\OSDModel"
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Checking OSDModel parent path: $parentPath"
            if (Test-Path -Path $parentPath) {
                # Folder
                $matchedDirs = Get-ChildItem -Path $parentPath -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*$osdModel*" }
                foreach ($dir in $matchedDirs) {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDModel folder match: $($dir.FullName)"
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for OSDModel folder match."
                    Add-WindowsDriver -Path $OfflinePath -Driver $dir.FullName -Recurse -ForceUnsigned `
                        -LogPath "$LogPath\dism-add-windowsdriver-osdfolder.log" `
                        -ErrorAction SilentlyContinue | Out-Null
                }
                # Zip
                $matchedZips = Get-ChildItem -Path $parentPath -File -Filter "*.zip" -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -like "*$osdModel*" }
                foreach ($zip in $matchedZips) {
                    $expandPath = Join-Path -Path $expandRoot -ChildPath $zip.BaseName
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDModel zip match: $($zip.FullName)"
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding OSDModel zip to $expandPath"
                    Expand-Archive -Path $zip.FullName -DestinationPath $expandPath -Force
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for expanded OSDModel zip."
                    Add-WindowsDriver -Path $OfflinePath -Driver $expandPath -Recurse -ForceUnsigned `
                        -LogPath "$LogPath\dism-add-windowsdriver-osdfolder.log" `
                        -ErrorAction SilentlyContinue | Out-Null
                    if (Test-Path -LiteralPath $expandPath) {
                        Remove-Item -LiteralPath $expandPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                # PS1
                $matchedScripts = Get-ChildItem -Path $parentPath -File -Filter "*.ps1" -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -like "*$osdModel*" }
                foreach ($script in $matchedScripts) {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDModel ps1 match: $($script.FullName)"
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Invoking OSDModel script match: $($script.FullName)"
                    & $script.FullName
                }
            }
        }
        #endregion

        #region OSDProduct — name contains OSDProduct value
        if (-not [string]::IsNullOrWhiteSpace($osdProduct)) {
            $parentPath = "$($drive.Name):\OSDCloud\DriverPacks\OSDProduct"
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Checking OSDProduct parent path: $parentPath"
            if (Test-Path -Path $parentPath) {
                # Folder
                $matchedDirs = Get-ChildItem -Path $parentPath -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*$osdProduct*" }
                foreach ($dir in $matchedDirs) {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDProduct folder match: $($dir.FullName)"
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for OSDProduct folder match."
                    Add-WindowsDriver -Path $OfflinePath -Driver $dir.FullName -Recurse -ForceUnsigned `
                        -LogPath "$LogPath\dism-add-windowsdriver-osdfolder.log" `
                        -ErrorAction SilentlyContinue | Out-Null
                }
                # Zip
                $matchedZips = Get-ChildItem -Path $parentPath -File -Filter "*.zip" -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -like "*$osdProduct*" }
                foreach ($zip in $matchedZips) {
                    $expandPath = Join-Path -Path $expandRoot -ChildPath $zip.BaseName
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDProduct zip match: $($zip.FullName)"
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Expanding OSDProduct zip to $expandPath"
                    Expand-Archive -Path $zip.FullName -DestinationPath $expandPath -Force
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Add-WindowsDriver for expanded OSDProduct zip."
                    Add-WindowsDriver -Path $OfflinePath -Driver $expandPath -Recurse -ForceUnsigned `
                        -LogPath "$LogPath\dism-add-windowsdriver-osdfolder.log" `
                        -ErrorAction SilentlyContinue | Out-Null
                    if (Test-Path -LiteralPath $expandPath) {
                        Remove-Item -LiteralPath $expandPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                # PS1
                $matchedScripts = Get-ChildItem -Path $parentPath -File -Filter "*.ps1" -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -like "*$osdProduct*" }
                foreach ($script in $matchedScripts) {
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDProduct ps1 match: $($script.FullName)"
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Invoking OSDProduct script match: $($script.FullName)"
                    & $script.FullName
                }
            }
        }
        #endregion
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
