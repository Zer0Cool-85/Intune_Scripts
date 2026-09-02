#requires -Version 5.1

<#
    SystemSupportInfo.UI.psm1

    Builds the WPF interface from configuration and binds it to the data
    supplied by SystemSupportInfo.Core.psm1.
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$coreModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'SystemSupportInfo.Core.psm1'
$coreModule = Import-Module -Name $coreModulePath -Force -PassThru -ErrorAction Stop

function Test-WpfColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        $converter = [System.Windows.Media.BrushConverter]::new()
        $null = $converter.ConvertFromString($Value)
        return $true
    }
    catch {
        throw "Configuration value '$Name' is not a valid WPF color: $Value"
    }
}

function Assert-SystemSupportConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Configuration
    )

    foreach ($section in @('Application', 'Branding', 'ServiceDesk', 'Text', 'Summary', 'Fields')) {
        if (-not $Configuration.ContainsKey($section)) {
            throw "The configuration is missing the '$section' section."
        }
    }

    $requiredApplicationSettings = @(
        'WindowTitle', 'Subtitle', 'Width', 'Height', 'MinWidth', 'MinHeight',
        'Columns', 'Resizable', 'ShowPrivacyNotice'
    )
    foreach ($settingName in $requiredApplicationSettings) {
        if (-not $Configuration.Application.ContainsKey($settingName)) {
            throw "Application.$settingName is required."
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$Configuration.Application.WindowTitle)) {
        throw 'Application.WindowTitle cannot be empty.'
    }

    $columns = [int]$Configuration.Application.Columns
    if ($columns -lt 1 -or $columns -gt 3) {
        throw 'Application.Columns must be between 1 and 3.'
    }

    foreach ($dimensionName in @('Width', 'Height', 'MinWidth', 'MinHeight')) {
        if (([double]$Configuration.Application[$dimensionName]) -le 0) {
            throw "Application.$dimensionName must be greater than zero."
        }
    }

    $colorNames = @(
        'AccentColor',
        'AccentHoverColor',
        'WindowColor',
        'HeaderColor',
        'CardColor',
        'CardBorderColor',
        'PrimaryTextColor',
        'SecondaryTextColor',
        'SecondaryButtonColor',
        'SecondaryButtonHoverColor',
        'InfoPanelColor',
        'InfoPanelBorderColor',
        'InfoPanelTextColor',
        'SuccessTextColor',
        'ErrorTextColor'
    )

    foreach ($colorName in $colorNames) {
        if (-not $Configuration.Branding.ContainsKey($colorName)) {
            throw "Branding.$colorName is required."
        }

        $null = Test-WpfColor `
            -Value ([string]$Configuration.Branding[$colorName]) `
            -Name "Branding.$colorName"
    }

    if (-not $Configuration.Branding.ContainsKey('FallbackMark')) {
        throw 'Branding.FallbackMark is required.'
    }

    $requiredTextSettings = @(
        'PrivacyNotice', 'DefaultStatus', 'CopySummaryButton', 'RefreshButton',
        'Unavailable', 'DateFormat', 'RefreshingMessage',
        'RefreshCompleteMessage', 'RefreshErrorMessage',
        'RefreshBeforeCopyMessage', 'SummaryCopiedMessage',
        'ClipboardErrorMessage', 'NoValueMessage',
        'ServiceDeskOpeningMessage', 'ServiceDeskErrorMessage',
        'ServiceDeskNotConfiguredMessage'
    )
    foreach ($settingName in $requiredTextSettings) {
        if (-not $Configuration.Text.ContainsKey($settingName)) {
            throw "Text.$settingName is required."
        }
    }

    try {
        $null = (Get-Date).ToString([string]$Configuration.Text.DateFormat)
    }
    catch {
        throw 'Text.DateFormat is not a valid .NET date/time format string.'
    }

    foreach ($settingName in @('Heading', 'IncludeCollectedAt', 'CollectedLabel')) {
        if (-not $Configuration.Summary.ContainsKey($settingName)) {
            throw "Summary.$settingName is required."
        }
    }

    foreach ($settingName in @('Url', 'ButtonText')) {
        if (-not $Configuration.ServiceDesk.ContainsKey($settingName)) {
            throw "ServiceDesk.$settingName is required."
        }
    }

    $seenKeys = @{}
    foreach ($field in @($Configuration.Fields)) {
        foreach ($propertyName in @('Key', 'Label', 'Section')) {
            if (-not $field.ContainsKey($propertyName) -or [string]::IsNullOrWhiteSpace([string]$field[$propertyName])) {
                throw "Every Fields entry must contain a non-empty '$propertyName' value."
            }
        }

        $key = [string]$field.Key
        if ($seenKeys.ContainsKey($key)) {
            throw "Fields contains the duplicate key '$key'."
        }

        $seenKeys[$key] = $true
    }

    if ($seenKeys.Count -eq 0) {
        throw 'Fields must contain at least one field definition.'
    }

    $serviceDeskUrl = [string]$Configuration.ServiceDesk.Url
    if (-not [string]::IsNullOrWhiteSpace($serviceDeskUrl)) {
        try {
            $uri = [uri]$serviceDeskUrl
        }
        catch {
            throw 'ServiceDesk.Url must be a valid absolute HTTP or HTTPS URL.'
        }

        if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http', 'https') -or [string]::IsNullOrWhiteSpace($uri.Host)) {
            throw 'ServiceDesk.Url must be a valid absolute HTTP or HTTPS URL.'
        }
    }

    return $true
}

function Test-SystemSupportInfoConfiguration {
    <#
    .SYNOPSIS
        Validates a SystemSupportInfo configuration hashtable.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Configuration
    )

    return Assert-SystemSupportConfiguration -Configuration $Configuration
}

function Resolve-ApplicationAssetPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ApplicationRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path -Path $ApplicationRoot -ChildPath $Path
}

function Set-SupportClipboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    try {
        [System.Windows.Clipboard]::SetText($Text)
        return $true
    }
    catch {
        try {
            Set-Clipboard -Value $Text -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }
}

function Write-SystemSupportDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Context,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    try {
        $logDirectory = [System.IO.Path]::GetDirectoryName($LogPath)
        if (-not [string]::IsNullOrWhiteSpace($logDirectory)) {
            $null = [System.IO.Directory]::CreateDirectory($logDirectory)
        }

        $message = '[{0}] {1}: {2}{3}{4}{3}' -f `
            [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'),
            $Context,
            $ErrorRecord.Exception.Message,
            [Environment]::NewLine,
            $ErrorRecord.ScriptStackTrace

        [System.IO.File]::AppendAllText(
            $LogPath,
            $message,
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    catch {
        # Diagnostics must never prevent the support window from loading.
    }
}

function ConvertTo-SupportTicketSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Data,

        [Parameter(Mandatory)]
        [hashtable]$Configuration
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(([string]$Configuration.Summary.Heading))

    if ([bool]$Configuration.Summary.IncludeCollectedAt) {
        $collectedLabel = [string]$Configuration.Summary.CollectedLabel
        $lines.Add(('{0}: {1}' -f $collectedLabel, $Data.CollectedAt))
    }

    $lines.Add('')
    $currentSection = $null

    foreach ($field in @($Configuration.Fields)) {
        $isVisible = -not $field.ContainsKey('Visible') -or [bool]$field.Visible
        $includeInSummary = -not $field.ContainsKey('IncludeInSummary') -or [bool]$field.IncludeInSummary

        if (-not $isVisible -or -not $includeInSummary) {
            continue
        }

        $section = [string]$field.Section
        if ($section -ne $currentSection) {
            if ($null -ne $currentSection) {
                $lines.Add('')
            }

            $lines.Add($section.ToUpperInvariant())
            $currentSection = $section
        }

        $label = if ($field.ContainsKey('SummaryLabel')) { [string]$field.SummaryLabel } else { [string]$field.Label }
        $property = $Data.PSObject.Properties[[string]$field.Key]
        $value = if ($null -ne $property) { [string]$property.Value } else { [string]$Configuration.Text.Unavailable }
        $lines.Add(('{0}: {1}' -f $label, $value))
    }

    return ($lines -join [Environment]::NewLine)
}

function Show-SystemSupportInfo {
    <#
    .SYNOPSIS
        Displays the configurable System Support Information window.

    .PARAMETER Configuration
        Hashtable loaded from a SystemSupportInfo configuration PSD1 file.

    .PARAMETER ApplicationRoot
        Root used to resolve relative logo and asset paths.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Configuration,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ApplicationRoot
    )

    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw 'This WPF interface requires STA mode. Run powershell.exe -STA or pwsh.exe -STA.'
    }

    $null = Assert-SystemSupportConfiguration -Configuration $Configuration

    $xamlText = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Device Support Information"
    Width="760"
    Height="720"
    MinWidth="680"
    MinHeight="600"
    WindowStartupLocation="CenterScreen"
    WindowStyle="None"
    ResizeMode="CanResizeWithGrip"
    AllowsTransparency="True"
    Background="Transparent"
    FontFamily="Segoe UI"
    UseLayoutRounding="True"
    SnapsToDevicePixels="True">

    <Window.Resources>
        <SolidColorBrush x:Key="AccentBrush" Color="__ACCENT__" />
        <SolidColorBrush x:Key="AccentHoverBrush" Color="__ACCENT_HOVER__" />
        <SolidColorBrush x:Key="WindowBrush" Color="__WINDOW__" />
        <SolidColorBrush x:Key="CardBrush" Color="__CARD__" />
        <SolidColorBrush x:Key="CardBorderBrush" Color="__CARD_BORDER__" />
        <SolidColorBrush x:Key="PrimaryTextBrush" Color="__PRIMARY_TEXT__" />
        <SolidColorBrush x:Key="SecondaryTextBrush" Color="__SECONDARY_TEXT__" />

        <Style x:Key="BaseButtonStyle" TargetType="Button">
            <Setter Property="Foreground" Value="White" />
            <Setter Property="Background" Value="{StaticResource AccentBrush}" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Padding" Value="16,9" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="FocusVisualStyle" Value="{x:Null}" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border
                            Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            CornerRadius="8"
                            Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource AccentHoverBrush}" />
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Opacity" Value="0.78" />
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Opacity" Value="0.45" />
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SecondaryButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
            <Setter Property="Background" Value="__SECONDARY_BUTTON__" />
            <Setter Property="BorderBrush" Value="__CARD_BORDER__" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="Padding" Value="16,8" />
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="__SECONDARY_BUTTON_HOVER__" />
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="HeaderButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
            <Setter Property="Width" Value="38" />
            <Setter Property="Height" Value="34" />
            <Setter Property="Padding" Value="0" />
            <Setter Property="Margin" Value="4,0,0,0" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="Foreground" Value="__SECONDARY_TEXT__" />
            <Setter Property="FontFamily" Value="Segoe MDL2 Assets" />
            <Setter Property="FontSize" Value="12" />
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="__CARD_BORDER__" />
                    <Setter Property="Foreground" Value="White" />
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="CloseButtonStyle" TargetType="Button" BasedOn="{StaticResource HeaderButtonStyle}">
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#C42B1C" />
                    <Setter Property="Foreground" Value="White" />
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="InfoCardStyle" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource CardBrush}" />
            <Setter Property="BorderBrush" Value="{StaticResource CardBorderBrush}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="CornerRadius" Value="10" />
            <Setter Property="Padding" Value="14,11" />
            <Setter Property="Margin" Value="0,0,10,10" />
            <Setter Property="MinHeight" Value="67" />
        </Style>

        <Style x:Key="FieldLabelStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource SecondaryTextBrush}" />
            <Setter Property="FontSize" Value="10" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Margin" Value="0,0,0,3" />
        </Style>

        <Style x:Key="FieldValueStyle" TargetType="TextBox">
            <Setter Property="Foreground" Value="{StaticResource PrimaryTextBrush}" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Padding" Value="0" />
            <Setter Property="FontSize" Value="14" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="IsReadOnly" Value="True" />
            <Setter Property="TextWrapping" Value="NoWrap" />
            <Setter Property="HorizontalScrollBarVisibility" Value="Hidden" />
            <Setter Property="VerticalContentAlignment" Value="Center" />
            <Setter Property="SelectionBrush" Value="{StaticResource AccentBrush}" />
            <Setter Property="CaretBrush" Value="White" />
            <Setter Property="ToolTipService.ShowDuration" Value="60000" />
        </Style>

        <Style x:Key="FieldCopyButtonStyle" TargetType="Button" BasedOn="{StaticResource BaseButtonStyle}">
            <Setter Property="Width" Value="34" />
            <Setter Property="Height" Value="34" />
            <Setter Property="Padding" Value="0" />
            <Setter Property="Margin" Value="10,0,0,0" />
            <Setter Property="Background" Value="Transparent" />
            <Setter Property="Foreground" Value="__SECONDARY_TEXT__" />
            <Setter Property="FontFamily" Value="Segoe MDL2 Assets" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="ToolTip" Value="Copy this value" />
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="__CARD_BORDER__" />
                    <Setter Property="Foreground" Value="White" />
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SectionTitleStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="__PRIMARY_TEXT__" />
            <Setter Property="FontSize" Value="12" />
            <Setter Property="FontWeight" Value="Bold" />
            <Setter Property="Margin" Value="2,12,0,9" />
        </Style>
    </Window.Resources>

    <Border
        Margin="12"
        Background="{StaticResource WindowBrush}"
        BorderBrush="__CARD_BORDER__"
        BorderThickness="1"
        CornerRadius="15">
        <Border.Effect>
            <DropShadowEffect Color="#000000" BlurRadius="24" ShadowDepth="0" Opacity="0.5" />
        </Border.Effect>

        <DockPanel LastChildFill="True">
            <Border
                x:Name="HeaderBar"
                DockPanel.Dock="Top"
                Height="94"
                Background="__HEADER__"
                CornerRadius="14,14,0,0">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>

                    <Grid Width="52" Height="52" Margin="20,0,14,0" VerticalAlignment="Center">
                        <Ellipse Fill="{StaticResource AccentBrush}" />
                        <TextBlock
                            x:Name="FallbackLogo"
                            Text="i"
                            Foreground="White"
                            FontFamily="Segoe UI"
                            FontSize="31"
                            FontWeight="Bold"
                            HorizontalAlignment="Center"
                            VerticalAlignment="Center"
                            Margin="0,-2,0,0" />
                        <Image
                            x:Name="BrandLogo"
                            Width="46"
                            Height="46"
                            Stretch="Uniform"
                            Visibility="Collapsed" />
                    </Grid>

                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                        <TextBlock
                            x:Name="TitleText"
                            Text="Device Support Information"
                            Foreground="{StaticResource PrimaryTextBrush}"
                            FontSize="21"
                            FontWeight="SemiBold" />
                        <TextBlock
                            x:Name="SubtitleText"
                            Text="Copy the details your support team needs."
                            Foreground="{StaticResource SecondaryTextBrush}"
                            FontSize="12"
                            Margin="0,4,0,0" />
                    </StackPanel>

                    <StackPanel
                        Grid.Column="2"
                        Orientation="Horizontal"
                        Margin="0,14,14,0"
                        VerticalAlignment="Top">
                        <Button
                            x:Name="MinimizeButton"
                            Content="&#xE921;"
                            Style="{StaticResource HeaderButtonStyle}"
                            ToolTip="Minimize" />
                        <Button
                            x:Name="CloseButton"
                            Content="&#xE8BB;"
                            Style="{StaticResource CloseButtonStyle}"
                            ToolTip="Close (Esc)" />
                    </StackPanel>
                </Grid>
            </Border>

            <Border
                DockPanel.Dock="Bottom"
                Height="76"
                Background="__HEADER__"
                BorderBrush="__CARD_BORDER__"
                BorderThickness="0,1,0,0"
                CornerRadius="0,0,14,14">
                <Grid Margin="20,13">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="Auto" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>

                    <TextBlock
                        x:Name="StatusText"
                        Grid.Column="0"
                        Text="Choose one value or copy the full ticket summary."
                        Foreground="{StaticResource SecondaryTextBrush}"
                        FontSize="12"
                        TextWrapping="Wrap"
                        VerticalAlignment="Center"
                        Margin="0,0,16,0" />

                    <Button
                        x:Name="ServiceDeskButton"
                        Grid.Column="1"
                        Content="Open service desk"
                        Style="{StaticResource SecondaryButtonStyle}"
                        MinWidth="138"
                        Margin="0,0,10,0"
                        Visibility="Collapsed"
                        ToolTip="Open the service desk in your default browser" />

                    <Button
                        x:Name="RefreshButton"
                        Grid.Column="2"
                        Content="Refresh"
                        Style="{StaticResource SecondaryButtonStyle}"
                        Width="104"
                        Margin="0,0,10,0"
                        ToolTip="Refresh device details (F5)" />

                    <Button
                        x:Name="CopySummaryButton"
                        Grid.Column="3"
                        Content="Copy ticket summary"
                        Style="{StaticResource BaseButtonStyle}"
                        MinWidth="178"
                        ToolTip="Copy all details (Ctrl+Shift+C)" />
                </Grid>
            </Border>

            <ScrollViewer
                VerticalScrollBarVisibility="Auto"
                HorizontalScrollBarVisibility="Disabled"
                PanningMode="VerticalOnly">
                <StackPanel Margin="22,16,12,18">
                    <Border
                        x:Name="PrivacyPanel"
                        Background="__INFO_PANEL__"
                        BorderBrush="__INFO_PANEL_BORDER__"
                        BorderThickness="1"
                        CornerRadius="9"
                        Padding="13,10"
                        Margin="0,0,10,2">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock
                                Text="&#xE946;"
                                FontFamily="Segoe MDL2 Assets"
                                Foreground="__INFO_PANEL_TEXT__"
                                FontSize="14"
                                VerticalAlignment="Center"
                                Margin="0,0,9,0" />
                            <TextBlock
                                x:Name="PrivacyText"
                                Text="Nothing is submitted automatically."
                                Foreground="__INFO_PANEL_TEXT__"
                                FontSize="11.5"
                                TextWrapping="Wrap"
                                VerticalAlignment="Center" />
                        </StackPanel>
                    </Border>

                    <StackPanel x:Name="FieldsPanel" />
                </StackPanel>
            </ScrollViewer>
        </DockPanel>
    </Border>
</Window>
'@

    $replacementValues = [ordered]@{
        '__ACCENT__'                = [string]$Configuration.Branding.AccentColor
        '__ACCENT_HOVER__'          = [string]$Configuration.Branding.AccentHoverColor
        '__WINDOW__'                = [string]$Configuration.Branding.WindowColor
        '__HEADER__'                = [string]$Configuration.Branding.HeaderColor
        '__CARD__'                  = [string]$Configuration.Branding.CardColor
        '__CARD_BORDER__'           = [string]$Configuration.Branding.CardBorderColor
        '__PRIMARY_TEXT__'          = [string]$Configuration.Branding.PrimaryTextColor
        '__SECONDARY_TEXT__'        = [string]$Configuration.Branding.SecondaryTextColor
        '__SECONDARY_BUTTON__'      = [string]$Configuration.Branding.SecondaryButtonColor
        '__SECONDARY_BUTTON_HOVER__'= [string]$Configuration.Branding.SecondaryButtonHoverColor
        '__INFO_PANEL__'            = [string]$Configuration.Branding.InfoPanelColor
        '__INFO_PANEL_BORDER__'     = [string]$Configuration.Branding.InfoPanelBorderColor
        '__INFO_PANEL_TEXT__'       = [string]$Configuration.Branding.InfoPanelTextColor
    }

    foreach ($replacement in $replacementValues.GetEnumerator()) {
        $xamlText = $xamlText.Replace($replacement.Key, $replacement.Value)
    }

    try {
        [xml]$xaml = $xamlText
        $reader = [System.Xml.XmlNodeReader]::new($xaml)
        $window = [Windows.Markup.XamlReader]::Load($reader)
    }
    catch {
        throw "Unable to load the System Support Information window. $($_.Exception.Message)"
    }

    $window.Title = [string]$Configuration.Application.WindowTitle
    $window.Width = [double]$Configuration.Application.Width
    $window.Height = [double]$Configuration.Application.Height
    $window.MinWidth = [double]$Configuration.Application.MinWidth
    $window.MinHeight = [double]$Configuration.Application.MinHeight
    $window.ResizeMode = if ([bool]$Configuration.Application.Resizable) {
        [System.Windows.ResizeMode]::CanResizeWithGrip
    }
    else {
        [System.Windows.ResizeMode]::NoResize
    }
    
    # Open at minimum width and use the full available screen height.
    $workArea = [System.Windows.SystemParameters]::WorkArea
    
    $window.WindowState = [System.Windows.WindowState]::Normal
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $window.Width = $window.MinWidth
    $window.Height = $workArea.Height
    $window.Top = $workArea.Top
    $window.Left = $workArea.Left + (($workArea.Width - $window.Width) / 2)

    $headerBar         = $window.FindName('HeaderBar')
    $titleText         = $window.FindName('TitleText')
    $subtitleText      = $window.FindName('SubtitleText')
    $minimizeButton    = $window.FindName('MinimizeButton')
    $closeButton       = $window.FindName('CloseButton')
    $serviceDeskButton = $window.FindName('ServiceDeskButton')
    $refreshButton     = $window.FindName('RefreshButton')
    $copySummaryButton = $window.FindName('CopySummaryButton')
    $statusText        = $window.FindName('StatusText')
    $brandLogo         = $window.FindName('BrandLogo')
    $fallbackLogo      = $window.FindName('FallbackLogo')
    $privacyPanel      = $window.FindName('PrivacyPanel')
    $privacyText       = $window.FindName('PrivacyText')
    $fieldsPanel       = $window.FindName('FieldsPanel')

    $titleText.Text = [string]$Configuration.Application.WindowTitle
    $subtitleText.Text = [string]$Configuration.Application.Subtitle
    $copySummaryButton.Content = [string]$Configuration.Text.CopySummaryButton
    $refreshButton.Content = [string]$Configuration.Text.RefreshButton
    $fallbackLogo.Text = [string]$Configuration.Branding.FallbackMark

    if ([bool]$Configuration.Application.ShowPrivacyNotice) {
        $privacyText.Text = [string]$Configuration.Text.PrivacyNotice
    }
    else {
        $privacyPanel.Visibility = [System.Windows.Visibility]::Collapsed
    }

    $brushConverter = [System.Windows.Media.BrushConverter]::new()
    $statusBrushes = @{
        Default = $brushConverter.ConvertFromString([string]$Configuration.Branding.SecondaryTextColor)
        Info    = $brushConverter.ConvertFromString([string]$Configuration.Branding.PrimaryTextColor)
        Success = $brushConverter.ConvertFromString([string]$Configuration.Branding.SuccessTextColor)
        Error   = $brushConverter.ConvertFromString([string]$Configuration.Branding.ErrorTextColor)
    }

    $logoPath = Resolve-ApplicationAssetPath `
        -Path ([string]$Configuration.Branding.LogoPath) `
        -ApplicationRoot $ApplicationRoot

    if ($logoPath -and (Test-Path -LiteralPath $logoPath -PathType Leaf)) {
        try {
            $resolvedLogoPath = (Resolve-Path -LiteralPath $logoPath -ErrorAction Stop).Path
            $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bitmap.BeginInit()
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.UriSource = [uri]$resolvedLogoPath
            $bitmap.EndInit()
            $bitmap.Freeze()

            $brandLogo.Source = $bitmap
            $brandLogo.Visibility = [System.Windows.Visibility]::Visible
            $fallbackLogo.Visibility = [System.Windows.Visibility]::Collapsed
            $window.Icon = $bitmap
        }
        catch {
            # A bad optional image should not stop the support window.
        }
    }

    $serviceDeskUri = $null
    $serviceDeskEnabled = -not $Configuration.ServiceDesk.ContainsKey('Enabled') -or [bool]$Configuration.ServiceDesk.Enabled
    if ($serviceDeskEnabled -and -not [string]::IsNullOrWhiteSpace([string]$Configuration.ServiceDesk.Url)) {
        $serviceDeskUri = [uri]$Configuration.ServiceDesk.Url
        $serviceDeskButton.Content = [string]$Configuration.ServiceDesk.ButtonText
        $serviceDeskButton.ToolTip = 'Open {0} in your default browser' -f $serviceDeskUri.Host
        $serviceDeskButton.Visibility = [System.Windows.Visibility]::Visible
    }

    $state = @{
        Data = $null
    }

    # GetNewClosure creates a dynamic module. Capture the module-scoped command
    # objects explicitly so event handlers can invoke them in both Windows
    # PowerShell 5.1 and PowerShell 7.
    $getSystemSupportDataCommand = $coreModule.ExportedCommands['Get-SystemSupportData']
    if ($null -eq $getSystemSupportDataCommand) {
        throw 'The core module did not export Get-SystemSupportData.'
    }
    $setSupportClipboardCommand = Get-Command `
        -Name 'Set-SupportClipboard' `
        -CommandType Function `
        -ErrorAction Stop
    $convertToSupportTicketSummaryCommand = Get-Command `
        -Name 'ConvertTo-SupportTicketSummary' `
        -CommandType Function `
        -ErrorAction Stop
    $writeSystemSupportDiagnosticCommand = Get-Command `
        -Name 'Write-SystemSupportDiagnostic' `
        -CommandType Function `
        -ErrorAction Stop
    $diagnosticLogPath = Join-Path `
        -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath 'SystemSupportInfo\SystemSupportInfo.log'

    $statusResetTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $statusResetTimer.Interval = [TimeSpan]::FromSeconds(4)
    $statusResetTimer.Add_Tick({
        param($sender, $eventArgs)

        $sender.Stop()
        $statusText.Text = [string]$Configuration.Text.DefaultStatus
        $statusText.Foreground = $statusBrushes.Default
    }.GetNewClosure())

    $showStatus = {
        param(
            [string]$Message,
            [ValidateSet('Info', 'Success', 'Error')]
            [string]$Type = 'Info'
        )

        $statusResetTimer.Stop()
        $statusText.Text = $Message
        $statusText.Foreground = $statusBrushes[$Type]

        if ($Type -ne 'Info') {
            $statusResetTimer.Start()
        }
    }.GetNewClosure()

    $statusText.Text = [string]$Configuration.Text.DefaultStatus
    $statusText.Foreground = $statusBrushes.Default

    $fieldControls = @{}
    $fieldDefinitions = @{}
    $sectionControls = [ordered]@{}

    foreach ($field in @($Configuration.Fields)) {
        $isVisible = -not $field.ContainsKey('Visible') -or [bool]$field.Visible
        if (-not $isVisible) {
            continue
        }

        $key = [string]$field.Key
        $section = [string]$field.Section
        $fieldDefinitions[$key] = $field

        if (-not $sectionControls.Contains($section)) {
            $sectionTitle = [System.Windows.Controls.TextBlock]::new()
            $sectionTitle.Text = $section.ToUpperInvariant()
            $sectionTitle.Style = $window.FindResource('SectionTitleStyle')
            $null = $fieldsPanel.Children.Add($sectionTitle)

            $sectionGrid = [System.Windows.Controls.Primitives.UniformGrid]::new()
            $sectionGrid.Columns = [int]$Configuration.Application.Columns
            $sectionControls[$section] = $sectionGrid
            $null = $fieldsPanel.Children.Add($sectionGrid)
        }

        $card = [System.Windows.Controls.Border]::new()
        $card.Style = $window.FindResource('InfoCardStyle')

        $cardGrid = [System.Windows.Controls.Grid]::new()
        $valueColumn = [System.Windows.Controls.ColumnDefinition]::new()
        $valueColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $buttonColumn = [System.Windows.Controls.ColumnDefinition]::new()
        $buttonColumn.Width = [System.Windows.GridLength]::Auto
        $null = $cardGrid.ColumnDefinitions.Add($valueColumn)
        $null = $cardGrid.ColumnDefinitions.Add($buttonColumn)

        $textPanel = [System.Windows.Controls.StackPanel]::new()

        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = ([string]$field.Label).ToUpperInvariant()
        $label.Style = $window.FindResource('FieldLabelStyle')
        $null = $textPanel.Children.Add($label)

        $valueBox = [System.Windows.Controls.TextBox]::new()
        $valueBox.Style = $window.FindResource('FieldValueStyle')
        $valueBox.Text = [string]$Configuration.Text.Unavailable
        $valueBox.ToolTip = [string]$Configuration.Text.Unavailable
        $null = $textPanel.Children.Add($valueBox)
        [System.Windows.Controls.Grid]::SetColumn($textPanel, 0)
        $null = $cardGrid.Children.Add($textPanel)

        $copyButton = [System.Windows.Controls.Button]::new()
        $copyButton.Content = [char]0xE8C8
        $copyButton.Style = $window.FindResource('FieldCopyButtonStyle')
        $copyButton.Tag = $key
        $copyButton.ToolTip = 'Copy {0}' -f ([string]$field.Label).ToLowerInvariant()
        [System.Windows.Controls.Grid]::SetColumn($copyButton, 1)
        $null = $cardGrid.Children.Add($copyButton)

        try {
            [System.Windows.Automation.AutomationProperties]::SetName(
                $copyButton,
                ('Copy {0}' -f [string]$field.Label)
            )
        }
        catch {
            # Accessibility metadata is helpful but nonessential.
        }

        $card.Child = $cardGrid
        $null = $sectionControls[$section].Children.Add($card)
        $fieldControls[$key] = $valueBox

        $copyButton.Add_Click({
            param($sender, $eventArgs)

            $selectedKey = [string]$sender.Tag
            $selectedField = $fieldDefinitions[$selectedKey]
            $property = if ($state.Data) { $state.Data.PSObject.Properties[$selectedKey] } else { $null }
            $value = if ($null -ne $property) { [string]$property.Value } else { '' }

            if ([string]::IsNullOrWhiteSpace($value)) {
                & $showStatus -Message ([string]$Configuration.Text.NoValueMessage) -Type Error
                return
            }

            if (& $setSupportClipboardCommand -Text $value) {
                & $showStatus -Message ('{0} copied.' -f [string]$selectedField.Label) -Type Success
            }
            else {
                & $showStatus -Message ([string]$Configuration.Text.ClipboardErrorMessage) -Type Error
            }
        }.GetNewClosure())
    }

    $refreshData = {
        $refreshButton.IsEnabled = $false
        $copySummaryButton.IsEnabled = $false
        & $showStatus -Message ([string]$Configuration.Text.RefreshingMessage)

        $window.Dispatcher.Invoke(
            [Action]{},
            [System.Windows.Threading.DispatcherPriority]::Render
        )

        try {
            $state.Data = & $getSystemSupportDataCommand `
                -UnavailableText ([string]$Configuration.Text.Unavailable) `
                -DateFormat ([string]$Configuration.Text.DateFormat)

            foreach ($key in $fieldControls.Keys) {
                $property = $state.Data.PSObject.Properties[$key]
                $value = if ($null -ne $property) { [string]$property.Value } else { [string]$Configuration.Text.Unavailable }
                $fieldControls[$key].Text = $value
                $fieldControls[$key].ToolTip = $value
            }

            $statusText.ToolTip = $null
            & $showStatus -Message ([string]$Configuration.Text.RefreshCompleteMessage) -Type Success
        }
        catch {
            $refreshError = $_
            foreach ($key in $fieldControls.Keys) {
                if ([string]::IsNullOrWhiteSpace([string]$fieldControls[$key].Text)) {
                    $fieldControls[$key].Text = [string]$Configuration.Text.Unavailable
                    $fieldControls[$key].ToolTip = [string]$Configuration.Text.Unavailable
                }
            }

            & $writeSystemSupportDiagnosticCommand `
                -LogPath $diagnosticLogPath `
                -Context 'Refresh failed' `
                -ErrorRecord $refreshError
            $statusText.ToolTip = 'Error: {0}{1}Diagnostic log: {2}' -f `
                $refreshError.Exception.Message,
                [Environment]::NewLine,
                $diagnosticLogPath
            & $showStatus -Message ([string]$Configuration.Text.RefreshErrorMessage) -Type Error
        }
        finally {
            $refreshButton.IsEnabled = $true
            $copySummaryButton.IsEnabled = $null -ne $state.Data
        }
    }.GetNewClosure()

    $copySummary = {
        if ($null -eq $state.Data) {
            & $showStatus -Message ([string]$Configuration.Text.RefreshBeforeCopyMessage) -Type Error
            return
        }

        $summary = & $convertToSupportTicketSummaryCommand `
            -Data $state.Data `
            -Configuration $Configuration
        if (& $setSupportClipboardCommand -Text $summary) {
            & $showStatus -Message ([string]$Configuration.Text.SummaryCopiedMessage) -Type Success
        }
        else {
            & $showStatus -Message ([string]$Configuration.Text.ClipboardErrorMessage) -Type Error
        }
    }.GetNewClosure()

    $headerBar.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)

        if ($eventArgs.ClickCount -eq 2 -and [bool]$Configuration.Application.Resizable) {
            $window.WindowState = if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
            return
        }

        try {
            $window.DragMove()
        }
        catch {
            # DragMove can throw when the mouse is released during the call.
        }
    }.GetNewClosure())

    $minimizeButton.Add_Click({
        param($sender, $eventArgs)
        $window.WindowState = [System.Windows.WindowState]::Minimized
    }.GetNewClosure())

    $closeButton.Add_Click({
        param($sender, $eventArgs)
        $window.Close()
    }.GetNewClosure())

    $refreshButton.Add_Click({
        param($sender, $eventArgs)
        & $refreshData
    }.GetNewClosure())

    $serviceDeskButton.Add_Click({
        param($sender, $eventArgs)

        if ($null -eq $serviceDeskUri) {
            & $showStatus -Message ([string]$Configuration.Text.ServiceDeskNotConfiguredMessage) -Type Error
            return
        }

        try {
            Start-Process -FilePath $serviceDeskUri.AbsoluteUri -ErrorAction Stop
            & $showStatus -Message ([string]$Configuration.Text.ServiceDeskOpeningMessage) -Type Success
        }
        catch {
            & $showStatus -Message ([string]$Configuration.Text.ServiceDeskErrorMessage) -Type Error
        }
    }.GetNewClosure())

    $copySummaryButton.Add_Click({
        param($sender, $eventArgs)
        & $copySummary
    }.GetNewClosure())

    $window.Add_PreviewKeyDown({
        param($sender, $eventArgs)

        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            $window.Close()
            $eventArgs.Handled = $true
            return
        }

        if ($eventArgs.Key -eq [System.Windows.Input.Key]::F5) {
            & $refreshData
            $eventArgs.Handled = $true
            return
        }

        $modifiers = [System.Windows.Input.Keyboard]::Modifiers
        $hasControl = ($modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
        $hasShift = ($modifiers -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0

        if ($hasControl -and $hasShift -and $eventArgs.Key -eq [System.Windows.Input.Key]::C) {
            & $copySummary
            $eventArgs.Handled = $true
        }
    }.GetNewClosure())

    & $refreshData
    $null = $window.ShowDialog()
}

Export-ModuleMember -Function Show-SystemSupportInfo, Test-SystemSupportInfoConfiguration
