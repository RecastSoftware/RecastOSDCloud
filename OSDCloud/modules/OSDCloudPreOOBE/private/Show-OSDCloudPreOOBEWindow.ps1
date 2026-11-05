function New-OSDCloudPreOOBEState {
    <#
    .SYNOPSIS
        Creates the ordered PreOOBE sequence with discovered applications.
    .DESCRIPTION
        Keeps UI-independent task results and worker ownership in one state object.
        OEM drivers run first because they may be required for network connectivity.
        Discovers local application packages after the four built-in tasks.
        Nothing runs until Start-OSDCloudPreOOBEState is called.
    .EXAMPLE
        New-OSDCloudPreOOBEState
    .NOTES
        Application discovery reads folders; installation waits for Start.
    #>
    [CmdletBinding()]
    param ()
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Create sequence"
    $output = [Collections.Generic.List[string]]::new()
    $startClock = $null
    try {
        $startClock = Get-OSDCloudPreOOBEClock
        $message = "Running OS clock at start: $($startClock.Text); time zone $($startClock.TimeZoneId); UTC $($startClock.Utc.ToString('o'))."
    }
    catch { $message = "Unable to read the running OS clock: $($_.Exception.Message)" }
    $output.Add($message)
    Write-OOBEMenuLog -Message $message
    return @{
        Tasks = @(
            [pscustomobject]@{ Type = 'DriverPack'; Name = 'Driver unpack / install'; Enabled = $true; Outcome = 'Pending'; DurationMs = 0L; Started = $null; Finished = $null },
            [pscustomobject]@{ Type = 'Time'; Name = 'Synchronizing internet time'; Enabled = $true; Outcome = 'Pending'; DurationMs = 0L; Started = $null; Finished = $null },
            [pscustomobject]@{ Type = 'Software'; Name = 'Updating Windows 11'; Enabled = $true; Outcome = 'Pending'; DurationMs = 0L; Started = $null; Finished = $null },
            [pscustomobject]@{ Type = 'Driver'; Name = 'Updating Drivers'; Enabled = $true; Outcome = 'Pending'; DurationMs = 0L; Started = $null; Finished = $null }
            foreach ($application in Get-OSDCloudPreOOBEApplication) {
                [pscustomobject]@{
                    Type = 'Application'; Name = $application.Name; Path = $application.Path
                    Command = $application.Command
                    Enabled = ($application.DefaultSelected -ne $false)
                    Outcome = 'Pending'; DurationMs = 0L; Started = $null; Finished = $null
                }
            }
        )
        Worker = $null; Active = $null; Shared = $null; CloseRequested = $false
        RebootRequired = $false; Started = $false; Complete = $false; Done = $false
        StepDelaySeconds = 10; StepDelay = $null; StepTask = $null; StepRemaining = 10; StartNow = $false
        Paused = $false; PausedTask = $null; StartClock = $startClock
        Output = $output; SummaryWritten = $false
    }
}

function Resume-OSDCloudPreOOBEState {
    <#
    .SYNOPSIS
        Resumes the PreOOBE sequence after a paused Windows Update failure.
    .DESCRIPTION
        Retry returns the failed task to Pending so it runs again after the step
        delay. Otherwise the failure is kept and the remaining tasks continue.
    .PARAMETER State
        Engine state from New-OSDCloudPreOOBEState.
    .PARAMETER Retry
        Runs the failed task again.
    .EXAMPLE
        Resume-OSDCloudPreOOBEState -State $state -Retry
    .NOTES
        Called by the Retry and Continue buttons.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State, [switch]$Retry)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Resume"
    if (-not $State.Paused) { return }
    $task = $State.PausedTask
    if ($Retry -and $task) {
        $task.Outcome = 'Pending'
        $task.DurationMs = 0L
        $task.Started = $null
        $task.Finished = $null
        $message = "Retrying $($task.Name) by technician request."
    }
    else { $message = "Continuing after $($task.Name) failure by technician request." }
    $State.Paused = $false
    $State.PausedTask = $null
    $State.Output.Add($message)
    Write-OOBEMenuLog -Message $message
}

function Start-OSDCloudPreOOBEState {
    <#
    .SYNOPSIS
        Starts the PreOOBE sequence or the counting-down step immediately.
    .DESCRIPTION
        The first call starts the sequence. While a step is counting down, a later
        call starts that step without waiting for the remaining seconds.
    .PARAMETER State
        Engine state from New-OSDCloudPreOOBEState.
    .EXAMPLE
        Start-OSDCloudPreOOBEState -State $state
    .NOTES
        Called by the Start button.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Start"
    if ($State.Done -or $State.CloseRequested) { return }
    if (-not $State.Started) {
        $State.Started = $true
        $message = 'OSDCloud PreOOBE started by technician.'
    }
    elseif ($State.StepDelay -and $State.StepTask) {
        $State.StartNow = $true
        $message = "Starting $($State.StepTask.Name) now by technician request."
    }
    else { return }
    $State.Output.Add($message)
    Write-OOBEMenuLog -Message $message
}

function Update-OSDCloudPreOOBEState {
    <#
    .SYNOPSIS
        Advances task execution without blocking WPF.
    .DESCRIPTION
        Waits for Start, then owns one worker at a time and waits StepDelaySeconds (10)
        before each task starts. Unchecked (disabled) tasks are skipped when reached.
        Failure never becomes success; an Updating Windows 11 failure pauses until
        Retry or Continue. After all tasks finish the engine waits for Continue to OOBE
        (a close request). Close requests cancel updates safely, finish active OEM
        and application installations, and skip pending work.
    .PARAMETER State
        Engine state from New-OSDCloudPreOOBEState.
    .PARAMETER PreviewOnly
        Simulates external operations.
    .EXAMPLE
        Update-OSDCloudPreOOBEState -State $state -PreviewOnly
    .NOTES
        The dispatcher calls this repeatedly; task installers run on the worker.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State, [switch]$PreviewOnly)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Tick"
    if ($State.Done) { return }
    if ($State.CloseRequested) {
        $State.Paused = $false
        $State.PausedTask = $null
        $State.StepDelay = $null
        $State.StepTask = $null
        foreach ($task in $State.Tasks) {
            if ($task.Outcome -eq 'Pending') {
                $task.Outcome = 'Skipped'
                $task.Finished = (Get-Date).ToUniversalTime().ToString('o')
                Write-OOBEMenuLog -Message "Skipped $($task.Name): window closure requested."
            }
        }
        if ($State.Worker -and $State.Active.Type -notin 'DriverPack','Application') { $State.Shared.CancelRequested = $true }
    }
    if (-not $State.Started -and -not $State.CloseRequested) { return }
    if ($State.Worker) {
        $message = $null
        while ($State.Shared.Messages.TryDequeue([ref]$message)) { $State.Output.Add($message) }
        Receive-OSDCloudPreOOBEProcessOutput -State $State
        if (-not $State.Worker.Handle.IsCompleted) { return }
        try {
            [void]$State.Worker.Pipeline.EndInvoke($State.Worker.Handle)
            if ($State.Worker.Pipeline.Streams.Error.Count -gt 0) {
                throw ($State.Worker.Pipeline.Streams.Error | Out-String)
            }
            if ($State.Shared.Outcome -notin 'Succeeded','Failed','Skipped','Cancelled','NotApplicable') {
                throw "Worker ended without a terminal task outcome: $($State.Shared.Outcome)"
            }
            $State.Active.Outcome = $State.Shared.Outcome
        }
        catch {
            $State.Active.Outcome = 'Failed'
            Write-OOBEMenuLog -Message "$($State.Active.Name) worker failed: $($_.Exception.ToString())"
            $message = "$($State.Active.Name) worker failed: $(Get-OSDCloudPreOOBEErrorMessage -Exception $_.Exception)"
            $State.Output.Add($message)
            Write-OOBEMenuLog -Message $message
        }
        finally {
            while ($State.Shared.Messages.TryDequeue([ref]$message)) { $State.Output.Add($message) }
            Receive-OSDCloudPreOOBEProcessOutput -State $State
            $State.RebootRequired = $State.RebootRequired -or $State.Shared.RebootRequired
            $State.Active.DurationMs = $State.Shared.DurationMs
            $State.Active.Finished = (Get-Date).ToUniversalTime().ToString('o')
            Write-OOBEMenuLog -Message "Task $($State.Active.Name) ended $($State.Active.Outcome), $($State.Active.DurationMs) ms."
            if ($State.Active.Type -eq 'Software' -and $State.Active.Outcome -eq 'Failed' -and -not $State.CloseRequested) {
                $State.Paused = $true
                $State.PausedTask = $State.Active
                $message = "$($State.Active.Name) failed. Paused: verify the system date, time and time zone using Shell, then select Retry or Continue."
                $State.Output.Add($message)
                Write-OOBEMenuLog -Message $message
            }
            $State.Worker.Pipeline.Dispose()
            $State.Worker.Runspace.Dispose()
            $State.Worker = $null
            $State.Active = $null
        }
    }
    if ($State.Paused) { return }
    $next = @($State.Tasks | Where-Object Outcome -eq 'Pending' | Select-Object -First 1)
    while ($next.Count -and -not $next[0].Enabled) {
        $next[0].Outcome = 'Skipped'
        $next[0].Finished = (Get-Date).ToUniversalTime().ToString('o')
        $message = "Skipped $($next[0].Name): unchecked by technician."
        $State.Output.Add($message)
        Write-OOBEMenuLog -Message $message
        if ($State.StepTask -eq $next[0]) { $State.StepDelay = $null; $State.StepTask = $null; $State.StartNow = $false }
        $next = @($State.Tasks | Where-Object Outcome -eq 'Pending' | Select-Object -First 1)
    }
    if ($next.Count -and -not $State.CloseRequested) {
        if ($State.StepDelaySeconds -gt 0) {
            if (-not $State.StepDelay -or $State.StepTask -ne $next[0]) {
                $State.StepDelay = [Diagnostics.Stopwatch]::StartNew()
                $State.StepTask = $next[0]
                $message = "$($next[0].Name) starting in $($State.StepDelaySeconds) seconds."
                $State.Output.Add($message)
                Write-OOBEMenuLog -Message $message
            }
            $State.StepRemaining = [Math]::Max(0, $State.StepDelaySeconds - [int][Math]::Floor($State.StepDelay.Elapsed.TotalSeconds))
            if ($State.StepRemaining -gt 0 -and -not $State.StartNow) { return }
            $State.StepDelay = $null
            $State.StepTask = $null
            $State.StartNow = $false
        }
        $State.Active = $next[0]
        $State.Active.Outcome = 'Running'
        $State.Active.Started = (Get-Date).ToUniversalTime().ToString('o')
        $State.Shared = [hashtable]::Synchronized(@{
            Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new()
            ProcessOutput = [Collections.Concurrent.ConcurrentQueue[string]]::new()
            Status = $State.Active.Name; CancelRequested = $false; RebootRequired = $State.RebootRequired
            Succeeded = $false; Outcome = 'Running'; DurationMs = 0L; InstallationActive = $false; ClockTestActive = $false
        })
        if ($State.Active.Type -eq 'Application') {
            $State.Shared.ApplicationPath = $State.Active.Path
            $State.Shared.ApplicationCommand = $State.Active.Command
            $State.Shared.ApplicationName = $State.Active.Name
        }
        Write-OOBEMenuLog -Message "Starting task $($State.Active.Name)."
        try {
            $State.Worker = Start-OOBEMenuUpdateWorker -Type $State.Active.Type -State $State.Shared -PreviewOnly:$PreviewOnly
        }
        catch {
            $State.Active.Outcome = 'Failed'
            $State.Active.Finished = (Get-Date).ToUniversalTime().ToString('o')
            Write-OOBEMenuLog -Message "Could not start $($State.Active.Name): $($_.Exception.ToString())"
            $message = "Could not start $($State.Active.Name): $(Get-OSDCloudPreOOBEErrorMessage -Exception $_.Exception)"
            $State.Output.Add($message)
            Write-OOBEMenuLog -Message $message
            if ($State.Active.Type -eq 'Software') {
                $State.Paused = $true
                $State.PausedTask = $State.Active
                $message = "$($State.Active.Name) failed. Paused: verify the system date, time and time zone using Shell, then select Retry or Continue."
                $State.Output.Add($message)
                Write-OOBEMenuLog -Message $message
            }
            $State.Active = $null
        }
        return
    }
    if (-not $State.SummaryWritten) {
        $State.SummaryWritten = $true
        $summary = [ordered]@{ Completed = (Get-Date).ToUniversalTime().ToString('o'); RebootRequired = $State.RebootRequired; Tasks = $State.Tasks }
        $root = if ($PreviewOnly) { $env:TEMP } else { Join-Path $env:WINDIR 'Temp\osdcloud-logs' }
        try {
            [void][IO.Directory]::CreateDirectory($root)
            $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'OSDCloudPreOOBE-results.json') -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            $message = "Could not persist PreOOBE results: $($_.Exception.Message)"
            $State.Output.Add($message)
            Write-Error -Message $message -ErrorAction Continue
            Write-OOBEMenuLog -Message $message
        }
        foreach ($task in $State.Tasks) {
            $message = "$($task.Name): $($task.Outcome) ($($task.DurationMs) ms)."
            $State.Output.Add($message)
            Write-OOBEMenuLog -Message $message
        }
        $State.Complete = $true
        Write-OOBEMenuLog -Message 'Tasks complete. Waiting for Continue to OOBE.'
    }
    if ($State.CloseRequested) {
        $State.Done = $true
        Write-OOBEMenuLog -Message "PreOOBE finished; exit 0. Reboot required $($State.RebootRequired); no reboot initiated."
    }
}

function Receive-OSDCloudPreOOBEProcessOutput {
    <#
    .SYNOPSIS
        Moves live installer output from the worker into the window output.
    .DESCRIPTION
        Drains the active worker's ProcessOutput queue into State.Output and
        writes the drained lines to OSDCloudPreOOBE.log in one append.
    .PARAMETER State
        Engine state from New-OSDCloudPreOOBEState.
    .EXAMPLE
        Receive-OSDCloudPreOOBEProcessOutput -State $state
    .NOTES
        Called on the dispatcher thread by Update-OSDCloudPreOOBEState.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][hashtable]$State)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Drain installer output"
    if (-not $State.Shared -or $null -eq $State.Shared.ProcessOutput) { return }
    $lines = [Collections.Generic.List[string]]::new()
    $line = $null
    while ($State.Shared.ProcessOutput.TryDequeue([ref]$line)) { $lines.Add($line) }
    if ($lines.Count -eq 0) { return }
    $State.Output.AddRange($lines)
    Write-OOBEMenuLog -Message $lines.ToArray()
}

function Add-OSDCloudPreOOBEOutputText {
    <#
    .SYNOPSIS
        Appends new output lines to the window and limits retained lines.
    .DESCRIPTION
        Appends all new State.Output lines in one update, scrolls to the end,
        and removes the oldest displayed lines once more than MaximumLines plus
        a 10 percent margin are shown, keeping MaximumLines. Log files keep
        the complete output.
    .PARAMETER TextBox
        Output text box.
    .PARAMETER Output
        Engine output list.
    .PARAMETER Ui
        Window state holding OutputCount and DisplayedLengths.
    .PARAMETER MaximumLines
        Number of most recent lines kept in the text box.
    .EXAMPLE
        Add-OSDCloudPreOOBEOutputText -TextBox $box -Output $engine.Output -Ui $ui
    .NOTES
        Called on the dispatcher thread.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]$TextBox,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[string]]$Output,
        [Parameter(Mandatory)][hashtable]$Ui,
        [ValidateRange(10, 100000)][int]$MaximumLines = 5000
    )
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Append output"
    if ($Ui.OutputCount -ge $Output.Count) { return }
    if (-not $Ui.DisplayedLengths) { $Ui.DisplayedLengths = [Collections.Generic.Queue[int]]::new() }
    $text = [Text.StringBuilder]::new()
    while ($Ui.OutputCount -lt $Output.Count) {
        $line = "$($Output[$Ui.OutputCount])`r`n"
        [void]$text.Append($line)
        $Ui.DisplayedLengths.Enqueue($line.Length)
        $Ui.OutputCount++
    }
    $TextBox.AppendText($text.ToString())
    if ($Ui.DisplayedLengths.Count -gt [int]($MaximumLines * 1.1)) {
        $remove = 0
        while ($Ui.DisplayedLengths.Count -gt $MaximumLines) { $remove += $Ui.DisplayedLengths.Dequeue() }
        $TextBox.Text = $TextBox.Text.Substring($remove)
    }
    $TextBox.ScrollToEnd()
}

function Show-OOBEMenuWindow {
    <#
    .SYNOPSIS
        Displays task progress and starts PreOOBE automation after rendering.
    .DESCRIPTION
        Provides independent Shell and Tools menus and an initially expanded step
        list with checkboxes, Start and Skip Step actions, and Continue to OOBE after
        completion. Output fills available height.
    .PARAMETER ReadyEventName
        Optional session-bridge readiness signal.
    .EXAMPLE
        Show-OOBEMenuWindow
    .NOTES
        Requires an STA console input desktop. Preview simulates tasks.
    #>
    [CmdletBinding()]
    param ([string]$ReadyEventName)
    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Show progress"
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
 Title="OSDCloudPreOOBE" Width="820" Height="480" MinWidth="520" MinHeight="360"
 WindowStartupLocation="Manual" Background="#161F5B" Foreground="#F5F5F5"
 FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" Topmost="True"
 UseLayoutRounding="True" SnapsToDevicePixels="True" KeyboardNavigation.TabNavigation="Cycle"
 Cursor="Arrow" ForceCursor="True" AutomationProperties.Name="OSDCloudPreOOBE task engine">
 <shell:WindowChrome.WindowChrome>
  <shell:WindowChrome CaptionHeight="48" GlassFrameThickness="0"
   ResizeBorderThickness="8" UseAeroCaptionButtons="False"/>
 </shell:WindowChrome.WindowChrome>
 <Window.Resources>
  <SolidColorBrush x:Key="SurfaceBrush" Color="#1C2868"/>
  <SolidColorBrush x:Key="ControlBrush" Color="#243475"/>
  <SolidColorBrush x:Key="BorderBrush" Color="#53639C"/>
  <SolidColorBrush x:Key="HoverBrush" Color="#2D4088"/>
  <SolidColorBrush x:Key="AccentBrush" Color="#31D1FF"/>
  <SolidColorBrush x:Key="SidebarBrush" Color="#111949"/>
  <SolidColorBrush x:Key="SecondaryTextBrush" Color="#CDD9F3"/>
  <Style TargetType="Button">
   <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
   <Setter Property="Foreground" Value="#F5F5F5"/><Setter Property="Background" Value="{StaticResource ControlBrush}"/>
   <Setter Property="Padding" Value="12,7"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
     BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
     <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Background" Value="{StaticResource HoverBrush}"/></Trigger>
     <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonBorder" Property="Background" Value="{StaticResource SurfaceBrush}"/></Trigger>
     <Trigger Property="IsKeyboardFocused" Value="True">
      <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#FFFFFF"/>
      <Setter TargetName="ButtonBorder" Property="BorderThickness" Value="3"/>
     </Trigger>
     <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="PrimaryButtonStyle" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
   <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
   <Setter Property="Foreground" Value="#111949"/><Setter Property="FontWeight" Value="SemiBold"/>
   <Setter Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
   <Setter Property="MinWidth" Value="96"/><Setter Property="MinHeight" Value="36"/>
   <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
   </Style.Triggers>
  </Style>
  <Style x:Key="CaptionFocusVisual">
   <Setter Property="Control.Template"><Setter.Value><ControlTemplate>
    <Rectangle Margin="2" Stroke="{StaticResource AccentBrush}" StrokeThickness="1" RadiusX="2" RadiusY="2" SnapsToDevicePixels="True"/>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="CaptionButtonStyle" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
   <Setter Property="Background" Value="Transparent"/><Setter Property="Height" Value="48"/>
   <Setter Property="FocusVisualStyle" Value="{StaticResource CaptionFocusVisual}"/>
   <Setter Property="shell:WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="CaptionBorder" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
     <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="CaptionBorder" Property="Background" Value="{StaticResource HoverBrush}"/></Trigger>
     <Trigger Property="IsPressed" Value="True"><Setter TargetName="CaptionBorder" Property="Background" Value="{StaticResource ControlBrush}"/></Trigger>
     <Trigger Property="IsKeyboardFocused" Value="True">
      <Setter TargetName="CaptionBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
      <Setter TargetName="CaptionBorder" Property="BorderThickness" Value="2"/>
     </Trigger>
     <MultiTrigger><MultiTrigger.Conditions><Condition Property="Tag" Value="Close"/><Condition Property="IsMouseOver" Value="True"/></MultiTrigger.Conditions>
      <Setter TargetName="CaptionBorder" Property="Background" Value="#C42B1C"/>
     </MultiTrigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style x:Key="IconStyle" TargetType="TextBlock">
   <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
   <Setter Property="FontSize" Value="14"/><Setter Property="VerticalAlignment" Value="Center"/>
  </Style>
  <Style x:Key="StepCheckBoxStyle" TargetType="CheckBox">
   <Setter Property="Foreground" Value="#F5F5F5"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Height" Value="40"/><Setter Property="Padding" Value="19,0,12,0"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
    <Border x:Name="StepBorder" Background="Transparent" Padding="{TemplateBinding Padding}">
     <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
      <Border x:Name="Box" Width="18" Height="18" CornerRadius="4" BorderThickness="1"
       BorderBrush="{StaticResource BorderBrush}" Background="{StaticResource ControlBrush}">
       <TextBlock x:Name="Check" Text="&#xE73E;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12"
        Foreground="#111949" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
      </Border>
      <ContentPresenter Margin="12,0,0,0" VerticalAlignment="Center"/>
     </StackPanel>
    </Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsChecked" Value="True">
      <Setter TargetName="Check" Property="Visibility" Value="Visible"/>
      <Setter TargetName="Box" Property="Background" Value="{StaticResource AccentBrush}"/>
      <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
     </Trigger>
     <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="StepBorder" Property="Background" Value="{StaticResource HoverBrush}"/></Trigger>
     <Trigger Property="IsKeyboardFocused" Value="True">
      <Setter TargetName="StepBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
      <Setter TargetName="StepBorder" Property="BorderThickness" Value="2"/>
     </Trigger>
     <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="ContextMenu">
   <Setter Property="KeyboardNavigation.TabNavigation" Value="Cycle"/>
   <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/><Setter Property="Foreground" Value="#F5F5F5"/>
   <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/><Setter Property="FontSize" Value="13"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ContextMenu">
    <Border Background="{TemplateBinding Background}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="4">
     <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Cycle"/>
    </Border>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="MenuItem">
   <Setter Property="KeyboardNavigation.IsTabStop" Value="True"/>
   <Setter Property="Foreground" Value="#F5F5F5"/><Setter Property="Padding" Value="12,7"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="MenuItem">
    <Border x:Name="MenuBorder" Background="Transparent" CornerRadius="4" Padding="{TemplateBinding Padding}">
     <ContentPresenter ContentSource="Header" RecognizesAccessKey="True"/>
    </Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="MenuBorder" Property="Background" Value="{StaticResource HoverBrush}"/></Trigger>
     <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="MenuBorder" Property="Background" Value="{StaticResource HoverBrush}"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="TextBox">
   <Setter Property="Foreground" Value="#F5F5F5"/><Setter Property="Background" Value="{StaticResource ControlBrush}"/>
   <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/><Setter Property="Padding" Value="8"/>
  </Style>
  <Style TargetType="ScrollBar">
   <Setter Property="Width" Value="12"/>
   <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
    <Grid Background="{TemplateBinding Background}">
     <Track x:Name="PART_Track" IsDirectionReversed="True" Orientation="{TemplateBinding Orientation}"
      Minimum="{TemplateBinding Minimum}" Maximum="{TemplateBinding Maximum}" ViewportSize="{TemplateBinding ViewportSize}"
      Value="{Binding Value, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
      <Track.DecreaseRepeatButton>
       <RepeatButton Command="ScrollBar.PageUpCommand" Focusable="False">
        <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template>
       </RepeatButton>
      </Track.DecreaseRepeatButton>
      <Track.Thumb>
       <Thumb>
        <Thumb.Template><ControlTemplate TargetType="Thumb">
         <Border x:Name="ThumbBorder" Background="{StaticResource BorderBrush}" CornerRadius="4" Margin="2"/>
         <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ThumbBorder" Property="Background" Value="{StaticResource AccentBrush}"/></Trigger>
          <Trigger Property="IsDragging" Value="True"><Setter TargetName="ThumbBorder" Property="Background" Value="{StaticResource AccentBrush}"/></Trigger>
         </ControlTemplate.Triggers>
        </ControlTemplate></Thumb.Template>
       </Thumb>
      </Track.Thumb>
      <Track.IncreaseRepeatButton>
       <RepeatButton Command="ScrollBar.PageDownCommand" Focusable="False">
        <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template>
       </RepeatButton>
      </Track.IncreaseRepeatButton>
     </Track>
    </Grid>
    <ControlTemplate.Triggers>
     <Trigger Property="Orientation" Value="Horizontal"><Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
   <Style.Triggers>
    <Trigger Property="Orientation" Value="Horizontal">
     <Setter Property="Width" Value="Auto"/><Setter Property="Height" Value="12"/>
    </Trigger>
   </Style.Triggers>
  </Style>
 </Window.Resources>
 <Grid>
  <Grid.RowDefinitions><RowDefinition Height="48"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Grid Background="{StaticResource SidebarBrush}">
   <Grid.ColumnDefinitions><ColumnDefinition Width="56"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <Button x:Name="PaneToggleButton" KeyboardNavigation.TabIndex="10" Width="56" Padding="0" Style="{StaticResource CaptionButtonStyle}" ToolTip="Collapse steps" AutomationProperties.Name="Collapse steps">
    <TextBlock Text="&#xE700;" Style="{StaticResource IconStyle}"/>
   </Button>
   <TextBlock x:Name="TitleText" Grid.Column="1" Text="Recast Software - OSDCloud PreOOBE" FontWeight="SemiBold" Margin="4,0,4,0" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
   <StackPanel Grid.Column="2" Orientation="Horizontal">
    <Button x:Name="ToolsMenuButton" KeyboardNavigation.TabIndex="11" Style="{StaticResource CaptionButtonStyle}" ToolTip="Deployment tools and Wi-Fi" AutomationProperties.Name="Tools">
     <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE90F;" Style="{StaticResource IconStyle}" Margin="0,0,8,0"/><TextBlock Text="Tools" VerticalAlignment="Center"/></StackPanel>
    </Button>
    <Button x:Name="ShellMenuButton" KeyboardNavigation.TabIndex="12" Style="{StaticResource CaptionButtonStyle}" ToolTip="Open a command shell" AutomationProperties.Name="Shell">
     <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE756;" Style="{StaticResource IconStyle}" Margin="0,0,8,0"/><TextBlock Text="Shell" VerticalAlignment="Center"/></StackPanel>
    </Button>
    <Button x:Name="MinimizeButton" KeyboardNavigation.TabIndex="13" Width="40" Padding="0" Style="{StaticResource CaptionButtonStyle}" ToolTip="Minimize" AutomationProperties.Name="Minimize"><TextBlock Text="&#xE921;" Style="{StaticResource IconStyle}"/></Button>
    <Button x:Name="MaximizeButton" KeyboardNavigation.TabIndex="14" Width="40" Padding="0" Style="{StaticResource CaptionButtonStyle}" ToolTip="Maximize" AutomationProperties.Name="Maximize"><TextBlock x:Name="MaximizeGlyph" Text="&#xE922;" Style="{StaticResource IconStyle}"/></Button>
    <Button x:Name="CloseButton" KeyboardNavigation.TabIndex="15" Width="40" Padding="0" Tag="Close" Style="{StaticResource CaptionButtonStyle}" ToolTip="Finish active operation and continue setup" AutomationProperties.Name="Cancel remaining tasks and continue setup"><TextBlock Text="&#xE8BB;" Style="{StaticResource IconStyle}"/></Button>
   </StackPanel>
  </Grid>
  <Grid Grid.Row="1">
   <Grid.ColumnDefinitions><ColumnDefinition x:Name="SidebarColumn" Width="220"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <Border Background="{StaticResource SidebarBrush}">
    <ScrollViewer Focusable="False" KeyboardNavigation.IsTabStop="False" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
     <StackPanel x:Name="StepPanel" Margin="0,8,0,0" AutomationProperties.Name="PreOOBE steps"/>
    </ScrollViewer>
   </Border>
  <Grid Grid.Column="1" Margin="24,16">
   <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <ScrollViewer x:Name="TaskSummaryScrollViewer" Focusable="True" KeyboardNavigation.IsTabStop="True" KeyboardNavigation.TabIndex="1000000" MaxHeight="120" VerticalScrollBarVisibility="Auto" AutomationProperties.Name="PreOOBE task summary">
     <StackPanel x:Name="TaskSummaryPanel"/>
    </ScrollViewer>
   <ProgressBar x:Name="ProgressBar" Grid.Row="1" Height="4" BorderThickness="0" Margin="0,8,0,12" Foreground="{StaticResource AccentBrush}" Background="{StaticResource ControlBrush}"/>
   <TextBox x:Name="OutputTextBox" KeyboardNavigation.TabIndex="1000001" Grid.Row="2" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" AutomationProperties.Name="PreOOBE task output"/>
   <DockPanel Grid.Row="3" Margin="0,12,0,0" LastChildFill="True">
    <Button x:Name="StepButton" KeyboardNavigation.TabIndex="0" IsDefault="True" Style="{StaticResource PrimaryButtonStyle}" DockPanel.Dock="Right" Content="Start" Margin="12,0,0,0" AutomationProperties.Name="Start OSDCloud PreOOBE"/>
    <Button x:Name="ContinueOobeButton" KeyboardNavigation.TabIndex="0" Style="{StaticResource PrimaryButtonStyle}" DockPanel.Dock="Right" Content="Continue to OOBE" Visibility="Collapsed" Margin="12,0,0,0" AutomationProperties.Name="Continue to OOBE"/>
    <Button x:Name="ContinueButton" KeyboardNavigation.TabIndex="2" DockPanel.Dock="Right" Content="Continue" Visibility="Collapsed" Margin="12,0,0,0" AutomationProperties.Name="Continue with the remaining tasks"/>
    <Button x:Name="RetryButton" KeyboardNavigation.TabIndex="1" DockPanel.Dock="Right" Content="Retry" Visibility="Collapsed" Margin="12,0,0,0" AutomationProperties.Name="Retry Updating Windows 11"/>
    <TextBlock x:Name="StatusText" Text="Starting..." TextWrapping="Wrap" VerticalAlignment="Center" Foreground="{StaticResource SecondaryTextBrush}" AutomationProperties.LiveSetting="Polite"/>
   </DockPanel>
  </Grid>
  </Grid>
  <Border x:Name="ContextBorder" Grid.Row="2" Background="{StaticResource SidebarBrush}" Padding="16,10" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0" Visibility="Collapsed">
   <TextBlock x:Name="ContextText" Text="" TextWrapping="Wrap" AutomationProperties.LiveSetting="Polite"/>
  </Border>
 </Grid>
</Window>
'@
    $reader = [Xml.XmlNodeReader]::new($xaml)
    try { $window = [Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }
    $windowTitle = 'Recast Software - OSDCloud PreOOBE'
    if ($OSDCloudPreOOBEVersion) { $windowTitle += " $OSDCloudPreOOBEVersion" }
    $window.Title = $windowTitle
    $window.FindName('TitleText').Text = $windowTitle
    if ($Preview) { $window.Title += ' (Preview)' }
    $engine = New-OSDCloudPreOOBEState
    $ui = @{ ExitCode = 0; Source = $null; OutputCount = 0 }
    $pointerPath = Join-Path $env:WINDIR 'Cursors\aero_arrow_xl.cur'
    try {
        if (-not (Test-Path -LiteralPath $pointerPath -PathType Leaf)) { throw "Pointer file missing: $pointerPath" }
        $ui.Cursor = [Windows.Input.Cursor]::new($pointerPath)
        $window.Cursor = $ui.Cursor
    }
    catch {
        $message = "Unable to load the extra-large PreOOBE pointer; using the standard arrow: $($_.Exception.Message)"
        Write-Warning -Message $message
        Write-OOBEMenuLog -Message $message
    }
    $updateContext = {
        $messages = @(
            if ($Preview) { 'Preview | No network or system changes' }
            if ($engine.RebootRequired) { 'Reboot required; no automatic reboot' }
        )
        $window.FindName('ContextText').Text = $messages -join ' | '
        $window.FindName('ContextBorder').Visibility = if ($messages.Count) { 'Visible' } else { 'Collapsed' }
    }
    $area = [Windows.SystemParameters]::WorkArea
    $window.Width = [Math]::Min($window.Width, $area.Width)
    $window.Height = [Math]::Min($window.Height, $area.Height)
    $window.MinWidth = [Math]::Min($window.MinWidth, $area.Width)
    $window.MinHeight = [Math]::Min($window.MinHeight, $area.Height)
    $window.Left = $area.Left + [Math]::Min(20, [Math]::Max(0, $area.Width - $window.Width))
    $window.Top = $area.Top + [Math]::Min(20, [Math]::Max(0, $area.Height - $window.Height))
    $hook = [Windows.Interop.HwndSourceHook]{
        param ([IntPtr]$Handle, [int]$Message, [IntPtr]$WParam, [IntPtr]$LParam, [ref]$Handled)
        if ($Message -eq 0x24) { [Recast.OOBE.Native]::AdjustMaximize($Handle, $LParam); $Handled.Value = $true }
        return [IntPtr]::Zero
    }
    $window.Add_SourceInitialized({
        $ui.Source = [Windows.Interop.HwndSource]::FromHwnd([Windows.Interop.WindowInteropHelper]::new($window).Handle)
        $ui.Source.AddHook($hook)
    })
    $launch = {
        param ([string]$Action)
        try {
            if ($Action -eq 'Connect to Wi-Fi') {
                if ($Preview) {
                    $message = 'Preview: would open Connect to Wi-Fi. No adapter scans or network changes.'
                    $engine.Output.Add($message)
                    Write-OOBEMenuLog -Message $message
                    return
                }
                if ($engine.Worker -or $ui.WirelessState -or $engine.CloseRequested) {
                    throw 'Wait for the active task or Wi-Fi dialog to finish before opening Connect to Wi-Fi.'
                }
                $timer.Stop()
                $ui.WirelessState = @{
                    Messages = [Collections.Concurrent.ConcurrentQueue[string]]::new()
                    CancelRequested = $false
                }
                $window.IsEnabled = $false
                try { [void](Invoke-OSDCloudPreOOBEWirelessRecovery -State $ui.WirelessState) }
                finally {
                    $message = $null
                    while ($ui.WirelessState.Messages.TryDequeue([ref]$message)) { $engine.Output.Add($message) }
                    $ui.WirelessState = $null
                    $window.IsEnabled = $true
                    if (-not $engine.Done) { $timer.Start() }
                }
                return
            }
            if ($Action -in 'CMD Prompt','Windows PowerShell') {
                $ps = $Action -eq 'Windows PowerShell'
                $exe = Get-OOBEMenuNativePath -PowerShell:$ps
                $arguments = if ($ps) { '-NoLogo -NoProfile -NoExit -STA' } else { '/d /k' }
            }
            else {
                $exe = Get-OOBEMenuNativePath -Notepad
                $path = switch ($Action) {
                    'Open oobe.cmd' { Join-Path $env:WINDIR 'Setup\Scripts\OOBE.cmd' }
                    'Open setupcomplete.cmd' { Join-Path $env:WINDIR 'Setup\Scripts\SetupComplete.cmd' }
                    'Open autopilot.csv' { 'C:\Windows\Temp\osdcloud-logs\Autopilot.csv' }
                    default { throw "Unknown tool: $Action" }
                }
                if (-not $Preview -and -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "File missing: $path" }
                $arguments = "`"$path`""
            }
            if ($Preview) { $message = "Preview: would open $exe $arguments" }
            else {
                $child = [Recast.OOBE.Native]::Launch($exe, $arguments, $true, 0)
                try { $message = "Opened $Action PID $($child.Id)." }
                finally { $child.Dispose() }
            }
            $engine.Output.Add($message)
            Write-OOBEMenuLog -Message $message
        }
        catch {
            $message = "Unable to open $Action`: $($_.Exception.Message)"
            $engine.Output.Add($message)
            Write-Error -Message $message -ErrorAction Continue
            Write-OOBEMenuLog -Message $message
        }
    }
    foreach ($definition in @(
        @{ Button = 'ShellMenuButton'; Items = @('CMD Prompt','Windows PowerShell') },
        @{ Button = 'ToolsMenuButton'; Items = @(
            'Connect to Wi-Fi','Open oobe.cmd','Open setupcomplete.cmd'
            if (Test-Path -LiteralPath 'C:\Windows\Temp\osdcloud-logs\Autopilot.csv' -PathType Leaf) { 'Open autopilot.csv' }
        ) }
    )) {
        $button = $window.FindName($definition.Button)
        $menu = [Windows.Controls.ContextMenu]::new()
        $menu.Style = $window.FindResource([Windows.Controls.ContextMenu])
        $menu.PlacementTarget = $button
        $menu.Placement = 'Bottom'
        $menu.Cursor = $window.Cursor
        $menu.ForceCursor = $true
        $menu.Add_Opened({ [void]$this.Items[0].Focus() })
        $button.ContextMenu = $menu
        foreach ($header in $definition.Items) {
            $item = [Windows.Controls.MenuItem]::new()
            $item.Header = $header
            if ($header -eq 'Connect to Wi-Fi') { $ui.WirelessMenuItem = $item }
            $item.Style = $window.FindResource([Windows.Controls.MenuItem])
            [Windows.Automation.AutomationProperties]::SetName($item, $header)
            $item.Add_Click({ & $launch ([string]$this.Header) })
            [void]$menu.Items.Add($item)
        }
        $button.Add_Click({ $this.ContextMenu.IsOpen = $true })
    }
    $window.FindName('StepButton').Add_Click({
        if (-not $engine.Started -or $engine.StepDelay) { Start-OSDCloudPreOOBEState -State $engine; return }
        if ($engine.Worker -and $engine.Active.Type -in 'Software','Driver') {
            $engine.Shared.CancelRequested = $true
            Write-OOBEMenuLog -Message "Skip requested for $($engine.Active.Name)."
        }
    })
    $window.FindName('ContinueOobeButton').Add_Click({
        Write-OOBEMenuLog -Message 'Continue to OOBE selected.'
        $window.Close()
    })
    $ui.PaneExpanded = $true
    $ui.StepBoxes = [Collections.Generic.List[object]]::new()
    $setPane = {
        $window.FindName('SidebarColumn').Width = [Windows.GridLength]::new($(if ($ui.PaneExpanded) { 220 } else { 56 }))
        $name = if ($ui.PaneExpanded) { 'Collapse steps' } else { 'Expand steps' }
        $window.FindName('PaneToggleButton').ToolTip = $name
        [Windows.Automation.AutomationProperties]::SetName($window.FindName('PaneToggleButton'), $name)
        foreach ($box in $ui.StepBoxes) { $box.Content = if ($ui.PaneExpanded) { $box.Tag.Name } else { $null } }
    }
    foreach ($task in $engine.Tasks) {
        $box = [Windows.Controls.CheckBox]::new()
        $box.Style = $window.FindResource('StepCheckBoxStyle')
        [Windows.Input.KeyboardNavigation]::SetTabIndex($box, 20 + $ui.StepBoxes.Count)
        $box.IsChecked = $task.Enabled
        $box.Tag = $task
        $box.ToolTip = "$($task.Name) - uncheck to skip"
        [Windows.Automation.AutomationProperties]::SetName($box, $task.Name)
        $toggleStep = {
            $this.Tag.Enabled = [bool]$this.IsChecked
            $state = if ($this.Tag.Enabled) { 'checked' } else { 'unchecked' }
            Write-OOBEMenuLog -Message "$($this.Tag.Name) $state by technician."
        }
        $box.Add_Checked($toggleStep)
        $box.Add_Unchecked($toggleStep)
        [void]$window.FindName('StepPanel').Children.Add($box)
        $ui.StepBoxes.Add($box)
    }
    $window.FindName('PaneToggleButton').Add_Click({ $ui.PaneExpanded = -not $ui.PaneExpanded; & $setPane })
    & $setPane
    for ($index = 0; $index -lt $engine.Tasks.Count; $index++) {
        $text = [Windows.Controls.TextBlock]::new()
        $text.Name = "TaskText$index"
        $text.Margin = [Windows.Thickness]::new(0,0,0,8)
        $text.TextWrapping = 'Wrap'
        $text.Text = "$($engine.Tasks[$index].Name) - $($engine.Tasks[$index].Outcome)"
        $window.RegisterName($text.Name, $text)
        [void]$window.FindName('TaskSummaryPanel').Children.Add($text)
    }
    $window.FindName('RetryButton').Add_Click({ Resume-OSDCloudPreOOBEState -State $engine -Retry })
    $window.FindName('ContinueButton').Add_Click({ Resume-OSDCloudPreOOBEState -State $engine })
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        try {
            $focusedControl = [Windows.Input.Keyboard]::FocusedElement
            Update-OSDCloudPreOOBEState -State $engine -PreviewOnly:$Preview
            $ui.WirelessMenuItem.IsEnabled = -not $engine.Worker -and -not $engine.CloseRequested
            Add-OSDCloudPreOOBEOutputText -TextBox $window.FindName('OutputTextBox') -Output $engine.Output -Ui $ui
            for ($index = 0; $index -lt $engine.Tasks.Count; $index++) {
                $task = $engine.Tasks[$index]
                $outcome = if ($engine.StepDelay -and $engine.StepTask -eq $task -and $task.Outcome -eq 'Pending') { "Starting in $($engine.StepRemaining) seconds" }
                elseif ($engine.Paused -and $engine.PausedTask -eq $task) { 'Failed - Paused' }
                elseif ($task.Outcome -eq 'Pending' -and -not $task.Enabled) { 'Will be skipped' }
                else { $task.Outcome }
                $window.FindName("TaskText$index").Text = "$($task.Name) - $outcome"
                $ui.StepBoxes[$index].IsEnabled = $task.Outcome -eq 'Pending' -and -not $engine.CloseRequested
            }
            $stepButton = $window.FindName('StepButton')
            if (-not $engine.Started -or $engine.StepDelay) {
                $stepButton.Content = 'Start'
                $stepButton.IsEnabled = -not $engine.CloseRequested
                $label = if ($engine.Started) { "Start $($engine.StepTask.Name) now" } else { 'Start OSDCloud PreOOBE' }
            }
            else {
                $stepButton.Content = 'Skip Step'
                $stepButton.IsEnabled = $null -ne $engine.Worker -and $engine.Active.Type -in 'Software','Driver' -and -not $engine.Shared.CancelRequested
                $label = 'Skip current update after its active operation'
            }
            [Windows.Automation.AutomationProperties]::SetName($stepButton, $label)
            $stepButton.Visibility = if ($engine.Paused -or $engine.Complete) { 'Collapsed' } else { 'Visible' }
            $window.FindName('ContinueOobeButton').Visibility = if ($engine.Complete) { 'Visible' } else { 'Collapsed' }
            $pausedVisibility = if ($engine.Paused) { 'Visible' } else { 'Collapsed' }
            $window.FindName('RetryButton').Visibility = $pausedVisibility
            $window.FindName('ContinueButton').Visibility = $pausedVisibility
            $stepButton.IsDefault = $stepButton.Content -eq 'Start' -and $stepButton.IsEnabled -and $stepButton.IsVisible
            $window.FindName('ContinueOobeButton').IsDefault = $engine.Complete
            if ($window.IsActive -and $focusedControl -is [Windows.UIElement] -and
                (-not $focusedControl.IsVisible -or -not $focusedControl.IsEnabled)) {
                $focusTarget = if ($engine.Complete) { $window.FindName('ContinueOobeButton') }
                elseif ($engine.Paused) { $window.FindName('RetryButton') }
                elseif ($stepButton.IsEnabled) { $stepButton }
                else { $window.FindName('PaneToggleButton') }
                [void]$focusTarget.Focus()
            }
            $window.FindName('ProgressBar').IsIndeterminate = $null -ne $engine.Worker
            if ($engine.Complete) { $window.FindName('StatusText').Text = 'OSDCloud PreOOBE complete. Select Continue to OOBE.' }
            elseif ($engine.CloseRequested) { $window.FindName('StatusText').Text = 'Closing after the active operation finishes safely.' }
            elseif (-not $engine.Started) { $window.FindName('StatusText').Text = 'Ready. Select Start to begin OSDCloud PreOOBE.' }
            elseif ($engine.Paused) { $window.FindName('StatusText').Text = "$($engine.PausedTask.Name) failed. Verify the system date, time and time zone using Shell, then select Retry or Continue." }
            elseif ($engine.StepDelay) { $window.FindName('StatusText').Text = "$($engine.StepTask.Name) - Starting in $($engine.StepRemaining) seconds." }
            elseif ($engine.Shared) { $window.FindName('StatusText').Text = $engine.Shared.Status }
            & $updateContext
            if ($engine.Done) { $timer.Stop(); $window.Close() }
        }
        catch {
            $ui.ExitCode = 1
            Write-OOBEMenuLog -Message "Scheduler failed: $($_.Exception.ToString())"
            Write-Error -Message $_.Exception.Message -ErrorAction Continue
            $engine.CloseRequested = $true
            if (-not $engine.Worker) { $engine.Done = $true; $timer.Stop(); $window.Close() }
        }
    })
    $window.FindName('MinimizeButton').Add_Click({ $window.WindowState = 'Minimized' })
    $window.FindName('MaximizeButton').Add_Click({ $window.WindowState = if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } })
    $window.Add_StateChanged({
        $window.FindName('MaximizeGlyph').Text = if ($window.WindowState -eq 'Maximized') { [char]0xE923 } else { [char]0xE922 }
        $name = if ($window.WindowState -eq 'Maximized') { 'Restore' } else { 'Maximize' }
        $window.FindName('MaximizeButton').ToolTip = $name
        [Windows.Automation.AutomationProperties]::SetName($window.FindName('MaximizeButton'),$name)
    })
    $window.FindName('CloseButton').Add_Click({ $window.Close() })
    $window.Add_PreviewKeyDown({
        if ($_.Key -eq [Windows.Input.Key]::Escape) { $_.Handled = $true; $window.Close() }
    })
    $window.Add_Closing({
        if ($ui.WirelessState) { $ui.WirelessState.CancelRequested = $true }
        if (-not $engine.Done) {
            $_.Cancel = $true
            $engine.CloseRequested = $true
            Write-OOBEMenuLog -Message 'Window closure requested; active installer will not be terminated.'
        }
    })
    $window.Add_Closed({
        $timer.Stop()
        if ($ui.Source) { $ui.Source.RemoveHook($hook) }
    })
    $window.Add_ContentRendered({
        try {
            if (-not [Recast.OOBE.Native]::IsInputDesktop()) { throw 'Not on the console input desktop.' }
            $activated = $window.Activate()
            [void]$window.FindName('StepButton').Focus()
            Write-OOBEMenuLog -Message "PreOOBE rendered: session $([Diagnostics.Process]::GetCurrentProcess().SessionId), desktop $([Recast.OOBE.Native]::Desktop), activated $activated, topmost $($window.Topmost), bounds $($window.Left),$($window.Top) $($window.ActualWidth)x$($window.ActualHeight)."
            if ($ReadyEventName) {
                $signal = [Threading.EventWaitHandle]::OpenExisting($ReadyEventName)
                try { [void]$signal.Set() } finally { $signal.Dispose() }
            }
            & $updateContext
            $timer.Start()
        }
        catch {
            $ui.ExitCode = 1
            $engine.Done = $true
            Write-OOBEMenuLog -Message "PreOOBE visibility failed: $($_.Exception.ToString())"
            $window.Close()
        }
    })
    try { [void]$window.ShowDialog() }
    finally {
        $timer.Stop()
        if ($ui.Cursor) { $ui.Cursor.Dispose() }
        if ($engine.Worker) {
            $engine.Shared.CancelRequested = $true
            try { [void]$engine.Worker.Pipeline.EndInvoke($engine.Worker.Handle) }
            finally { $engine.Worker.Pipeline.Dispose(); $engine.Worker.Runspace.Dispose(); $engine.Worker = $null }
        }
    }
    return $ui.ExitCode
}
