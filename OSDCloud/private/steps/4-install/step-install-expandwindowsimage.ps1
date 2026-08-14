function step-install-expandwindowsimage {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] C:\"
    #=================================================
    #   Create ScratchDirectory
    $Params = @{
        ErrorAction = 'SilentlyContinue'
        Force       = $true
        ItemType    = 'Directory'
        Path        = 'C:\OSDCloud\Temp'
    }
    if (-not (Test-Path $Params.Path -ErrorAction SilentlyContinue)) {
        New-Item @Params | Out-Null
    }
    #=================================================
    # Build the Params
    $windowsImagePath = [string]$global:OSDCloudWorkflowInvoke.WindowsImagePath
    if ($windowsImagePath -match '\.swm$') {
        #TODO - Add support for multiple SWM files
        $Params = @{
            ApplyPath             = 'C:\'
            ErrorAction           = 'Stop'
            ImagePath             = $windowsImagePath
            Name                  = (Get-WindowsImage -ImagePath $windowsImagePath).ImageName
            ScratchDirectory      = 'C:\OSDCloud\Temp'
            SplitImageFilePattern = $windowsImagePath.replace('install.swm', 'install*.swm')
        }
    }
    else {
        $Params = @{
            ApplyPath        = 'C:\'
            ErrorAction      = 'Stop'
            ImagePath        = $global:OSDCloudWorkflowInvoke.WindowsImagePath
            Index            = $global:OSDCloudWorkflowInvoke.WindowsImageIndex
            ScratchDirectory = 'C:\OSDCloud\Temp'
        }
    }

    $global:OSDCloudWorkflowInvoke.ParamsExpandWindowsImage = $Params
    #=================================================
    # Expand WindowsImage
    if ($global:OSDCoreDevice.IsWinPE -eq $true) {
        try {
            Expand-WindowsImage @Params | Out-Null
        }
        catch {
            Write-Warning "[$(Get-Date -format s)] Expand-WindowsImage failed."
            Write-Warning "[$(Get-Date -format s)] $_"
            Write-Warning 'Press Ctrl+C to exit OSDCloud'
            Start-Sleep -Seconds 86400
            exit
        }
    }
    #=================================================
    # Remove OS after expanding the image
    $Params = @{
        ErrorAction = 'SilentlyContinue'
        Force       = $true
        Path        = 'C:\OSDCloud\Temp'
    }
    if (Test-Path $Params.Path -ErrorAction SilentlyContinue) {
        Remove-Item @Params | Out-Null
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
