# ================================
# System Information
# ================================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------------- XAML (parser-safe) ----------------
$inputXML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="System Information"
    WindowStartupLocation="CenterScreen"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    Width="475"
    Height="600"
    ResizeMode="NoResize"
    Icon="C:\temp\info.ico">

  <Window.Resources>
        <!-- Rounded Button -->
        <Style TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="#5BA63C"/> 
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Margin" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="20"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                            <Border.Effect>
                                <DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.4"/>
                            </Border.Effect>
                        </Border>
                        <ControlTemplate.Triggers>
                            <!-- Hover -->
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#89DF4C"/>
                            </Trigger>
                            <!-- Pressed -->
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#776F67"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

  <Border
      CornerRadius="14"
      Background="#EE1E1E1E"
      BorderBrush="#40FFFFFF"
      BorderThickness="0">
    <Border.Effect>
      <DropShadowEffect
          Color="#000000"
          Direction="270"
          ShadowDepth="0"
          BlurRadius="20"
          Opacity="0.4" />
    </Border.Effect>
    
    <DockPanel LastChildFill="True">

      <!-- Header -->
      <Grid
          x:Name="HeaderBar"
          DockPanel.Dock="Top"
          Height="48"
          Background="#2D2D2D"
          Margin="5,5,5,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*" />
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>

        <Image
            Grid.Column="0"
            Source="c:\temp\info.png"
            Width="26"
            Height="26"
            HorizontalAlignment="Left"
            Margin="15,0,0,0" />

        <TextBlock
            Grid.Column="0"
            Text="System Information"
            Foreground="White"
            FontSize="20"
            FontWeight="Bold"
            VerticalAlignment="Center"
            Margin="45,0,0,0" />

        <Button
            x:Name="BtnMin"
            Grid.Column="1"
            Content="—"
            Width="42"
            Height="28"
            Margin="0,10,4,10"
            Background="Transparent"
            Foreground="#DDFFFFFF"
            BorderThickness="0"
            Cursor="Hand" />
        <Button
            x:Name="BtnClose"
            Grid.Column="2"
            Content="✕"
            Width="42"
            Height="28"
            Margin="0,10,10,10"
            Background="Transparent"
            Foreground="#DDFFFFFF"
            BorderThickness="0"
            Cursor="Hand" />
      </Grid>

      <!-- Content -->
      <Grid Margin="20,10,20,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="125" />
          <ColumnDefinition Width="*" />
        </Grid.ColumnDefinitions>

        <!-- Row defs -->
        <Grid.RowDefinitions>
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="32" />
          <RowDefinition Height="105" />
        </Grid.RowDefinitions>

        <!-- Labels -->
        <TextBlock Grid.Row="0"  Grid.Column="0" Text="Computer Name:"    Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="1"  Grid.Column="0" Text="Logged-in User:"   Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="2"  Grid.Column="0" Text="Operating System:" Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="3"  Grid.Column="0" Text="OS Architecture:"  Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="4"  Grid.Column="0" Text="OS Version:"       Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="5"  Grid.Column="0" Text="OS Build:"         Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="7"  Grid.Column="0" Text="Boot Time:"        Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="8"  Grid.Column="0" Text="Uptime:"           Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="9"  Grid.Column="0" Text="Make:"             Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="10" Grid.Column="0" Text="Model:"            Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="11" Grid.Column="0" Text="Serial:"         Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="12" Grid.Column="0" Text="Physical Memory:"  Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="13" Grid.Column="0" Text="C: Free Space:"    Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="14" Grid.Column="0" Text="IP Address:"       Foreground="#DDFFFFFF" VerticalAlignment="Center" />

        <!-- TextBoxes with values -->
        <TextBox x:Name="PCName"       Grid.Row="0"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="LoggedInUser" Grid.Row="1"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="OSName"       Grid.Row="2"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="OSArch"       Grid.Row="3"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="OSVersion"    Grid.Row="4"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="OSBuild"      Grid.Row="5"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="BootTime"     Grid.Row="7"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="Uptime"       Grid.Row="8"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="Make"         Grid.Row="9"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="ModelName"    Grid.Row="10" Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="Serial"       Grid.Row="11" Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="Memory"       Grid.Row="12" Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="FreeSpace"    Grid.Row="13" Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="IPAddress"    Grid.Row="14" Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <Button x:Name="Button_Copy" Content="Copy" HorizontalAlignment="Left" Margin="0,7,0,0" Grid.Row="16" Grid.Column="1" VerticalAlignment="Top" Width="75" Height="40" FontWeight="Bold" ToolTip="Copy all system information to clipboard" />
        <Button x:Name="Button_Refresh" Content="Refresh" HorizontalAlignment="Left" Margin="80,7,0,0" Grid.Row="16" Grid.Column="1" VerticalAlignment="Top" Width="75" Height="40" FontWeight="Bold" ToolTip="Refresh system information"  />
        <Button x:Name="Button_Exit" Content="Exit" HorizontalAlignment="Left" Margin="160,7,0,0" Grid.Row="16" Grid.Column="1" VerticalAlignment="Top" Width="75" Height="40" FontWeight="Bold" ToolTip="Close window" />

      </Grid>


    </DockPanel>
  </Border>
</Window>
"@
$inputXML = $inputXML -replace 'mc:Ignorable="d"','' -replace "x:N",'N'  -replace '^<Win.*', '<Window'
# --------------- Load XAML safely ---------------
[xml]$XAML = $inputXML
$reader = New-Object System.Xml.XmlNodeReader $XAML
try {
    $Form = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Host "Unable to load XAML. Check for paste/quote issues." -ForegroundColor Yellow
    throw
}

# Drag by header only (avoids dragging when clicking inside inputs)
$WPFHeaderBar = $Form.FindName('HeaderBar')
if ($WPFHeaderBar) { $WPFHeaderBar.Add_MouseLeftButtonDown({ $Form.DragMove() }) }

$WPFBtnClose = $Form.FindName('BtnClose')
$WPFBtnMin   = $Form.FindName('BtnMin')
if ($WPFBtnClose) { $WPFBtnClose.Add_Click({ $Form.Close() }) }
if ($WPFBtnMin)   { $WPFBtnMin.Add_Click({ $Form.WindowState = 'Minimized' }) }

# Map all named controls as $WPF<name>
$XAML.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name "WPF$($_.Name)" -Value $Form.FindName($_.Name)
}

# ---------------- Functions ----------------
Function Copy-ToClipboard {
    $ClipBoard = ""
    if ($WPFPCName)       { $ClipBoard += "PC Name:`t$($WPFPCName.Text)`r`n" }
    if ($WPFLoggedInUser) { $ClipBoard += "Logged-in User:`t$($WPFLoggedInUser.Text)`r`n" }
    if ($WPFOSName)       { $ClipBoard += "OS:`t$($WPFOSName.Text)`r`n" }
    if ($WPFOSArch)       { $ClipBoard += "OS Arch:`t$($WPFOSArch.Text)`r`n" }
    if ($WPFOSVersion)    { $ClipBoard += "OS Version:`t$($WPFOSVersion.Text)`r`n" }
    if ($WPFOSBuild)      { $ClipBoard += "OS Build:`t$($WPFOSBuild.Text)`r`n" }
    if ($WPFBootTime)     { $ClipBoard += "Boot Time:`t$($WPFBootTime.Text)`r`n" }
    if ($WPFUptime)       { $ClipBoard += "Uptime:`t$($WPFUptime.Text)`r`n" }
    if ($WPFMake)         { $ClipBoard += "Make:`t$($WPFMake.Text)`r`n" }
    if ($WPFModelName)    { $ClipBoard += "Model:`t$($WPFModelName.Text)`r`n" }
    if ($WPFSerial)       { $ClipBoard += "Serial:`t$($WPFSerial.Text)`r`n" }
    if ($WPFMemory)       { $ClipBoard += "Memory:`t$($WPFMemory.Text)`r`n" }
    if ($WPFFreeSpace)    { $ClipBoard += "Free Space:`t$($WPFFreeSpace.Text)`r`n" }
    if ($WPFIPAddress)    { $ClipBoard += "IP Address:`t$($WPFIPAddress.Text)`r`n" }
    Set-Clipboard -Value $ClipBoard
}

Function Get-PCInfo {
    $cs     = Get-CimInstance CIM_ComputerSystem
    $bios   = Get-CimInstance CIM_BIOSElement
    $os     = Get-CimInstance CIM_OperatingSystem
    $osInfo = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $osName = (Get-WmiObject Win32_OperatingSystem).Caption
    
    $WPFPCName.Text       = $cs.Name
    $WPFLoggedInUser.Text = "{0}\{1}" -f $env:USERDOMAIN,$env:USERNAME
    $WPFOSName.Text       = $osName
    $WPFOSArch.Text       = $os.OSArchitecture
    $WPFOSVersion.Text    = if ($osInfo.DisplayVersion) { $osInfo.DisplayVersion } else { $osInfo.ReleaseID }
    $WPFOSBuild.Text      = "$($osInfo.CurrentBuildNumber).$($osInfo.UBR)"
    $WPFBootTime.Text   = $os.LastBootUpTime

    $uptime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptimeSpan = (Get-Date) - $uptime

    $uptimeParts = @()

    if ($uptimeSpan.Days -gt 0) {
        $uptimeParts += "{0} day{1}" -f $uptimeSpan.Days, ($(if($uptimeSpan.Days -ne 1){"s"}))
    }
    if ($uptimeSpan.Hours -gt 0) {
        $uptimeParts += "{0} hour{1}" -f $uptimeSpan.Hours, ($(if($uptimeSpan.Hours -ne 1){"s"}))
    }
    if ($uptimeSpan.Minutes -gt 0) {
        $uptimeParts += "{0} min{1}" -f $uptimeSpan.Minutes, ($(if($uptimeSpan.Minutes -ne 1){"s"}))
    }

    # If all are 0, show seconds
    if ($uptimeParts.Count -eq 0) {
        $uptimeParts += "{0} sec{1}" -f $uptimeSpan.Seconds, ($(if($uptimeSpan.Seconds -ne 1){"s"}))
    }

    $WPFUptime.Text = $uptimeParts -join ", "

    $WPFMake.Text      = $cs.Manufacturer
    $WPFModelName.Text = $cs.Model
    $WPFSerial.Text    = $bios.SerialNumber
    $WPFMemory.Text    = "{0:N2} GB" -f ($cs.TotalPhysicalMemory / 1GB)

    try {
        $WPFFreeSpace.Text = "{0:N2} GB" -f ((Get-PSDrive -Name C).Free / 1GB)
    } catch { $WPFFreeSpace.Text = "N/A" }

    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
               Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress } |
               Select-Object -ExpandProperty IPAddress
        $WPFIPAddress.Text = ($ips -join ", ")
    } catch { $WPFIPAddress.Text = "N/A" }
}

# Buttons
$WPFButton_Copy.Add_Click({ Copy-ToClipboard })
$WPFButton_Refresh.Add_Click({ Get-PCInfo })
$WPFButton_Exit.Add_Click({ $Form.Close() })

# Optional icon
$Form.Icon = 'C:\temp\info.ico'

<# Fade-in
$Form.Opacity = 0
$Form.Loaded.Add({
    $fade = New-Object Windows.Media.Animation.DoubleAnimation(0,1,[TimeSpan]::FromMilliseconds(350))
    $Form.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
})#>

# Load data + show
Get-PCInfo
$Form.ShowDialog() | Out-Null
