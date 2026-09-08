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
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Creating scratch directory: $($Params.Path)"
        New-Item @Params | Out-Null
    }
    #=================================================
    # Build the Params
    $windowsImagePath = [string]$global:OSDCloudWorkflowInvoke.WindowsImagePath
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] WindowsImagePath: $windowsImagePath"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] WindowsImageIndex: $($global:OSDCloudWorkflowInvoke.WindowsImageIndex)"
    if ($windowsImagePath -match '\.swm$') {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Split WIM/SWM image detected. Building Expand-WindowsImage parameters with SplitImageFilePattern."
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
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Standard Windows image detected. Building Expand-WindowsImage parameters with ImageIndex."
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
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Expand-WindowsImage with parameters: $($Params | Out-String)"
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
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Device is not WinPE; skipping Expand-WindowsImage execution."
    }
    #=================================================
    # Remove OS after expanding the image
    $Params = @{
        ErrorAction = 'SilentlyContinue'
        Force       = $true
        Path        = 'C:\OSDCloud\Temp'
    }
    if (Test-Path $Params.Path -ErrorAction SilentlyContinue) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Removing scratch directory: $($Params.Path)"
        Remove-Item @Params | Out-Null
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
