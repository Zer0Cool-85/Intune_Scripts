#requires -version 5.1

<#
.SYNOPSIS
    Displays an indeterminate authentication progress popup.

.DESCRIPTION
    Standalone WPF example showing:
      - Header: Authenticating
      - Body: Please complete authentication
      - Indeterminate progress bar
      - Progress text: Waiting for auth
      - A single Cancel button

    The script writes "Cancel" to the pipeline when the popup is dismissed.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AuthProgressPopup.ps1
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Authenticating"
        Width="560"
        Height="300"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        ShowInTaskbar="True"
        Topmost="True"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        FontFamily="Segoe UI">

    <Window.Resources>
        <Style x:Key="CancelButtonStyle" TargetType="{x:Type Button}">
            <Setter Property="Width" Value="104"/>
            <Setter Property="Height" Value="38"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="Foreground" Value="#202124"/>
            <Setter Property="BorderBrush" Value="#D1D5DB"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Button}">
                        <Border x:Name="ButtonBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>

                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder"
                                        Property="Background"
                                        Value="#F3F4F6"/>
                                <Setter TargetName="ButtonBorder"
                                        Property="BorderBrush"
                                        Value="#9CA3AF"/>
                            </Trigger>

                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder"
                                        Property="Background"
                                        Value="#E5E7EB"/>
                            </Trigger>

                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonBorder"
                                        Property="BorderBrush"
                                        Value="#2563EB"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Border Margin="12"
                Background="#FFFFFF"
                CornerRadius="14">
            <Border.Effect>
                <DropShadowEffect BlurRadius="24"
                                  ShadowDepth="4"
                                  Opacity="0.24"
                                  Color="#000000"/>
            </Border.Effect>

            <Grid Margin="32,28,32,24">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Grid x:Name="DragArea"
                      Grid.Row="0"
                      Background="Transparent">
                    <TextBlock Text="Authenticating"
                               Foreground="#202124"
                               FontSize="25"
                               FontWeight="SemiBold"/>
                </Grid>

                <TextBlock Grid.Row="1"
                           Margin="0,12,0,0"
                           Text="Please complete authentication"
                           Foreground="#5F6368"
                           FontSize="15"/>

                <StackPanel Grid.Row="2"
                            Margin="0,28,0,0">
                    <ProgressBar x:Name="AuthProgressBar"
                                 Height="8"
                                 Minimum="0"
                                 Maximum="100"
                                 IsIndeterminate="True"
                                 Foreground="#2563EB"
                                 Background="#E5E7EB"
                                 BorderThickness="0"
                                 IsHitTestVisible="False"/>

                    <TextBlock x:Name="ProgressText"
                               Margin="0,9,0,0"
                               Text="Waiting for auth"
                               HorizontalAlignment="Center"
                               Foreground="#5F6368"
                               FontSize="13"/>
                </StackPanel>

                <Button x:Name="CancelButton"
                        Grid.Row="4"
                        Content="Cancel"
                        HorizontalAlignment="Right"
                        Style="{StaticResource CancelButtonStyle}"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$XmlReader = [System.Xml.XmlNodeReader]::new($Xaml)

try {
    $Window = [System.Windows.Markup.XamlReader]::Load($XmlReader)
}
finally {
    $XmlReader.Close()
}

$CancelButton = $Window.FindName('CancelButton')
$DragArea     = $Window.FindName('DragArea')

# Tag serves as a simple return value for the popup.
$Window.Tag = 'Cancel'

$CancelButton.Add_Click({
    $Window.Tag = 'Cancel'
    $Window.Close()
})

$Window.Add_KeyDown({
    param($Sender, $EventArgs)

    if ($EventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
        $Sender.Tag = 'Cancel'
        $Sender.Close()
    }
})

$DragArea.Add_MouseLeftButtonDown({
    if ($_.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        $Window.DragMove()
    }
})

$CancelButton.Focus() | Out-Null
[void]$Window.ShowDialog()

Write-Output ([string]$Window.Tag)
