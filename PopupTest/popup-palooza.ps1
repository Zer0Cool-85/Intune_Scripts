Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function Set-WpfImageSource {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Image]$ImageControl,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        $ImageControl.Visibility = 'Collapsed'
        return
    }

    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = [Uri]::new($Path, [UriKind]::Absolute)
        $bitmap.EndInit()
        $bitmap.Freeze()

        $ImageControl.Source = $bitmap
        $ImageControl.Visibility = 'Visible'
    }
    catch {
        $ImageControl.Visibility = 'Collapsed'
    }
}

function Set-WpfWindowIcon {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $stream = [System.IO.File]::OpenRead($Path)

        try {
            $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create(
                $stream,
                [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            )

            $iconFrame = $decoder.Frames[0]
            $iconFrame.Freeze()
            $Window.Icon = $iconFrame
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        # A missing or invalid icon should not prevent the dialog from opening.
    }
}

function Show-TempAdminRequestDialog {
    param(
        [string]$LogoPath,
        [string]$WindowTitle = 'Admin Elevation',
        [string]$HeaderTitle = 'Temporary Administrator Access',
        [string]$HeaderSubtitle = 'Enter the reason you need elevated rights.',
        [int]$MinimumLength = 10,
        [string]$IconPath = 'C:\ProgramData\Branding\SecurityLock.ico',
        [System.Windows.Window]$Owner
    )

    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Admin Elevation"
    Width="580"
    Height="460"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    FontFamily="Segoe UI"
    ShowInTaskbar="True"
    Topmost="True"
    UseLayoutRounding="True"
    SnapsToDevicePixels="True">

    <Window.Resources>
        <Style x:Key="SecondaryButtonStyle" TargetType="{x:Type Button}">
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
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder"
                                        Property="Opacity"
                                        Value="0.55"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimaryButtonStyle" TargetType="{x:Type Button}">
            <Setter Property="Width" Value="104"/>
            <Setter Property="Height" Value="38"/>
            <Setter Property="Background" Value="#2563EB"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#2563EB"/>
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
                                        Value="#1D4ED8"/>
                                <Setter TargetName="ButtonBorder"
                                        Property="BorderBrush"
                                        Value="#1D4ED8"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder"
                                        Property="Background"
                                        Value="#1E40AF"/>
                                <Setter TargetName="ButtonBorder"
                                        Property="BorderBrush"
                                        Value="#1E40AF"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonBorder"
                                        Property="BorderBrush"
                                        Value="#93C5FD"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder"
                                        Property="Opacity"
                                        Value="0.55"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ReasonTextBoxStyle" TargetType="{x:Type TextBox}">
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="BorderBrush" Value="#D1D5DB"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="Foreground" Value="#202124"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Style.Triggers>
                <Trigger Property="IsKeyboardFocused" Value="True">
                    <Setter Property="BorderBrush" Value="#2563EB"/>
                    <Setter Property="BorderThickness" Value="1.5"/>
                </Trigger>
            </Style.Triggers>
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

            <Grid Margin="30,26,30,24">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="16"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Preserve the separate bordered header section. -->
                <Border x:Name="dragArea"
                        Grid.Row="0"
                        Background="#F8FAFC"
                        CornerRadius="10"
                        Padding="18"
                        BorderBrush="#E5E7EB"
                        BorderThickness="1">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="64"/>
                            <ColumnDefinition Width="14"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <Border Width="58"
                                Height="58"
                                Background="#FFFFFF"
                                CornerRadius="10"
                                BorderBrush="#E5E7EB"
                                BorderThickness="1"
                                VerticalAlignment="Top">
                            <Image x:Name="imgLogo"
                                   Width="52"
                                   Height="52"
                                   Stretch="Uniform"
                                   RenderOptions.BitmapScalingMode="HighQuality"
                                   Visibility="Collapsed"/>
                        </Border>

                        <StackPanel Grid.Column="2"
                                    VerticalAlignment="Center">
                            <TextBlock x:Name="txtHeaderTitle"
                                       Text="Temporary Administrator Access"
                                       FontSize="24"
                                       FontWeight="SemiBold"
                                       Foreground="#202124"/>
                            <TextBlock x:Name="txtHeaderSubtitle"
                                       Text="Enter the reason you need elevated rights."
                                       Margin="0,7,0,0"
                                       FontSize="14"
                                       Foreground="#5F6368"
                                       TextWrapping="Wrap"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <!-- Preserve the separate bordered reason-entry section. -->
                <Border Grid.Row="2"
                        Background="#FFFFFF"
                        CornerRadius="10"
                        Padding="18"
                        BorderBrush="#E5E7EB"
                        BorderThickness="1">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="10"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="8"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <TextBlock Grid.Row="0"
                                   Text="Reason for admin access"
                                   FontSize="14"
                                   FontWeight="SemiBold"
                                   Foreground="#202124"/>

                        <TextBox x:Name="txtReason"
                                 Grid.Row="2"
                                 Height="48"
                                 AcceptsReturn="False"
                                 TextWrapping="NoWrap"
                                 VerticalScrollBarVisibility="Disabled"
                                 HorizontalScrollBarVisibility="Disabled"
                                 MaxLength="75"
                                 Style="{StaticResource ReasonTextBoxStyle}"/>

                        <TextBlock x:Name="txtValidation"
                                   Grid.Row="4"
                                   Foreground="#C62828"
                                   FontSize="12"
                                   Visibility="Collapsed"
                                   Text="Please enter at least 10 characters."/>
                    </Grid>
                </Border>

                <TextBlock x:Name="txtFooter"
                           Grid.Row="3"
                           Margin="0,15,0,0"
                           Foreground="#5F6368"
                           FontSize="13"
                           Text="Your access will be removed automatically after 30 minutes."/>

                <Grid Grid.Row="4"
                      Margin="0,18,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <Button x:Name="btnCancel"
                            Grid.Column="1"
                            Content="Cancel"
                            IsCancel="True"
                            Style="{StaticResource SecondaryButtonStyle}"/>

                    <Button x:Name="btnSubmit"
                            Grid.Column="2"
                            Margin="10,0,0,0"
                            Content="Submit"
                            IsDefault="True"
                            Style="{StaticResource PrimaryButtonStyle}"/>
                </Grid>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml

    try {
        $window = [Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Close()
    }

    $imgLogo          = $window.FindName('imgLogo')
    $txtHeaderTitle   = $window.FindName('txtHeaderTitle')
    $txtHeaderSubtitle = $window.FindName('txtHeaderSubtitle')
    $txtReason        = $window.FindName('txtReason')
    $txtValidation    = $window.FindName('txtValidation')
    $btnSubmit        = $window.FindName('btnSubmit')
    $btnCancel        = $window.FindName('btnCancel')
    $dragArea         = $window.FindName('dragArea')

    $window.Title = $WindowTitle
    $txtHeaderTitle.Text = $HeaderTitle
    $txtHeaderSubtitle.Text = $HeaderSubtitle

    if ($null -ne $Owner) {
        $window.Owner = $Owner
        $window.WindowStartupLocation = 'CenterOwner'
    }

    Set-WpfWindowIcon -Window $window -Path $IconPath
    Set-WpfImageSource -ImageControl $imgLogo -Path $LogoPath

    $result = [pscustomobject]@{
        Submitted = $false
        Cancelled = $false
        Reason    = $null
    }

    $btnSubmit.Add_Click({
        $reason = $txtReason.Text.Trim()

        if ($reason.Length -lt $MinimumLength) {
            $txtValidation.Text = "Please enter at least $MinimumLength characters."
            $txtValidation.Visibility = 'Visible'
            return
        }

        $result.Submitted = $true
        $result.Reason = $reason
        $window.DialogResult = $true
    })

    $btnCancel.Add_Click({
        $result.Cancelled = $true
        $window.DialogResult = $false
    })

    $window.Add_Closing({
        if (-not $result.Submitted) {
            $result.Cancelled = $true
        }
    })

    $dragArea.Add_MouseLeftButtonDown({
        param($Sender, $EventArgs)

        if ($EventArgs.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
            $window.DragMove()
        }
    })

    $window.Add_Loaded({
        [void]$txtReason.Focus()
    })

    [void]$window.ShowDialog()
    return $result
}

function Show-TempAdminMessageDialog {
    param(
        [string]$LogoPath,
        [string]$WindowTitle = 'Admin Privileges',
        [string]$HeaderTitle = 'Notification',
        [string]$Message = '',
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Style = 'Info',
        [string]$IconPath = 'C:\ProgramData\Branding\SecurityLock.ico',
        [System.Windows.Window]$Owner
    )

    $accent = switch ($Style) {
        'Success' { '#2E7D32' }
        'Warning' { '#C77700' }
        'Error'   { '#C62828' }
        default   { '#2563EB' }
    }

    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Admin Privileges"
    Width="540"
    Height="330"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    FontFamily="Segoe UI"
    ShowInTaskbar="True"
    Topmost="True"
    UseLayoutRounding="True"
    SnapsToDevicePixels="True">

    <Window.Resources>
        <Style x:Key="PrimaryButtonStyle" TargetType="{x:Type Button}">
            <Setter Property="Width" Value="104"/>
            <Setter Property="Height" Value="38"/>
            <Setter Property="Background" Value="#2563EB"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#2563EB"/>
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
                                        Value="#1D4ED8"/>
                                <Setter TargetName="ButtonBorder"
                                        Property="BorderBrush"
                                        Value="#1D4ED8"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder"
                                        Property="Background"
                                        Value="#1E40AF"/>
                                <Setter TargetName="ButtonBorder"
                                        Property="BorderBrush"
                                        Value="#1E40AF"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonBorder"
                                        Property="BorderBrush"
                                        Value="#93C5FD"/>
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

            <Grid Margin="30,26,30,24">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Preserve the bordered message section. -->
                <Border x:Name="dragArea"
                        Grid.Row="0"
                        Background="#F8FAFC"
                        CornerRadius="10"
                        Padding="18"
                        BorderBrush="#E5E7EB"
                        BorderThickness="1">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="64"/>
                            <ColumnDefinition Width="14"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <Border Width="58"
                                Height="58"
                                Background="#FFFFFF"
                                CornerRadius="10"
                                BorderBrush="#E5E7EB"
                                BorderThickness="1"
                                VerticalAlignment="Top">
                            <Image x:Name="imgLogo"
                                   Width="52"
                                   Height="52"
                                   Stretch="Uniform"
                                   RenderOptions.BitmapScalingMode="HighQuality"
                                   Visibility="Collapsed"/>
                        </Border>

                        <StackPanel Grid.Column="2"
                                    VerticalAlignment="Center">
                            <Border x:Name="accentBar"
                                    Width="52"
                                    Height="5"
                                    CornerRadius="3"
                                    Background="#2563EB"
                                    HorizontalAlignment="Left"/>
                            <TextBlock x:Name="txtHeaderTitle"
                                       Margin="0,10,0,0"
                                       Text="Notification"
                                       FontSize="24"
                                       FontWeight="SemiBold"
                                       Foreground="#202124"/>
                            <TextBlock x:Name="txtMessage"
                                       Margin="0,10,0,0"
                                       Text=""
                                       FontSize="15"
                                       Foreground="#5F6368"
                                       TextWrapping="Wrap"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <Button x:Name="btnOk"
                        Grid.Row="1"
                        Margin="0,18,0,0"
                        HorizontalAlignment="Right"
                        Content="OK"
                        IsDefault="True"
                        Style="{StaticResource PrimaryButtonStyle}"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml

    try {
        $window = [Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Close()
    }

    $imgLogo       = $window.FindName('imgLogo')
    $accentBar     = $window.FindName('accentBar')
    $txtHeaderTitle = $window.FindName('txtHeaderTitle')
    $txtMessage    = $window.FindName('txtMessage')
    $btnOk         = $window.FindName('btnOk')
    $dragArea      = $window.FindName('dragArea')

    $window.Title = $WindowTitle
    $txtHeaderTitle.Text = $HeaderTitle
    $txtMessage.Text = $Message
    $accentBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($accent)

    if ($null -ne $Owner) {
        $window.Owner = $Owner
        $window.WindowStartupLocation = 'CenterOwner'
    }

    Set-WpfWindowIcon -Window $window -Path $IconPath
    Set-WpfImageSource -ImageControl $imgLogo -Path $LogoPath

    $btnOk.Add_Click({
        $window.DialogResult = $true
    })

    $dragArea.Add_MouseLeftButtonDown({
        param($Sender, $EventArgs)

        if ($EventArgs.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
            $window.DragMove()
        }
    })

    $window.Add_Loaded({
        [void]$btnOk.Focus()
    })

    [void]$window.ShowDialog()
}
