function Show-EmailConfirm {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Email confirmation"
        Width="560"
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

        <Style x:Key="LinkTextStyle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="17"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="HorizontalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="0,6,0,6"/>
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

                    <TextBlock Grid.Column="1"
                               Text="Email confirmation"
                               FontSize="20"
                               FontWeight="SemiBold"
                               Foreground="#111827"
                               VerticalAlignment="Center"/>

                    <Button x:Name="btnClose"
                            Grid.Column="2"
                            Style="{StaticResource CloseButtonStyle}"
                            Content="×"/>
                </Grid>
            </Border>

            <!-- Body -->
            <StackPanel Grid.Row="1"
                        Margin="26,22,26,10"
                        HorizontalAlignment="Stretch">
                <TextBlock Text="Company Account Confirmation"
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

                <TextBlock TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="16"
                           Foreground="#374151"
                           LineHeight="24"
                           Margin="0,0,0,12">
Please confirm that you have reset the password for your new Company email address.
                </TextBlock>

                <TextBlock TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="16"
                           Foreground="#374151"
                           LineHeight="24"
                           Margin="0,0,0,10">
If you have not reset your password, please click the following link and follow the steps to reset.
                </TextBlock>

                <TextBlock Style="{StaticResource LinkTextStyle}">
                    <Hyperlink x:Name="lnkReset"
                               NavigateUri="https://passwordreset.microsoftonline.com/">
                        Password Reset Portal
                    </Hyperlink>
                </TextBlock>

                <TextBlock TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="16"
                           Foreground="#374151"
                           LineHeight="24"
                           Margin="0,10,0,0">
If you have already reset your account click Yes to proceed with the migration.
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

    $window   = [Windows.Markup.XamlReader]::Parse($xaml)
    $btnYes   = $window.FindName("btnYes")
    $btnNo    = $window.FindName("btnNo")
    $btnClose = $window.FindName("btnClose")
    $titleBar = $window.FindName("TitleBar")
    $lnkReset = $window.FindName("lnkReset")

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

    $lnkReset.Add_Click({
        $window.DialogResult = $false
        Start-Process 'https://passwordreset.microsoftonline.com/'
        $window.Close()
    })

    $titleBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    return $window.ShowDialog()
}



function Show-EmailPopup {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $isValidEmail = $false
    $email = ""

    while (-not $isValidEmail) {
        $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Confirmation"
        Width="560"
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

        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="Foreground" Value="#111827"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1.5"/>
            <Setter Property="Height" Value="42"/>
            <Setter Property="Width" Value="320"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="TextBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="10">
                            <ScrollViewer x:Name="PART_ContentHost"
                                          Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="TextBorder" Property="BorderBrush" Value="#4F46E5"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="TextBorder" Property="Opacity" Value="0.6"/>
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

                    <TextBlock Grid.Column="1"
                               Text="Confirmation"
                               FontSize="20"
                               FontWeight="SemiBold"
                               Foreground="#111827"
                               VerticalAlignment="Center"/>

                    <Button x:Name="btnClose"
                            Grid.Column="2"
                            Style="{StaticResource CloseButtonStyle}"
                            Content="×"/>
                </Grid>
            </Border>

            <!-- Body -->
            <StackPanel Grid.Row="1"
                        Margin="26,22,26,10"
                        HorizontalAlignment="Stretch">
                <TextBlock Text="Email address required"
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

                <TextBlock Text="Please enter your Company.com email address:"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="16"
                           Foreground="#374151"
                           LineHeight="24"
                           Margin="0,0,0,14"/>

                <TextBox x:Name="txtEmail"
                         Style="{StaticResource ModernTextBox}"
                         HorizontalAlignment="Center"
                         Margin="0,0,0,14"/>

                <TextBlock Text="Click OK to proceed with migration or Cancel to exit."
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="15"
                           Foreground="#6B7280"
                           Margin="0,0,0,4"/>
            </StackPanel>

            <!-- Footer -->
            <Border Grid.Row="2" Padding="0,8,0,22">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                    <Button x:Name="btnYes"
                            Content="OK"
                            Width="130"
                            Height="46"
                            Style="{StaticResource ModernButton}"
                            IsDefault="True"/>

                    <Button x:Name="btnNo"
                            Content="Cancel"
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

        $window   = [Windows.Markup.XamlReader]::Parse($xaml)
        $txtEmail = $window.FindName("txtEmail")
        $btnYes   = $window.FindName("btnYes")
        $btnNo    = $window.FindName("btnNo")
        $btnClose = $window.FindName("btnClose")
        $titleBar = $window.FindName("TitleBar")

        $window.Tag = 'Cancel'

        $window.Add_ContentRendered({
            $txtEmail.Focus()
            $txtEmail.SelectAll()
        })

        $txtEmail.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
                $window.Tag = 'OK'
                $window.Close()
            }
        })

        $btnYes.Add_Click({
            $window.Tag = 'OK'
            $window.Close()
        })

        $btnNo.Add_Click({
            $window.Tag = 'Cancel'
            $window.Close()
        })

        $btnClose.Add_Click({
            $window.Tag = 'Cancel'
            $window.Close()
        })

        $titleBar.Add_MouseLeftButtonDown({
            $window.DragMove()
        })

        [void]$window.ShowDialog()

        if ($window.Tag -eq 'Cancel') {
            return $null
        }

        $email = $txtEmail.Text.Trim()

        if (-not [string]::IsNullOrWhiteSpace($email) -and $email -like "*@Company.com") {
            $isValidEmail = $true
        }
        elseif ([System.Windows.MessageBox]::Show(
            "Invalid email or empty email. Please enter a valid email address ending with '@Company.com'. Would you like to try again?",
            "Invalid Email",
            "YesNo",
            [System.Windows.MessageBoxImage]::Warning
        ) -eq "No") {
            return $null
        }
    }

    return $email
}


function Show-MigrationComplete {
    [CmdletBinding()]
    param()

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
                           Text="Automatic reboot in 90 seconds."
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

    $secondsRemaining = 90
    $rebootTriggered = $false

    $invokeReboot = {
        if ($rebootTriggered) { return }
        $rebootTriggered = $true

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

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({
        $secondsRemaining--

        if ($secondsRemaining -le 0) {
            $txtCountdown.Text = "Automatic reboot in 0 seconds."
            & $invokeReboot
            return
        }

        $txtCountdown.Text = "Automatic reboot in $secondsRemaining seconds."
    })

    $window.Add_Closed({
        if ($timer) {
            $timer.Stop()
        }
    })

    $timer.Start()

    return $window.ShowDialog()
}
