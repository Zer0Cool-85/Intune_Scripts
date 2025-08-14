# ================================
# PC Info - WPF (Windows 11 style)
# Fixed-size; draggable; no scrollbars
# ================================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------------- XAML (parser-safe) ----------------
$inputXML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="PC Information"
    WindowStartupLocation="CenterScreen"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    Width="720"
    Height="620"
    ResizeMode="NoResize"> <!-- Change to CanResize/CanResizeWithGrip to allow resizing -->

  <Border
      CornerRadius="14"
      Background="#EE1E1E1E"
      BorderBrush="#40FFFFFF"
      BorderThickness="1">
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
          Margin="0,0,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*" />
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>

        <TextBlock
            Grid.Column="0"
            Text="PC Information"
            Foreground="White"
            FontSize="18"
            FontWeight="Bold"
            VerticalAlignment="Center"
            Margin="12,0,0,0" />

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
      <Grid Margin="18">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="220" />
          <ColumnDefinition Width="*" />
        </Grid.ColumnDefinitions>

        <!-- Row defs FIRST to avoid parser issues -->
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
          <RowDefinition Height="32" />
          <RowDefinition Height="12" />
          <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <!-- Labels -->
        <TextBlock Grid.Row="0"  Grid.Column="0" Text="Computer Name:"    Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="1"  Grid.Column="0" Text="Logged-in User:"   Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="2"  Grid.Column="0" Text="Operating System:" Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="3"  Grid.Column="0" Text="OS Architecture:"  Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="4"  Grid.Column="0" Text="OS Version:"       Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="5"  Grid.Column="0" Text="OS Build:"         Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="6"  Grid.Column="0" Text="Last Reboot:"      Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="7"  Grid.Column="0" Text="Uptime:"           Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="8"  Grid.Column="0" Text="Make:"             Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="9"  Grid.Column="0" Text="Model:"            Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="10" Grid.Column="0" Text="Serial #:"         Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="11" Grid.Column="0" Text="Physical Memory:"  Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="12" Grid.Column="0" Text="C: Free Space:"    Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="13" Grid.Column="0" Text="IP Address:"       Foreground="#DDFFFFFF" VerticalAlignment="Center" />
        <TextBlock Grid.Row="14" Grid.Column="0" Text="Network Adapter(s):" Foreground="#DDFFFFFF" VerticalAlignment="Center" />

        <!-- Values -->
        <TextBox x:Name="PCName"       Grid.Row="0"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="LoggedInUser" Grid.Row="1"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="OSName"       Grid.Row="2"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="OSArch"       Grid.Row="3"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="OSVersion"    Grid.Row="4"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="OSBuild"      Grid.Row="5"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="LastReboot"   Grid.Row="6"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="Uptime"       Grid.Row="7"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="Make"         Grid.Row="8"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="ModelName"    Grid.Row="9"  Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="Serial"       Grid.Row="10" Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="Memory"       Grid.Row="11" Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="FreeSpace"    Grid.Row="12" Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />
        <TextBox x:Name="IPAddress"    Grid.Row="13" Grid.Column="1" IsReadOnly="True" Margin="0,2"  Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6" />

        <!-- DataGrid -->
        <DataGrid
            x:Name="MACAddress"
            Grid.Row="15"
            Grid.ColumnSpan="2"
            Height="180"
            AutoGenerateColumns="True"
            CanUserAddRows="False"
            HeadersVisibility="Column"
            Margin="0,8,0,0"
            Background="#292929"
            Foreground="White"
            GridLinesVisibility="Horizontal"
            RowBackground="#2E2E2E"
            AlternatingRowBackground="#353535"
            BorderBrush="#444"
            BorderThickness="1" />
      </Grid>

      <!-- Footer Buttons -->
      <Grid
          DockPanel.Dock="Bottom"
          Height="64"
          Margin="12,0,12,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*" />
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>

        <StackPanel
            Grid.Column="1"
            Orientation="Horizontal"
            HorizontalAlignment="Right"
            VerticalAlignment="Center">
          <Button x:Name="Button_IPConfig"      Content="IP Config"   Margin="0,0,8,0" Padding="10,6" />
          <Button x:Name="Button_PrinterConfig" Content="Printer Cfg" Margin="0,0,8,0" Padding="10,6" />
          <Button x:Name="Button_Copy"          Content="Copy"        Margin="0,0,8,0" Padding="10,6" />
          <Button x:Name="Button_Refresh"       Content="Refresh"     Margin="0,0,8,0" Padding="10,6" />
          <Button x:Name="Button_Exit"          Content="Exit"                      Padding="10,6" />
        </StackPanel>
      </Grid>

    </DockPanel>
  </Border>
</Window>
"@

# --------------- Load XAML safely ---------------
[xml]$XAML = $inputXML
$reader = New-Object System.Xml.XmlNodeReader $XAML
try {
    $Form = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Host "Unable to load XAML. Check for paste/quote issues." -ForegroundColor Yellow
    throw
}

# --------------- Wire up drag + buttons ---------------
# Drag by header only (avoids dragging when clicking inside inputs)
$WPFHeaderBar = $Form.FindName('HeaderBar')
if ($WPFHeaderBar) { $WPFHeaderBar.Add_MouseLeftButtonDown({ $Form.DragMove() }) }

$WPFBtnClose = $Form.FindName('BtnClose')
$WPFBtnMin   = $Form.FindName('BtnMin')
if ($WPFBtnClose) { $WPFBtnClose.Add_Click({ $Form.Close() }) }
if ($WPFBtnMin)   { $WPFBtnMin.Add_Click({ $Form.WindowState = 'Minimized' }) }

# Map all named controls as $WPF<name>
$XAML.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name ("WPF{0}" -f $_.Name) -Value $Form.FindName($_.Name)
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
    if ($WPFLastReboot)   { $ClipBoard += "Last Reboot:`t$($WPFLastReboot.Text)`r`n" }
    if ($WPFUptime)       { $ClipBoard += "Uptime:`t$($WPFUptime.Text)`r`n" }
    if ($WPFMake)         { $ClipBoard += "Make:`t$($WPFMake.Text)`r`n" }
    if ($WPFModelName)    { $ClipBoard += "Model:`t$($WPFModelName.Text)`r`n" }
    if ($WPFSerial)       { $ClipBoard += "Serial:`t$($WPFSerial.Text)`r`n" }
    if ($WPFMemory)       { $ClipBoard += "Memory:`t$($WPFMemory.Text)`r`n" }
    if ($WPFFreeSpace)    { $ClipBoard += "Free Space:`t$($WPFFreeSpace.Text)`r`n" }
    if ($WPFIPAddress)    { $ClipBoard += "IP Address:`t$($WPFIPAddress.Text)`r`n" }
    if ($WPFMACAddress -and $WPFMACAddress.ItemsSource) {
        foreach ($Nic in $WPFMACAddress.ItemsSource) {
            $ClipBoard += "Device:`t$($Nic.Name)`r`nMAC:`t$($Nic.MacAddress)`r`n"
        }
    }
    Set-Clipboard -Value $ClipBoard
}

Function Get-PCInfo {
    $cs     = Get-CimInstance CIM_ComputerSystem
    $bios   = Get-CimInstance CIM_BIOSElement
    $os     = Get-CimInstance CIM_OperatingSystem
    $osInfo = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

    $WPFPCName.Text       = $cs.Name
    $WPFLoggedInUser.Text = "{0}\{1}" -f $env:USERDOMAIN,$env:USERNAME
    $WPFOSName.Text       = $osInfo.ProductName
    $WPFOSArch.Text       = $os.OSArchitecture
    $WPFOSVersion.Text    = if ($osInfo.DisplayVersion) { $osInfo.DisplayVersion } else { $osInfo.ReleaseID }
    $WPFOSBuild.Text      = "$($osInfo.CurrentBuildNumber).$($osInfo.UBR)"
    $WPFLastReboot.Text   = $os.LastBootUpTime

    $uptime = (Get-Date) - $os.LastBootUpTime
    $WPFUptime.Text = "{0} days, {1:hh\:mm\:ss}" -f [Math]::Floor($uptime.TotalDays), $uptime

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

    try {
        $WPFMACAddress.ItemsSource = @( Get-NetAdapter | Select-Object Name, MacAddress )
    } catch { $WPFMACAddress.ItemsSource = @() }
}

# Buttons
$WPFButton_IPConfig.Add_Click({ ipconfig /all 2>&1 | Out-GridView -Title "IPConfig /All" })
$WPFButton_PrinterConfig.Add_Click({
    try {
        Get-CimInstance Cim_Printer |
            Select-Object Name, Default, Location, Local, PortName, DriverName |
            Out-GridView -Title "Printer Configuration"
    } catch {
        [System.Windows.MessageBox]::Show("Unable to query printers: $($_.Exception.Message)","Printer Cfg")
    }
})
$WPFButton_Copy.Add_Click({ Copy-ToClipboard })
$WPFButton_Refresh.Add_Click({ Get-PCInfo })
$WPFButton_Exit.Add_Click({ $Form.Close() })

# Optional icon
# $Form.Icon = 'C:\Program Files\PCInfo\PCInfo.ico'

# Fade-in
$Form.Opacity = 0
$Form.Loaded.Add({
    $fade = New-Object Windows.Media.Animation.DoubleAnimation(0,1,[TimeSpan]::FromMilliseconds(350))
    $Form.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
})

# Load data + show
Get-PCInfo
$Form.ShowDialog() | Out-Null
