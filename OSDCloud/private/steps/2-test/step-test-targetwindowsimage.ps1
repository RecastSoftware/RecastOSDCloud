<#
.SYNOPSIS
Validates Windows image availability for an OSDCloud workflow task.

.DESCRIPTION
Checks that the selected Windows image can be used before download and install
steps run. The step first accepts an existing local image selected in
$global:OSDCloudWorkflowInvoke.OperatingSystemCacheObject. If no cached image is
available, it validates
$global:OSDCloudWorkflowInvoke.OperatingSystemCloudObject.FilePath by checking
whether the URL responds online or whether the matching image file is already
available under OSDCloud\OS on a local file system drive.

When the Windows image cannot be validated online or offline, the step waits so
the user can cancel the deployment before exiting.

.PARAMETER LaunchMethod
Reserved for launch-method specific validation. Defaults to
$global:OSDCloudWorkflowInvoke.LaunchMethod.

.EXAMPLE
step-test-targetwindowsimage

Validates the Windows image configured in the workflow invocation snapshot.

.NOTES
Internal workflow step used by OSDCloud deployment tasks.

.OUTPUTS
None. This function does not return objects.
#>
function step-test-targetwindowsimage {
    [CmdletBinding()]
    param (
        [System.String]
        $LaunchMethod = $global:OSDCloudWorkflowInvoke.LaunchMethod
    )
    #=================================================
    $Error.Clear()
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $OperatingSystemCloudObject = $global:OSDCloudWorkflowInvoke.OperatingSystemCloudObject
    $OperatingSystemCacheObject = $global:OSDCloudWorkflowInvoke.OperatingSystemCacheObject
    $OperatingSystemFilePath = [string]$OperatingSystemCloudObject.FilePath
    if ([string]::IsNullOrWhiteSpace($OperatingSystemFilePath)) {
        $OperatingSystemFilePath = [string]$OperatingSystemCloudObject.Url
    }
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] LaunchMethod: $LaunchMethod"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OperatingSystemFilePath: $OperatingSystemFilePath"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OperatingSystemCacheObject: $OperatingSystemCacheObject"
    #=================================================
    # Is there a cached image file already selected?
    if ($OperatingSystemCacheObject) {
        $OperatingSystemCachePath = if ($OperatingSystemCacheObject.FullName) { $OperatingSystemCacheObject.FullName } else { [string]$OperatingSystemCacheObject }
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing selected cache path: $OperatingSystemCachePath"
        if (Test-Path -LiteralPath $OperatingSystemCachePath) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Cached Windows image was found."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $OperatingSystemCachePath"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem is available offline. OK."
            return
        }
    }
    #=================================================
    # Is there an Operating System ImageFile URL?
    if ([string]::IsNullOrWhiteSpace($OperatingSystemFilePath)) {
        Write-Warning "[$(Get-Date -format s)] OperatingSystemCloudObject does not have a FilePath or Url to validate."
        Write-Warning 'Press Ctrl+C to exit OSDCloud'
        Start-Sleep -Seconds 86400
        exit
    }
    #=================================================
    # Is it reachable online?
    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $OperatingSystemFilePath"
    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Testing OperatingSystem URL with HEAD request."
        $WebRequest = Invoke-WebRequest -Uri $OperatingSystemFilePath -UseBasicParsing -Method Head
        if ($WebRequest.StatusCode -eq 200) {
            Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OperatingSystem URL is reachable online."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem URL returned a 200 status code. OK."
            return
        }
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem URL is not reachable online and cannot be downloaded."
    }
    #=================================================
    # Does the file exist on a Drive?
    $FileName = if ($OperatingSystemCloudObject.FileName) { [string]$OperatingSystemCloudObject.FileName } else { Split-Path $OperatingSystemFilePath -Leaf }
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Searching local drives for OperatingSystem file: $FileName"
    $MatchingFiles = @()
    $MatchingFiles = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        Get-ChildItem "$($_.Name):\OSDCloud\OS\" -Include "$FileName" -File -Recurse -Force -ErrorAction Ignore
    }
    if ($MatchingFiles) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Offline OperatingSystem matches found: $(@($MatchingFiles).Count)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] $($MatchingFiles[0].FullName)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem is available offline. OK."
        return
    }
    else {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] OperatingSystem is not available offline."
    }
    #=================================================
    # Can't access the file so need to bail
    Write-Warning "[$(Get-Date -format s)] Unable to validate if the OperatingSystem is reachable online or offline."
    Write-Warning 'Press Ctrl+C to exit OSDCloud'
    Start-Sleep -Seconds 86400
    Exit
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}

<#
    if ($LaunchMethod) {
        #TODO This is not working for Core
        #$null = Install-Module -Name $global:OSDCloudWorkflowInvoke.LaunchMethod -Force -ErrorAction Ignore -WarningAction Ignore
    }
#>
