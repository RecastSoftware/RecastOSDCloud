function step-install-bcdboot {
    [CmdletBinding()]
    param ()
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"
    #=================================================
    $LogPath = "C:\Windows\Temp\osdcloud-logs"
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] OSBuild: $($global:OSDCloudWorkflowInvoke.OSBuild); LogPath: $LogPath"

    # https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/bcdboot-command-line-options-techref-di?view=windows-11
    # https://support.microsoft.com/en-us/topic/how-to-manage-the-windows-boot-manager-revocations-for-secure-boot-changes-associated-with-cve-2023-24932-41a975df-beb2-40c1-99a3-b3ff139f832d

    Push-Location -Path "C:\Windows\System32"
    if ($global:OSDCloudWorkflowInvoke.OSBuild -lt 26200) {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running bcdboot.exe with legacy /v option."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] C:\Windows\System32\bcdboot.exe C:\Windows /c /v"
        $BCDBootOutput = & C:\Windows\System32\bcdboot.exe C:\Windows /c /v
        $BCDBootOutput | Out-File -FilePath "$LogPath\bcdboot.txt" -Force
    }
    else {
        Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Running bcdboot.exe with /bootex option for newer OS build."
        Write-Host -ForegroundColor DarkGray "[$(Get-Date -format s)] [INFO] C:\Windows\System32\bcdboot.exe C:\Windows /c /bootex"
        $BCDBootOutput = & C:\Windows\System32\bcdboot.exe C:\Windows /c /bootex
        $BCDBootOutput | Out-File -FilePath "$LogPath\bcdboot.txt" -Force
    }
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] bcdboot output written to $LogPath\bcdboot.txt"
    Pop-Location
    #=================================================
    Write-Verbose -Message "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] End"
    #=================================================
}
