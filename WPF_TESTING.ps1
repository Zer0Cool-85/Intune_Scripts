Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Optional: set this to your logo path
$CompanyLogoPath = "C:\ProgramData\Company\Branding\logo.png"

function Set-WpfImageSource {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Image]$ImageControl,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
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

function Show-TempAdminRequestDialog {
    param(
        [string]$LogoPath,
        [string]$WindowTitle = "Admin Privileges",
        [string]$HeaderTitle = "Temporary Administrator Access",
        [string]$HeaderSubtitle = "Enter the reason you need elevated rights.",
        [int]$MinimumLength = 10
    )

    [xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="$WindowTitle"
    Width="560"
    Height="420"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanMinimize"
    WindowStyle="SingleBorderWindow"
    Background="#F3F6FB"
    FontFamily="Segoe UI"
    ShowInTaskbar="True">

    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Height" Value="36"/>
            <Setter Property="MinWidth" Value="110"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="18"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="White" CornerRadius="14" Padding="18" BorderBrush="#D9E1EC" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="72"/>
                    <ColumnDefinition Width="14"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Width="64" Height="64" Background="#EEF3FA" CornerRadius="12" VerticalAlignment="Top">
                    <Image x:Name="imgLogo" Width="48" Height="48" Stretch="Uniform" Visibility="Collapsed"/>
                </Border>

                <StackPanel Grid.Column="2" VerticalAlignment="Center">
                    <TextBlock x:Name="txtHeaderTitle"
                               Text="$HeaderTitle"
                               FontSize="22"
                               FontWeight="SemiBold"
                               Foreground="#1F2937"/>
                    <TextBlock x:Name="txtHeaderSubtitle"
                               Text="$HeaderSubtitle"
                               Margin="0,6,0,0"
                               FontSize="13"
                               Foreground="#5B6472"
                               TextWrapping="Wrap"/>
                </StackPanel>
            </Grid>
        </Border>

        <Border Grid.Row="2" Background="White" CornerRadius="14" Padding="18" BorderBrush="#D9E1EC" BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="10"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="8"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0"
                           Text="Reason for admin access"
                           FontSize="14"
                           FontWeight="SemiBold"
                           Foreground="#1F2937"/>

                <TextBox x:Name="txtReason"
                         Grid.Row="2"
                         AcceptsReturn="True"
                         TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled"
                         FontSize="13"
                         Padding="12"
                         BorderBrush="#C9D4E5"
                         BorderThickness="1.2"
                         Background="#FBFCFE"
                         MaxLength="500"/>

                <TextBlock x:Name="txtValidation"
                           Grid.Row="4"
                           Foreground="#C62828"
                           FontSize="12"
                           Visibility="Collapsed"
                           Text="Please enter at least 10 characters."/>
            </Grid>
        </Border>

        <Grid Grid.Row="3" Margin="0,16,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <TextBlock x:Name="txtFooter"
                       VerticalAlignment="Center"
                       Foreground="#5B6472"
                       FontSize="12"
                       Text="Your access will be removed automatically after 30 minutes."/>

            <Button x:Name="btnCancel"
                    Grid.Column="1"
                    Content="Cancel"
                    Background="#E8EDF5"
                    Foreground="#1F2937"/>

            <Button x:Name="btnSubmit"
                    Grid.Column="2"
                    Margin="10,0,0,0"
                    Content="Submit"
                    Background="#0F6CBD"
                    Foreground="White"/>
        </Grid>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $imgLogo       = $window.FindName("imgLogo")
    $txtReason     = $window.FindName("txtReason")
    $txtValidation = $window.FindName("txtValidation")
    $btnSubmit     = $window.FindName("btnSubmit")
    $btnCancel     = $window.FindName("btnCancel")

    Set-WpfImageSource -ImageControl $imgLogo -Path $LogoPath

    $result = [pscustomobject]@{
        Submitted = $false
        Reason    = $null
    }

    $btnSubmit.Add_Click({
        $reason = $txtReason.Text.Trim()

        if ($reason.Length -lt $MinimumLength) {
            $txtValidation.Text = "Please enter at least $MinimumLength characters."
            $txtValidation.Visibility = "Visible"
            return
        }

        $result.Submitted = $true
        $result.Reason = $reason
        $window.DialogResult = $true
        $window.Close()
    })

    $btnCancel.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    $null = $window.ShowDialog()
    return $result
}

function Show-TempAdminMessageDialog {
    param(
        [string]$LogoPath,
        [string]$WindowTitle = "Admin Privileges",
        [string]$HeaderTitle = "Notification",
        [string]$Message = "",
        [ValidateSet("Info","Success","Warning","Error")]
        [string]$Style = "Info"
    )

    $accent = switch ($Style) {
        "Success" { "#2E7D32" }
        "Warning" { "#C77700" }
        "Error"   { "#C62828" }
        default   { "#0F6CBD" }
    }

    [xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="$WindowTitle"
    Width="500"
    Height="270"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanMinimize"
    WindowStyle="SingleBorderWindow"
    Background="#F3F6FB"
    FontFamily="Segoe UI"
    ShowInTaskbar="True">

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="White" CornerRadius="14" Padding="18" BorderBrush="#D9E1EC" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="72"/>
                    <ColumnDefinition Width="14"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Width="64" Height="64" Background="#EEF3FA" CornerRadius="12" VerticalAlignment="Top">
                    <Image x:Name="imgLogo" Width="48" Height="48" Stretch="Uniform" Visibility="Collapsed"/>
                </Border>

                <StackPanel Grid.Column="2">
                    <Border Width="52" Height="6" CornerRadius="3" Background="$accent" HorizontalAlignment="Left"/>
                    <TextBlock x:Name="txtHeaderTitle"
                               Margin="0,12,0,0"
                               Text="$HeaderTitle"
                               FontSize="22"
                               FontWeight="SemiBold"
                               Foreground="#1F2937"/>
                    <TextBlock x:Name="txtMessage"
                               Margin="0,12,0,0"
                               Text="$Message"
                               FontSize="13"
                               Foreground="#4B5563"
                               TextWrapping="Wrap"/>
                </StackPanel>
            </Grid>
        </Border>

        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="btnOk"
                    Height="36"
                    MinWidth="110"
                    Padding="14,6"
                    FontSize="13"
                    FontWeight="SemiBold"
                    BorderThickness="0"
                    Cursor="Hand"
                    Content="OK"
                    Background="$accent"
                    Foreground="White"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $imgLogo = $window.FindName("imgLogo")
    $btnOk   = $window.FindName("btnOk")

    Set-WpfImageSource -ImageControl $imgLogo -Path $LogoPath

    $btnOk.Add_Click({
        $window.DialogResult = $true
        $window.Close()
    })

    $null = $window.ShowDialog()
}


########################################################################################################################################
########################################################################################################################################
########################################################################################################################################

$dialogResult = Show-TempAdminRequestDialog -LogoPath $CompanyLogoPath -WindowTitle $appName

if ($dialogResult.Submitted) {
    $reason = $dialogResult.Reason

    Show-TempAdminMessageDialog `
        -LogoPath $CompanyLogoPath `
        -WindowTitle $appName `
        -HeaderTitle "Request Submitted" `
        -Message "You are now a member of the Administrators group. Membership will be revoked after 30 minutes." `
        -Style Info

    Write-EventLog -LogName $logName -Source $logSource -EventID 3003 -Message "$adminName, $reason"
    Write-EventLog -LogName $logName -Source $logSource -EventID 3004 -Message $entraUser
}
else {
    Show-TempAdminMessageDialog `
        -LogoPath $CompanyLogoPath `
        -WindowTitle $appName `
        -HeaderTitle "Request Cancelled" `
        -Message "You didn't enter a valid reason for temporary admin rights." `
        -Style Warning
}

########################################################################################################################################
########################################################################################################################################
########################################################################################################################################

function request {
    $entraUser = Get-EntraPrincipal
    $adminUser = Get-LocalGroupMember -Group TempAdmin -Member $entraUser -ErrorAction SilentlyContinue

    if ($adminUser) {
        $adminName = $adminUser.Name

        $dialogResult = Show-TempAdminRequestDialog -LogoPath $CompanyLogoPath -WindowTitle $appName

        if ($dialogResult.Submitted) {
            $reason = $dialogResult.Reason

            Show-TempAdminMessageDialog `
                -LogoPath $CompanyLogoPath `
                -WindowTitle $appName `
                -HeaderTitle "Request Submitted" `
                -Message "You are now a member of the Administrators group. Membership will be revoked after 30 minutes." `
                -Style Info

            Write-EventLog -LogName $logName -Source $logSource -EventID 3003 -Message "$adminName, $reason"
            Write-EventLog -LogName $logName -Source $logSource -EventID 3004 -Message $entraUser
        }
        else {
            Show-TempAdminMessageDialog `
                -LogoPath $CompanyLogoPath `
                -WindowTitle $appName `
                -HeaderTitle "Request Cancelled" `
                -Message "You didn't enter a valid reason for temporary admin rights." `
                -Style Warning
        }
    }
    else {
        Show-TempAdminMessageDialog `
            -LogoPath $CompanyLogoPath `
            -WindowTitle $appName `
            -HeaderTitle "Access Denied" `
            -Message "Please contact CorpIT if you need admin rights." `
            -Style Error
    }
}

########################################################################################################################################

##                 ANOTHER TEST

########################################################################################################################################
########################################################################################################################################

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Example logo path
$CompanyLogoPath = "C:\ProgramData\Company\Branding\logo.png"

function Set-WpfImageSource {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Image]$ImageControl,

        [Parameter(Mandatory)]
        [System.Windows.Controls.TextBlock]$FallbackControl,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        $ImageControl.Visibility = 'Collapsed'
        $FallbackControl.Visibility = 'Visible'
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
        $FallbackControl.Visibility = 'Collapsed'
    }
    catch {
        $ImageControl.Visibility = 'Collapsed'
        $FallbackControl.Visibility = 'Visible'
    }
}

function Show-TempAdminRequestDialog {
    param(
        [string]$LogoPath,
        [string]$WindowTitle = "Admin Privileges",
        [string]$HeaderTitle = "Temporary Administrator Access",
        [string]$HeaderSubtitle = "Provide a business reason for temporary elevation.",
        [string]$RequestedBy = "",
        [int]$MinimumLength = 10,
        [int]$MaximumLength = 500
    )

    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Width="640"
    Height="500"
    MinWidth="640"
    MinHeight="500"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanMinimize"
    WindowStyle="SingleBorderWindow"
    Background="#F3F6FB"
    FontFamily="Segoe UI"
    ShowInTaskbar="True">

    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Height" Value="38"/>
            <Setter Property="MinWidth" Value="120"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder"
                                Background="{TemplateBinding Background}"
                                CornerRadius="10">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
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

        <Style x:Key="FieldTextBox" TargetType="TextBox">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="10"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1.2"/>
            <Setter Property="Background" Value="#FBFCFE"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header Card -->
        <Border Grid.Row="0"
                Background="White"
                CornerRadius="16"
                Padding="18"
                BorderBrush="#D8E1ED"
                BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="74"/>
                    <ColumnDefinition Width="16"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Width="68"
                        Height="68"
                        Background="#ECF3FB"
                        CornerRadius="14"
                        VerticalAlignment="Top">
                    <Grid>
                        <Image x:Name="imgLogo"
                               Width="46"
                               Height="46"
                               Stretch="Uniform"
                               Visibility="Collapsed"/>
                        <TextBlock x:Name="txtLogoFallback"
                                   Text="C"
                                   FontSize="26"
                                   FontWeight="SemiBold"
                                   Foreground="#0F6CBD"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"/>
                    </Grid>
                </Border>

                <StackPanel Grid.Column="2" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets"
                                   Text="&#xE72E;"
                                   FontSize="16"
                                   Margin="0,1,8,0"
                                   Foreground="#0F6CBD"/>
                        <TextBlock x:Name="txtHeaderTitle"
                                   FontSize="22"
                                   FontWeight="SemiBold"
                                   Foreground="#1F2937"/>
                    </StackPanel>

                    <TextBlock x:Name="txtHeaderSubtitle"
                               Margin="0,8,0,0"
                               FontSize="13"
                               Foreground="#5B6472"
                               TextWrapping="Wrap"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main Card -->
        <Border Grid.Row="2"
                Background="White"
                CornerRadius="16"
                Padding="18"
                BorderBrush="#D8E1ED"
                BorderThickness="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="8"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="16"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="8"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="10"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0"
                           Text="Requested by"
                           FontSize="13"
                           FontWeight="SemiBold"
                           Foreground="#1F2937"/>

                <TextBox x:Name="txtRequestedBy"
                         Grid.Row="2"
                         IsReadOnly="True"
                         Style="{StaticResource FieldTextBox}"
                         Background="#F6F8FB"
                         Foreground="#4B5563"/>

                <TextBlock Grid.Row="4"
                           Text="Reason for admin access"
                           FontSize="13"
                           FontWeight="SemiBold"
                           Foreground="#1F2937"/>

                <TextBox x:Name="txtReason"
                         Grid.Row="6"
                         Style="{StaticResource FieldTextBox}"
                         AcceptsReturn="True"
                         TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled"
                         VerticalContentAlignment="Top"
                         TextAlignment="Left"
                         MinHeight="180"/>

                <Grid Grid.Row="8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock x:Name="txtStatus"
                               Text="Enter at least 10 characters."
                               FontSize="12"
                               Foreground="#6B7280"/>

                    <TextBlock x:Name="txtCounter"
                               Grid.Column="1"
                               FontSize="12"
                               Foreground="#6B7280"
                               Text="0 / 500"/>
                </Grid>
            </Grid>
        </Border>

        <!-- Footer -->
        <Border Grid.Row="4"
                Background="White"
                CornerRadius="16"
                Padding="14"
                BorderBrush="#D8E1ED"
                BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock x:Name="txtFooter"
                           VerticalAlignment="Center"
                           Foreground="#5B6472"
                           FontSize="12"
                           Text="Temporary admin access is automatically removed after 30 minutes."/>

                <Button x:Name="btnCancel"
                        Grid.Column="1"
                        Style="{StaticResource ModernButton}"
                        Background="#E7EDF5"
                        Foreground="#1F2937"
                        Content="Cancel"/>

                <Button x:Name="btnSubmit"
                        Grid.Column="2"
                        Margin="10,0,0,0"
                        Style="{StaticResource ModernButton}"
                        Background="#0F6CBD"
                        Foreground="White"
                        Content="Submit"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $window.Title = $WindowTitle

    $imgLogo        = $window.FindName("imgLogo")
    $txtLogoFallback= $window.FindName("txtLogoFallback")
    $txtHeaderTitle = $window.FindName("txtHeaderTitle")
    $txtHeaderSub   = $window.FindName("txtHeaderSubtitle")
    $txtRequestedBy = $window.FindName("txtRequestedBy")
    $txtReason      = $window.FindName("txtReason")
    $txtStatus      = $window.FindName("txtStatus")
    $txtCounter     = $window.FindName("txtCounter")
    $btnSubmit      = $window.FindName("btnSubmit")
    $btnCancel      = $window.FindName("btnCancel")

    $txtHeaderTitle.Text = $HeaderTitle
    $txtHeaderSub.Text   = $HeaderSubtitle
    $txtRequestedBy.Text = $RequestedBy
    $txtReason.MaxLength = $MaximumLength
    $txtCounter.Text     = "0 / $MaximumLength"

    Set-WpfImageSource -ImageControl $imgLogo -FallbackControl $txtLogoFallback -Path $LogoPath

    $result = [pscustomobject]@{
        Submitted = $false
        Reason    = $null
    }

    $txtReason.Add_TextChanged({
        $length = $txtReason.Text.Trim().Length
        $txtCounter.Text = "$length / $MaximumLength"

        if ($length -ge $MinimumLength) {
            $txtStatus.Text = "Reason length looks good."
            $txtStatus.Foreground = [System.Windows.Media.Brushes]::ForestGreen
        }
        else {
            $remaining = $MinimumLength - $length
            $txtStatus.Text = "Enter at least $MinimumLength characters. $remaining more needed."
            $txtStatus.Foreground = [System.Windows.Media.Brushes]::DimGray
        }
    })

    $btnSubmit.Add_Click({
        $reason = $txtReason.Text.Trim()

        if ($reason.Length -lt $MinimumLength) {
            $remaining = $MinimumLength - $reason.Length
            $txtStatus.Text = "Please enter at least $MinimumLength characters. $remaining more needed."
            $txtStatus.Foreground = [System.Windows.Media.Brushes]::Firebrick
            return
        }

        $result.Submitted = $true
        $result.Reason = $reason
        $window.DialogResult = $true
        $window.Close()
    })

    $btnCancel.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    $null = $window.ShowDialog()
    return $result
}

function Show-TempAdminMessageDialog {
    param(
        [string]$LogoPath,
        [string]$WindowTitle = "Admin Privileges",
        [string]$HeaderTitle = "Notification",
        [string]$Message = "",
        [ValidateSet("Info","Success","Warning","Error")]
        [string]$Style = "Info"
    )

    $accent = switch ($Style) {
        "Success" { "#2E7D32" }
        "Warning" { "#B7791F" }
        "Error"   { "#C62828" }
        default   { "#0F6CBD" }
    }

    $glyph = switch ($Style) {
        "Success" { [char]0xE73E } # check mark
        "Warning" { [char]0xE7BA } # warning
        "Error"   { [char]0xEA39 } # error badge
        default   { [char]0xE946 } # info
    }

    [xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Width="540"
    Height="290"
    MinWidth="540"
    MinHeight="290"
    WindowStartupLocation="CenterScreen"
    ResizeMode="CanMinimize"
    WindowStyle="SingleBorderWindow"
    Background="#F3F6FB"
    FontFamily="Segoe UI"
    ShowInTaskbar="True">

    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Height" Value="38"/>
            <Setter Property="MinWidth" Value="120"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder"
                                Background="{TemplateBinding Background}"
                                CornerRadius="10">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.92"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.80"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0"
                Background="White"
                CornerRadius="16"
                Padding="18"
                BorderBrush="#D8E1ED"
                BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="74"/>
                    <ColumnDefinition Width="16"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Width="68"
                        Height="68"
                        Background="#ECF3FB"
                        CornerRadius="14"
                        VerticalAlignment="Top">
                    <Grid>
                        <Image x:Name="imgLogo"
                               Width="46"
                               Height="46"
                               Stretch="Uniform"
                               Visibility="Collapsed"/>
                        <TextBlock x:Name="txtLogoFallback"
                                   Text="C"
                                   FontSize="26"
                                   FontWeight="SemiBold"
                                   Foreground="#0F6CBD"
                                   HorizontalAlignment="Center"
                                   VerticalAlignment="Center"/>
                    </Grid>
                </Border>

                <StackPanel Grid.Column="2">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock x:Name="txtGlyph"
                                   FontFamily="Segoe MDL2 Assets"
                                   FontSize="16"
                                   Margin="0,1,8,0"/>
                        <TextBlock x:Name="txtHeaderTitle"
                                   FontSize="22"
                                   FontWeight="SemiBold"
                                   Foreground="#1F2937"/>
                    </StackPanel>

                    <Border x:Name="brAccent"
                            Width="58"
                            Height="6"
                            CornerRadius="3"
                            Margin="0,12,0,0"
                            HorizontalAlignment="Left"/>

                    <TextBlock x:Name="txtMessage"
                               Margin="0,14,0,0"
                               FontSize="13"
                               Foreground="#4B5563"
                               TextWrapping="Wrap"/>
                </StackPanel>
            </Grid>
        </Border>

        <StackPanel Grid.Row="2"
                    Orientation="Horizontal"
                    HorizontalAlignment="Right">
            <Button x:Name="btnOK"
                    Style="{StaticResource ModernButton}"
                    Content="OK"
                    Background="#0F6CBD"
                    Foreground="White"/>
        </StackPanel>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $window.Title = $WindowTitle

    $imgLogo         = $window.FindName("imgLogo")
    $txtLogoFallback = $window.FindName("txtLogoFallback")
    $txtGlyph        = $window.FindName("txtGlyph")
    $txtHeaderTitle  = $window.FindName("txtHeaderTitle")
    $txtMessage      = $window.FindName("txtMessage")
    $brAccent        = $window.FindName("brAccent")
    $btnOK           = $window.FindName("btnOK")

    $txtGlyph.Text = $glyph
    $txtGlyph.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($accent)
    $txtHeaderTitle.Text = $HeaderTitle
    $txtMessage.Text = $Message
    $brAccent.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($accent)
    $btnOK.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($accent)

    Set-WpfImageSource -ImageControl $imgLogo -FallbackControl $txtLogoFallback -Path $LogoPath

    $btnOK.Add_Click({
        $window.DialogResult = $true
        $window.Close()
    })

    $null = $window.ShowDialog()
}

function request {
    $entraUser = Get-EntraPrincipal
    $adminUser = Get-LocalGroupMember -Group TempAdmin -Member $entraUser -ErrorAction SilentlyContinue

    if ($adminUser) {
        $adminName = $adminUser.Name

        $dialogResult = Show-TempAdminRequestDialog `
            -LogoPath $CompanyLogoPath `
            -WindowTitle $appName `
            -HeaderTitle "Temporary Administrator Access" `
            -HeaderSubtitle "Please provide a brief business reason for temporary elevation." `
            -RequestedBy $entraUser `
            -MinimumLength 10 `
            -MaximumLength 500

        if ($dialogResult.Submitted) {
            $reason = $dialogResult.Reason

            Show-TempAdminMessageDialog `
                -LogoPath $CompanyLogoPath `
                -WindowTitle $appName `
                -HeaderTitle "Request Submitted" `
                -Message "Your temporary admin request has been submitted. Access will be removed automatically after 30 minutes." `
                -Style Info

            Write-EventLog -LogName $logName -Source $logSource -EventID 3003 -Message "$adminName, $reason"
            Write-EventLog -LogName $logName -Source $logSource -EventID 3004 -Message $entraUser
        }
        else {
            Show-TempAdminMessageDialog `
                -LogoPath $CompanyLogoPath `
                -WindowTitle $appName `
                -HeaderTitle "Request Cancelled" `
                -Message "No admin access request was submitted." `
                -Style Warning
        }
    }
    else {
        Show-TempAdminMessageDialog `
            -LogoPath $CompanyLogoPath `
            -WindowTitle $appName `
            -HeaderTitle "Access Denied" `
            -Message "Please contact CorpIT if you need temporary admin rights." `
            -Style Error
    }
}
