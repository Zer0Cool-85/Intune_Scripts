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
        [ValidateSet('Defer','YesNo','OkCancel','Ok')]
        [string]$DialogMode = 'YesNo',

        [Parameter(Mandatory = $false)]
        [string]$PrimaryButtonText,

        [Parameter(Mandatory = $false)]
        [string]$SecondaryButtonText,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [int[]]$DeferOptions = @(4, 8, 24),

        [Parameter(Mandatory = $false)]
        [int]$DefaultDeferHours = 4,

        [Parameter(Mandatory = $false)]
        [switch]$DisableDefer
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    switch ($DialogMode) {
        'Defer' {
            if ([string]::IsNullOrWhiteSpace($PrimaryButtonText))   { $PrimaryButtonText   = 'Continue' }
            if ([string]::IsNullOrWhiteSpace($SecondaryButtonText)) { $SecondaryButtonText = $null }
        }
        'YesNo' {
            if ([string]::IsNullOrWhiteSpace($PrimaryButtonText))   { $PrimaryButtonText   = 'Yes' }
            if ([string]::IsNullOrWhiteSpace($SecondaryButtonText)) { $SecondaryButtonText = 'No' }
        }
        'OkCancel' {
            if ([string]::IsNullOrWhiteSpace($PrimaryButtonText))   { $PrimaryButtonText   = 'OK' }
            if ([string]::IsNullOrWhiteSpace($SecondaryButtonText)) { $SecondaryButtonText = 'Cancel' }
        }
        'Ok' {
            if ([string]::IsNullOrWhiteSpace($PrimaryButtonText))   { $PrimaryButtonText   = 'OK' }
            $SecondaryButtonText = $null
        }
    }

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Popup"
        Width="580"
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

        <Style x:Key="ModernComboBox" TargetType="ComboBox">
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
            <Setter Property="Height" Value="40"/>
            <Setter Property="MinWidth" Value="120"/>
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
                        <TextBlock x:Name="txtWindowTitle"
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

            <!-- Footer -->
            <Border Grid.Row="2" Padding="0,10,0,22">
                <StackPanel Orientation="Horizontal"
                            HorizontalAlignment="Center"
                            VerticalAlignment="Center">

                    <StackPanel x:Name="deferPanel"
                                Orientation="Horizontal"
                                VerticalAlignment="Center"
                                Margin="0,0,8,0">
                        <ComboBox x:Name="cmbDeferHours"
                                  Style="{StaticResource ModernComboBox}"/>

                        <Button x:Name="btnDefer"
                                Content="Defer"
                                Width="115"
                                Height="46"
                                Style="{StaticResource SecondaryButton}"/>
                    </StackPanel>

                    <Button x:Name="btnSecondary"
                            Width="130"
                            Height="46"
                            Style="{StaticResource SecondaryButton}"
                            Margin="8,0,8,0"
                            IsCancel="True"/>

                    <Button x:Name="btnPrimary"
                            Width="130"
                            Height="46"
                            Style="{StaticResource ModernButton}"
                            Margin="8,0,8,0"
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
    $btnPrimary     = $window.FindName('btnPrimary')
    $btnSecondary   = $window.FindName('btnSecondary')
    $btnDefer       = $window.FindName('btnDefer')
    $btnClose       = $window.FindName('btnClose')
    $titleBar       = $window.FindName('TitleBar')
    $deferPanel     = $window.FindName('deferPanel')
    $cmbDeferHours  = $window.FindName('cmbDeferHours')

    $window.Title        = $Title
    $txtWindowTitle.Text = $Title
    $txtHeader.Text      = $HeaderText
    $txtMessage.Text     = $MessageText
    $btnPrimary.Content  = $PrimaryButtonText

    if ([string]::IsNullOrWhiteSpace($SecondaryButtonText)) {
        $btnSecondary.Visibility = 'Collapsed'
    }
    else {
        $btnSecondary.Content    = $SecondaryButtonText
        $btnSecondary.Visibility = 'Visible'
    }

    $validDeferOptions = $DeferOptions | Where-Object { $_ -gt 0 } | Sort-Object -Unique
    if (-not $validDeferOptions) {
        $validDeferOptions = @(4, 8, 24)
    }

    $cmbDeferHours.DisplayMemberPath = 'Display'
    $cmbDeferHours.SelectedValuePath = 'Hours'

    foreach ($hours in $validDeferOptions) {
        $label = if ($hours -eq 1) { '1 hour' } else { "$hours hours" }

        [void]$cmbDeferHours.Items.Add([pscustomobject]@{
            Display = $label
            Hours   = [int]$hours
        })
    }

    $defaultIndex = 0
    for ($i = 0; $i -lt $validDeferOptions.Count; $i++) {
        if ([int]$validDeferOptions[$i] -eq [int]$DefaultDeferHours) {
            $defaultIndex = $i
            break
        }
    }
    $cmbDeferHours.SelectedIndex = $defaultIndex

    if ($DialogMode -eq 'Defer' -and -not $DisableDefer.IsPresent) {
        $deferPanel.Visibility = 'Visible'
    }
    else {
        $deferPanel.Visibility = 'Collapsed'
    }

    $window.Tag = $null

    $btnPrimary.Add_Click({
        $window.Tag = [pscustomobject]@{
            Action       = 'Primary'
            ButtonText   = [string]$btnPrimary.Content
            DialogMode   = $DialogMode
            Accepted     = $true
            DeferHours   = $null
            DeferUntil   = $null
            Timestamp    = (Get-Date)
        }
        $window.Close()
    })

    if ($btnSecondary.Visibility -eq 'Visible') {
        $btnSecondary.Add_Click({
            $window.Tag = [pscustomobject]@{
                Action       = 'Secondary'
                ButtonText   = [string]$btnSecondary.Content
                DialogMode   = $DialogMode
                Accepted     = $false
                DeferHours   = $null
                DeferUntil   = $null
                Timestamp    = (Get-Date)
            }
            $window.Close()
        })
    }

    if ($deferPanel.Visibility -eq 'Visible') {
        $btnDefer.Add_Click({
            $selectedHours = [int]$cmbDeferHours.SelectedValue
            $deferUntil    = (Get-Date).AddHours($selectedHours)

            $window.Tag = [pscustomobject]@{
                Action       = 'Defer'
                ButtonText   = [string]$btnDefer.Content
                DialogMode   = $DialogMode
                Accepted     = $null
                DeferHours   = $selectedHours
                DeferUntil   = $deferUntil
                Timestamp    = (Get-Date)
            }
            $window.Close()
        })
    }

    $btnClose.Add_Click({
        $window.Tag = [pscustomobject]@{
            Action       = 'Closed'
            ButtonText   = $null
            DialogMode   = $DialogMode
            Accepted     = $null
            DeferHours   = $null
            DeferUntil   = $null
            Timestamp    = (Get-Date)
        }
        $window.Close()
    })

    $window.Add_Closing({
        if (-not $window.Tag) {
            $window.Tag = [pscustomobject]@{
                Action       = 'Closed'
                ButtonText   = $null
                DialogMode   = $DialogMode
                Accepted     = $null
                DeferHours   = $null
                DeferUntil   = $null
                Timestamp    = (Get-Date)
            }
        }
    })

    $titleBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    [void]$window.ShowDialog()
    return $window.Tag
}


