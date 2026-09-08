function step-install-getwindowsimageindex {
    <#
        .SYNOPSIS
        First, verify the WindowsImage to ensure that it is valid for deployment.
        Second, determine the ImageIndex to expand, or to allow the user to select the ImageIndex.

        .INPUTS
        $global:OSDCloudWorkflowInvoke.FileInfoWindowsImage
        Contains the FileInfo object of the WindowsImage to be expanded.
        This variable was created step-install-downloadwindowsimage

        $global:OSDCloudWorkflowInvoke.FileInfoWindowsImage.FullName
        Contains the FullName of the WindowsImage to be expanded.
        This variable was created by step-install-downloadwindowsimage

        $global:OSDCloudWorkflowInvoke.OSEditionId
        Contains the EditionId of the WindowsImage to be expanded.
        This property is copied from the pre-deployment state before workflow execution.

        .OUTPUTS
        $global:OSDCloudWorkflowInvoke.WindowsImageIndex
        Contains the ImageIndex of the WindowsImage to be expanded.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [System.String]
        $ImagePath = $global:OSDCloudWorkflowInvoke.FileInfoWindowsImage.FullName,

        [Parameter(Mandatory = $false)]
        [System.String]
        $EditionId = $global:OSDCloudWorkflowInvoke.OSEditionId,

        [Parameter(Mandatory = $false)]
        [System.String]
        $ImageName
    )
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] ImagePath: $ImagePath"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] EditionId: $EditionId; ImageName: $ImageName"

    # Do we have a WindowsImage to test?
    if ($null -eq $ImagePath) {
        Write-Warning "[$(Get-Date -format s)] WindowsImage does not have an ImagePath."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    # Does the Path exist?
    if (-not (Test-Path $ImagePath)) {
        Write-Warning "[$(Get-Date -format s)] WindowsImage does not exist at the ImagePath."
        Write-Warning $ImagePath
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    # Does Get-WindowsImage work?
    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running Get-WindowsImage against $ImagePath."
        $WindowsImage = Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop
    }
    catch {
        Write-Warning "[$(Get-Date -format s)] Unable to verify the Windows Image using Get-WindowsImage."
        Write-Warning "[$(Get-Date -format s)] $_"
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    # Is there only one ImageIndex?
    $WindowsImageCount = ($WindowsImage).Count
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] WindowsImageCount: $WindowsImageCount"

    if ($WindowsImageCount -eq 1) {
        # Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OSDCloud only found a single ImageIndex to expand"
        $global:OSDCloudWorkflowInvoke.WindowsImageIndex = 1
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Single image found; WindowsImageIndex set to 1."
        return
    }
    #=================================================
    # Get the ImageIndex of the ImageName
    if ($ImageName) {
        $ImageIndex = ($WindowsImage | Where-Object { $_.ImageName -eq $ImageName }).ImageIndex
        $global:OSDCloudWorkflowInvoke.WindowsImageIndex = $ImageIndex
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] ImageName match set WindowsImageIndex to $ImageIndex."
        return
    }
    #=================================================
    # Get the ImageIndex of the EditionId
    if ($EditionId) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Searching Windows image indexes for EditionId $EditionId."
        $MatchingWindowsImage = $WindowsImage | `
            ForEach-Object { Get-WindowsImage -ImagePath $ImagePath -Index $_.ImageIndex } | `
            Where-Object { $_.EditionId -eq $EditionId }

        if ($MatchingWindowsImage -and $MatchingWindowsImage.Count -eq 1) {
            $global:OSDCloudWorkflowInvoke.WindowsImage = $MatchingWindowsImage
            $global:OSDCloudWorkflowInvoke.WindowsImageIndex = $MatchingWindowsImage.ImageIndex
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] EditionId match set WindowsImageIndex to $($global:OSDCloudWorkflowInvoke.WindowsImageIndex)."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] EditionId $EditionId found at ImageIndex $($global:OSDCloudWorkflowInvoke.WindowsImageIndex)"
            return
        }
    }
    #=================================================
    # Unable to determine which ImageIndex to apply, so prompt the user to select the ImageIndex
    Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] Select the WindowsImage to expand"
    $SelectWindowsImage = $WindowsImage | Where-Object { $_.ImageSize -gt 3000000000 }

    if ($SelectWindowsImage) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Prompting user to select from $(@($SelectWindowsImage).Count) image indexes."
        $SelectWindowsImage | Select-Object -Property ImageIndex, ImageName | Format-Table | Out-Host

        do {
            $SelectReadHost = Read-Host -Prompt 'Select an WindowsImage to expand by ImageIndex [Number]'
        }
        until (((($SelectReadHost -ge 0) -and ($SelectReadHost -in $SelectWindowsImage.ImageIndex))))

        $global:OSDCloudWorkflowInvoke.WindowsImageIndex = $SelectReadHost
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] User selected WindowsImageIndex $SelectReadHost."
        return
    }
    #=================================================
    # Everything we tried failed, so exit OSDCloud
    Write-Warning "[$(Get-Date -format s)] Unable to determine the ImageIndex to apply."
    Write-Warning 'Press Ctrl+C to exit OSDCloud'
    Start-Sleep -Seconds 86400
    exit
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
