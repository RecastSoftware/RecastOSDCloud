function Show-OSDCloudBootPasswordDialog {
    <#
    .SYNOPSIS
        Requests a masked profile password

    .DESCRIPTION
        Shows a dark WPF PasswordBox dialog. Creation requires confirmation;
        unlocking verifies the supplied authenticated profile token before closing.
        Incorrect passwords remain in the dialog for retry. Cancellation returns
        nothing. Passwords are never converted into managed plaintext strings.

    .PARAMETER Owner
        Specifies an optional owning WPF window.

    .PARAMETER Title
        Specifies the dialog title.

    .PARAMETER ConfirmPassword
        Requires matching nonempty password and confirmation entries.

    .PARAMETER Token
        Specifies the profile access token to verify when unlocking.

    .EXAMPLE
        PS> $password = Show-OSDCloudBootPasswordDialog -ConfirmPassword

        Returns a confirmed SecureString owned by the caller, or nothing on cancel.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Security.SecureString.

    .NOTES
        Author:  David Segura
        Company: Recast Software
        Version: 1.0.0
        Date:    2026-11-05
        The caller must dispose the returned SecureString.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param (
        [System.Windows.Window]$Owner,
        [string]$Title = 'Unlock BootMenu Profile',
        [switch]$ConfirmPassword,
        [string]$Token
    )

    $Error.Clear()
    Write-Verbose "[$(Get-Date -Format s)] [$($MyInvocation.MyCommand.Name)] Requesting profile password"
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    if ($Token) { $null = ConvertTo-OSDCloudBootStringEnvelope -Token $Token }
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="440" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        Background="#161F5B" Foreground="#F5F5F5" FontFamily="Segoe UI Variable Text, Segoe UI"
        FontSize="13" ShowInTaskbar="False" UseLayoutRounding="True">
    <Window.Resources>
        <SolidColorBrush x:Key="ControlBrush" Color="#243475"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#53639C"/>
        <SolidColorBrush x:Key="AccentBrush" Color="#31D1FF"/>
        <SolidColorBrush x:Key="HoverBrush" Color="#2D4088"/>
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource ControlBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="MinWidth" Value="96"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="{StaticResource HoverBrush}"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="PasswordBox">
            <Setter Property="Background" Value="{StaticResource ControlBrush}"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="Margin" Value="0,6,0,12"/>
        </Style>
    </Window.Resources>
    <StackPanel Margin="24">
        <TextBlock x:Name="PasswordInstructions" Text="Enter the password to start this BootMenu profile." TextWrapping="Wrap" Margin="0,0,0,16"/>
        <TextBlock Text="Password"/>
        <PasswordBox x:Name="Password" AutomationProperties.Name="Profile password"/>
        <StackPanel x:Name="Confirmation">
            <TextBlock Text="Confirm password"/>
            <PasswordBox x:Name="ConfirmPassword" AutomationProperties.Name="Confirm profile password"/>
        </StackPanel>
        <TextBlock x:Name="PasswordError" Foreground="#FFCC80" TextWrapping="Wrap" Margin="0,0,0,12"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Content="Cancel" IsCancel="True" Margin="0,0,8,0"/>
            <Button x:Name="AcceptPassword" Content="Unlock" IsDefault="True"
                    Background="{StaticResource AccentBrush}" Foreground="#161F5B"/>
        </StackPanel>
    </StackPanel>
</Window>
'@
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    try { $dialog = [System.Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Dispose() }
    $dialog.Title = $Title
    if ($Owner) {
        $dialog.Owner = $Owner
        $dialog.WindowStartupLocation = 'CenterOwner'
        $dialog.Resources.MergedDictionaries.Add($Owner.Resources)
    }
    $dialog.MaxWidth = [System.Windows.SystemParameters]::WorkArea.Width
    $dialog.MaxHeight = [System.Windows.SystemParameters]::WorkArea.Height
    $passwordBox = $dialog.FindName('Password')
    $confirmationBox = $dialog.FindName('ConfirmPassword')
    $errorText = $dialog.FindName('PasswordError')
    $accept = $dialog.FindName('AcceptPassword')
    $dialog.FindName('Confirmation').Visibility = if ($ConfirmPassword) { 'Visible' } else { 'Collapsed' }
    if ($ConfirmPassword) {
        $dialog.FindName('PasswordInstructions').Text = 'Set the password required to start this profile in WinPE. Built-in profiles must be cloned before saving.'
        $accept.Content = 'Set Password'
    }
    $state = @{ Password = $null }
    $accept.Add_Click({
        $first = $passwordBox.SecurePassword
        $second = $null
        $firstPointer = $secondPointer = [IntPtr]::Zero
        try {
            if ($first.Length -eq 0) { $errorText.Text = 'Enter a nonempty password.'; return }
            if ($ConfirmPassword) {
                $second = $confirmationBox.SecurePassword
                $different = $first.Length -bxor $second.Length
                if ($different -eq 0) {
                    $firstPointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($first)
                    $secondPointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($second)
                    for ($index = 0; $index -lt $first.Length; $index++) {
                        $different = $different -bor (
                            [System.Runtime.InteropServices.Marshal]::ReadInt16($firstPointer, 2 * $index) -bxor
                            [System.Runtime.InteropServices.Marshal]::ReadInt16($secondPointer, 2 * $index))
                    }
                }
                if ($different -ne 0) { $errorText.Text = 'The passwords do not match.'; return }
            }
            if ($Token) {
                $value = Invoke-OSDCloudBootStringCrypto -Token $Token -Password $first
                if ($value -cne 'OSDCloudBootMenu profile access') { throw 'Invalid profile password token.' }
            }
            $state.Password = $first
            $dialog.DialogResult = $true
        }
        catch [System.Security.Cryptography.CryptographicException] { $errorText.Text = 'Incorrect password or modified profile token. Try again.' }
        catch { $errorText.Text = $_.Exception.Message }
        finally {
            $value = $null
            if ($firstPointer -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($firstPointer) }
            if ($secondPointer -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secondPointer) }
            if ($second) { $second.Dispose() }
            if ($null -eq $state.Password) { $first.Dispose() }
        }
    })
    $dialog.Add_ContentRendered({ [void]$passwordBox.Focus() })
    try {
        if ($dialog.ShowDialog() -eq $true) { return $state.Password }
    }
    finally {
        $passwordBox.Clear()
        $confirmationBox.Clear()
    }
}
