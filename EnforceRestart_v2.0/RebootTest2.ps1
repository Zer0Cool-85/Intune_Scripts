function Show-RebootCountdownPrompt {
    <#
    .SYNOPSIS
        Modern WPF reboot prompt with countdown, optional deferrals, and forced restart.

    .DESCRIPTION
        Displays a modern-looking WPF dialog prompting the user to restart.
        Supports:
          - Countdown to forced restart
          - "No hide" window near end of countdown
          - Optional deferrals tracked in registry
          - Optional no-countdown persistent prompt

    .PARAMETER CountdownSeconds
        Total seconds until forced restart. Default 3600 (1 hour).

    .PARAMETER NoHideSeconds
        In the last N seconds, the window cannot be minimized/hidden and deferral can be disabled. Default 30.

    .PARAMETER NoCountdown
        If set, no countdown is shown; prompt persists (reappears) every PersistIntervalSeconds.

    .PARAMETER PersistIntervalSeconds
        When -NoCountdown is used, bring the prompt back every N seconds if minimized. Default 300 (5 min).

    .PARAMETER TopMost
        Keep the prompt on top. Default $true.

    .PARAMETER AllowDefer
        Enable a Defer button. Default $true.

    .PARAMETER DeferTimes
        Max number of deferrals allowed. Default 2.

    .PARAMETER DeferCooldownMinutes
        Optional: if user defers, you can choose to exit and re-run later via your deployment logic.
        This function records the defer and exits immediately.

    .PARAMETER RegPath
        Registry path for deferral tracking. Default HKCU:\Software\Company\RebootPrompt

    .PARAMETER Title
        Window title. Default "Restart Required".

    .PARAMETER Message
        Main message displayed to the user.

    .PARAMETER RestartNowText
        Text for restart button.

    .PARAMETER RestartLaterText
        Text for minimize button.

    .PARAMETER DeferText
        Base text for defer button. Remaining count is appended automatically.

    .PARAMETER LogPath
        Optional log file path.

    .OUTPUTS
        PSCustomObject with Result + details.
        Result can be: RestartNow, Deferred, Minimized, TimeoutRestart, Closed

    #>
    [CmdletBinding()]
    param(
        [int]$CountdownSeconds = 3600,
        [int]$NoHideSeconds = 30,
        [switch]$NoCountdown,
        [int]$PersistIntervalSeconds = 300,
        [bool]$TopMost = $true,

        [bool]$AllowDefer = $true,
        [int]$DeferTimes = 2,
        [int]$DeferCooldownMinutes = 60,

        [string]$RegPath = "HKCU:\Software\Company\RebootPrompt",

        [string]$Title = "Restart Required",
        [string]$Message = "Your device needs to restart to finish applying updates. Please save your work.",

        [string]$RestartNowText = "Restart now",
        [string]$RestartLaterText = "Minimize",
        [string]$DeferText = "Defer",

        [string]$LogPath = "$env:ProgramData\Company\Logs\RebootPrompt.log"
    )

    # -----------------------------
    # Helpers
    # -----------------------------
    function Write-Log {
        param(
            [Parameter(Mandatory)][string]$Text,
            [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
        )
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts][$Level] $Text"
        Write-Host $line
        try {
            $dir = Split-Path -Path $LogPath -Parent
            if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
            Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
        } catch {}
    }

    function Ensure-RegKey {
        if (-not (Test-Path $RegPath)) {
            New-Item -Path $RegPath -Force | Out-Null
        }
    }

    function Get-DeferState {
        Ensure-RegKey
        $p = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Remaining = [int]($p.RemainingDeferTimes  -as [int] ?? $DeferTimes)
            LastDefer = ($p.LastDeferUtc -as [string])
        }
    }

    function Set-DeferState {
        param([int]$Remaining)
        Ensure-RegKey
        New-ItemProperty -Path $RegPath -Name "RemainingDeferTimes" -Value $Remaining -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $RegPath -Name "LastDeferUtc" -Value ((Get-Date).ToUniversalTime().ToString("o")) -PropertyType String -Force | Out-Null
    }

    function Clear-DeferState {
        if (Test-Path $RegPath) { Remove-Item -Path $RegPath -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # Prevent multiple prompts in the same session (simple mutex)
    $mutexName = "Global\Company_RebootPrompt"
    $createdNew = $false
    try {
        $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
        if (-not $createdNew) {
            Write-Log "Existing reboot prompt detected (mutex). Exiting." "WARN"
            return [pscustomobject]@{ Result="AlreadyRunning" }
        }
    } catch {}

    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

        Write-Log "Launching WPF reboot prompt. CountdownSeconds=$CountdownSeconds NoCountdown=$($NoCountdown.IsPresent) AllowDefer=$AllowDefer"

        # -----------------------------
        # Resolve deferral state
        # -----------------------------
        $deferState = $null
        $remainingDefers = 0
        if ($AllowDefer) {
            $deferState = Get-DeferState
            $remainingDefers = [int]$deferState.Remaining
            if ($remainingDefers -lt 0) { $remainingDefers = 0 }
        }

        # -----------------------------
        # WPF XAML (modern-ish flat layout)
        # -----------------------------
        $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title"
        Width="520" Height="320"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        WindowStyle="SingleBorderWindow"
        Background="#FF0F172A"
        Foreground="White"
        ShowInTaskbar="True">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" CornerRadius="14" Background="#FF111827" Padding="14" BorderBrush="#FF1F2937" BorderThickness="1">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <Border Width="36" Height="36" CornerRadius="10" Background="#FF1D4ED8" Margin="0,0,12,0">
                    <TextBlock Text="!" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel>
                    <TextBlock Text="$Title" FontSize="18" FontWeight="SemiBold"/>
                    <TextBlock Text="Action required" Opacity="0.75" FontSize="12" Margin="0,2,0,0"/>
                </StackPanel>
            </StackPanel>
        </Border>

        <!-- Body -->
        <Border Grid.Row="1" Margin="0,14,0,14" CornerRadius="14" Background="#FF111827" Padding="16" BorderBrush="#FF1F2937" BorderThickness="1">
            <StackPanel>
                <TextBlock Name="TxtMessage" TextWrapping="Wrap" FontSize="14" Opacity="0.95">
                    $Message
                </TextBlock>

                <Border Name="CountdownPanel" Margin="0,16,0,0" CornerRadius="12" Background="#FF0B1220" Padding="14" BorderBrush="#FF1F2937" BorderThickness="1">
                    <StackPanel>
                        <TextBlock Text="Time remaining until restart" Opacity="0.8" FontSize="12"/>
                        <TextBlock Name="TxtCountdown" Text="00:00:00" FontSize="34" FontWeight="Bold" Margin="0,6,0,0"/>
                        <TextBlock Name="TxtNoHide" Text="" Opacity="0.75" FontSize="12" Margin="0,6,0,0"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </Border>

        <!-- Buttons -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <TextBlock Name="TxtFooter" Grid.Column="0" VerticalAlignment="Center" Opacity="0.7" FontSize="12"
                       Text="Please save your work before restarting."/>

            <Button Name="BtnMinimize" Grid.Column="1" Margin="8,0,0,0" Padding="14,8"
                    Background="#FF111827" BorderBrush="#FF374151" Foreground="White"
                    BorderThickness="1" Cursor="Hand">
                $RestartLaterText
            </Button>

            <Button Name="BtnDefer" Grid.Column="2" Margin="8,0,0,0" Padding="14,8"
                    Background="#FF111827" BorderBrush="#FF374151" Foreground="White"
                    BorderThickness="1" Cursor="Hand">
                $DeferText
            </Button>

            <Button Name="BtnRestart" Grid.Column="3" Margin="8,0,0,0" Padding="14,8"
                    Background="#FF2563EB" BorderBrush="#FF2563EB" Foreground="White"
                    BorderThickness="1" Cursor="Hand" FontWeight="SemiBold">
                $RestartNowText
            </Button>
        </Grid>
    </Grid>
</Window>
"@

        # Load XAML
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
        $win = [Windows.Markup.XamlReader]::Load($reader)

        # Grab controls
        $TxtCountdown   = $win.FindName("TxtCountdown")
        $TxtNoHide      = $win.FindName("TxtNoHide")
        $TxtFooter      = $win.FindName("TxtFooter")
        $CountdownPanel = $win.FindName("CountdownPanel")
        $BtnRestart     = $win.FindName("BtnRestart")
        $BtnMinimize    = $win.FindName("BtnMinimize")
        $BtnDefer       = $win.FindName("BtnDefer")

        # Apply options
        $win.Topmost = $TopMost

        # Disable close (X): we can't truly remove it with simple WindowStyle,
        # but we can intercept Closing and cancel if user tries to close it.
        $script:allowClose = $false
        $win.Add_Closing({
            if (-not $script:allowClose) {
                $_.Cancel = $true
                # If they try to close it, just bring it back.
                $win.WindowState = "Normal"
                $win.Activate()
                $win.Topmost = $TopMost
            }
        })

        # Handle no-countdown mode
        if ($NoCountdown) {
            $CountdownPanel.Visibility = "Collapsed"
            $TxtFooter.Text = "Restart is required. This message will keep returning until you restart."
        }

        # Defer button state
        if (-not $AllowDefer) {
            $BtnDefer.Visibility = "Collapsed"
        } else {
            if ($remainingDefers -le 0) {
                $BtnDefer.IsEnabled = $false
                $BtnDefer.Content = "No deferrals remaining"
            } else {
                $BtnDefer.Content = "$DeferText ($remainingDefers remaining)"
            }
        }

        # -----------------------------
        # Timers
        # -----------------------------
        $start = Get-Date
        $deadline = $start.AddSeconds($CountdownSeconds)

        $dispatcherTimer = New-Object Windows.Threading.DispatcherTimer
        $dispatcherTimer.Interval = [TimeSpan]::FromSeconds(1)

        $persistTimer = New-Object Windows.Threading.DispatcherTimer
        $persistTimer.Interval = [TimeSpan]::FromSeconds([Math]::Max(15, $PersistIntervalSeconds))

        $doRestart = {
            Write-Log "Restart triggered."
            try { Clear-DeferState } catch {}
            $script:allowClose = $true
            $dispatcherTimer.Stop()
            $persistTimer.Stop()
            $win.Close()

            # Force reboot
            Restart-Computer -Force
        }

        $updateCountdown = {
            if ($NoCountdown) { return }

            $now = Get-Date
            $remaining = $deadline - $now
            if ($remaining.TotalSeconds -le 0) {
                # Countdown completed
                & $doRestart
                return
            }

            # Format HH:MM:SS (hours can exceed 24)
            $hours = [int][Math]::Floor($remaining.TotalHours)
            $TxtCountdown.Text = "{0}:{1:d2}:{2:d2}" -f $hours, $remaining.Minutes, $remaining.Seconds

            # Enforce "no hide" window near end
            if ($remaining.TotalSeconds -le $NoHideSeconds) {
                $BtnMinimize.IsEnabled = $false
                if ($AllowDefer) { $BtnDefer.IsEnabled = $false }
                $TxtNoHide.Text = "Restart can no longer be delayed."

                if ($win.WindowState -eq "Minimized") {
                    $win.WindowState = "Normal"
                }
                $win.Topmost = $TopMost
                $win.Activate()
            } else {
                $TxtNoHide.Text = ""
            }
        }

        # Countdown tick
        $dispatcherTimer.Add_Tick({ & $updateCountdown })

        # Persistence tick (for NoCountdown mode or if you want it)
        $persistTimer.Add_Tick({
            if ($win.WindowState -eq "Minimized") {
                $win.WindowState = "Normal"
            }
            $win.Topmost = $TopMost
            $win.Activate()
        })

        # -----------------------------
        # Button handlers
        # -----------------------------
        $BtnRestart.Add_Click({
            Write-Log "User clicked Restart now."
            & $doRestart
        })

        $BtnMinimize.Add_Click({
            Write-Log "User clicked Minimize."
            $win.WindowState = "Minimized"
        })

        $BtnDefer.Add_Click({
            if (-not $AllowDefer) { return }

            # Re-check remaining on click (defensive)
            $state = Get-DeferState
            $rem = [int]$state.Remaining
            if ($rem -le 0) { return }

            $newRemaining = $rem - 1
            Set-DeferState -Remaining $newRemaining
            Write-Log "User deferred reboot. Remaining defers: $newRemaining"

            # Close UI and let your deployment re-run later (or schedule another prompt externally)
            $script:allowClose = $true
            $dispatcherTimer.Stop()
            $persistTimer.Stop()
            $win.Close()

            return
        })

        # Start timers and show
        if (-not $NoCountdown) { & $updateCountdown; $dispatcherTimer.Start() }
        if ($NoCountdown) { $persistTimer.Start() }

        $null = $win.ShowDialog()

        # If we got here without restarting, return a result to caller
        # (In a real deployment, you might use this return to decide next actions.)
        Write-Log "Prompt window closed."
        return [pscustomobject]@{
            Result               = "Closed"
            CountdownSeconds     = $CountdownSeconds
            NoCountdown          = [bool]$NoCountdown
            AllowDefer           = $AllowDefer
            RemainingDefersAfter = (Get-DeferState).Remaining
            RegPath              = $RegPath
            LogPath              = $LogPath
        }
    }
    finally {
        try { if ($mutex) { $mutex.ReleaseMutex() | Out-Null; $mutex.Dispose() } } catch {}
    }
}

# -----------------------------
# Example usage
# -----------------------------
# Countdown prompt (1 hour) with last 60 seconds "no hide"
# Show-RebootCountdownPrompt -CountdownSeconds 3600 -NoHideSeconds 60 -AllowDefer $true -DeferTimes 2

# No-countdown persistent prompt every 5 minutes
# Show-RebootCountdownPrompt -NoCountdown -PersistIntervalSeconds 300 -AllowDefer $false
