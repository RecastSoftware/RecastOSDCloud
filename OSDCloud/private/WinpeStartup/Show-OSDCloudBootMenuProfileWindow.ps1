function Show-OSDCloudBootMenuProfileWindow {
    <#
    .SYNOPSIS
        Shows a WPF window for selecting an OSDCloud BootMenu profile.

    .DESCRIPTION
        Displays the discovered OSDCloud BootMenu profiles in a small dark window
        styled like OSDCloud Boot, with a custom title bar showing
        "OSDCloud BootMenu" and the OSDCloud module version, and the Recast logo
        in the footer. Only profile names are listed; hovering over a
        profile shows its JSON path and asset folder. Start, Enter, or a
        double-click returns the selected profile. Cancel, Escape, or closing
        the window returns nothing.

        A collapsed left menu provides shortcuts. The title bar menu button
        expands it to show labels. Profiles returns to the profile list.
        Keyboard Layout lists the keyboard layouts available in WinPE; selecting
        a different layout applies it to the current session with
        wpeutil SetKeyboardLayout without changing the selected profile.
        OSDCloud Explorer opens Start-OSDCloudExplorer in a separate window.
        Shortcut failures are shown in the window and do not close it.

        Throws when WPF cannot be loaded or the window cannot be shown so the
        caller can fall back to the console prompt.

    .PARAMETER Profiles
        Profile candidate objects from Get-OSDCloudBootMenuProfileCandidates. Each
        object must have Profile and Path properties and may have AssetPath.

    .PARAMETER TestMode
        Marks the window as a test in its title and footer. Selecting a keyboard
        layout reports the wpeutil command it would run instead of changing the
        layout. Used by Test-OSDCloudBootMenu in full Windows.

    .EXAMPLE
        $selected = Show-OSDCloudBootMenuProfileWindow -Profiles @(Get-OSDCloudBootMenuProfileCandidates)

        Shows the profile selector and returns the selected candidate or $null.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Used by Invoke-OSDCloudBootMenu unless -CLI is specified.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Profiles,

        [switch]$TestMode
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -format s)] [$($MyInvocation.MyCommand.Name)] Start"

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Recast Software - OSDCloud BootMenu" Width="640" Height="480" MinWidth="480" MinHeight="360"
        WindowStartupLocation="CenterScreen" Background="#161F5B" BorderBrush="#000000" BorderThickness="1" Topmost="True"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" Foreground="#F5F5F5"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
    <shell:WindowChrome.WindowChrome>
        <shell:WindowChrome CaptionHeight="48" GlassFrameThickness="0,0,0,1"
                            ResizeBorderThickness="{x:Static SystemParameters.WindowResizeBorderThickness}"
                            UseAeroCaptionButtons="False"/>
    </shell:WindowChrome.WindowChrome>
    <Window.Resources>
        <SolidColorBrush x:Key="AccentBrush" Color="#31D1FF"/>
        <SolidColorBrush x:Key="SurfaceBrush" Color="#1C2868"/>
        <SolidColorBrush x:Key="ControlBrush" Color="#243475"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#53639C"/>
        <SolidColorBrush x:Key="HoverBrush" Color="#2D4088"/>
        <SolidColorBrush x:Key="SelectionBrush" Color="#1F50A5"/>
        <SolidColorBrush x:Key="SecondaryTextBrush" Color="#CDD9F3"/>
        <SolidColorBrush x:Key="SidebarBrush" Color="#111949"/>
        <Style x:Key="ScrollBarThumbStyle" TargetType="Thumb">
            <Setter Property="Background" Value="{StaticResource ControlBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Margin" Value="2"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border x:Name="ThumbBorder" CornerRadius="4" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ThumbBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                                <Setter TargetName="ThumbBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="ThumbBorder" Property="Background" Value="{StaticResource AccentBrush}"/>
                                <Setter TargetName="ThumbBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollBarPageButtonStyle" TargetType="RepeatButton">
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="IsTabStop" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Border Background="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="12"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="{TemplateBinding Background}">
                            <Track x:Name="PART_Track" IsDirectionReversed="True"
                                   Minimum="{TemplateBinding Minimum}" Maximum="{TemplateBinding Maximum}"
                                   Value="{TemplateBinding Value}" ViewportSize="{TemplateBinding ViewportSize}">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton x:Name="PageDecrease" Command="ScrollBar.PageUpCommand"
                                                  Style="{StaticResource ScrollBarPageButtonStyle}"/>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource ScrollBarThumbStyle}"/>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton x:Name="PageIncrease" Command="ScrollBar.PageDownCommand"
                                                  Style="{StaticResource ScrollBarPageButtonStyle}"/>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Orientation" Value="Horizontal">
                                <Setter Property="Width" Value="Auto"/>
                                <Setter Property="Height" Value="12"/>
                                <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/>
                                <Setter TargetName="PageDecrease" Property="Command" Value="{x:Static ScrollBar.PageLeftCommand}"/>
                                <Setter TargetName="PageIncrease" Property="Command" Value="{x:Static ScrollBar.PageRightCommand}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="CornerRadius" Value="4"/>
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
        <Style x:Key="SidebarNavigationIconStyle" TargetType="TextBlock" BasedOn="{StaticResource IconStyle}">
            <Setter Property="FontSize" Value="18"/>
            <Setter Property="Height" Value="20"/>
            <Setter Property="LineHeight" Value="20"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>
        <Style x:Key="StatusTextStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource SecondaryTextBrush}"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="TextWrapping" Value="NoWrap"/>
            <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
            <Setter Property="ToolTip" Value="{Binding Text, RelativeSource={RelativeSource Self}}"/>
            <Style.Triggers>
                <Trigger Property="Text" Value="">
                    <Setter Property="ToolTip" Value="{x:Null}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="SidebarLabelStyle" TargetType="TextBlock">
            <Setter Property="TextWrapping" Value="NoWrap"/>
            <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
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
        <Style x:Key="SidebarNavigationItemStyle" TargetType="ListBoxItem">
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="Margin" Value="0,1"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Grid>
                            <Border x:Name="RowBorder" Background="Transparent" BorderBrush="Transparent"
                                    BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
                                <ContentPresenter x:Name="NavigationContent" Margin="4,0,0,0"
                                                  HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
                            </Border>
                            <Border x:Name="SelectedIndicator" Width="3" Margin="0,6"
                                    HorizontalAlignment="Left" Background="{StaticResource AccentBrush}"
                                    CornerRadius="2" Visibility="Collapsed" IsHitTestVisible="False"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <DataTrigger Binding="{Binding Tag, RelativeSource={RelativeSource AncestorType=ListBox}}" Value="Compact">
                                <Setter TargetName="NavigationContent" Property="Margin" Value="0"/>
                            </DataTrigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="RowBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="RowBorder" Property="Background" Value="{StaticResource ControlBrush}"/>
                                <Setter TargetName="SelectedIndicator" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="RowBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SidebarButtonStyle" TargetType="Button">
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="Margin" Value="0,1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="RowBorder" Background="{TemplateBinding Background}" BorderBrush="Transparent"
                                BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter x:Name="ButtonContent" Margin="4,0,0,0" RecognizesAccessKey="True"
                                              HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Tag" Value="Compact">
                                <Setter TargetName="ButtonContent" Property="Margin" Value="0"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="RowBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="RowBorder" Property="Background" Value="{StaticResource ControlBrush}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="RowBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
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
        <!-- WPF shows FocusVisualStyle only for keyboard focus, so mouse clicks leave no outline. -->
        <Style x:Key="TitleBarFocusVisualStyle">
            <Setter Property="Control.Template">
                <Setter.Value>
                    <ControlTemplate>
                        <Rectangle Margin="4,6" RadiusX="4" RadiusY="4" Stroke="#F5F5F5"
                                   StrokeThickness="1" SnapsToDevicePixels="True"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="TitleBarButtonStyle" TargetType="Button">
            <Setter Property="Width" Value="46"/>
            <Setter Property="Height" Value="48"/>
            <Setter Property="Margin" Value="0"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource TitleBarFocusVisualStyle}"/>
            <Setter Property="shell:WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="CaptionBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CaptionBorder" Property="Background" Value="{StaticResource HoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="CaptionBorder" Property="Background" Value="{StaticResource ControlBrush}"/>
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="Tag" Value="Close"/>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="CaptionBorder" Property="Background" Value="#C42B1C"/>
                            </MultiTrigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="Tag" Value="Close"/>
                                    <Condition Property="IsPressed" Value="True"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="CaptionBorder" Property="Background" Value="#A82418"/>
                            </MultiTrigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="TitleBarCloseButtonStyle" TargetType="Button" BasedOn="{StaticResource TitleBarButtonStyle}">
            <Setter Property="Tag" Value="Close"/>
        </Style>
        <Style x:Key="TitleBarIconStyle" TargetType="TextBlock" BasedOn="{StaticResource IconStyle}">
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Height" Value="Auto"/>
            <Setter Property="LineHeight" Value="NaN"/>
            <Setter Property="LineStackingStrategy" Value="MaxHeight"/>
            <Setter Property="Foreground" Value="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>
    </Window.Resources>
    <Grid x:Name="WindowLayout">
        <Grid.ColumnDefinitions>
            <ColumnDefinition x:Name="SidebarColumn" Width="56"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="48"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border x:Name="TitleBarBackground" Grid.ColumnSpan="2" Background="{StaticResource SidebarBrush}"/>
        <Grid x:Name="TitleBar" Grid.ColumnSpan="2" Background="Transparent"
              AutomationProperties.Name="OSDCloud BootMenu title bar">
            <Grid.Style>
                <Style TargetType="Grid">
                    <Style.Triggers>
                        <DataTrigger Binding="{Binding IsActive, RelativeSource={RelativeSource AncestorType=Window}}" Value="False">
                            <Setter Property="Opacity" Value="0.65"/>
                        </DataTrigger>
                    </Style.Triggers>
                </Style>
            </Grid.Style>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="PaneToggle" Style="{StaticResource TitleBarButtonStyle}" Margin="5,0"
                    ToolTip="Expand navigation" AutomationProperties.Name="Expand navigation"
                    AutomationProperties.HelpText="Navigation is collapsed.">
                <TextBlock Text="&#xE700;" Style="{StaticResource TitleBarIconStyle}" FontSize="16"/>
            </Button>
            <Grid Grid.Column="1" Margin="16,0,24,0" VerticalAlignment="Center">
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <TextBlock x:Name="WindowHeading" Text="OSDCloud BootMenu" FontSize="16" FontWeight="SemiBold"
                           TextWrapping="NoWrap" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"
                           AutomationProperties.Name="OSDCloud BootMenu"/>
                <TextBlock x:Name="WindowSubtitle" Grid.Column="1" Margin="12,0,0,0"
                           Foreground="{StaticResource SecondaryTextBrush}" TextWrapping="NoWrap"
                           TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
            </Grid>
            <StackPanel Grid.Column="2" Orientation="Horizontal">
                <Button x:Name="TitleBarMinimize" Style="{StaticResource TitleBarButtonStyle}"
                        ToolTip="Minimize" AutomationProperties.Name="Minimize">
                    <TextBlock Text="&#xE921;" Style="{StaticResource TitleBarIconStyle}"/>
                </Button>
                <Button x:Name="TitleBarMaximize" Style="{StaticResource TitleBarButtonStyle}"
                        ToolTip="Maximize" AutomationProperties.Name="Maximize">
                    <TextBlock x:Name="TitleBarMaximizeIcon" Text="&#xE922;" Style="{StaticResource TitleBarIconStyle}"/>
                </Button>
                <Button x:Name="TitleBarClose" Style="{StaticResource TitleBarCloseButtonStyle}"
                        ToolTip="Close" AutomationProperties.Name="Close">
                    <TextBlock Text="&#xE8BB;" Style="{StaticResource TitleBarIconStyle}"/>
                </Button>
            </StackPanel>
        </Grid>
        <Border x:Name="SidebarPanel" Grid.Row="1" Grid.Column="0" Background="{StaticResource SidebarBrush}" Padding="4,8">
            <Grid>
                <ScrollViewer Focusable="False"
                              HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Auto">
                    <StackPanel>
                        <ListBox x:Name="Navigation" Background="Transparent" BorderThickness="0" Padding="0" Tag="Compact"
                                 FontSize="15" ItemContainerStyle="{StaticResource SidebarNavigationItemStyle}"
                                 AutomationProperties.Name="Boot Menu navigation" SelectionMode="Single">
                            <ListBox.Template>
                                <ControlTemplate TargetType="ListBox">
                                    <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                                        <ItemsPresenter/>
                                    </Border>
                                </ControlTemplate>
                            </ListBox.Template>
                            <ListBoxItem x:Name="ProfileNavigationItem" IsSelected="True"
                                         ToolTip="Select the Boot Menu profile to start."
                                         AutomationProperties.Name="Profiles"
                                         AutomationProperties.HelpText="Show the Boot Menu profiles.">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xE77B;" Style="{StaticResource SidebarNavigationIconStyle}" Margin="0,0,10,0"/>
                                    <TextBlock Text="Profiles" Style="{StaticResource SidebarLabelStyle}"/>
                                </StackPanel>
                            </ListBoxItem>
                            <ListBoxItem x:Name="KeyboardNavigationItem"
                                         ToolTip="Change the keyboard layout for this WinPE session."
                                         AutomationProperties.Name="Keyboard Layout"
                                         AutomationProperties.HelpText="Show keyboard layouts to change the layout for this WinPE session.">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xE765;" Style="{StaticResource SidebarNavigationIconStyle}" Margin="0,0,10,0"/>
                                    <TextBlock Text="Keyboard Layout" Style="{StaticResource SidebarLabelStyle}"/>
                                </StackPanel>
                            </ListBoxItem>
                        </ListBox>
                        <Button x:Name="ExplorerButton" Style="{StaticResource SidebarButtonStyle}" Tag="Compact" FontSize="15"
                                ToolTip="Open OSDCloud Explorer in a separate window."
                                AutomationProperties.Name="OSDCloud Explorer"
                                AutomationProperties.HelpText="Open OSDCloud Explorer in a separate window.">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="&#xEC50;" Style="{StaticResource SidebarNavigationIconStyle}" Margin="0,0,10,0"/>
                                <TextBlock Text="OSDCloud Explorer" Style="{StaticResource SidebarLabelStyle}"/>
                            </StackPanel>
                        </Button>
                    </StackPanel>
                </ScrollViewer>
            </Grid>
        </Border>
        <Grid Grid.Row="1" Grid.Column="1" Margin="36,24">
            <Border x:Name="ProfilePage" Style="{StaticResource CardStyle}">
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
                               AutomationProperties.Name="Boot Menu profile"/>
                    <StackPanel Grid.Row="0" Grid.Column="1">
                        <TextBlock Style="{StaticResource CardTitleStyle}" Text="Boot Menu Profile"/>
                        <TextBlock Foreground="{StaticResource SecondaryTextBrush}" Margin="0,6,0,12"
                                   Text="Select the profile to start. Hover over a profile for its location."/>
                    </StackPanel>
                    <ListBox x:Name="ProfileList" Grid.Row="1" Grid.Column="1"
                             ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                             AutomationProperties.Name="Startup profiles"/>
                    <TextBlock x:Name="StatusText" Grid.Row="2" Grid.Column="1" Margin="0,8,0,0"
                               Style="{StaticResource StatusTextStyle}"/>
                </Grid>
            </Border>
            <Border x:Name="KeyboardPage" Style="{StaticResource CardStyle}" Visibility="Collapsed">
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
                    <TextBlock Grid.Row="0" Grid.Column="0" Style="{StaticResource IconStyle}" Text="&#xE765;"
                               AutomationProperties.Name="Keyboard layout"/>
                    <StackPanel Grid.Row="0" Grid.Column="1">
                        <TextBlock Style="{StaticResource CardTitleStyle}" Text="Keyboard Layout"/>
                        <TextBlock Foreground="{StaticResource SecondaryTextBrush}" Margin="0,6,0,12"
                                   Text="Select a layout to apply it to this WinPE session."/>
                    </StackPanel>
                    <ListBox x:Name="KeyboardLayoutList" Grid.Row="1" Grid.Column="1"
                             ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                             AutomationProperties.Name="Keyboard layouts"
                             AutomationProperties.HelpText="Selecting a layout applies it to this WinPE session."/>
                    <TextBlock x:Name="KeyboardStatusText" Grid.Row="2" Grid.Column="1" Margin="0,8,0,0"
                               Style="{StaticResource StatusTextStyle}"/>
                </Grid>
            </Border>
        </Grid>
        <Border Grid.Row="2" Grid.ColumnSpan="2" Background="{StaticResource SidebarBrush}" BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,1,0,0" Padding="16,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Image x:Name="LogoImage" Height="40" Stretch="Uniform" VerticalAlignment="Center" Margin="0,0,12,0"
                       AutomationProperties.Name="Recast Software"/>
                <TextBlock x:Name="FooterStatusText" Grid.Column="1" Style="{StaticResource StatusTextStyle}" VerticalAlignment="Center"/>
                <StackPanel Grid.Column="2" Orientation="Horizontal">
                    <Button x:Name="CancelButton" Content="Cancel" Width="112" IsCancel="True"
                            Background="{StaticResource ControlBrush}" BorderBrush="{StaticResource BorderBrush}" Foreground="#F5F5F5"
                            AutomationProperties.Name="Cancel Boot Menu profile selection"/>
                    <Button x:Name="StartButton" Content="Start" Width="112" IsDefault="True"
                            Background="{StaticResource AccentBrush}" BorderBrush="{StaticResource AccentBrush}" Foreground="#161F5B"
                            AutomationProperties.Name="Start OSDCloud BootMenu with the selected profile"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $profileList = $window.FindName('ProfileList')
    $statusText = $window.FindName('StatusText')
    $startButton = $window.FindName('StartButton')
    $sidebarColumn = $window.FindName('SidebarColumn')
    $sidebarPanel = $window.FindName('SidebarPanel')
    $paneToggle = $window.FindName('PaneToggle')
    $navigation = $window.FindName('Navigation')
    $profileNavigationItem = $window.FindName('ProfileNavigationItem')
    $keyboardNavigationItem = $window.FindName('KeyboardNavigationItem')
    $explorerButton = $window.FindName('ExplorerButton')
    $profilePage = $window.FindName('ProfilePage')
    $keyboardPage = $window.FindName('KeyboardPage')
    $keyboardLayoutList = $window.FindName('KeyboardLayoutList')
    $keyboardStatusText = $window.FindName('KeyboardStatusText')
    $footerStatusText = $window.FindName('FooterStatusText')
    $windowLayout = $window.FindName('WindowLayout')
    $windowSubtitle = $window.FindName('WindowSubtitle')
    $titleBarMinimize = $window.FindName('TitleBarMinimize')
    $titleBarMaximize = $window.FindName('TitleBarMaximize')
    $titleBarMaximizeIcon = $window.FindName('TitleBarMaximizeIcon')
    $titleBarClose = $window.FindName('TitleBarClose')
    $logoImage = $window.FindName('LogoImage')
    $state = @{ Selected = $null }

    $moduleVersion = $null
    try {
        $moduleVersion = [string](Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '..\..\OSDCloud.psd1') -ErrorAction Stop).ModuleVersion
    }
    catch {
        Write-Verbose "[$($MyInvocation.MyCommand.Name)] Module version unavailable: $($_.Exception.Message)"
    }
    $windowSubtitle.Text = if ($TestMode) { "$moduleVersion (Test)".Trim() } else { $moduleVersion }
    $window.Title = ("Recast Software - OSDCloud BootMenu $($windowSubtitle.Text)").Trim()

    $logoPath = Join-Path $PSScriptRoot '..\..\core\recast-logo.png'
    try {
        $logo = [System.Windows.Media.Imaging.BitmapImage]::new()
        $logo.BeginInit()
        $logo.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $logo.UriSource = [uri][System.IO.Path]::GetFullPath($logoPath)
        $logo.EndInit()
        $logo.Freeze()
        $logoImage.Source = $logo
    }
    catch {
        Write-Verbose "[$($MyInvocation.MyCommand.Name)] Recast logo unavailable: $($_.Exception.Message)"
        $logoImage.Visibility = 'Collapsed'
    }

    $workArea = [System.Windows.SystemParameters]::WorkArea
    $window.MinWidth = [Math]::Min($window.MinWidth, $workArea.Width)
    $window.MinHeight = [Math]::Min($window.MinHeight, $workArea.Height)
    $window.Width = [Math]::Min($window.Width, $workArea.Width)
    $window.Height = [Math]::Min($window.Height, $workArea.Height)

    #region Title bar
    $updateWindowState = {
        $maximized = $window.WindowState -eq [System.Windows.WindowState]::Maximized
        $titleBarMaximizeIcon.Text = [string][char]$(if ($maximized) { 0xE923 } else { 0xE922 })
        $action = if ($maximized) { 'Restore' } else { 'Maximize' }
        $titleBarMaximize.ToolTip = $action
        [System.Windows.Automation.AutomationProperties]::SetName($titleBarMaximize, $action)
        $windowLayout.Margin = [System.Windows.Thickness]::new(0)
        $presentationSource = [System.Windows.PresentationSource]::FromVisual($window)
        if ($maximized -and $presentationSource) {
            # A maximized custom-chrome window extends past the monitor work area; inset the layout to keep it visible.
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                $handle = [System.Windows.Interop.WindowInteropHelper]::new($window).Handle
                $area = [System.Windows.Forms.Screen]::FromHandle($handle).WorkingArea
                $origin = $window.PointToScreen([System.Windows.Point]::new(0, 0))
                $end = $window.PointToScreen([System.Windows.Point]::new($window.ActualWidth, $window.ActualHeight))
                $transform = $presentationSource.CompositionTarget.TransformFromDevice
                $inset = $transform.Transform([System.Windows.Vector]::new(
                        [Math]::Max(0, $area.Left - $origin.X), [Math]::Max(0, $area.Top - $origin.Y)))
                $outset = $transform.Transform([System.Windows.Vector]::new(
                        [Math]::Max(0, $end.X - $area.Right), [Math]::Max(0, $end.Y - $area.Bottom)))
                $windowLayout.Margin = [System.Windows.Thickness]::new($inset.X, $inset.Y, $outset.X, $outset.Y)
            }
            catch {
                $windowLayout.Margin = [System.Windows.SystemParameters]::WindowResizeBorderThickness
            }
        }
        $window.BorderThickness = [System.Windows.Thickness]::new($(if ($maximized) { 0 } else { 1 }))
    }
    $window.Add_StateChanged($updateWindowState)
    $window.Add_SizeChanged($updateWindowState)
    $titleBarMinimize.Add_Click({ [System.Windows.SystemCommands]::MinimizeWindow($window) })
    $titleBarMaximize.Add_Click({
            if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) {
                [System.Windows.SystemCommands]::RestoreWindow($window)
            }
            else { [System.Windows.SystemCommands]::MaximizeWindow($window) }
        })
    $titleBarClose.Add_Click({ [System.Windows.SystemCommands]::CloseWindow($window) })
    #endregion

    foreach ($profileEntry in $Profiles) {
        $assetText = if ($profileEntry.AssetPath) { "Assets: $($profileEntry.AssetPath)" } else { 'Assets: none (JSON-only legacy profile)' }
        $item = [System.Windows.Controls.ListBoxItem]::new()
        $item.Content = [string]$profileEntry.Profile
        $item.Tag = $profileEntry
        $item.ToolTip = "$($profileEntry.Profile)`nProfile: $($profileEntry.Path)`n$assetText"
        [System.Windows.Automation.AutomationProperties]::SetName($item, [string]$profileEntry.Profile)
        [void]$profileList.Items.Add($item)
    }

    $statusText.Text = '{0} profiles found. Enter to start; Escape to cancel.' -f $Profiles.Count
    $profileList.SelectedIndex = 0
    if ($TestMode) {
        $footerStatusText.Text = 'Test mode. Start returns the profile without running it.'
    }

    #region Sidebar
    $sidebarState = @{ Compact = $true }
    $sidebarEntries = @(
        foreach ($element in @($profileNavigationItem, $keyboardNavigationItem, $explorerButton)) {
            [pscustomobject]@{
                Element    = $element
                Icon       = $element.Content.Children[0]
                IconMargin = $element.Content.Children[0].Margin
                Label      = $element.Content.Children[1]
                ToolTip    = [string]$element.ToolTip
            }
        }
    )

    $updateSidebar = {
        $compact = $sidebarState.Compact
        $sidebarColumn.Width = [System.Windows.GridLength]::new($(if ($compact) { 56 } else { 200 }))
        $sidebarPanel.Padding = if ($compact) {
            [System.Windows.Thickness]::new(4, 8, 4, 8)
        }
        else { [System.Windows.Thickness]::new(8) }
        $compactTag = if ($compact) { 'Compact' } else { $null }
        $navigation.Tag = $compactTag
        $explorerButton.Tag = $compactTag
        foreach ($entry in $sidebarEntries) {
            $entry.Label.Visibility = if ($compact) { 'Collapsed' } else { 'Visible' }
            $entry.Icon.Margin = if ($compact) { [System.Windows.Thickness]::new(0) } else { $entry.IconMargin }
            $entry.Element.HorizontalContentAlignment = if ($compact) { 'Center' } else { 'Stretch' }
            $entry.Element.ToolTip = if ($compact) { "$($entry.Label.Text): $($entry.ToolTip)" } else { $entry.ToolTip }
        }
        $action = if ($compact) { 'Expand navigation' } else { 'Collapse navigation' }
        $paneToggle.ToolTip = $action
        [System.Windows.Automation.AutomationProperties]::SetName($paneToggle, $action)
        [System.Windows.Automation.AutomationProperties]::SetHelpText(
            $paneToggle, $(if ($compact) { 'Navigation is collapsed.' } else { 'Navigation is expanded.' }))
    }
    & $updateSidebar

    $paneToggle.Add_Click({
            $sidebarState.Compact = -not $sidebarState.Compact
            & $updateSidebar
        })
    #endregion

    #region Keyboard layout
    $keyboardState = @{ Loaded = $false; Suppress = $false; CurrentId = $null }
    $loadKeyboardLayouts = {
        if ($keyboardState.Loaded) { return }
        $keyboardState.Loaded = $true

        try {
            $layouts = @(Get-OSDCloudBootMenuKeyboardLayout -ErrorAction Stop)
        }
        catch {
            $keyboardLayoutList.IsEnabled = $false
            $keyboardStatusText.Text = "Keyboard layouts are unavailable: $($_.Exception.Message)"
            return
        }

        $currentItem = $null
        foreach ($layout in $layouts) {
            $layoutItem = [System.Windows.Controls.ListBoxItem]::new()
            $layoutItem.Content = if ($layout.IsCurrent) { "$($layout.Name) (current)" } else { [string]$layout.Name }
            $layoutItem.Tag = $layout
            $layoutItem.ToolTip = "$($layout.Name)`nLayout ID: $($layout.Id)`nInput locale: $($layout.InputLocale)"
            [System.Windows.Automation.AutomationProperties]::SetName($layoutItem, [string]$layoutItem.Content)
            [void]$keyboardLayoutList.Items.Add($layoutItem)
            if ($layout.IsCurrent -and -not $currentItem) { $currentItem = $layoutItem }
        }

        if ($keyboardLayoutList.Items.Count -eq 0) {
            $keyboardLayoutList.IsEnabled = $false
            $keyboardStatusText.Text = 'No keyboard layouts were found in this WinPE session.'
            return
        }

        # Selecting the current layout on load must not apply it again.
        $keyboardState.Suppress = $true
        try {
            $keyboardLayoutList.SelectedItem = if ($currentItem) { $currentItem } else { $keyboardLayoutList.Items[0] }
        }
        finally { $keyboardState.Suppress = $false }
        if ($currentItem) { $keyboardState.CurrentId = $currentItem.Tag.Id }
        $keyboardLayoutList.ScrollIntoView($keyboardLayoutList.SelectedItem)
        $keyboardStatusText.Text = '{0} layouts found. Selecting a layout applies it.' -f $keyboardLayoutList.Items.Count
    }

    $applyKeyboardLayout = {
        $layoutItem = $keyboardLayoutList.SelectedItem
        if (-not $layoutItem) { return }

        $layout = $layoutItem.Tag
        if ($layout.Id -eq $keyboardState.CurrentId) {
            $keyboardStatusText.Text = "$($layout.Name) is the current keyboard layout."
            return
        }
        if ($TestMode) {
            $keyboardStatusText.Text = "Test mode: would run wpeutil SetKeyboardLayout $($layout.InputLocale) for $($layout.Name)."
            return
        }
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        try {
            Set-OSDCloudBootMenuKeyboardLayout -InputLocale $layout.InputLocale -Confirm:$false -ErrorAction Stop
            foreach ($existingItem in $keyboardLayoutList.Items) {
                $existingItem.Content = [string]$existingItem.Tag.Name
                [System.Windows.Automation.AutomationProperties]::SetName($existingItem, [string]$existingItem.Content)
            }
            $layoutItem.Content = "$($layout.Name) (current)"
            [System.Windows.Automation.AutomationProperties]::SetName($layoutItem, [string]$layoutItem.Content)
            $keyboardState.CurrentId = $layout.Id
            $keyboardStatusText.Text = "Keyboard layout set to $($layout.Name) ($($layout.InputLocale))."
        }
        catch {
            $keyboardStatusText.Text = "Unable to set keyboard layout $($layout.Name): $($_.Exception.Message)"
        }
        finally {
            $window.Cursor = $null
        }
    }

    # A short delay lets arrow-key browsing settle so wpeutil runs once for the final selection.
    $keyboardApplyTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $keyboardApplyTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $keyboardApplyTimer.Add_Tick({
            $keyboardApplyTimer.Stop()
            & $applyKeyboardLayout
        })
    $keyboardLayoutList.Add_SelectionChanged({
            if ($keyboardState.Suppress -or $null -eq $keyboardLayoutList.SelectedItem) { return }
            $keyboardApplyTimer.Stop()
            $keyboardApplyTimer.Start()
        })
    $window.Add_Closed({ $keyboardApplyTimer.Stop() })
    #endregion

    $showSelectedPage = {
        $showKeyboard = ($navigation.SelectedItem -eq $keyboardNavigationItem)
        $profilePage.Visibility = if ($showKeyboard) { 'Collapsed' } else { 'Visible' }
        $keyboardPage.Visibility = if ($showKeyboard) { 'Visible' } else { 'Collapsed' }
        # Enter must not start the Boot Menu while choosing a keyboard layout.
        $startButton.IsDefault = -not $showKeyboard
        if ($showKeyboard) { & $loadKeyboardLayouts }
    }

    $navigation.Add_SelectionChanged({
            if ($null -eq $navigation.SelectedItem) {
                $navigation.SelectedItem = $profileNavigationItem
                return
            }
            & $showSelectedPage
        })

    $explorerButton.Add_Click({
            try {
                Start-OSDCloudExplorer -ErrorAction Stop
                $footerStatusText.Text = 'OSDCloud Explorer opened in a separate window.'
            }
            catch {
                $footerStatusText.Text = "Unable to open OSDCloud Explorer: $($_.Exception.Message)"
            }
        })

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
