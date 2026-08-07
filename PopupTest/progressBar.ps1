#requires -version 5.1

<#
.SYNOPSIS
    Reusable asynchronous WPF authentication progress popup.

.DESCRIPTION
    Defines Show-AuthProgress and Close-AuthProgress for use inside a larger
    Windows PowerShell script.

    The popup runs on its own STA runspace, so its indeterminate progress bar
    continues animating and its Cancel button remains responsive even while the
    calling script is inside a timeout loop or waiting on a background job.

    Show-AuthProgress returns a controller object with these members:

      $authProg.Cancelled
      $authProg.IsOpen
      $authProg.CloseReason
      $authProg.SetText('Verifying authentication...')
      $authProg.Close('Complete')

    Dot-source this file to load the functions:

      . .\AuthProgressPopup.ps1

    Or paste the function definitions into the function section of the main
    script. This file does not display anything merely by being dot-sourced.
#>

function Show-AuthProgress {
    [CmdletBinding()]
    param(
        [string]$Title = 'Authenticating',

        [string]$Message = 'Please complete authentication',

        [string]$ProgressText = 'Waiting for auth',

        [ValidateRange(1000, 30000)]
        [int]$ReadyTimeoutMilliseconds = 5000
    )

    $SharedState = [hashtable]::Synchronized(@{
        Ready           = $false
        Closed          = $false
        CloseRequested  = $false
        CancelRequested = $false
        CloseReason     = 'Pending'
        ProgressText    = $ProgressText
        StartupError    = $null
    })

    $PopupScript = {
        param(
            [hashtable]$State,
            [string]$WindowTitle,
            [string]$BodyMessage,
            [string]$InitialProgressText
        )

        try {
            Add-Type -AssemblyName PresentationFramework
            Add-Type -AssemblyName PresentationCore
            Add-Type -AssemblyName WindowsBase

            [xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Authenticating"
        Width="560"
        Height="300"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        AllowsTransparency="True"
        Background="Transparent"
        ShowInTaskbar="True"
        Topmost="True"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        FontFamily="Segoe UI">

    <Window.Resources>
        <Style x:Key="CancelButtonStyle" TargetType="{x:Type Button}">
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

            <Grid Margin="32,28,32,24">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Grid x:Name="DragArea"
                      Grid.Row="0"
                      Background="Transparent">
                    <TextBlock x:Name="HeaderText"
                               Text="Authenticating"
                               Foreground="#202124"
                               FontSize="25"
                               FontWeight="SemiBold"/>
                </Grid>

                <TextBlock x:Name="BodyText"
                           Grid.Row="1"
                           Margin="0,12,0,0"
                           Text="Please complete authentication"
                           Foreground="#5F6368"
                           FontSize="15"/>

                <StackPanel Grid.Row="2"
                            Margin="0,28,0,0">
                    <ProgressBar x:Name="AuthProgressBar"
                                 Height="8"
                                 Minimum="0"
                                 Maximum="100"
                                 IsIndeterminate="True"
                                 Foreground="#2563EB"
                                 Background="#E5E7EB"
                                 BorderThickness="0"
                                 IsHitTestVisible="False"/>

                    <TextBlock x:Name="ProgressText"
                               Margin="0,9,0,0"
                               Text="Waiting for auth"
                               HorizontalAlignment="Center"
                               Foreground="#5F6368"
                               FontSize="13"/>
                </StackPanel>

                <Button x:Name="CancelButton"
                        Grid.Row="4"
                        Content="Cancel"
                        HorizontalAlignment="Right"
                        Style="{StaticResource CancelButtonStyle}"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

            $XmlReader = [System.Xml.XmlNodeReader]::new($Xaml)

            try {
                $AuthWindow =
                    [System.Windows.Markup.XamlReader]::Load($XmlReader)
            }
            finally {
                $XmlReader.Close()
            }

            $HeaderText   = $AuthWindow.FindName('HeaderText')
            $BodyText     = $AuthWindow.FindName('BodyText')
            $ProgressText = $AuthWindow.FindName('ProgressText')
            $CancelButton = $AuthWindow.FindName('CancelButton')
            $DragArea     = $AuthWindow.FindName('DragArea')

            $AuthWindow.Title = $WindowTitle
            $HeaderText.Text = $WindowTitle
            $BodyText.Text = $BodyMessage
            $ProgressText.Text = $InitialProgressText

            $State.ProgressText = $InitialProgressText

            $CloseTimer =
                [System.Windows.Threading.DispatcherTimer]::new()

            $CloseTimer.Interval =
                [timespan]::FromMilliseconds(100)

            $CloseTimer.Add_Tick({
                $RequestedText = [string]$State.ProgressText

                if ($ProgressText.Text -ne $RequestedText) {
                    $ProgressText.Text = $RequestedText
                }

                if ($State.CloseRequested) {
                    $CloseTimer.Stop()
                    $AuthWindow.Close()
                }
            })

            $CancelButton.Add_Click({
                $State.CancelRequested = $true
                $State.CloseReason = 'Cancel'
                $State.CloseRequested = $true
                $AuthWindow.Close()
            })

            $AuthWindow.Add_Closing({
                param($Sender, $EventArgs)

                if (-not $State.CloseRequested) {
                    $State.CancelRequested = $true
                    $State.CloseReason = 'Cancel'
                    $State.CloseRequested = $true
                }
            })

            $DragArea.Add_MouseLeftButtonDown({
                param($Sender, $EventArgs)

                if (
                    $EventArgs.LeftButton -eq
                    [System.Windows.Input.MouseButtonState]::Pressed
                ) {
                    $AuthWindow.DragMove()
                }
            })

            $CloseTimer.Start()
            $State.Ready = $true

            [void]$AuthWindow.ShowDialog()
        }
        catch {
            $State.StartupError = $_.Exception.Message
            throw
        }
        finally {
            if ($null -ne $CloseTimer) {
                $CloseTimer.Stop()
            }

            $State.Ready = $false
            $State.Closed = $true
        }
    }

    $PopupRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()

    $PopupRunspace.ApartmentState =
        [System.Threading.ApartmentState]::STA

    $PopupRunspace.ThreadOptions =
        [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread

    $PopupRunspace.Open()

    $PopupPowerShell = [powershell]::Create()
    $PopupPowerShell.Runspace = $PopupRunspace

    [void]$PopupPowerShell.AddScript($PopupScript.ToString())
    [void]$PopupPowerShell.AddArgument($SharedState)
    [void]$PopupPowerShell.AddArgument($Title)
    [void]$PopupPowerShell.AddArgument($Message)
    [void]$PopupPowerShell.AddArgument($ProgressText)

    $AsyncResult = $PopupPowerShell.BeginInvoke()

    $ReadyWatch = [System.Diagnostics.Stopwatch]::StartNew()

    while (
        -not $SharedState.Ready -and
        -not $AsyncResult.IsCompleted -and
        $ReadyWatch.ElapsedMilliseconds -lt $ReadyTimeoutMilliseconds
    ) {
        Start-Sleep -Milliseconds 25
    }

    $ReadyWatch.Stop()

    if (-not $SharedState.Ready) {
        $ErrorText = [string]$SharedState.StartupError

        if ([string]::IsNullOrWhiteSpace($ErrorText)) {
            $ErrorText =
                ($PopupPowerShell.Streams.Error | Out-String).Trim()
        }

        if ([string]::IsNullOrWhiteSpace($ErrorText)) {
            $ErrorText =
                'The authentication progress popup did not become ready.'
        }

        $SharedState.CloseRequested = $true

        if (-not $AsyncResult.AsyncWaitHandle.WaitOne(1000)) {
            $PopupPowerShell.Stop()
        }
        else {
            try {
                [void]$PopupPowerShell.EndInvoke($AsyncResult)
            }
            catch {
                # The startup error is reported below.
            }
        }

        $PopupPowerShell.Dispose()
        $PopupRunspace.Dispose()

        throw $ErrorText
    }

    $Controller = [pscustomobject][ordered]@{
        PSTypeName  = 'AuthProgressPopup.Controller'
        State       = $SharedState
        PowerShell  = $PopupPowerShell
        Runspace    = $PopupRunspace
        AsyncResult = $AsyncResult
        Disposed    = $false
    }

    $Controller | Add-Member `
        -MemberType ScriptProperty `
        -Name Cancelled `
        -Value {
            return [bool]$this.State.CancelRequested
        }

    $Controller | Add-Member `
        -MemberType ScriptProperty `
        -Name IsOpen `
        -Value {
            return (
                -not $this.Disposed -and
                -not [bool]$this.State.Closed
            )
        }

    $Controller | Add-Member `
        -MemberType ScriptProperty `
        -Name CloseReason `
        -Value {
            return [string]$this.State.CloseReason
        }

    $Controller | Add-Member `
        -MemberType ScriptMethod `
        -Name SetText `
        -Value {
            param([string]$Text)

            if (-not $this.Disposed) {
                $this.State.ProgressText = $Text
            }
        }

    $Controller | Add-Member `
        -MemberType ScriptMethod `
        -Name Close `
        -Value {
            param(
                [string]$Reason = 'Complete',
                [int]$WaitMilliseconds = 3000
            )

            if ($this.Disposed) {
                return
            }

            $this.State.CloseReason = $Reason
            $this.State.CloseRequested = $true

            if (-not $this.AsyncResult.IsCompleted) {
                [void]$this.AsyncResult.AsyncWaitHandle.WaitOne(
                    $WaitMilliseconds
                )
            }

            if ($this.AsyncResult.IsCompleted) {
                try {
                    [void]$this.PowerShell.EndInvoke(
                        $this.AsyncResult
                    )
                }
                catch {
                    # Closing should remain safe during script cleanup.
                }
            }
            else {
                try {
                    $this.PowerShell.Stop()
                }
                catch {
                    # The runspace may already be shutting down.
                }
            }

            $this.PowerShell.Dispose()
            $this.Runspace.Dispose()
            $this.Disposed = $true
        }

    Write-Output -NoEnumerate $Controller
}
