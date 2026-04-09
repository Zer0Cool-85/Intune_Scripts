function Show-MigrationComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$EnableAutoRebootTimer,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$AutoRebootSeconds = 90
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Migration Complete"
        Width="920"
        SizeToContent="Height"
        Icon="$PSScriptRoot\icon.ico"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        Topmost="True"
        ShowInTaskbar="True"
        Background="Transparent"
        AllowsTransparency="True">

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
                <Grid Margin="16,12,16,12">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Image Grid.Column="0"
                           Source="$PSScriptRoot\logo.png"
                           Width="42"
                           Height="42"
                           Margin="0,0,12,0"
                           RenderOptions.BitmapScalingMode="HighQuality"/>

                    <TextBlock Grid.Column="1"
                               Text="Migration Complete"
                               FontSize="20"
                               FontWeight="SemiBold"
                               Foreground="#111827"
                               VerticalAlignment="Center"/>
                </Grid>
            </Border>

            <!-- Body -->
            <StackPanel Grid.Row="1"
                        Margin="26,22,26,14"
                        HorizontalAlignment="Stretch">

                <TextBlock Text="Your PC will reboot in a moment"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="24"
                           FontWeight="SemiBold"
                           Foreground="#111827"
                           Margin="0,0,0,12"/>

                <Border Height="1"
                        Background="#D1D5DB"
                        Margin="0,0,0,18"
                        HorizontalAlignment="Stretch"/>

                <Border CornerRadius="14"
                        BorderBrush="#E5E7EB"
                        BorderThickness="1"
                        Background="#F8FAFC"
                        Padding="6"
                        Margin="0,0,0,18">
                    <Image Source="$PSScriptRoot\LoginScreen.png"
                           Width="800"
                           Height="500"
                           Stretch="Uniform"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Top"
                           RenderOptions.BitmapScalingMode="HighQuality"/>
                </Border>

                <TextBlock TextAlignment="Center"
                           TextWrapping="Wrap"
                           FontSize="16"
                           Foreground="#374151"
                           LineHeight="24"
                           Margin="0,0,0,8">
                    <Run FontWeight="SemiBold">When you get back to the login screen, click </Run>
                    <Run FontWeight="Bold">Other User</Run>
                    <Run FontWeight="SemiBold"> in the bottom left.</Run>
                    <LineBreak/>
                    <LineBreak/>
                    Sign in using your new <Run FontWeight="Bold">@Company.com</Run> email address and password.
                    <LineBreak/>
                    <LineBreak/>
                    Should you run into issues, please contact the IT support team.
                </TextBlock>

                <TextBlock x:Name="txtCountdown"
                           Visibility="Collapsed"
                           TextAlignment="Center"
                           FontSize="14"
                           Foreground="#6B7280"
                           Margin="0,6,0,0"/>
            </StackPanel>

            <!-- Footer -->
            <Border Grid.Row="2" Padding="0,8,0,22">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                    <Button x:Name="btnYes"
                            Content="Click to Reboot PC Now"
                            Width="240"
                            Height="48"
                            Style="{StaticResource ModernButton}"
                            IsDefault="True"/>
                </StackPanel>
            </Border>
        </Grid>
    </Border>
</Window>
"@

    $window       = [Windows.Markup.XamlReader]::Parse($xaml)
    $btnYes       = $window.FindName("btnYes")
    $titleBar     = $window.FindName("TitleBar")
    $txtCountdown = $window.FindName("txtCountdown")

    $state = [pscustomobject]@{
        SecondsRemaining = $AutoRebootSeconds
        RebootTriggered  = $false
    }

    $timer = $null

    $invokeReboot = {
        if ($state.RebootTriggered) { return }
        $state.RebootTriggered = $true

        if ($timer) {
            $timer.Stop()
        }

        $window.DialogResult = $true
        $window.Close()
        Restart-Computer -Force
    }

    $window.Add_KeyDown({
        param(
            [Parameter(Mandatory)][object]$sender,
            [Parameter(Mandatory)][Windows.Input.KeyEventArgs]$e
        )

        if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
            & $invokeReboot
        }
    })

    $btnYes.Add_Click({
        & $invokeReboot
    })

    $titleBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    if ($EnableAutoRebootTimer) {
        $txtCountdown.Visibility = 'Visible'
        $txtCountdown.Text = "Automatic reboot in $($state.SecondsRemaining) seconds."

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(1)
        $timer.Add_Tick({
            $state.SecondsRemaining--

            if ($state.SecondsRemaining -le 0) {
                $txtCountdown.Text = "Automatic reboot in 0 seconds."
                & $invokeReboot
                return
            }

            $unit = if ($state.SecondsRemaining -eq 1) { 'second' } else { 'seconds' }
            $txtCountdown.Text = "Automatic reboot in $($state.SecondsRemaining) $unit."
        })

        $timer.Start()
    }

    $window.Add_Closed({
        if ($timer) {
            $timer.Stop()
        }
    })

    return $window.ShowDialog()
}
