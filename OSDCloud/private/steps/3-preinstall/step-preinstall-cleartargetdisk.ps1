function step-preinstall-cleartargetdisk {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [System.Nullable[System.Int32]]
        $DiskNumber = $global:OSDCloudWorkflowInvoke.DeploymentDiskNumber
    )
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Force: $($global:OSDCloudWorkflowInvoke.Force)"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DiskNumber: $DiskNumber"

    if ($global:OSDCloudWorkflowInvoke.Force -eq $true) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Force is enabled; disk-clearing confirmation will be disabled."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Force was specified. Disk-clearing confirmation prompts are disabled"
        if (-not $PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = 'None'
        }
    }

    if ($env:SystemDrive -ne 'X:') {
        Write-Warning "[$($MyInvocation.MyCommand.Name)] Disk clearing is only supported in WinPE; no disks were cleared."
        return
    }

    $LocalDisks = @(
        Get-Disk -ErrorAction Stop |
            Where-Object {
                ($_.IsOffline -eq $false) -and
                ($_.OperationalStatus -ne 'No Media') -and
                ($_.BusType -notin @('File Backed Virtual', 'MAX', 'Microsoft Reserved', 'USB', 'Virtual')) -and
                ($_.IsBoot -eq $false)
            } |
            Sort-Object -Property Number
    )

    if ($null -ne $DiskNumber) {
        $TargetDisks = @($LocalDisks | Where-Object { $_.Number -eq $DiskNumber })
        if ($TargetDisks.Count -eq 0) {
            Write-Warning "[$($MyInvocation.MyCommand.Name)] Disk $DiskNumber is not an eligible non-boot local disk; no disks were cleared."
            return
        }
    }
    elseif ($LocalDisks.Count -eq 1) {
        $TargetDisks = @($LocalDisks)
    }
    elseif ($LocalDisks.Count -gt 1) {
        Write-Warning "[$($MyInvocation.MyCommand.Name)] Multiple eligible local disks were detected. Specify DiskNumber to select the deployment disk; no disks were cleared."
        return
    }
    else {
        Write-Warning "[$($MyInvocation.MyCommand.Name)] No eligible non-boot local disks were detected; no disks were cleared."
        return
    }

    foreach ($Disk in $TargetDisks) {
        $TargetDescription = "Disk $($Disk.Number) $($Disk.BusType) $([int]($Disk.Size / 1000000000))GB $($Disk.FriendlyName)"
        if ($PSCmdlet.ShouldProcess($TargetDescription, 'Clean disk with DiskPart')) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Cleaning Disk $($Disk.Number) with DiskPart."
            $DiskPartCommands = @(
                "select disk $($Disk.Number)"
                'clean'
                'exit'
            )
            $DiskPartOutput = $DiskPartCommands | diskpart.exe
            $DiskPartExitCode = $LASTEXITCODE
            if (($null -ne $DiskPartExitCode) -and ($DiskPartExitCode -ne 0)) {
                throw "DiskPart failed to clean disk $($Disk.Number) with exit code $DiskPartExitCode. $DiskPartOutput"
            }
        }
    }
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
