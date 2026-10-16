BeforeAll {
    . "$PSScriptRoot\Invoke-OSDCloudTimedOperation.ps1"
    $originalInvoke = Get-Variable -Name OSDCloudWorkflowInvoke -Scope Global -ErrorAction SilentlyContinue
}

AfterAll {
    if ($originalInvoke) { $global:OSDCloudWorkflowInvoke = $originalInvoke.Value }
    else { Remove-Variable -Name OSDCloudWorkflowInvoke -Scope Global -ErrorAction SilentlyContinue }
}

Describe 'Deployment phase timing' {
    BeforeEach {
        $global:OSDCloudWorkflowInvoke = [ordered]@{ Durations = @{} }
    }

    It 'preserves output and accumulates unrounded seconds across attempts' {
        $output = Invoke-OSDCloudTimedOperation -Name stepOSDownload -Action {
            [System.Threading.Thread]::Sleep(30)
            'content'
        }
        $output | Should -Be 'content'
        $global:OSDCloudWorkflowInvoke.CompletedTransfers.stepOSDownload | Should -BeTrue
        $first = $global:OSDCloudWorkflowInvoke.Durations.stepOSDownload
        Invoke-OSDCloudTimedOperation -Name stepOSDownload -Action { [System.Threading.Thread]::Sleep(30) }
        $first | Should -BeGreaterOrEqual 0.03
        $global:OSDCloudWorkflowInvoke.Durations.stepOSDownload | Should -BeGreaterOrEqual ($first + 0.03)
    }

    It 'records partial time and preserves the original terminating error' {
        {
            Invoke-OSDCloudTimedOperation -Name stepDriverPackExpand -Action {
                [System.Threading.Thread]::Sleep(30)
                throw 'Synthetic extraction failure'
            }
        } | Should -Throw '*Synthetic extraction failure*'
        $global:OSDCloudWorkflowInvoke.Durations.stepDriverPackExpand | Should -BeGreaterOrEqual 0.03
    }

    It 'classifies an existing <Phase> destination as reuse, not a new download' -TestCases @(
        @{ Phase = 'stepOSDownload' }
        @{ Phase = 'stepOSCache' }
    ) {
        param ($Phase)
        Mock Test-Path { $true }
        $output = Invoke-OSDCloudTimedOperation -Name $Phase -CachedFilePath 'F:\os.esd' -Action { 'cached' }
        $output | Should -Be 'cached'
        $global:OSDCloudWorkflowInvoke.Durations.stepOSDownload | Should -BeNullOrEmpty
        $global:OSDCloudWorkflowInvoke.Durations.stepOSCopy | Should -Not -BeNullOrEmpty
        $global:OSDCloudWorkflowInvoke.CompletedTransfers.stepOSCopy | Should -BeTrue
        $global:OSDCloudWorkflowInvoke.CompletedTransfers.stepOSDownload | Should -BeNullOrEmpty
        $global:OSDCloudWorkflowInvoke.CompletedTransfers.stepOSCache | Should -BeNullOrEmpty
    }

    It 'does not mark a failed transfer as completed' {
        {
            Invoke-OSDCloudTimedOperation -Name stepOSDownload -Action { throw 'Download failed' }
        } | Should -Throw '*Download failed*'
        $global:OSDCloudWorkflowInvoke.CompletedTransfers | Should -BeNullOrEmpty
        $global:OSDCloudWorkflowInvoke.Durations.stepOSDownload | Should -Not -BeNullOrEmpty
    }
}
