<#
.SYNOPSIS
Validates driver pack availability for an OSDCloud workflow task.

.DESCRIPTION
Checks the selected driver pack before driver download and injection steps run.
The step treats DriverPackName values of None and Microsoft Update Catalog as
valid bypass states. When a driver pack object is present, it validates that the
object has a Url, then checks whether that URL responds online or whether the
matching driver pack file is already available under OSDCloud\DriverPacks on a
local file system drive.

If the driver pack cannot be validated online or offline, the workflow continues
without a driver pack by clearing the driver pack values in the deployment state
and workflow invocation snapshot.

.PARAMETER DriverPackName
Name of the selected driver pack. Defaults to
$global:OSDCloudWorkflowInvoke.DriverPackName.

.PARAMETER DriverPackObject
Driver pack metadata object used for URL and file-name validation. Defaults to
$global:OSDCloudWorkflowInvoke.DriverPackObject.

.EXAMPLE
step-test-targetdriverpack

Validates the driver pack configured in the workflow invocation snapshot.

.NOTES
Internal workflow step used by OSDCloud deployment tasks.

.OUTPUTS
None. This function does not return objects.
#>
function step-test-targetdriverpack {
    [CmdletBinding()]
    param (
        [System.String]
        $DriverPackName = $global:OSDCloudWorkflowInvoke.DriverPackName,

        $DriverPackObject = $global:OSDCloudWorkflowInvoke.DriverPackObject
    )
    #=================================================
    $Error.Clear()
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    # Is DriverPackName set to None?
    if ($DriverPackName -eq 'None') {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPackName is set to None. OK."
        return
    }
    #=================================================
    # Is DriverPackName set to Microsoft Update Catalog?
    if ($DriverPackName -eq 'Microsoft Update Catalog') {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPackName is set to Microsoft Update Catalog. OK."
        return
    }
    #=================================================
    # Is there a DriverPack Object?
    if (-not ($DriverPackObject)) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPackObject is not set. OK."
        return
    }
    #=================================================
    # Is there a URL?
    if (-not $($DriverPackObject.Url)) {
        Write-Warning "[$(Get-Date -format s)] DriverPackObject does not have a Url to validate."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    # Is it reachable online?
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($DriverPackObject.Url)"
    try {
        $WebRequest = Invoke-WebRequest -Uri $DriverPackObject.Url -UseBasicParsing -Method Head
        if ($WebRequest.StatusCode -eq 200) {
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack URL returned a 200 status code. OK."
            return
        }
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack URL is not reachable online and cannot be downloaded."
    }
    #=================================================
    # Does the file exist on a Drive?
    $FileName = Split-Path $DriverPackObject.Url -Leaf
    $MatchingFiles = @()
    $MatchingFiles = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        Get-ChildItem "$($_.Name):\OSDCloud\DriverPacks\" -Include "$FileName" -File -Recurse -Force -ErrorAction Ignore
    }
    if ($MatchingFiles) {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($MatchingFiles[0].FullName)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack is available offline. OK."
        return
    }
    else {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack is not available offline."
    }
    #=================================================
    # DriverPack does not exist
    Write-Warning "[$(Get-Date -format s)] Unable to validate if the DriverPack is reachable online or offline."
    Write-Warning "[$(Get-Date -format s)] OSDCloud will continue without a DriverPack. Clearing variables."
    $global:OSDCloudDeploy.DriverPackObject = $null
    $global:OSDCloudDeploy.DriverPackName = 'None'
    if ($global:OSDCloudWorkflowInvoke) {
        $global:OSDCloudWorkflowInvoke.DriverPackObject = $null
        $global:OSDCloudWorkflowInvoke.DriverPackName = 'None'
    }
    Write-Host -ForegroundColor DarkCyan "[$(Get-Date -format s)] Continuing in 5 seconds..."
    Write-Host -ForegroundColor DarkGray "Press Ctrl+C to exit OSDCloud"
    Start-Sleep -Seconds 5
    #endregion
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
