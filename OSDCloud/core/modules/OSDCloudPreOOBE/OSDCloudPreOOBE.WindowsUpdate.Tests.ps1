Import-Module "$PSScriptRoot\OSDCloudPreOOBE.psd1" -Force
InModuleScope OSDCloudPreOOBE {
    BeforeAll {
        $Preview = $true
        Initialize-OOBEMenuNative
        $originalDrive = $env:SystemDrive
    }
    AfterAll { $env:SystemDrive = $originalDrive }

    Describe 'Standalone Windows Update engine' {
        BeforeEach {
            $env:SystemDrive = 'C:'
            Mock Write-OOBEMenuLog {}
            Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $true } }
            Mock Get-ItemProperty { [pscustomobject]@{ InstallationType = 'Client'; CurrentBuildNumber = '26100' } }
            $state = [hashtable]::Synchronized(@{
                Status = ''; Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new()
                CancelRequested = $false; Succeeded = $false; RebootRequired = $false
            })
            $script:wu = @{
                State = $state; Calls = [Collections.Generic.List[string]]::new()
                SearchCode = 2; DownloadCode = 2; DownloadItemCode = 2; DownloadHResult = 0
                InstallCode = 2; InstallItemCode = 2; InstallHResult = 0
                RebootRequired = $false; CancelAfterDownload = $false
            }
            $script:wu.Update = [pscustomobject]@{
                Title = 'Windows 11 cumulative update'; EulaAccepted = $false; IsDownloaded = $true
                InstallationBehavior = [pscustomobject]@{ CanRequestUserInput = $false }
            }
            $script:wu.Update | Add-Member ScriptMethod AcceptEula {
                $script:wu.Calls.Add('AcceptEula'); $this.EulaAccepted = $true
            }
            $script:wu.Updates = [pscustomobject]@{ Count = 1 }
            $script:wu.Updates | Add-Member ScriptMethod Item {
                param($Index)
                if ($script:wu.UpdateList) { return $script:wu.UpdateList[$Index] }
                return $script:wu.Update
            }
            $script:wu.Searcher = [pscustomobject]@{}
            $script:wu.Searcher | Add-Member ScriptMethod Search {
                param($Criteria)
                $script:wu.Calls.Add($Criteria)
                return [pscustomobject]@{ ResultCode = $script:wu.SearchCode; Updates = $script:wu.Updates }
            }
            $script:wu.Downloader = [pscustomobject]@{ Updates = $null }
            $script:wu.Downloader | Add-Member ScriptMethod Download {
                $script:wu.Calls.Add('Download')
                if ($script:wu.CancelAfterDownload) { $script:wu.State.CancelRequested = $true }
                $result = [pscustomobject]@{ ResultCode = $script:wu.DownloadCode }
                $result | Add-Member ScriptMethod GetUpdateResult {
                    param($Index)
                    return [pscustomobject]@{ ResultCode = $script:wu.DownloadItemCode; HResult = $script:wu.DownloadHResult }
                }
                return $result
            }
            $script:wu.Installer = [pscustomobject]@{
                Updates = $null; ForceQuiet = $false; AllowSourcePrompts = $true; RebootRequiredBeforeInstallation = $false
            }
            $script:wu.Installer | Add-Member ScriptMethod Install {
                $script:wu.Calls.Add('Install')
                $result = [pscustomobject]@{ ResultCode = $script:wu.InstallCode; RebootRequired = $script:wu.RebootRequired }
                $result | Add-Member ScriptMethod GetUpdateResult {
                    param($Index)
                    return [pscustomobject]@{
                        ResultCode = $script:wu.InstallItemCode; HResult = $script:wu.InstallHResult
                        RebootRequired = $script:wu.RebootRequired
                    }
                }
                return $result
            }
            $script:wu.Session = [pscustomobject]@{ ClientApplicationID = '' }
            $script:wu.Session | Add-Member ScriptMethod CreateUpdateSearcher { return $script:wu.Searcher }
            $script:wu.Session | Add-Member ScriptMethod CreateUpdateDownloader { return $script:wu.Downloader }
            $script:wu.Session | Add-Member ScriptMethod CreateUpdateInstaller { return $script:wu.Installer }
            Mock New-Object { $script:wu.Session } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
            Mock New-Object {
                $selection = [pscustomobject]@{}
                $selection | Add-Member ScriptMethod Add { param($Update) return 0 }
                return $selection
            } -ParameterFilter { $ComObject -eq 'Microsoft.Update.UpdateColl' }
        }

        It 'uses one policy-configured session, filters software and accepts EULAs using the API' {
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            $script:wu.Calls | Should -Contain "IsInstalled=0 and IsHidden=0 and Type='Software'"
            $script:wu.Calls | Should -Contain 'AcceptEula'
            $script:wu.Calls | Should -Contain 'Download'
            $script:wu.Calls | Should -Contain 'Install'
            $script:wu.Installer.ForceQuiet | Should -BeTrue
            $script:wu.Installer.AllowSourcePrompts | Should -BeFalse
            $state.Succeeded | Should -BeTrue
            $state.Status | Should -Be 'Finished. Installed: 1. Failed: 0. Skipped: 0.'
            Should -Invoke New-Object -Times 1 -Exactly -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
        }

        It 'searches driver updates once and reports a required reboot without initiating one' {
            $script:wu.RebootRequired = $true
            Invoke-OOBEMenuWindowsUpdate -Type Driver -State $state
            $script:wu.Calls | Should -Contain "IsInstalled=0 and IsHidden=0 and Type='Driver'"
            $state.RebootRequired | Should -BeTrue
            $state.Status | Should -BeLike '*Reboot required; no reboot initiated*'
        }

        It 'does not download or install excluded Preview or interactive updates' {
            foreach ($reason in 'Preview', 'Interactive') {
                $script:wu.Calls.Clear()
                $script:wu.Update.Title = if ($reason -eq 'Preview') { 'Windows 11 Preview update' } else { 'Interactive update' }
                $script:wu.Update.InstallationBehavior.CanRequestUserInput = $reason -eq 'Interactive'
                Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
                $script:wu.Calls | Should -Not -Contain 'Download'
                $script:wu.Calls | Should -Not -Contain 'Install'
                $script:wu.Calls | Should -Not -Contain 'AcceptEula'
                $state.Status | Should -BeLike '*Installed: 0. Failed: 0. Skipped: 1*'
            }
        }

        It 'reports no updates without any installation' {
            $script:wu.Updates.Count = 0
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            $state.Status | Should -BeLike 'No updates found*'
            $script:wu.Calls | Should -Not -Contain 'Install'
        }

        It 'refuses partial or failed searches instead of treating them as no updates' {
            $script:wu.SearchCode = 3
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            $state.Status | Should -BeLike 'Windows Update failed:*search did not succeed*'
            $state.Succeeded | Should -BeFalse
            $script:wu.Calls | Should -Not -Contain 'Download'
        }

        It 'reports download HRESULT and never installs a failed or incomplete download' {
            $script:wu.DownloadItemCode = 4
            $script:wu.DownloadHResult = -2145124329
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*Download failed*HRESULT 0x*'
            $state.Succeeded | Should -BeFalse
            $state.Status | Should -BeLike '*Failed: 1*'
            $script:wu.Calls | Should -Not -Contain 'Install'
        }

        It 'requires the actual downloaded content even if download result says success' {
            $script:wu.Update.IsDownloaded = $false
            Invoke-OOBEMenuWindowsUpdate -Type Driver -State $state
            $state.Succeeded | Should -BeFalse
            $script:wu.Calls | Should -Not -Contain 'Install'
        }

        It 'reports partial installation as failure, not Done' {
            $script:wu.InstallCode = 3
            $script:wu.InstallItemCode = 4
            $script:wu.InstallHResult = -2145124329
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*Installation failed or partially succeeded*HRESULT*'
            $state.Status | Should -BeLike '*Installed: 0. Failed: 1*'
            $state.Succeeded | Should -BeFalse
        }

        It 'does not install when WUA requires a reboot first' {
            $script:wu.Installer.RebootRequiredBeforeInstallation = $true
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            $state.RebootRequired | Should -BeTrue
            $state.Succeeded | Should -BeFalse
            $state.Status | Should -BeLike '*requires a reboot before installation*'
            $script:wu.Calls | Should -Not -Contain 'Install'
        }

        It 'cancels between download and installation without force-killing WUA' {
            $script:wu.CancelAfterDownload = $true
            Invoke-OOBEMenuWindowsUpdate -Type Driver -State $state
            $state.Status | Should -BeLike 'Cancelled*'
            $state.Succeeded | Should -BeFalse
            $script:wu.Calls | Should -Contain 'Download'
            $script:wu.Calls | Should -Not -Contain 'Install'
        }

        It 'does not start a scan if cancellation was already requested' {
            $state.CancelRequested = $true
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            $state.Status | Should -BeLike '*cancelled before starting*'
            Should -Invoke New-Object -Times 0 -Exactly
        }

        It 'guards WinPE, non-SYSTEM, and unsupported operating systems before COM creation' {
            Mock Get-OOBEMenuContext { [pscustomobject]@{ IsSystem = $false } }
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            $state.Status | Should -BeLike '*full Windows running as SYSTEM*'
            Should -Invoke New-Object -Times 0 -Exactly
        }

        It 'rejects Windows 10 without changing update settings' {
            Mock Get-ItemProperty { [pscustomobject]@{ InstallationType = 'Client'; CurrentBuildNumber = '19045' } }
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            $state.Status | Should -BeLike '*require Windows 11*'
            Should -Invoke New-Object -Times 0 -Exactly
        }

        It 'reports COM startup errors rather than a success-shaped result' {
            Mock New-Object { throw 'Update service unavailable' } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            $state.Status | Should -BeLike '*Windows Update failed*Update service unavailable*'
            $state.Succeeded | Should -BeFalse
        }

        It 'reports a failed update and still processes subsequent independent updates' {
            $first = [pscustomobject]@{
                Title = 'Failed EULA update'; EulaAccepted = $false; IsDownloaded = $true
                InstallationBehavior = [pscustomobject]@{ CanRequestUserInput = $false }
            }
            $first | Add-Member ScriptMethod AcceptEula { throw 'EULA acceptance failed' }
            $script:wu.UpdateList = @($first, $script:wu.Update)
            $script:wu.Updates.Count = 2
            Invoke-OOBEMenuWindowsUpdate -Type Software -State $state
            $state.Status | Should -BeLike '*Installed: 1. Failed: 1*'
            $state.Succeeded | Should -BeFalse
            ($state.Messages.ToArray() -join "`n") | Should -BeLike '*Failed EULA update*EULA acceptance failed*'
        }

        It 'rejects WinPE before COM creation' {
            $env:SystemDrive = 'X:'
            Invoke-OOBEMenuWindowsUpdate -Type Driver -State $state
            $state.Status | Should -BeLike '*full Windows running as SYSTEM*'
            Should -Invoke New-Object -Times 0 -Exactly
        }
    }

    Describe 'Windows Update worker lifecycle' {
        It 'runs asynchronously on an STA thread with managed shared state and no real update calls' {
            Mock Get-Command {
                [pscustomobject]@{ Definition = 'param($Type, $State) $State.Status = "$Type/$([Threading.Thread]::CurrentThread.ApartmentState)"; $State.Succeeded = $true' }
            } -ParameterFilter { $Name -eq 'Invoke-OSDCloudPreOOBETask' }
            $state = [hashtable]::Synchronized(@{ Status = ''; Succeeded = $false })
            $worker = Start-OOBEMenuUpdateWorker -Type Driver -State $state
            try {
                $worker.Handle.AsyncWaitHandle.WaitOne(10000) | Should -BeTrue
                [void]$worker.Pipeline.EndInvoke($worker.Handle)
                $worker.Pipeline.Streams.Error.Count | Should -Be 0
                $state.Status | Should -Be 'Driver/STA'
                $state.Succeeded | Should -BeTrue
            }
            finally { $worker.Pipeline.Dispose(); $worker.Runspace.Dispose() }
        }
    }
}
