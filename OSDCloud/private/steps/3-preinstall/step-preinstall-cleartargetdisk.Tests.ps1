BeforeAll {
    if (-not ('OSDCloudTimingTestHost' -as [type])) {
        Add-Type -ReferencedAssemblies ([System.Management.Automation.PSObject].Assembly.Location) -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
using System.Threading;

public class OSDCloudTimingTestUI : PSHostUserInterface {
    public bool Accept = true;
    public int Prompts;
    public override PSHostRawUserInterface RawUI { get { return null; } }
    public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
        Prompts++;
        Thread.Sleep(100);
        for (int i = 0; i < choices.Count; i++) {
            if (choices[i].Label.Replace("&", "") == (Accept ? "Yes" : "No")) return i;
        }
        throw new InvalidOperationException("Expected confirmation choice was not found.");
    }
    public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions) { throw new NotSupportedException(); }
    public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName) { throw new NotSupportedException(); }
    public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes types, PSCredentialUIOptions options) { throw new NotSupportedException(); }
    public override string ReadLine() { throw new NotSupportedException(); }
    public override SecureString ReadLineAsSecureString() { throw new NotSupportedException(); }
    public override void Write(string value) {}
    public override void Write(ConsoleColor foreground, ConsoleColor background, string value) {}
    public override void WriteLine(string value) {}
    public override void WriteErrorLine(string value) {}
    public override void WriteDebugLine(string value) {}
    public override void WriteProgress(long sourceId, ProgressRecord record) {}
    public override void WriteVerboseLine(string value) {}
    public override void WriteWarningLine(string value) {}
}
public class OSDCloudTimingTestHost : PSHost {
    private readonly Guid instanceId = Guid.NewGuid();
    public OSDCloudTimingTestUI TestUI = new OSDCloudTimingTestUI();
    public override PSHostUserInterface UI { get { return TestUI; } }
    public override Guid InstanceId { get { return instanceId; } }
    public override string Name { get { return "OSDCloudTimingTestHost"; } }
    public override Version Version { get { return new Version(1, 0); } }
    public override CultureInfo CurrentCulture { get { return CultureInfo.InvariantCulture; } }
    public override CultureInfo CurrentUICulture { get { return CultureInfo.InvariantCulture; } }
    public override void SetShouldExit(int exitCode) { throw new NotSupportedException(); }
    public override void EnterNestedPrompt() { throw new NotSupportedException(); }
    public override void ExitNestedPrompt() { throw new NotSupportedException(); }
    public override void NotifyBeginApplication() {}
    public override void NotifyEndApplication() {}
}
'@
    }
}

Describe 'Disk confirmation duration' {
    It 'measures only confirmation and preserves safety: <Mode>' -TestCases @(
        @{ Mode = 'Accept' }
        @{ Mode = 'Decline' }
        @{ Mode = 'Force' }
        @{ Mode = 'ForceConfirm' }
        @{ Mode = 'ConfirmFalse' }
        @{ Mode = 'WhatIf' }
    ) {
        param ($Mode)
        $testHost = New-Object OSDCloudTimingTestHost
        $testHost.TestUI.Accept = $Mode -ne 'Decline'
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($testHost)
        $powershell = [powershell]::Create()
        $originalSystemDrive = $env:SystemDrive
        try {
            $runspace.Open()
            $powershell.Runspace = $runspace
            $null = $powershell.AddScript({
                param ($Root, $Mode)
                . "$Root\..\..\Invoke-OSDCloudTimedOperation.ps1"
                . "$Root\step-preinstall-cleartargetdisk.ps1"
                $env:SystemDrive = 'X:'
                $global:OSDCloudWorkflowInvoke = [ordered]@{ Force = $Mode -in @('Force', 'ForceConfirm'); DeploymentDiskNumber = 0; Durations = @{} }
                function Get-Disk {
                    [CmdletBinding()] param ()
                    [pscustomobject]@{ Number = 0; IsOffline = $false; OperationalStatus = 'Online'; BusType = 'NVMe'; IsBoot = $false; Size = 128GB; FriendlyName = 'Test' }
                }
                function diskpart.exe {
                    [System.Threading.Thread]::Sleep(400)
                    $global:diskCleaned = $true
                    $global:LASTEXITCODE = 0
                }
                if ($Mode -eq 'Force') { step-preinstall-cleartargetdisk }
                elseif ($Mode -eq 'ConfirmFalse') { step-preinstall-cleartargetdisk -Confirm:$false }
                elseif ($Mode -eq 'WhatIf') { step-preinstall-cleartargetdisk -WhatIf }
                else { step-preinstall-cleartargetdisk -Confirm }
                [pscustomobject]@{ Wait = $global:OSDCloudWorkflowInvoke.Durations.stepClearDisk; Cleaned = [bool]$global:diskCleaned }
            }).AddArgument($PSScriptRoot).AddArgument($Mode)
            $output = $powershell.Invoke()
            $powershell.Streams.Error.Count | Should -Be 0
            $output.Count | Should -Be 1
            if ($Mode -in @('Accept', 'Decline', 'ForceConfirm')) {
                $testHost.TestUI.Prompts | Should -Be 1
                $output[0].Wait | Should -BeGreaterOrEqual 0.1
            }
            else { $testHost.TestUI.Prompts | Should -Be 0 }
            $output[0].Wait | Should -BeLessThan 0.4
            $output[0].Cleaned | Should -Be ($Mode -in @('Accept', 'Force', 'ForceConfirm', 'ConfirmFalse'))
        }
        finally {
            $env:SystemDrive = $originalSystemDrive
            $powershell.Dispose()
            $runspace.Dispose()
        }
    }
}
