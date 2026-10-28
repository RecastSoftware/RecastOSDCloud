function Show-WinpeStartupProfileWindow {
    <#
    .SYNOPSIS
        Shows a WPF window for selecting a WinpeStartup profile.

    .DESCRIPTION
        Displays the discovered WinpeStartup profiles in a small dark window
        styled like OSDCloud Boot. Only profile names are listed; hovering over a
        profile shows its JSON path and asset folder. Start, Enter, or a
        double-click returns the selected profile. Cancel, Escape, or closing
        the window returns nothing.

        Throws when WPF cannot be loaded or the window cannot be shown so the
        caller can fall back to the console prompt.

    .PARAMETER Profiles
        Profile candidate objects from Get-WinpeStartupProfileCandidates. Each
        object must have Profile and Path properties and may have AssetPath.

    .EXAMPLE
        $selected = Show-WinpeStartupProfileWindow -Profiles @(Get-WinpeStartupProfileCandidates)

        Shows the profile selector and returns the selected candidate or $null.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Used by Invoke-WinpeStartup unless -CLI is specified.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Profiles
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Recast Software - OSDCloud WinpeStartup" Width="640" Height="480" MinWidth="480" MinHeight="360"
        WindowStartupLocation="CenterScreen" Background="#161F5B" Topmost="True"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" Foreground="#F5F5F5"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <SolidColorBrush x:Key="AccentBrush" Color="#31D1FF"/>
        <SolidColorBrush x:Key="SurfaceBrush" Color="#1C2868"/>
        <SolidColorBrush x:Key="ControlBrush" Color="#243475"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#53639C"/>
        <SolidColorBrush x:Key="HoverBrush" Color="#2D4088"/>
        <SolidColorBrush x:Key="SelectionBrush" Color="#1F50A5"/>
        <SolidColorBrush x:Key="SecondaryTextBrush" Color="#CDD9F3"/>
        <SolidColorBrush x:Key="SidebarBrush" Color="#111949"/>
        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="16"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="TextWrapping" Value="Wrap"/>
        </Style>
        <Style x:Key="CardTitleStyle" TargetType="TextBlock" BasedOn="{StaticResource {x:Type TextBlock}}">
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="LineHeight" Value="24"/>
            <Setter Property="LineStackingStrategy" Value="BlockLineHeight"/>
        </Style>
        <Style x:Key="IconStyle" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
            <Setter Property="FontSize" Value="20"/>
            <Setter Property="Foreground" Value="{StaticResource AccentBrush}"/>
            <Setter Property="Height" Value="24"/>
            <Setter Property="LineHeight" Value="24"/>
            <Setter Property="LineStackingStrategy" Value="BlockLineHeight"/>
            <Setter Property="TextWrapping" Value="NoWrap"/>
            <Setter Property="VerticalAlignment" Value="Top"/>
        </Style>
        <Style TargetType="ToolTip">
            <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="MaxWidth" Value="560"/>
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="Background" Value="{StaticResource SidebarBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Padding" Value="4"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
        </Style>
        <Style TargetType="ListBoxItem">
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="Margin" Value="0,1"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="RowBorder" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="RowBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="RowBorder" Property="Background" Value="{StaticResource SelectionBrush}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="RowBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="Margin" Value="8,0,0,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1"
                                CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#F5F5F5"/>
                                <Setter TargetName="ButtonBorder" Property="BorderThickness" Value="2"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="28,24,28,12">
            <TextBlock Text="OSDCloud" FontSize="24" FontWeight="SemiBold" Foreground="{StaticResource AccentBrush}"/>
            <TextBlock Text="WinpeStartup" Foreground="{StaticResource SecondaryTextBrush}" Margin="0,2,0,0"/>
        </StackPanel>
        <Border Grid.Row="1" Style="{StaticResource CardStyle}" Margin="28,0,28,24">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="36"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Grid.Column="0" Style="{StaticResource IconStyle}" Text="&#xE77B;"
                           AutomationProperties.Name="Startup profile"/>
                <StackPanel Grid.Row="0" Grid.Column="1">
                    <TextBlock Style="{StaticResource CardTitleStyle}" Text="Build: Startup Profile"/>
                    <TextBlock Foreground="{StaticResource SecondaryTextBrush}" Margin="0,6,0,10"
                               Text="Select the profile WinpeStartup applies before running startup steps. Hover over a profile for its location."/>
                </StackPanel>
                <ListBox x:Name="ProfileList" Grid.Row="1" Grid.Column="1"
                         ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                         AutomationProperties.Name="Startup profiles"/>
                <TextBlock x:Name="StatusText" Grid.Row="2" Grid.Column="1" Margin="0,8,0,0"
                           Foreground="{StaticResource SecondaryTextBrush}" FontSize="11"/>
            </Grid>
        </Border>
        <Border Grid.Row="2" Background="{StaticResource SidebarBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0" Padding="16,10">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="CancelButton" Content="Cancel" Width="112" IsCancel="True"
                        Background="{StaticResource ControlBrush}" BorderBrush="{StaticResource BorderBrush}" Foreground="#F5F5F5"
                        AutomationProperties.Name="Cancel WinpeStartup"/>
                <Button x:Name="StartButton" Content="Start" Width="112" IsDefault="True"
                        Background="{StaticResource AccentBrush}" BorderBrush="{StaticResource AccentBrush}" Foreground="#161F5B"
                        AutomationProperties.Name="Start WinpeStartup with the selected profile"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
'@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $profileList = $window.FindName('ProfileList')
    $statusText = $window.FindName('StatusText')
    $startButton = $window.FindName('StartButton')
    $state = @{ Selected = $null }

    foreach ($profileEntry in $Profiles) {
        $assetText = if ($profileEntry.AssetPath) { "Assets: $($profileEntry.AssetPath)" } else { 'Assets: none (JSON-only legacy profile)' }
        $item = [System.Windows.Controls.ListBoxItem]::new()
        $item.Content = [string]$profileEntry.Profile
        $item.Tag = $profileEntry
        $item.ToolTip = "$($profileEntry.Profile)`nProfile: $($profileEntry.Path)`n$assetText"
        [System.Windows.Automation.AutomationProperties]::SetName($item, [string]$profileEntry.Profile)
        [void]$profileList.Items.Add($item)
    }

    $statusText.Text = '{0} profiles found. Enter or double-click to start; Escape to cancel.' -f $Profiles.Count
    $profileList.SelectedIndex = 0

    $profileList.Add_SelectionChanged({
            $startButton.IsEnabled = ($null -ne $profileList.SelectedItem)
        })

    $completeSelection = {
        if ($profileList.SelectedItem) {
            $state.Selected = $profileList.SelectedItem.Tag
            $window.DialogResult = $true
        }
    }

    $startButton.Add_Click($completeSelection)
    $profileList.Add_MouseDoubleClick({
            if ($_.OriginalSource -is [System.Windows.FrameworkElement] -and $profileList.SelectedItem) {
                & $completeSelection
            }
        })

    $window.Add_ContentRendered({
            $selectedContainer = $profileList.ItemContainerGenerator.ContainerFromIndex($profileList.SelectedIndex)
            if ($selectedContainer) {
                [void]$selectedContainer.Focus()
            }
            $window.Topmost = $false
            [void]$window.Activate()
        })

    $dialogResult = $window.ShowDialog()

    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] DialogResult: $dialogResult"
    if ($dialogResult -eq $true) {
        return $state.Selected
    }

    return $null
}
