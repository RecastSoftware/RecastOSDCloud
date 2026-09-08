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

When a selected Microsoft Surface driver pack URL is unavailable, the step
refreshes that selected catalog entry and retries the latest URL once before
checking for offline content.

If the driver pack cannot be validated online or offline, the workflow continues
without a driver pack by clearing the driver pack values in the deployment state
and workflow invocation snapshot.

.PARAMETER DriverPackName
Name of the selected driver pack. Defaults to
$global:OSDCloudWorkflowInvoke.DriverPackName.

.PARAMETER DriverPackCloudObject
Driver pack metadata object used for URL and file-name validation. Defaults to
$global:OSDCloudWorkflowInvoke.DriverPackCloudObject.

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

        $DriverPackCloudObject = $global:OSDCloudWorkflowInvoke.DriverPackCloudObject
    )
    #=================================================
    $Error.Clear()
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
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
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($DriverPackCloudObject.Url)"
    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing DriverPack URL with HEAD request."
        $WebRequest = Invoke-WebRequest -Uri $DriverPackCloudObject.Url -UseBasicParsing -Method Head
        if ($WebRequest.StatusCode -eq 200) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DriverPack URL is reachable online."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack URL returned a 200 status code. OK."
            return
        }
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] DriverPack URL is not reachable online and cannot be downloaded."
    }
    #=================================================
    # Refresh a selected Microsoft Surface DriverPack and retry the latest URL
    if ($DriverPackCloudObject.Manufacturer -eq 'Microsoft' -and $DriverPackCloudObject.SystemId) {
        $surfaceOSDProduct = $DriverPackCloudObject.SystemId | Where-Object {
            -not [System.String]::IsNullOrWhiteSpace([System.String]$_)
        } | Select-Object -First 1

        if ($surfaceOSDProduct) {
            try {
                Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Refreshing selected Surface DriverPack for OSDProduct '$surfaceOSDProduct'."
                $refreshedDriverPackCloudObject = Update-OSDCoreDriverPackCloudObjectSurface -OSDProduct $surfaceOSDProduct -ErrorAction Stop
                if ($refreshedDriverPackCloudObject) {
                    $DriverPackCloudObject = $refreshedDriverPackCloudObject
                    $DriverPackName = $refreshedDriverPackCloudObject.Name
                    $driverPackCacheObject = Get-OSDCoreDriverPackCacheObject -DriverPackCloudObject $refreshedDriverPackCloudObject

                    if ($global:OSDCloudDeploy) {
                        $global:OSDCloudDeploy.DriverPackCacheObject = $driverPackCacheObject
                        $global:OSDCloudDeploy.DriverPackCloudObject = $refreshedDriverPackCloudObject
                        $global:OSDCloudDeploy.DriverPackName = $refreshedDriverPackCloudObject.Name
                    }
                    if ($global:OSDCloudWorkflowInvoke) {
                        $global:OSDCloudWorkflowInvoke.DriverPackCacheObject = $driverPackCacheObject
                        $global:OSDCloudWorkflowInvoke.DriverPackCloudObject = $refreshedDriverPackCloudObject
                        $global:OSDCloudWorkflowInvoke.DriverPackName = $refreshedDriverPackCloudObject.Name
                    }

                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Retrying refreshed DriverPack URL: $($refreshedDriverPackCloudObject.Url)"
                    try {
                        $WebRequest = Invoke-WebRequest -Uri $refreshedDriverPackCloudObject.Url -UseBasicParsing -Method Head
                        if ($WebRequest.StatusCode -eq 200) {
                            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Refreshed Surface DriverPack URL is reachable online."
                            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Refreshed DriverPack URL returned a 200 status code. OK."
                            return
                        }
                    }
                    catch {
                        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] Refreshed DriverPack URL is not reachable online."
                    }
                }
                else {
                    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] No refreshed Surface DriverPack matched OSDProduct '$surfaceOSDProduct'."
                }
            }
            catch {
                Write-Warning "[$(Get-Date -format s)] Unable to refresh the selected Surface DriverPack. Using the existing DriverPackCloudObject. $($_.Exception.Message)"
            }
        }
    }
    #=================================================
    # Does the file exist on a Drive?
    $FileName = Split-Path $DriverPackCloudObject.Url -Leaf
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Searching local drives for DriverPack file: $FileName"
    $MatchingFiles = @()
    $MatchingFiles = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        Get-ChildItem "$($_.Name):\OSDCloud\DriverPacks\" -Include "$FileName" -File -Recurse -Force -ErrorAction Ignore
    }
    if ($MatchingFiles) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Offline DriverPack matches found: $(@($MatchingFiles).Count)"
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
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Clearing driver pack values from deployment and workflow state."
    $global:OSDCloudDeploy.DriverPackCacheObject = $null
    $global:OSDCloudDeploy.DriverPackCloudObject = $null
    $global:OSDCloudDeploy.DriverPackName = 'None'
    if ($global:OSDCloudWorkflowInvoke) {
        $global:OSDCloudWorkflowInvoke.DriverPackCacheObject = $null
        $global:OSDCloudWorkflowInvoke.DriverPackCloudObject = $null
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
