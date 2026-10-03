function step-finalize-exportofflineosinfo {
    [CmdletBinding()]
    param ()
    #=================================================
    $Error.Clear()
    $ProgressPhase = 'Preparing offline Windows inventory reports'

    try {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
        $Step = $global:OSDCloudCurrentStep
        $StepLogPath = 'C:\Windows\Temp\osdcloud-logs'
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Exporting offline Windows image inventory reports."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Report destination:"
        Write-Host -ForegroundColor DarkGray "  $StepLogPath"

        $ProgressPhase = 'Reading the current WinPE build number'
        $CurrentOSInfo = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $CurrentOSBuild = $CurrentOSInfo.GetValue('CurrentBuild')
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Current WinPE OS build: $CurrentOSBuild"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Current WinPE build: $CurrentOSBuild"

        if (-not (Test-Path -LiteralPath $StepLogPath -PathType Container -ErrorAction Stop)) {
            $ProgressPhase = 'Creating the offline report directory'
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Creating report directory:"
            Write-Host -ForegroundColor DarkGray "  $StepLogPath"
            New-Item -Path $StepLogPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $Reports = @(
            [pscustomobject]@{
                Name = 'Get-AppxProvisionedPackage'
                FileName = 'Get-AppxProvisionedPackage.txt'
                Command = { Get-AppxProvisionedPackage -Path 'C:\' -ErrorAction Stop }
                Select = { param($Report) $Report | Sort-Object DisplayName }
            }
            [pscustomobject]@{
                Name = 'Get-WindowsCapability'
                FileName = 'Get-WindowsCapability.txt'
                Command = { Get-WindowsCapability -Path 'C:\' -ErrorAction Stop }
                Select = { param($Report) $Report | Sort-Object Name | Select-Object Name, State }
            }
            [pscustomobject]@{
                Name = 'Get-WindowsEdition'
                FileName = 'Get-WindowsEdition.txt'
                Command = { Get-WindowsEdition -Path 'C:\' -ErrorAction Stop }
                Select = { param($Report) $Report | Select-Object Edition }
            }
            [pscustomobject]@{
                Name = 'Get-WindowsOptionalFeature'
                FileName = 'Get-WindowsOptionalFeature.txt'
                Command = { Get-WindowsOptionalFeature -Path 'C:\' -ErrorAction Stop }
                Select = { param($Report) $Report | Sort-Object FeatureName | Select-Object FeatureName, State }
            }
            [pscustomobject]@{
                Name = 'Get-WindowsPackage'
                FileName = 'Get-WindowsPackage.txt'
                Command = { Get-WindowsPackage -Path 'C:\' -ErrorAction Stop }
                Select = { param($Report) $Report | Sort-Object PackageName | Select-Object PackageName, PackageState, ReleaseType }
            }
        )

        $SucceededReports = 0
        foreach ($ReportDefinition in $Reports) {
            $StepLogFile = Join-Path $StepLogPath $ReportDefinition.FileName
            $ProgressPhase = "Exporting $($ReportDefinition.Name)"
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Collecting $($ReportDefinition.Name) data."
            Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Writing report to:"
            Write-Host -ForegroundColor DarkGray "  $StepLogFile"

            try {
                $ReportData = & $ReportDefinition.Command
                if ($ReportData) {
                    $SelectedReportData = & $ReportDefinition.Select $ReportData
                    $SelectedReportData | Out-File -FilePath $StepLogFile -Force -Encoding ascii -ErrorAction Stop
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Exported $(@($ReportData).Count) record(s) to the report."
                }
                else {
                    'No data returned.' | Out-File -FilePath $StepLogFile -Force -Encoding ascii -ErrorAction Stop
                    Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] No data was returned; wrote an empty-result note."
                }
                $SucceededReports++
            }
            catch {
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Could not export $($ReportDefinition.Name): $($_.Exception.Message)"
                Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing with the remaining offline inventory reports."
            }
        }

        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Offline inventory report export finished. Successful reports: $SucceededReports of $($Reports.Count)."
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    }
    catch {
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [ERROR] Optional offline inventory export failed during '$ProgressPhase': $($_.Exception.Message)"
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [PROGRESS] Continuing OSDCloud without complete offline inventory reports."
    }
    #=================================================
}
