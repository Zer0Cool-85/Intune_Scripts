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







function Show-InfoPopup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HeaderText,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$MessageText,

        [Parameter(Mandatory = $false)]
        [string]$ContinueButtonText = 'Continue',

        [Parameter(Mandatory = $false)]
        [switch]$AllowDefer,

        [Parameter(Mandatory = $false)]
        [switch]$DisableDefer,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [int[]]$DeferOptions = @(4, 8, 24),

        [Parameter(Mandatory = $false)]
        [int]$DefaultDeferHours = 4,

        [Parameter(Mandatory = $false)]
        [switch]$UseOverlay,

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$')]
        [string]$OverlayColor = '#000000',

        [Parameter(Mandatory = $false)]
        [ValidateRange(0.0, 1.0)]
        [double]$OverlayOpacity = 0.35
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Popup"
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
            <Setter Property="Width" Value="32"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
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

        <Style x:Key="ModernComboBox" TargetType="ComboBox">
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
            <Setter Property="Height" Value="40"/>
            <Setter Property="MinWidth" Value="90"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
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
                        <TextBlock x:Name="txtWindowTitle"
                                   FontSize="20"
                                   FontWeight="SemiBold"
                                   Foreground="#111827"/>
                    </StackPanel>

                    <Button x:Name="btnClose"
                            Grid.Column="2"
                            Style="{StaticResource CloseButtonStyle}">
                        <Viewbox Width="10" Height="10">
                            <Canvas Width="10" Height="10">
                                <Line X1="1" Y1="1" X2="9" Y2="9"
                                      Stroke="#6B7280"
                                      StrokeThickness="1.8"
                                      StrokeStartLineCap="Round"
                                      StrokeEndLineCap="Round"/>
                                <Line X1="9" Y1="1" X2="1" Y2="9"
                                      Stroke="#6B7280"
                                      StrokeThickness="1.8"
                                      StrokeStartLineCap="Round"
                                      StrokeEndLineCap="Round"/>
                            </Canvas>
                        </Viewbox>
                    </Button>
                </Grid>
            </Border>

            <StackPanel Grid.Row="1"
                        Margin="26,22,26,10"
                        HorizontalAlignment="Stretch">
                <TextBlock x:Name="txtHeader"
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

                <TextBlock x:Name="txtMessage"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="16"
                           Foreground="#374151"
                           LineHeight="24"/>
            </StackPanel>

            <Border Grid.Row="2" Padding="0,10,0,22">
                <StackPanel Orientation="Horizontal"
                            HorizontalAlignment="Center"
                            VerticalAlignment="Center">

                    <StackPanel x:Name="deferPanel"
                                Orientation="Horizontal"
                                VerticalAlignment="Center"
                                Margin="0,0,8,0">
                        <TextBlock Text="Defer"
                                   VerticalAlignment="Center"
                                   Margin="0,0,8,0"
                                   FontSize="15"
                                   FontWeight="SemiBold"
                                   Foreground="#6B7280"/>

                        <ComboBox x:Name="cmbDeferHours"
                                  Style="{StaticResource ModernComboBox}"/>

                        <Button x:Name="btnDefer"
                                Content="Defer"
                                Width="115"
                                Height="46"
                                Style="{StaticResource SecondaryButton}"/>
                    </StackPanel>

                    <Button x:Name="btnContinue"
                            Width="130"
                            Height="46"
                            Style="{StaticResource ModernButton}"
                            IsDefault="True"/>
                </StackPanel>
            </Border>
        </Grid>
    </Border>
</Window>
"@

    $window         = [Windows.Markup.XamlReader]::Parse($xaml)
    $txtWindowTitle = $window.FindName('txtWindowTitle')
    $txtHeader      = $window.FindName('txtHeader')
    $txtMessage     = $window.FindName('txtMessage')
    $btnContinue    = $window.FindName('btnContinue')
    $btnDefer       = $window.FindName('btnDefer')
    $btnClose       = $window.FindName('btnClose')
    $titleBar       = $window.FindName('TitleBar')
    $deferPanel     = $window.FindName('deferPanel')
    $cmbDeferHours  = $window.FindName('cmbDeferHours')

    $window.Title        = $Title
    $txtWindowTitle.Text = $Title
    $txtHeader.Text      = $HeaderText
    $txtMessage.Text     = $MessageText
    $btnContinue.Content = $ContinueButtonText

    $validDeferOptions = $DeferOptions | Where-Object { $_ -gt 0 } | Sort-Object -Unique
    if (-not $validDeferOptions) {
        $validDeferOptions = @(4, 8, 24)
    }

    foreach ($hours in $validDeferOptions) {
        [void]$cmbDeferHours.Items.Add([int]$hours)
    }

    $defaultIndex = [array]::IndexOf([int[]]$validDeferOptions, [int]$DefaultDeferHours)
    if ($defaultIndex -lt 0) {
        $defaultIndex = 0
    }
    $cmbDeferHours.SelectedIndex = $defaultIndex

    $showDefer = $AllowDefer.IsPresent -and -not $DisableDefer.IsPresent
    if ($showDefer) {
        $deferPanel.Visibility = 'Visible'
    }
    else {
        $deferPanel.Visibility = 'Collapsed'
    }

    $window.Tag = $null
    $overlayWindow = $null

    if ($UseOverlay) {
        $overlayXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        ShowActivated="False"
        Topmost="True"
        Background="$OverlayColor"
        Opacity="$OverlayOpacity"
        AllowsTransparency="True"
        WindowStartupLocation="Manual"
        Left="0"
        Top="0">
</Window>
"@

        $overlayWindow = [Windows.Markup.XamlReader]::Parse($overlayXaml)
        $overlayWindow.Left   = [System.Windows.SystemParameters]::VirtualScreenLeft
        $overlayWindow.Top    = [System.Windows.SystemParameters]::VirtualScreenTop
        $overlayWindow.Width  = [System.Windows.SystemParameters]::VirtualScreenWidth
        $overlayWindow.Height = [System.Windows.SystemParameters]::VirtualScreenHeight
    }

    $btnContinue.Add_Click({
        $window.Tag = [pscustomobject]@{
            Action     = 'Continue'
            DeferHours = $null
            DeferUntil = $null
            Timestamp  = (Get-Date)
        }
        $window.Close()
    })

    if ($showDefer) {
        $btnDefer.Add_Click({
            $selectedHours = [int]$cmbDeferHours.SelectedItem
            $deferUntil    = (Get-Date).AddHours($selectedHours)

            $window.Tag = [pscustomobject]@{
                Action     = 'Defer'
                DeferHours = $selectedHours
                DeferUntil = $deferUntil
                Timestamp  = (Get-Date)
            }
            $window.Close()
        })
    }

    $btnClose.Add_Click({
        $window.Tag = [pscustomobject]@{
            Action     = 'Closed'
            DeferHours = $null
            DeferUntil = $null
            Timestamp  = (Get-Date)
        }
        $window.Close()
    })

    $window.Add_Closing({
        if (-not $window.Tag) {
            $window.Tag = [pscustomobject]@{
                Action     = 'Closed'
                DeferHours = $null
                DeferUntil = $null
                Timestamp  = (Get-Date)
            }
        }
    })

    $titleBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    try {
        if ($overlayWindow) {
            $overlayWindow.Show()
        }

        [void]$window.ShowDialog()
    }
    finally {
        if ($overlayWindow) {
            $overlayWindow.Close()
        }
    }

    return $window.Tag
}



function Show-MigrationProgress {
    <#
    .DESCRIPTION
    Creates a WPF progress window in a separate STA runspace and allows the
    status text to be updated dynamically. Optionally displays a fullscreen
    dim overlay behind the popup while the migration is running.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$StatusMessage = 'Starting Endpoint Migration...',

        [Parameter(Mandatory = $false)]
        [bool]$TopMost = $true,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$WindowTitle = 'Migration Status Updates',

        [Parameter(Mandatory = $false)]
        [bool]$UseOverlay = $true,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$OverlayColor = '#000000',

        [Parameter(Mandatory = $false)]
        [ValidateRange(0.0, 1.0)]
        [double]$OverlayOpacity = 0.25
    )

    if ($envHost.Name -match 'PowerGUI') {
        Write-Log -Level Warn -Message "$($envHost.Name) is not a supported host for WPF multi-threading. Progress dialog with message [$StatusMessage] will not be displayed."
        return
    }

    $progressRunning = $false
    try {
        if ($script:ProgressSyncHash -and
            $script:ProgressSyncHash.Window -and
            $script:ProgressSyncHash.Window.Dispatcher -and
            -not $script:ProgressSyncHash.Window.Dispatcher.HasShutdownStarted -and
            -not $script:ProgressSyncHash.Window.Dispatcher.HasShutdownFinished) {
            $progressRunning = $true
        }
    }
    catch {
        $progressRunning = $false
    }

    if (-not $progressRunning) {
        $script:ProgressSyncHash = [hashtable]::Synchronized(@{})
        $script:ProgressSyncHash.AllowClose = $false
        $script:ProgressSyncHash.Error = $null
        $script:ProgressSyncHash.Window = $null
        $script:ProgressSyncHash.OverlayWindow = $null
        $script:ProgressSyncHash.ProgressText = $null

        $script:ProgressRunspace = [runspacefactory]::CreateRunspace()
        $script:ProgressRunspace.ApartmentState = 'STA'
        $script:ProgressRunspace.ThreadOptions = 'ReuseThread'
        $script:ProgressRunspace.Open()

        $script:ProgressRunspace.SessionStateProxy.SetVariable('ProgressSyncHash', $script:ProgressSyncHash)
        $script:ProgressRunspace.SessionStateProxy.SetVariable('WindowTitle', $WindowTitle)
        $script:ProgressRunspace.SessionStateProxy.SetVariable('TopMost', $TopMost)
        $script:ProgressRunspace.SessionStateProxy.SetVariable('ProgressStatusMessage', $StatusMessage)
        $script:ProgressRunspace.SessionStateProxy.SetVariable('RsPSScriptRoot', $PSScriptRoot)
        $script:ProgressRunspace.SessionStateProxy.SetVariable('UseOverlay', $UseOverlay)
        $script:ProgressRunspace.SessionStateProxy.SetVariable('OverlayColor', $OverlayColor)
        $script:ProgressRunspace.SessionStateProxy.SetVariable('OverlayOpacity', $OverlayOpacity)

        $script:ProgressPowerShell = [powershell]::Create()
        $null = $script:ProgressPowerShell.AddScript({
            Add-Type -AssemblyName PresentationFramework
            Add-Type -AssemblyName PresentationCore
            Add-Type -AssemblyName WindowsBase

            [string]$xamlProgressString = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    x:Name="Window"
    Title="Migration Status"
    Padding="0,0,0,0"
    Margin="0,0,0,0"
    WindowStartupLocation="Manual"
    Top="0"
    Left="0"
    Topmost="True"
    WindowStyle="None"
    ResizeMode="NoResize"
    ShowInTaskbar="True"
    VerticalContentAlignment="Center"
    HorizontalContentAlignment="Center"
    SizeToContent="WidthAndHeight">
    <Window.Resources>
        <Storyboard x:Key="Storyboard1" RepeatBehavior="Forever">
            <DoubleAnimationUsingKeyFrames BeginTime="00:00:00"
                                           Storyboard.TargetName="ellipse"
                                           Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[2].(RotateTransform.Angle)">
                <SplineDoubleKeyFrame KeyTime="00:00:02" Value="360"/>
            </DoubleAnimationUsingKeyFrames>
        </Storyboard>
    </Window.Resources>
    <Window.Triggers>
        <EventTrigger RoutedEvent="FrameworkElement.Loaded">
            <BeginStoryboard Storyboard="{StaticResource Storyboard1}"/>
        </EventTrigger>
    </Window.Triggers>

    <Border BorderBrush="#2E1869" BorderThickness="10">
        <Grid Background="#F0F0F0" MinWidth="450" MaxWidth="750" Width="600">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
                <ColumnDefinition MinWidth="50" MaxWidth="75" Width="75"/>
                <ColumnDefinition MinWidth="350" Width="*"/>
            </Grid.ColumnDefinitions>

            <Image x:Name="ProgressBanner"
                   Grid.Row="0"
                   Grid.ColumnSpan="2"
                   Margin="0"
                   Source=""/>

            <TextBlock x:Name="ProgressText"
                       Grid.Row="1"
                       Grid.Column="1"
                       Margin="-10,10,10,10"
                       Text=""
                       FontSize="22"
                       HorizontalAlignment="Center"
                       VerticalAlignment="Center"
                       TextAlignment="Center"
                       Padding="10,0,10,0"
                       TextWrapping="Wrap"/>

            <Ellipse x:Name="ellipse"
                     Grid.Row="1"
                     Grid.Column="0"
                     Margin="0,0,0,0"
                     StrokeThickness="5"
                     RenderTransformOrigin="0.5,0.5"
                     Height="45"
                     Width="45"
                     HorizontalAlignment="Center"
                     VerticalAlignment="Center">
                <Ellipse.RenderTransform>
                    <TransformGroup>
                        <ScaleTransform/>
                        <SkewTransform/>
                        <RotateTransform/>
                    </TransformGroup>
                </Ellipse.RenderTransform>
                <Ellipse.Stroke>
                    <LinearGradientBrush EndPoint="0.445,0.997" StartPoint="0.555,0.003">
                        <GradientStop Color="White" Offset="0"/>
                        <GradientStop Color="#0078d4" Offset="1"/>
                    </LinearGradientBrush>
                </Ellipse.Stroke>
            </Ellipse>
        </Grid>
    </Border>
</Window>
'@

            [string]$xamlOverlayString = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    WindowStyle="None"
    ResizeMode="NoResize"
    ShowInTaskbar="False"
    ShowActivated="False"
    Topmost="True"
    AllowsTransparency="True"
    WindowStartupLocation="Manual"
    Left="0"
    Top="0"
    Background="#000000"
    Opacity="0.25">
</Window>
'@

            try {
                [xml]$xamlProgress = $xamlProgressString
                $progressReader = New-Object System.Xml.XmlNodeReader $xamlProgress
                $ProgressSyncHash.Window = [Windows.Markup.XamlReader]::Load($progressReader)

                $ProgressSyncHash.Window.TopMost = $TopMost
                $ProgressSyncHash.Window.Title = $WindowTitle
                $ProgressSyncHash.Window.Icon = "$RsPSScriptRoot\icon.ico"

                $ProgressBanner = $ProgressSyncHash.Window.FindName('ProgressBanner')
                $ProgressText   = $ProgressSyncHash.Window.FindName('ProgressText')

                $ProgressBanner.Source = "$RsPSScriptRoot\banner.png"
                $ProgressText.Text = $ProgressStatusMessage

                $ProgressSyncHash.ProgressText = $ProgressText

                if ($UseOverlay) {
                    [xml]$xamlOverlay = $xamlOverlayString
                    $overlayReader = New-Object System.Xml.XmlNodeReader $xamlOverlay
                    $ProgressSyncHash.OverlayWindow = [Windows.Markup.XamlReader]::Load($overlayReader)

                    $brushConverter = New-Object System.Windows.Media.BrushConverter
                    $ProgressSyncHash.OverlayWindow.Background = $brushConverter.ConvertFromString($OverlayColor)
                    $ProgressSyncHash.OverlayWindow.Opacity = [double]$OverlayOpacity
                    $ProgressSyncHash.OverlayWindow.Left = [double][System.Windows.SystemParameters]::VirtualScreenLeft
                    $ProgressSyncHash.OverlayWindow.Top = [double][System.Windows.SystemParameters]::VirtualScreenTop
                    $ProgressSyncHash.OverlayWindow.Width = [double][System.Windows.SystemParameters]::VirtualScreenWidth
                    $ProgressSyncHash.OverlayWindow.Height = [double][System.Windows.SystemParameters]::VirtualScreenHeight
                }

                $ProgressSyncHash.Window.Add_Loaded({
                    $screenWidth = [System.Windows.SystemParameters]::WorkArea.Width
                    $screenHeight = [System.Windows.SystemParameters]::WorkArea.Height

                    $ProgressSyncHash.Window.Left = [double](($screenWidth - $ProgressSyncHash.Window.ActualWidth) / 2)
                    $ProgressSyncHash.Window.Top = [double](($screenHeight - $ProgressSyncHash.Window.ActualHeight) / 50)

                    $ProgressSyncHash.Window.Activate()
                })

                $ProgressSyncHash.Window.Add_Closing({
                    if (-not $ProgressSyncHash.AllowClose) {
                        $_.Cancel = $true
                    }
                })

                $ProgressSyncHash.Window.Add_Closed({
                    try {
                        if ($ProgressSyncHash.OverlayWindow) {
                            $ProgressSyncHash.OverlayWindow.Close()
                        }
                    }
                    catch { }
                })

                $ProgressSyncHash.Window.Add_MouseLeftButtonDown({
                    $ProgressSyncHash.Window.DragMove()
                })

                if ($ProgressSyncHash.OverlayWindow) {
                    $null = $ProgressSyncHash.OverlayWindow.Show()
                }

                $null = $ProgressSyncHash.Window.ShowDialog()
            }
            catch {
                $ProgressSyncHash.Error = $_
            }
            finally {
                try {
                    if ($ProgressSyncHash.OverlayWindow) {
                        $ProgressSyncHash.OverlayWindow.Close()
                    }
                }
                catch { }
            }
        })

        $script:ProgressPowerShell.Runspace = $script:ProgressRunspace

        Write-Log -Level Info -Message "Creating the progress dialog in a separate thread with message: [$StatusMessage]."
        $script:ProgressAsyncResult = $script:ProgressPowerShell.BeginInvoke()

        $timeout = [datetime]::Now.AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 150
            $windowReady = $false
            try {
                if ($script:ProgressSyncHash.Window -and $script:ProgressSyncHash.ProgressText) {
                    $windowReady = $true
                }
            }
            catch {
                $windowReady = $false
            }
        } until ($windowReady -or [datetime]::Now -ge $timeout)

        if ($script:ProgressSyncHash.Error) {
            Write-Log -Level Error -Message "Failure while displaying progress dialog: $($script:ProgressSyncHash.Error)"
        }
    }
    else {
        try {
            $script:ProgressSyncHash.Window.Dispatcher.Invoke(
                [System.Action]{
                    $script:ProgressSyncHash.ProgressText.Text = $StatusMessage

                    $screenWidth = [System.Windows.SystemParameters]::WorkArea.Width
                    $screenHeight = [System.Windows.SystemParameters]::WorkArea.Height

                    $script:ProgressSyncHash.Window.Left = [double](($screenWidth - $script:ProgressSyncHash.Window.ActualWidth) / 2)
                    $script:ProgressSyncHash.Window.Top = [double](($screenHeight - $script:ProgressSyncHash.Window.ActualHeight) / 50)
                },
                [Windows.Threading.DispatcherPriority]::Send
            )

            Write-Log -Level Info -Message "Updated the progress message: [$StatusMessage]."
        }
        catch {
            Write-Log -Level Error -Message "Unable to update the progress message: $_"
        }
    }
}

function Close-MigrationProgress {
    <#
    .DESCRIPTION
    Closes the migration progress window, closes the overlay if present,
    and cleans up the runspace/hash.
    #>

    try {
        if ($script:ProgressSyncHash -and
            $script:ProgressSyncHash.Window -and
            $script:ProgressSyncHash.Window.Dispatcher -and
            -not $script:ProgressSyncHash.Window.Dispatcher.HasShutdownStarted -and
            -not $script:ProgressSyncHash.Window.Dispatcher.HasShutdownFinished) {

            $script:ProgressSyncHash.Window.Dispatcher.Invoke(
                [System.Action]{
                    try {
                        $script:ProgressSyncHash.AllowClose = $true
                    }
                    catch { }

                    try {
                        if ($script:ProgressSyncHash.OverlayWindow) {
                            $script:ProgressSyncHash.OverlayWindow.Close()
                        }
                    }
                    catch { }

                    try {
                        $script:ProgressSyncHash.Window.Close()
                    }
                    catch { }

                    try {
                        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
                    }
                    catch { }
                },
                [Windows.Threading.DispatcherPriority]::Send
            )
        }
    }
    catch { }

    try {
        if ($script:ProgressAsyncResult -and $script:ProgressPowerShell) {
            $script:ProgressPowerShell.EndInvoke($script:ProgressAsyncResult)
        }
    }
    catch { }

    try {
        if ($script:ProgressPowerShell) {
            $script:ProgressPowerShell.Dispose()
        }
    }
    catch { }

    try {
        if ($script:ProgressRunspace -and
            $script:ProgressRunspace.RunspaceStateInfo.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
            $script:ProgressRunspace.Close()
        }
    }
    catch { }

    try {
        if ($script:ProgressRunspace) {
            $script:ProgressRunspace.Dispose()
        }
    }
    catch { }

    try {
        if ($script:ProgressSyncHash) {
            $script:ProgressSyncHash.Clear()
        }
    }
    catch { }

    $script:ProgressAsyncResult = $null
    $script:ProgressPowerShell  = $null
    $script:ProgressRunspace    = $null
    $script:ProgressSyncHash    = $null
}
