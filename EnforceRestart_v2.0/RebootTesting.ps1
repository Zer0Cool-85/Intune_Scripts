param(
    [switch]$UiMode,                             # When present, run the WPF UI (user context)
    [int]$CountdownSeconds = 3600,
    [int]$NoHideSeconds = 30,
    [int]$DeferTimes = 2,
    [int]$DeferMinutes = 60,
    [string]$CompanyKey = "HKLM:\SOFTWARE\Company\RebootPrompt",
    [string]$ServiceUIPath = "C:\ProgramData\Company\Tools\ServiceUI.exe",
    [string]$TargetProcess = "explorer.exe"
)

# -----------------------------
# Shared helpers
# -----------------------------
function Write-Log([string]$Msg) { Write-Host ("[{0}] {1}" -f (Get-Date), $Msg) }

function Ensure-StateKey {
    if (-not (Test-Path $CompanyKey)) { New-Item -Path $CompanyKey -Force | Out-Null }
}

function Get-State {
    Ensure-StateKey
    $p = Get-ItemProperty -Path $CompanyKey -ErrorAction SilentlyContinue
    [pscustomobject]@{
        DeadlineUtc     = $p.DeadlineUtc
        RemainingDefers = [int]($p.RemainingDefers -as [int])
        LastAction      = $p.LastAction
        LastActionUtc   = $p.LastActionUtc
    }
}

function Set-StateValue([string]$Name, $Value, [Microsoft.Win32.RegistryValueKind]$Kind = [Microsoft.Win32.RegistryValueKind]::String) {
    Ensure-StateKey
    $rk = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey(($CompanyKey -replace '^HKLM:\\',''), $true)
    $rk.SetValue($Name, $Value, $Kind)
    $rk.Close()
}

function Initialize-StateIfNeeded {
    Ensure-StateKey

    $state = Get-State
    if (-not $state.DeadlineUtc) {
        $deadline = (Get-Date).ToUniversalTime().AddSeconds($CountdownSeconds).ToString("o")
        Set-StateValue -Name "DeadlineUtc" -Value $deadline
    }
    if (-not ($state.RemainingDefers -ge 0)) {
        Set-StateValue -Name "RemainingDefers" -Value $DeferTimes -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)
    }

    # Ensure LastAction is empty on first init
    if (-not (Get-State).LastAction) {
        Set-StateValue -Name "LastAction" -Value ""
        Set-StateValue -Name "LastActionUtc" -Value ""
    }
}

function Grant-UserWriteToStateKey {
    # Allow interactive users to write only to this key (needed for UiMode to set LastAction)
    # If your org already handles permissions via baseline/GPO, you can remove this.
    try {
        $path = "HKLM:\SOFTWARE\Company"
        if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
        if (-not (Test-Path $CompanyKey)) { New-Item $CompanyKey -Force | Out-Null }

        $acl = Get-Acl $CompanyKey
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
            "Users",
            "SetValue,CreateSubKey,ReadKey",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $CompanyKey -AclObject $acl
    } catch {
        Write-Log "WARN: Could not set registry ACL. UI may fail to record actions. $_"
    }
}

function Get-DeadlineLocal {
    $state = Get-State
    if (-not $state.DeadlineUtc) { return $null }
    return [DateTime]::Parse($state.DeadlineUtc).ToLocalTime()
}

# -----------------------------
# USER UI MODE (launched via ServiceUI)
# -----------------------------
function Show-RebootCountdownPromptUi {
    param(
        [int]$NoHideSeconds,
        [string]$CompanyKey
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $state = Get-ItemProperty -Path $CompanyKey -ErrorAction SilentlyContinue
    $deadlineUtc = $state.DeadlineUtc
    $remainingDefers = [int]($state.RemainingDefers -as [int])

    $deadlineLocal = [DateTime]::Parse($deadlineUtc).ToLocalTime()

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Restart Required" Width="520" Height="320"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#FF0F172A" Foreground="White">
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border CornerRadius="14" Background="#FF111827" Padding="14" BorderBrush="#FF1F2937" BorderThickness="1">
      <StackPanel Orientation="Horizontal">
        <Border Width="36" Height="36" CornerRadius="10" Background="#FF1D4ED8" Margin="0,0,12,0">
          <TextBlock Text="!" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel>
          <TextBlock Text="Restart Required" FontSize="18" FontWeight="SemiBold"/>
          <TextBlock Text="Save your work — a restart is needed to finish updates." Opacity="0.75" FontSize="12" Margin="0,2,0,0"/>
        </StackPanel>
      </StackPanel>
    </Border>

    <Border Grid.Row="1" Margin="0,14,0,14" CornerRadius="14" Background="#FF111827" Padding="16" BorderBrush="#FF1F2937" BorderThickness="1">
      <StackPanel>
        <TextBlock TextWrapping="Wrap" FontSize="14" Opacity="0.95">
Your device will restart automatically when the timer expires.
        </TextBlock>

        <Border Margin="0,16,0,0" CornerRadius="12" Background="#FF0B1220" Padding="14" BorderBrush="#FF1F2937" BorderThickness="1">
          <StackPanel>
            <TextBlock Text="Time remaining until restart" Opacity="0.8" FontSize="12"/>
            <TextBlock Name="TxtCountdown" Text="00:00:00" FontSize="34" FontWeight="Bold" Margin="0,6,0,0"/>
            <TextBlock Name="TxtNoHide" Text="" Opacity="0.75" FontSize="12" Margin="0,6,0,0"/>
          </StackPanel>
        </Border>
      </StackPanel>
    </Border>

    <Grid Grid.Row="2">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>

      <TextBlock Name="TxtFooter" Grid.Column="0" VerticalAlignment="Center" Opacity="0.7" FontSize="12"
                 Text="Please save your work before restarting."/>

      <Button Name="BtnMin" Grid.Column="1" Margin="8,0,0,0" Padding="14,8"
              Background="#FF111827" BorderBrush="#FF374151" Foreground="White" BorderThickness="1">
        Minimize
      </Button>

      <Button Name="BtnDefer" Grid.Column="2" Margin="8,0,0,0" Padding="14,8"
              Background="#FF111827" BorderBrush="#FF374151" Foreground="White" BorderThickness="1">
        Defer
      </Button>

      <Button Name="BtnRestart" Grid.Column="3" Margin="8,0,0,0" Padding="14,8"
              Background="#FF2563EB" BorderBrush="#FF2563EB" Foreground="White" BorderThickness="1" FontWeight="SemiBold">
        Restart now
      </Button>
    </Grid>
  </Grid>
</Window>
"@

    $win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    $TxtCountdown = $win.FindName("TxtCountdown")
    $TxtNoHide = $win.FindName("TxtNoHide")
    $BtnMin = $win.FindName("BtnMin")
    $BtnDefer = $win.FindName("BtnDefer")
    $BtnRestart = $win.FindName("BtnRestart")

    if ($remainingDefers -le 0) {
        $BtnDefer.IsEnabled = $false
        $BtnDefer.Content = "No deferrals remaining"
    } else {
        $BtnDefer.Content = "Defer ($remainingDefers remaining)"
    }

    # Disable closing via X
    $allowClose = $false
    $win.Add_Closing({ if (-not $allowClose) { $_.Cancel = $true } })

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)

    $timer.Add_Tick({
        $now = Get-Date
        $remaining = $deadlineLocal - $now
        if ($remaining.TotalSeconds -le 0) {
            # Tell SYSTEM to reboot (action only), then close UI
            try {
                Set-ItemProperty -Path $CompanyKey -Name "LastAction" -Value "TimeoutRestart" -Force
                Set-ItemProperty -Path $CompanyKey -Name "LastActionUtc" -Value ((Get-Date).ToUniversalTime().ToString("o")) -Force
            } catch {}
            $allowClose = $true
            $timer.Stop()
            $win.Close()
            return
        }

        $hours = [int][Math]::Floor($remaining.TotalHours)
        $TxtCountdown.Text = "{0}:{1:d2}:{2:d2}" -f $hours, $remaining.Minutes, $remaining.Seconds

        if ($remaining.TotalSeconds -le $NoHideSeconds) {
            $BtnMin.IsEnabled = $false
            $BtnDefer.IsEnabled = $false
            $TxtNoHide.Text = "Restart can no longer be delayed."
            if ($win.WindowState -eq "Minimized") { $win.WindowState = "Normal" }
            $win.Topmost = $true
            $win.Activate()
        } else {
            $TxtNoHide.Text = ""
        }
    })

    $BtnRestart.Add_Click({
        try {
            Set-ItemProperty -Path $CompanyKey -Name "LastAction" -Value "RestartNow" -Force
            Set-ItemProperty -Path $CompanyKey -Name "LastActionUtc" -Value ((Get-Date).ToUniversalTime().ToString("o")) -Force
        } catch {}
        $allowClose = $true
        $timer.Stop()
        $win.Close()
    })

    $BtnDefer.Add_Click({
        try {
            Set-ItemProperty -Path $CompanyKey -Name "LastAction" -Value "Defer" -Force
            Set-ItemProperty -Path $CompanyKey -Name "LastActionUtc" -Value ((Get-Date).ToUniversalTime().ToString("o")) -Force
        } catch {}
        $allowClose = $true
        $timer.Stop()
        $win.Close()
    })

    $BtnMin.Add_Click({ $win.WindowState = "Minimized" })

    $timer.Start()
    $null = $win.ShowDialog()
}

# -----------------------------
# SYSTEM MODE CONTROLLER
# -----------------------------
if ($UiMode) {
    # UI Mode expects to run as user context (via ServiceUI)
    Show-RebootCountdownPromptUi -NoHideSeconds $NoHideSeconds -CompanyKey $CompanyKey
    exit 0
}

# SYSTEM controller
Write-Log "SYSTEM controller starting."
Initialize-StateIfNeeded
Grant-UserWriteToStateKey

$deadlineLocal = Get-DeadlineLocal
Write-Log ("Deadline (local): {0}" -f $deadlineLocal)

# Launch UI via ServiceUI
if (-not (Test-Path $ServiceUIPath)) {
    throw "ServiceUI.exe not found at: $ServiceUIPath"
}

$scriptPath = $PSCommandPath
$uiArgs = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`" -UiMode -NoHideSeconds $NoHideSeconds -CompanyKey `"$CompanyKey`""

Write-Log "Launching UI with ServiceUI against $TargetProcess ..."
Start-Process -FilePath $ServiceUIPath -ArgumentList "$TargetProcess powershell.exe $uiArgs" -WindowStyle Hidden | Out-Null

# Controller loop: enforce deadline + react to user actions
while ($true) {
    $state = Get-State
    $deadlineUtc = [DateTime]::Parse($state.DeadlineUtc)
    $nowUtc = (Get-Date).ToUniversalTime()

    # If time is up, reboot
    if ($nowUtc -ge $deadlineUtc) {
        Write-Log "Deadline reached. Forcing reboot."
        Restart-Computer -Force
        break
    }

    switch ($state.LastAction) {
        "RestartNow" {
            Write-Log "User requested restart now. Rebooting."
            Restart-Computer -Force
            break
        }
        "TimeoutRestart" {
            Write-Log "UI timed out. Rebooting."
            Restart-Computer -Force
            break
        }
        "Defer" {
            $rem = [int]$state.RemainingDefers
            if ($rem -gt 0) {
                $newRem = $rem - 1
                Set-StateValue -Name "RemainingDefers" -Value $newRem -Kind ([Microsoft.Win32.RegistryValueKind]::DWord)

                # Push deadline out by DeferMinutes from now
                $newDeadline = (Get-Date).ToUniversalTime().AddMinutes($DeferMinutes).ToString("o")
                Set-StateValue -Name "DeadlineUtc" -Value $newDeadline

                # Clear last action so next run is clean
                Set-StateValue -Name "LastAction" -Value ""
                Set-StateValue -Name "LastActionUtc" -Value ""

                Write-Log "Deferred. RemainingDefers=$newRem NewDeadlineUtc=$newDeadline"
                exit 0
            } else {
                Write-Log "Defer clicked but no deferrals left. Ignoring."
                Set-StateValue -Name "LastAction" -Value ""
            }
        }
    }

    Start-Sleep -Seconds 2
}
