function Show-ConfirmPopup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CurrentAccount,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NewAccount
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Confirmation"
        Width="560"
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

            <!-- Title Bar -->
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
                        <TextBlock Text="Confirmation"
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
            <StackPanel Grid.Row="1"
                        Margin="26,22,26,16"
                        HorizontalAlignment="Stretch">

                <TextBlock Text="Ready to migrate account!"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="22"
                           FontWeight="SemiBold"
                           Foreground="#111827"
                           Margin="0,0,0,12"/>

                <Border Height="1"
                        Background="#D1D5DB"
                        Margin="0,0,0,16"
                        HorizontalAlignment="Stretch"/>

                <TextBlock Text="Please confirm user account information is accurate."
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="16"
                           Foreground="#374151"
                           LineHeight="24"
                           Margin="0,0,0,18"/>

                <Border Background="#F8FAFC"
                        BorderBrush="#E5E7EB"
                        BorderThickness="1"
                        CornerRadius="12"
                        Padding="16"
                        Margin="0,0,0,18">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="170"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock Grid.Row="0"
                                   Grid.Column="0"
                                   Text="Current Account Name:"
                                   FontSize="15"
                                   FontWeight="SemiBold"
                                   Foreground="#111827"
                                   Margin="0,0,12,10"/>

                        <TextBlock x:Name="txtCurrentAccount"
                                   Grid.Row="0"
                                   Grid.Column="1"
                                   FontSize="15"
                                   Foreground="#374151"
                                   TextWrapping="Wrap"
                                   Margin="0,0,0,10"/>

                        <TextBlock Grid.Row="1"
                                   Grid.Column="0"
                                   Text="New Account Name:"
                                   FontSize="15"
                                   FontWeight="SemiBold"
                                   Foreground="#111827"
                                   Margin="0,0,12,0"/>

                        <TextBlock x:Name="txtNewAccount"
                                   Grid.Row="1"
                                   Grid.Column="1"
                                   FontSize="15"
                                   Foreground="#374151"
                                   TextWrapping="Wrap"/>
                    </Grid>
                </Border>

                <TextBlock TextWrapping="Wrap"
                           TextAlignment="Left"
                           FontSize="16"
                           Foreground="#374151"
                           LineHeight="24">
                    If the current account and new account match your information, click 'Yes' to proceed.

                    If it does not match your information, click 'No' and contact IT support for assistance.
                </TextBlock>
            </StackPanel>

            <!-- Footer -->
            <Border Grid.Row="2"
                    BorderBrush="#E5E7EB"
                    BorderThickness="0,1,0,0"
                    Padding="0,14,0,22">
                <StackPanel Orientation="Horizontal"
                            HorizontalAlignment="Center">
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

    try {
        $window = [Windows.Markup.XamlReader]::Parse($xaml)

        $txtCurrentAccount = $window.FindName("txtCurrentAccount")
        $txtNewAccount     = $window.FindName("txtNewAccount")
        $btnYes            = $window.FindName("btnYes")
        $btnNo             = $window.FindName("btnNo")
        $btnClose          = $window.FindName("btnClose")
        $titleBar          = $window.FindName("TitleBar")

        $txtCurrentAccount.Text = $CurrentAccount
        $txtNewAccount.Text     = $NewAccount

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
    catch {
        $error1 = $_
        Write-Log -Message "$error1"
    }
}
