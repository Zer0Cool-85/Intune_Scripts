Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function Show-InfoPopup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title"
        Width="520"
        SizeToContent="Height"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        Topmost="True"
        ShowInTaskbar="True"
        Background="Transparent"
        AllowsTransparency="True"
        Icon="$PSScriptRoot\icon.ico">

    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Margin" Value="8,0,8,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Background" Value="#4F46E5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder"
                                Background="{TemplateBinding Background}"
                                CornerRadius="12"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.92"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.82"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#64748B"/>
        </Style>

        <Style x:Key="CloseButtonStyle" TargetType="Button">
            <Setter Property="Foreground" Value="#6B7280"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontSize" Value="18"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Width" Value="32"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="CloseBorder" Background="{TemplateBinding Background}" CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CloseBorder" Property="Background" Value="#F3F4F6"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="CloseBorder" Property="Background" Value="#E5E7EB"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border CornerRadius="22"
            Background="White"
            BorderBrush="#D1D5DB"
            BorderThickness="1.5"
            SnapsToDevicePixels="True">
        <Border.Effect>
            <DropShadowEffect BlurRadius="28" ShadowDepth="0" Opacity="0.22"/>
        </Border.Effect>

        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <Border x:Name="TitleBar"
                    Grid.Row="0"
                    Background="#F8FAFC"
                    CornerRadius="22,22,0,0"
                    BorderBrush="#E5E7EB"
                    BorderThickness="0,0,0,1">
                <Grid Margin="16,12,12,12">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <Image Grid.Column="0"
                           Source="$PSScriptRoot\logo.png"
                           Width="42"
                           Height="42"
                           Margin="0,0,12,0"
                           RenderOptions.BitmapScalingMode="HighQuality"/>

                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                        <TextBlock Text="$Title"
                                   FontSize="20"
                                   FontWeight="SemiBold"
                                   Foreground="#111827"/>
                    </StackPanel>

                    <Button x:Name="btnClose"
                            Grid.Column="2"
                            Style="{StaticResource CloseButtonStyle}"
                            Content="×"/>
                </Grid>
            </Border>

            <!-- Body -->
            <StackPanel Grid.Row="1" Margin="26,22,26,10" HorizontalAlignment="Center">
                <Image Source="$PSScriptRoot\logo.png"
                       Width="120"
                       Height="80"
                       Margin="0,0,0,18"
                       HorizontalAlignment="Center"
                       RenderOptions.BitmapScalingMode="HighQuality"/>

                <TextBlock TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="16"
                           Foreground="#374151"
                           LineHeight="24">
                    $Message
                </TextBlock>
            </StackPanel>

            <!-- Footer -->
            <Border Grid.Row="2" Padding="0,8,0,22">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                    <Button x:Name="btnYes"
                            Content="Yes"
                            Width="130"
                            Height="46"
                            Style="{StaticResource ModernButton}"
                            IsDefault="True"/>

                    <Button x:Name="btnNo"
                            Content="No"
                            Width="130"
                            Height="46"
                            Style="{StaticResource SecondaryButton}"
                            IsCancel="True"/>
                </StackPanel>
            </Border>
        </Grid>
    </Border>
</Window>
"@

    $window = [Windows.Markup.XamlReader]::Parse($xaml)

    $btnYes   = $window.FindName("btnYes")
    $btnNo    = $window.FindName("btnNo")
    $btnClose = $window.FindName("btnClose")
    $titleBar = $window.FindName("TitleBar")

    $btnYes.Add_Click({
        $window.DialogResult = $true
        $window.Close()
    })

    $btnNo.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    $btnClose.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    $titleBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    return $window.ShowDialog()
}
