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
        Width="560"
        SizeToContent="Height"
        MinHeight="260"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        Topmost="True"
        ShowInTaskbar="True"
        Background="Transparent"
        AllowsTransparency="True"
        Icon="$PSScriptRoot\icon.ico">

    <Window.Resources>

        <LinearGradientBrush x:Key="BrandGradient" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#35297F" Offset="0"/>
            <GradientStop Color="#6F1C67" Offset="0.5"/>
            <GradientStop Color="#F40EA4" Offset="1"/>
        </LinearGradientBrush>

        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="Margin" Value="8,0,8,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Background" Value="#35297F"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder"
                                Background="{TemplateBinding Background}"
                                CornerRadius="14">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.92"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.80"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
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

    <Border CornerRadius="24"
            Background="White"
            BorderBrush="#E5E7EB"
            BorderThickness="1.5">

        <Border.Effect>
            <DropShadowEffect BlurRadius="26" ShadowDepth="0" Opacity="0.22"/>
        </Border.Effect>

        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="8"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Branded accent strip -->
            <Border Grid.Row="0"
                    CornerRadius="24,24,0,0"
                    Background="{StaticResource BrandGradient}"/>

            <!-- Header -->
            <Border x:Name="TitleBar"
                    Grid.Row="1"
                    Background="White"
                    BorderBrush="#EFEFF4"
                    BorderThickness="0,0,0,1">
                <Grid Margin="20,14,14,14">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <Border Width="52"
                            Height="52"
                            CornerRadius="12"
                            Background="#F8FAFC"
                            BorderBrush="#E5E7EB"
                            BorderThickness="1"
                            Margin="0,0,14,0">
                        <Image Source="$PSScriptRoot\logo.png"
                               Stretch="Uniform"
                               Margin="6"
                               RenderOptions.BitmapScalingMode="HighQuality"/>
                    </Border>

                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                        <TextBlock Text="$Title"
                                   FontSize="21"
                                   FontWeight="SemiBold"
                                   Foreground="#111827"/>
                        <TextBlock Text="Please review and choose an option below"
                                   FontSize="12"
                                   Foreground="#6B7280"
                                   Margin="0,2,0,0"/>
                    </StackPanel>

                    <Button x:Name="btnClose"
                            Grid.Column="2"
                            Style="{StaticResource CloseButtonStyle}"
                            Content="×"
                            VerticalAlignment="Top"/>
                </Grid>
            </Border>

            <!-- Body -->
            <Grid Grid.Row="2" Margin="26,22,26,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="6"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Left accent rail -->
                <Border Grid.Column="0"
                        Width="6"
                        CornerRadius="3"
                        Background="{StaticResource BrandGradient}"
                        Margin="0,2,18,2"/>

                <StackPanel Grid.Column="1">
                    <StackPanel x:Name="MessageHost"/>
                </StackPanel>
            </Grid>

            <!-- Footer -->
            <Border Grid.Row="3" Padding="0,6,0,22">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                    <Button x:Name="btnYes"
                            Content="Yes"
                            Width="132"
                            Height="48"
                            Style="{StaticResource PrimaryButton}"
                            IsDefault="True"/>

                    <Button x:Name="btnNo"
                            Content="No"
                            Width="132"
                            Height="48"
                            Style="{StaticResource SecondaryButton}"
                            IsCancel="True"/>
                </StackPanel>
            </Border>
        </Grid>
    </Border>
</Window>
"@

    $window = [Windows.Markup.XamlReader]::Parse($xaml)

    $btnYes      = $window.FindName("btnYes")
    $btnNo       = $window.FindName("btnNo")
    $btnClose    = $window.FindName("btnClose")
    $titleBar    = $window.FindName("TitleBar")
    $messageHost = $window.FindName("MessageHost")

    # Support both plain text messages and injected XAML content
    if ($Message.Trim().StartsWith('<')) {
        $wrappedMessageXaml = @"
<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    $Message
</StackPanel>
"@
        $parsedContent = [Windows.Markup.XamlReader]::Parse($wrappedMessageXaml)

        foreach ($child in $parsedContent.Children) {
            [void]$messageHost.Children.Add($child)
        }
    }
    else {
        $textBlock = New-Object System.Windows.Controls.TextBlock
        $textBlock.Text = $Message
        $textBlock.TextWrapping = 'Wrap'
        $textBlock.FontSize = 16
        $textBlock.LineHeight = 24
        $textBlock.Foreground = '#374151'
        $textBlock.Margin = '0,0,0,4'
        [void]$messageHost.Children.Add($textBlock)
    }

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



$message = @"
<TextBlock FontSize="22" FontWeight="SemiBold" Foreground="#111827" Margin="0,0,0,14"
           Text="Starting migration process"/>

<TextBlock FontSize="16" Foreground="#374151" TextWrapping="Wrap">
    Please close all open applications and save your work before continuing.
</TextBlock>

<TextBlock FontSize="16" Foreground="#374151" Margin="0,14,0,0" TextWrapping="Wrap">
    Click Yes when you are ready to proceed.
</TextBlock>
"@

$result = Show-InfoPopup -Title "Endpoint Migration" -Message $message
