# If we are running as a 32-bit process on an x64 OS, re-launch as a 64-bit process.
# This is safer than checking PROCESSOR_ARCHITEW6432 directly because it only relaunches
# when the current PowerShell process is actually 32-bit.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $sysNativePowerShell = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path $sysNativePowerShell) {
        & $sysNativePowerShell -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File $PSCommandPath
        exit $LASTEXITCODE
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$imagePath = $PSScriptRoot 

#region functions
function Log() {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)] [String] $message
    )

    $ts = get-date -f "yyyy/MM/dd hh:mm:ss tt"
    Write-Output "$ts $message"
}
function Get-InstalledApplications {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [String]$Name
    )
    $uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $AllApps = @()
    foreach ($key in $uninstallKeys) {
        $app = Get-ItemProperty $key | Where-Object { $_.DisplayName -and $_.UninstallString } | Select-Object DisplayName, DisplayVersion, UninstallString
        $AllApps += $app
    }

    $AllApps | Where-Object { $_.DisplayName -like "*$($Name)*" }
}
function Uninstall-AppFull {

	param (
		[string]$appName
	)

	# Get a list of installed applications from Programs and Features
	$installedApps = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,
	HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
	Where-Object { $null -ne $_.DisplayName } |
	Select-Object DisplayName, UninstallString

	$allInstalledApps = $installedApps | Where-Object { $_.DisplayName -eq "$appName" }

	# Loop through the list of installed applications and uninstall them

	foreach ($app in $allInstalledApps) {
		$uninstallString = $app.UninstallString
		$displayName = $app.DisplayName
		if ($uninstallString -match "^msiexec.exe") {
			# For MSI-based uninstallers, modify the command from /I (install) to /X (uninstall)
			Log "MSI uninstaller"
			$filePath = "msiexec.exe"
			$pattern = '(?<=\{).+?(?=\})'
			$uninstallString = $uninstallString
			$appGUID = [regex]::Matches($uninstallString, $pattern).Value
			$arguments = " /x " + """" + "$appGUID" + """" + " /qn /norestart" # Add silent and no-restart switches
		} else {
			Log "EXE uninstaller"
			# EXE uninstaller, modify the command to add silent parameters for the specific application's uninstaller (e.g., /S, -silent, etc.)
			# Add silent parameters if known for the specific application's uninstaller (e.g., /S, -silent, etc.)
			if ($uninstallString -match '^\s*"([^"]+)"\s*(.*)$') {
				$filePath = $Matches[1]
				$argMatch = $Matches[2]
				if ($argMatch -notmatch '(?i)(^|\s)(/s|/silent|-silent|/quiet|-quiet)(\s|$)') {
					if ($argMatch -match '(^|\s)/\w+') {
						$arguments = ($argMatch.trim() + " /silent").Trim()
					}
					elseif ($argMatch -match '(^|\s)-\w+') {
						$arguments = ($argMatch.trim() + " -silent").Trim()
					}
					else {
						$arguments = ($argMatch.trim() + " /silent").Trim()
					}
				}
				elseif ($uninstallString -match '^\s*(\S+)\s*(.*)$') {
					$filePath = $Matches[1]
					$argMatch = $Matches[2]
					if ($argMatch -notmatch '(?i)(^|\s)(/s|/silent|-silent|/quiet|-quiet)(\s|$)') {
						if ($argMatch -match '(^|\s)/\w+') {
							$arguments = ($argMatch.trim() + " /silent").Trim()
						}
						elseif ($argMatch -match '(^|\s)-\w+') {
							$arguments = ($argMatch.trim() + " -silent").Trim()
						}
						else {
							$arguments = ($argMatch.trim() + " /silent").Trim()
						}			
					}
				}
			}
		}
		Log "Uninstalling: $displayName"
		Start-Process -FilePath "$filePath" -ArgumentList $arguments -Wait
	}
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

    if ($Host.Name -match 'PowerGUI') {
        Log "$($Host.Name) is not a supported host for WPF multi-threading. Progress dialog with message [$StatusMessage] will not be displayed."
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
        $script:ProgressRunspace.SessionStateProxy.SetVariable('RsPSScriptRoot', $imagePath)
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

    <Border BorderBrush="#422576" BorderThickness="8">
        <Grid Background="#ffffff" MinWidth="450" MaxWidth="750" Width="600">
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
                   Margin="0,5,0,0" 
                   RenderOptions.BitmapScalingMode="HighQuality" 
                   Height="100" 
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
                     Margin="0,0,0,10"
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

        Log "Creating the progress dialog in a separate thread with message: [$StatusMessage]."
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
            Log "Failure while displaying progress dialog: $($script:ProgressSyncHash.Error)"
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

            Log "Updated the progress message: [$StatusMessage]."
        }
        catch {
            Log "Unable to update the progress message: $_"
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
        [string]$YesButtonText = "Yes",

        [Parameter(Mandatory = $false)]
        [string]$NoButtonText = "No",
        
        [Parameter(Mandatory = $false)]
        [switch]$ShowNoButton  
    )

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
        Icon="$imagePath\icon.ico">

    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Margin" Value="8,0,8,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Background" Value="#4F2D8A"/>
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
                           Source="$imagePath\logo.png"
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
                            Content="X"/>
                </Grid>
            </Border>

            <!-- Body -->
            <StackPanel Grid.Row="1" Margin="26,22,26,10" HorizontalAlignment="Center">
                <TextBlock x:Name="txtHeader"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="30"
                           FontWeight="Bold"
                           Foreground="#30125F"
                           Margin="0,0,0,12"/>
                <Border Height="1"
                        Background="#D1D5DB"
                        Margin="0,0,0,16"
                        HorizontalAlignment="Stretch"/>
                <TextBlock x:Name="txtMessage"
                           TextWrapping="Wrap"
                           TextAlignment="Center"
                           FontSize="18"
                           Foreground="#000000"
                           LineHeight="24"/>                
            </StackPanel>

            <!-- Footer -->
            <Border Grid.Row="2"
                    BorderBrush="#E5E7EB"
                    BorderThickness="0,1,0,0"
                    Padding="0,14,0,22">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                    <Button x:Name="btnYes"
                            Width="130"
                            Height="46"
                            Style="{StaticResource ModernButton}"
                            IsDefault="True"/>

                    <Button x:Name="btnNo"
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
    $txtMessage = $window.FindName("txtMessage")
    $txtHeader = $window.FindName("txtHeader")

    $txtMessage.Text = $MessageText 
    $txtHeader.Text = $HeaderText
    $btnYes.Content = $YesButtonText

    if ($ShowNoButton){
        $btnNo.Visibility = "Visible"
        $btnNo.Content = $NoButtonText
    }
    else {
        $btnNo.Visibility = "Collapsed"
    }

    $btnYes.Add_Click({
        $window.DialogResult = $true
        $window.Close()
    })

    if ($ShowNoButton){
        $btnNo.Add_Click({
           $window.DialogResult = $false
           $window.Close()
        })
    }
      
    $btnClose.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    $titleBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    return $window.ShowDialog()
}
#endregion


#region hardened helper functions
function Initialize-Directory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    foreach ($item in $Path) {
        if (-not (Test-Path -LiteralPath $item)) {
            $null = New-Item -Path $item -ItemType Directory -Force
        }
    }
}

function Set-CompanyRegistryValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $false)]
        [ValidateSet('String','DWord')]
        [string]$PropertyType = 'String'
    )

    if (-not (Test-Path -LiteralPath $script:RegistryPath)) {
        $null = New-Item -Path $script:RegistryPath -Force
    }

    $null = New-ItemProperty -Path $script:RegistryPath -Name $Name -Value $Value -PropertyType $PropertyType -Force
}

function Get-CompanyRegistryValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        return (Get-ItemProperty -Path $script:RegistryPath -Name $Name -ErrorAction Stop).$Name
    }
    catch {
        return $null
    }
}

# Override the earlier function with a slightly safer registry inventory.
function Get-InstalledApplications {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Name = '*'
    )

    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($key in $uninstallKeys) {
        Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and
                (
                    $Name -eq '*' -or
                    $_.DisplayName -like "*$Name*"
                )
            } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString, QuietUninstallString, PSChildName
    }
}

function Split-UninstallString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$UninstallString
    )

    $trimmed = $UninstallString.Trim()

    if ($trimmed -match '^\s*"([^"]+)"\s*(.*)$') {
        return [pscustomobject]@{
            FilePath  = $Matches[1]
            Arguments = $Matches[2].Trim()
        }
    }

    $parts = $trimmed -split '\s+', 2
    return [pscustomobject]@{
        FilePath  = $parts[0]
        Arguments = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
    }
}

function Add-SilentUninstallSwitch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Arguments
    )

    if ([string]::IsNullOrWhiteSpace($Arguments)) {
        return '/quiet /norestart'
    }

    if ($Arguments -match '(?i)(^|\s)(/qn|/quiet|/s|/silent|-silent|-quiet)(\s|$)') {
        return $Arguments
    }

    if ($Arguments -match '(^|\s)-\w+') {
        return ($Arguments.Trim() + ' -silent').Trim()
    }

    return ($Arguments.Trim() + ' /silent').Trim()
}

function Invoke-ProcessWithTimeout {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ArgumentList,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 900,

        [Parameter(Mandatory = $false)]
        [string]$FriendlyName = $FilePath,

        [Parameter(Mandatory = $false)]
        [int[]]$SuccessExitCodes = @(0),

        [Parameter(Mandatory = $false)]
        [switch]$NoNewWindow,

        [Parameter(Mandatory = $false)]
        [System.Diagnostics.ProcessWindowStyle]$WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    )

    $command = Get-Command -Name $FilePath -ErrorAction SilentlyContinue
    $fileExists = Test-Path -LiteralPath $FilePath

    if (-not $fileExists -and -not $command) {
        Log "[$FriendlyName] File not found: $FilePath"
        return [pscustomobject]@{
            Name      = $FriendlyName
            FilePath  = $FilePath
            ExitCode  = $null
            TimedOut  = $false
            Success   = $false
            Message   = 'File not found'
        }
    }

    $startInfo = @{
        FilePath    = $FilePath
        PassThru    = $true
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($ArgumentList)) {
        $startInfo.ArgumentList = $ArgumentList
    }

    if ($NoNewWindow) {
        $startInfo.NoNewWindow = $true
    }
    else {
        $startInfo.WindowStyle = $WindowStyle
    }

    Log "[$FriendlyName] Starting: $FilePath $ArgumentList"
    Log "[$FriendlyName] Timeout: $TimeoutSeconds second(s)."

    try {
        $process = Start-Process @startInfo
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $completed) {
            Log "[$FriendlyName] Timeout reached. Killing process tree for PID $($process.Id)."
            try {
                & taskkill.exe /PID $process.Id /T /F | Out-Null
            }
            catch {
                Log "[$FriendlyName] Failed to kill process tree: $($_.Exception.Message)"
            }

            return [pscustomobject]@{
                Name      = $FriendlyName
                FilePath  = $FilePath
                ExitCode  = $null
                TimedOut  = $true
                Success   = $false
                Message   = "Timed out after $TimeoutSeconds second(s)"
            }
        }

        $exitCode = $process.ExitCode
        $success = $SuccessExitCodes -contains $exitCode

        Log "[$FriendlyName] Exit code: $exitCode. Success: $success"

        return [pscustomobject]@{
            Name      = $FriendlyName
            FilePath  = $FilePath
            ExitCode  = $exitCode
            TimedOut  = $false
            Success   = $success
            Message   = if ($success) { 'Completed successfully' } else { "Unexpected exit code: $exitCode" }
        }
    }
    catch {
        Log "[$FriendlyName] Failed to start or monitor process: $($_.Exception.Message)"
        return [pscustomobject]@{
            Name      = $FriendlyName
            FilePath  = $FilePath
            ExitCode  = $null
            TimedOut  = $false
            Success   = $false
            Message   = $_.Exception.Message
        }
    }
}

# Override the earlier function with timeout support and more reliable parsing.
function Uninstall-AppFull {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$appName,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 600
    )

    $installedApps = Get-InstalledApplications -Name $appName |
        Where-Object { $_.DisplayName -eq $appName }

    if (-not $installedApps) {
        Log "[$appName] No matching uninstall entry found."
        return
    }

    foreach ($app in $installedApps) {
        $displayName = $app.DisplayName
        $uninstallString = if (-not [string]::IsNullOrWhiteSpace($app.QuietUninstallString)) {
            $app.QuietUninstallString
        }
        else {
            $app.UninstallString
        }

        if ([string]::IsNullOrWhiteSpace($uninstallString)) {
            Log "[$displayName] No uninstall string found."
            continue
        }

        $productCode = $null

        if ($app.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') {
            $productCode = $app.PSChildName
        }
        elseif ($uninstallString -match '\{[0-9A-Fa-f-]{36}\}') {
            $productCode = $Matches[0]
        }

        if ($productCode -and $uninstallString -match '(?i)msiexec') {
            $arguments = "/x $productCode /qn /norestart"
            $null = Invoke-ProcessWithTimeout -FilePath 'msiexec.exe' -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -FriendlyName "Uninstall $displayName" -SuccessExitCodes @(0, 3010, 1605)
            continue
        }

        $command = Split-UninstallString -UninstallString $uninstallString
        $arguments = Add-SilentUninstallSwitch -Arguments $command.Arguments

        $null = Invoke-ProcessWithTimeout -FilePath $command.FilePath -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -FriendlyName "Uninstall $displayName" -SuccessExitCodes @(0, 3010)
    }
}

function Disable-TaskIfExists {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TaskName
    )

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            $null = Disable-ScheduledTask -TaskName $TaskName -ErrorAction Stop
            Log "Disabled scheduled task: $TaskName"
        }
        else {
            Log "Scheduled task not found, skipping disable: $TaskName"
        }
    }
    catch {
        Log "Failed to disable scheduled task [$TaskName]: $($_.Exception.Message)"
    }
}

function Wait-ForExplorer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        if (Get-Process -Name explorer -ErrorAction SilentlyContinue) {
            Log "Explorer detected. Continuing."
            return $true
        }

        Start-Sleep -Seconds 2
    } until ((Get-Date) -ge $deadline)

    Log "Explorer was not detected within $TimeoutSeconds second(s). Continuing anyway."
    return $false
}

function Get-WingetPath {
    [CmdletBinding()]
    param ()

    $command = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $resolved = @(Resolve-Path -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue)
    if ($resolved.Count -gt 0) {
        return ($resolved | Sort-Object -Property Path -Descending | Select-Object -First 1).Path
    }

    return $null
}

function Save-StepResult {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$StepName,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Result
    )

    if ($null -eq $Result) {
        return
    }

    $safeName = $StepName -replace '[^A-Za-z0-9]', ''
    Set-CompanyRegistryValue -Name "PostEnroll_${safeName}_Success" -Value ([int][bool]$Result.Success) -PropertyType DWord
    Set-CompanyRegistryValue -Name "PostEnroll_${safeName}_TimedOut" -Value ([int][bool]$Result.TimedOut) -PropertyType DWord

    if ($null -ne $Result.ExitCode) {
        # Store as a string so negative installer exit codes do not fail DWORD writes.
        Set-CompanyRegistryValue -Name "PostEnroll_${safeName}_ExitCode" -Value ([string]$Result.ExitCode) -PropertyType String
    }

    if ($Result.Message) {
        Set-CompanyRegistryValue -Name "PostEnroll_${safeName}_Message" -Value $Result.Message -PropertyType String
    }
}

function Install-CompanyPortal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 900
    )

    Show-MigrationProgress -StatusMessage "Installing Company Portal. Please wait..."

    if (Get-AppxPackage -AllUsers -Name 'Microsoft.CompanyPortal' -ErrorAction SilentlyContinue) {
        Log "[Company Portal] Already installed. Skipping."
        Set-CompanyRegistryValue -Name 'PostEnroll_CompanyPortal_Success' -Value 1 -PropertyType DWord
        return
    }

    $wingetPath = Get-WingetPath
    if (-not $wingetPath) {
        Log "[Company Portal] winget.exe was not found. Skipping Company Portal install."
        Set-CompanyRegistryValue -Name 'PostEnroll_CompanyPortal_Success' -Value 0 -PropertyType DWord
        Set-CompanyRegistryValue -Name 'PostEnroll_CompanyPortal_Message' -Value 'winget.exe was not found' -PropertyType String
        return
    }

    $companyPortalId = '9WZDNCRFJ3PZ'
    $arguments = "install --exact --id $companyPortalId --source msstore --silent --accept-package-agreements --accept-source-agreements --scope machine --disable-interactivity"

    $result = Invoke-ProcessWithTimeout -FilePath $wingetPath -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -FriendlyName 'Install Company Portal' -SuccessExitCodes @(0)
    Save-StepResult -StepName 'CompanyPortal' -Result $result
}

function Remove-OneDrive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 600
    )

    Show-MigrationProgress -StatusMessage "Removing OneDrive. Please wait..."

    $oneDriveInstall = Get-InstalledApplications -Name 'OneDrive'
    $oneDriveProcess = Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue
    $setupCandidates = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ }

    if (-not $oneDriveInstall -and -not $oneDriveProcess -and -not $setupCandidates) {
        Log "[OneDrive] Not detected. Skipping."
        Set-CompanyRegistryValue -Name 'PostEnroll_OneDrive_Success' -Value 1 -PropertyType DWord
        return
    }

    if ($oneDriveProcess) {
        Log "[OneDrive] Stopping running OneDrive processes."
        Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }

    if (-not $setupCandidates) {
        Log "[OneDrive] OneDriveSetup.exe not found. Skipping uninstall."
        Set-CompanyRegistryValue -Name 'PostEnroll_OneDrive_Success' -Value 0 -PropertyType DWord
        Set-CompanyRegistryValue -Name 'PostEnroll_OneDrive_Message' -Value 'OneDriveSetup.exe not found' -PropertyType String
        return
    }

    $setup = $setupCandidates | Select-Object -First 1
    $result = Invoke-ProcessWithTimeout -FilePath $setup -ArgumentList '/uninstall /allusers' -TimeoutSeconds $TimeoutSeconds -FriendlyName 'Uninstall OneDrive' -SuccessExitCodes @(0)
    Save-StepResult -StepName 'OneDrive' -Result $result
}

function Remove-Office {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 1800
    )

    Show-MigrationProgress -StatusMessage "Removing Office. Please wait..."

    $m365Install = Get-InstalledApplications -Name 'Microsoft 365 - en-us'
    $o365Install = Get-InstalledApplications -Name 'Office 16'

    if (-not $m365Install -and -not $o365Install) {
        Log "[Office] Not detected. Skipping."
        Set-CompanyRegistryValue -Name 'PostEnroll_Office_Success' -Value 1 -PropertyType DWord
        return
    }

    $odtSetup = Join-Path $env:ProgramData 'Microsoft\AutopilotBranding\ODT\Setup.exe'
    $odtUninstall = Join-Path $env:ProgramData 'Microsoft\AutopilotBranding\ODT\uninstall.xml'

    if (-not (Test-Path -LiteralPath $odtSetup) -or -not (Test-Path -LiteralPath $odtUninstall)) {
        Log "[Office] ODT setup or uninstall.xml missing. Setup: $odtSetup XML: $odtUninstall"
        Set-CompanyRegistryValue -Name 'PostEnroll_Office_Success' -Value 0 -PropertyType DWord
        Set-CompanyRegistryValue -Name 'PostEnroll_Office_Message' -Value 'ODT setup or uninstall.xml missing' -PropertyType String
        return
    }

    $result = Invoke-ProcessWithTimeout -FilePath $odtSetup -ArgumentList "/configure `"$odtUninstall`"" -TimeoutSeconds $TimeoutSeconds -FriendlyName 'Uninstall Office' -SuccessExitCodes @(0, 3010)
    Save-StepResult -StepName 'Office' -Result $result
}

function Remove-DellBloat {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 600
    )

    Show-MigrationProgress -StatusMessage "Removing OEM software. Please wait..."

    $details = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $manufacturer = $details.Manufacturer
    Log "[Dell cleanup] Device manufacturer: $manufacturer"

    if ($manufacturer -notlike '*Dell*') {
        Log "[Dell cleanup] Device is not Dell. Skipping."
        Set-CompanyRegistryValue -Name 'PostEnroll_DellCleanup_Success' -Value 1 -PropertyType DWord
        return
    }

    $uninstallPrograms = @(
        'Dell Optimizer',
        'Dell Power Manager',
        'DellOptimizerUI',
        'Dell SupportAssist OS Recovery',
        'Dell SupportAssist',
        'Dell Optimizer Service',
        'Dell Optimizer Core',
        'DellInc.PartnerPromo',
        'DellInc.DellOptimizer',
        'DellInc.DellCommandUpdate',
        'DellInc.DellPowerManager',
        'DellInc.DellDigitalDelivery',
        'DellInc.DellSupportAssistforPCs',
        'Dell Command | Update',
        'Dell Command | Update for Windows Universal',
        'Dell Command | Update for Windows 10',
        'Dell Command | Power Manager',
        'Dell Digital Delivery Service',
        'Dell Digital Delivery',
        'Dell Peripheral Manager',
        'Dell Power Manager Service',
        'Dell SupportAssist Remediation',
        'SupportAssist Recovery Assistant',
        'Dell SupportAssist OS Recovery Plugin for Dell Update',
        'Dell SupportAssistAgent',
        'Dell Update - SupportAssist Update Plugin',
        'Dell Core Services',
        'Dell Pair',
        'Dell Display Manager 2.0',
        'Dell Display Manager 2.1',
        'Dell Display Manager 2.2'
    ) | Select-Object -Unique

    foreach ($app in $uninstallPrograms) {
        Log "[Dell cleanup] Processing: $app"

        try {
            $provisionedPackages = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $app })
            foreach ($package in $provisionedPackages) {
                Log "[Dell cleanup] Removing provisioned package: $($package.DisplayName)"
                $null = Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Continue
            }
        }
        catch {
            Log "[Dell cleanup] Provisioned package removal failed for [$app]: $($_.Exception.Message)"
        }

        try {
            $appxPackages = @(Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue)
            foreach ($package in $appxPackages) {
                Log "[Dell cleanup] Removing Appx package: $($package.Name)"
                $null = Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Continue
            }
        }
        catch {
            Log "[Dell cleanup] Appx removal failed for [$app]: $($_.Exception.Message)"
        }

        Uninstall-AppFull -appName $app -TimeoutSeconds $TimeoutSeconds
    }

    Set-CompanyRegistryValue -Name 'PostEnroll_DellCleanup_Success' -Value 1 -PropertyType DWord
}

function Remove-ManageEngine {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 600
    )

    Show-MigrationProgress -StatusMessage "Removing ManageEngine. Please wait..."

    $agentFile = 'C:\Program Files (x86)\ManageEngine\UEMS_Agent\dcagent.dll'
    $uninstallBat = Join-Path $PSScriptRoot 'UninstallME.bat'
    $manageEngineInstalled = Test-Path -LiteralPath $agentFile

    if (-not $manageEngineInstalled -and -not (Get-InstalledApplications -Name 'ManageEngine UEMS - Agent')) {
        Log "[ManageEngine] Not detected. Skipping."
        Set-CompanyRegistryValue -Name 'PostEnroll_ManageEngine_Success' -Value 1 -PropertyType DWord
        return
    }

    $firstAttemptSuccess = $false

    if (Test-Path -LiteralPath $uninstallBat) {
        $result = Invoke-ProcessWithTimeout -FilePath 'cmd.exe' -ArgumentList "/c `"$uninstallBat`"" -TimeoutSeconds $TimeoutSeconds -FriendlyName 'Uninstall ManageEngine via BAT' -SuccessExitCodes @(0)
        Save-StepResult -StepName 'ManageEngineBat' -Result $result
        $firstAttemptSuccess = [bool]$result.Success
    }
    else {
        Log "[ManageEngine] UninstallME.bat was not found at $uninstallBat."
    }

    if (-not $firstAttemptSuccess -and (Get-InstalledApplications -Name 'ManageEngine UEMS - Agent')) {
        Log "[ManageEngine] BAT uninstall did not complete successfully. Trying registry uninstall entry instead of Win32_Product."
        Uninstall-AppFull -appName 'ManageEngine UEMS - Agent' -TimeoutSeconds $TimeoutSeconds
    }

    if (Test-Path -LiteralPath $agentFile) {
        Log "[ManageEngine] Agent file still exists after uninstall attempts: $agentFile"
        Set-CompanyRegistryValue -Name 'PostEnroll_ManageEngine_Success' -Value 0 -PropertyType DWord
        Set-CompanyRegistryValue -Name 'PostEnroll_ManageEngine_Message' -Value 'Agent file still exists after uninstall attempts' -PropertyType String
    }
    else {
        Log "[ManageEngine] Removal completed or agent file no longer detected."
        Set-CompanyRegistryValue -Name 'PostEnroll_ManageEngine_Success' -Value 1 -PropertyType DWord
    }
}

function Install-OktaVerify {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 900
    )

    Show-MigrationProgress -StatusMessage "Installing Okta Verify. Please wait..."

    $installer = Join-Path $script:MigrationRoot 'OktaVerifySetup.exe'

    if (-not (Test-Path -LiteralPath $installer)) {
        Log "[Okta Verify] Installer not found: $installer"
        Set-CompanyRegistryValue -Name 'OktaVerifyInstalled' -Value 0 -PropertyType DWord
        Set-CompanyRegistryValue -Name 'PostEnroll_OktaVerify_Message' -Value 'Installer not found' -PropertyType String
        return
    }

    $arguments = '/q SKU=ALL'
    $result = Invoke-ProcessWithTimeout -FilePath $installer -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -FriendlyName 'Install Okta Verify' -SuccessExitCodes @(0, 3010)
    Save-StepResult -StepName 'OktaVerify' -Result $result

    if (-not $result.Success -and -not $result.TimedOut) {
        Log "[Okta Verify] First install attempt failed. Retrying once after 30 seconds."
        Start-Sleep -Seconds 30

        $retryResult = Invoke-ProcessWithTimeout -FilePath $installer -ArgumentList $arguments -TimeoutSeconds $TimeoutSeconds -FriendlyName 'Install Okta Verify retry' -SuccessExitCodes @(0, 3010)
        Save-StepResult -StepName 'OktaVerifyRetry' -Result $retryResult

        if (-not $retryResult.Success) {
            Set-CompanyRegistryValue -Name 'OktaVerifyInstalled' -Value 0 -PropertyType DWord
        }
        else {
            Set-CompanyRegistryValue -Name 'OktaVerifyInstalled' -Value 1 -PropertyType DWord
        }
    }
    elseif ($result.Success) {
        Set-CompanyRegistryValue -Name 'OktaVerifyInstalled' -Value 1 -PropertyType DWord
    }
    else {
        Set-CompanyRegistryValue -Name 'OktaVerifyInstalled' -Value 0 -PropertyType DWord
    }
}

function Complete-PostEnrollTasks {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [bool]$ShowFinalPopup = $true
    )

    Disable-TaskIfExists -TaskName 'Post-Enroll'

    $userTaskTag = Join-Path $script:LogRoot 'UserTask.tag'
    if (Test-Path -LiteralPath $userTaskTag) {
        Log "UserTask.tag found. Disabling Post-Enroll-User."
        Disable-TaskIfExists -TaskName 'Post-Enroll-User'
    }
    else {
        Log "UserTask.tag not found. Leaving Post-Enroll-User unchanged."
    }

    if ($ShowFinalPopup) {
        $null = Show-InfoPopup -Title 'Final Device Preparation' `
            -HeaderText 'Intune Migration' `
            -MessageText "Intune migration is almost complete!`n`nPlease don't forget to complete the Okta configuration by signing in to the Okta Verify app and setting up your Offline Device Access.`n`nContact IT support if you need further assistance.`n`nEmail: helpdesk@Company.com" `
            -YesButtonText 'OK'
    }
}
#endregion hardened helper functions

# Main settings
$script:CompanyRoot = Join-Path $env:ProgramData 'Company'
$script:LogRoot = Join-Path $script:CompanyRoot 'Logs'
$script:MigrationRoot = Join-Path $script:CompanyRoot 'IntuneMigration'
$script:RegistryPath = 'HKLM:\Software\Company'

$completionName = 'PostEnrollSchdTask'
$exitCode = 0
$transcriptStarted = $false

try {
    Initialize-Directory -Path @($script:CompanyRoot, $script:LogRoot, $script:MigrationRoot)

    $logPath = Join-Path $script:LogRoot 'Post-Enroll.log'
    Start-Transcript -Path $logPath -Append -ErrorAction Stop
    $transcriptStarted = $true

    Log "===== Post-Enroll started. Computer: $env:COMPUTERNAME. User context: $env:USERDOMAIN\$env:USERNAME. PID: $PID ====="

    if (-not (Test-Path -LiteralPath $script:RegistryPath)) {
        Log "Creating registry path: $script:RegistryPath"
        $null = New-Item -Path $script:RegistryPath -Force
    }

    $alreadyCompleted = Get-CompanyRegistryValue -Name $completionName
    if ($alreadyCompleted -eq 1) {
        Log "Post-Enroll completion key already exists. Disabling scheduled tasks and exiting."
        Complete-PostEnrollTasks -ShowFinalPopup:$false
        $exitCode = 0
        return
    }

    $runCount = Get-CompanyRegistryValue -Name 'PostEnrollRunCount'
    if ($null -eq $runCount) {
        $runCount = 0
    }

    $runCount = [int]$runCount + 1
    Set-CompanyRegistryValue -Name 'PostEnrollRunCount' -Value $runCount -PropertyType DWord
    Set-CompanyRegistryValue -Name 'PostEnrollState' -Value 'InProgress' -PropertyType String
    Set-CompanyRegistryValue -Name 'PostEnrollStartUtc' -Value ([DateTime]::UtcNow.ToString('o')) -PropertyType String

    Log "Post-Enroll run count: $runCount"

    $null = Wait-ForExplorer -TimeoutSeconds 120

    Show-MigrationProgress -StatusMessage 'Finalizing device migration. Please wait...' -UseOverlay $true -OverlayColor '#000000' -OverlayOpacity 0.75

    Install-CompanyPortal -TimeoutSeconds 900
    Remove-OneDrive -TimeoutSeconds 600
    Remove-Office -TimeoutSeconds 1800
    Remove-DellBloat -TimeoutSeconds 600
    Remove-ManageEngine -TimeoutSeconds 600
    Install-OktaVerify -TimeoutSeconds 900

    # Only mark the task complete after the script reaches the end.
    # Individual step success/failure is stored separately under HKLM:\Software\Company.
    Set-CompanyRegistryValue -Name $completionName -Value 1 -PropertyType DWord
    Set-CompanyRegistryValue -Name 'PostEnrollState' -Value 'Complete' -PropertyType String
    Set-CompanyRegistryValue -Name 'PostEnrollCompleteUtc' -Value ([DateTime]::UtcNow.ToString('o')) -PropertyType String

    Log "Post-Enroll completed. Disabling scheduled tasks."

    Close-MigrationProgress
    Complete-PostEnrollTasks -ShowFinalPopup:$true

    $exitCode = 0
}
catch {
    $exitCode = 1
    $errorMessage = $_.Exception.Message
    Log "Post-Enroll failed: $errorMessage"
    Log "Script stack trace: $($_.ScriptStackTrace)"

    try {
        Set-CompanyRegistryValue -Name 'PostEnrollState' -Value 'Failed' -PropertyType String
        Set-CompanyRegistryValue -Name 'PostEnrollLastError' -Value $errorMessage -PropertyType String
        Set-CompanyRegistryValue -Name 'PostEnrollLastErrorUtc' -Value ([DateTime]::UtcNow.ToString('o')) -PropertyType String
    }
    catch {
        Log "Failed to write failure state to registry: $($_.Exception.Message)"
    }
}
finally {
    try {
        Close-MigrationProgress
    }
    catch { }

    if ($transcriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch { }
    }
}

exit $exitCode
