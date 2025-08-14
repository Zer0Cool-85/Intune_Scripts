# ==============================
# Load WPF assemblies
# ==============================
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationcore')
[void][System.Reflection.Assembly]::LoadWithPartialName('windowsbase')

# ==============================
# Define XAML (Modern W11 style, rounded corners, shadow)
# ==============================
$inputXML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Information 3.0" Height="600" Width="400"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" 
        AllowsTransparency="True"
        Background="#DD2D2D30"
        ResizeMode="NoResize">
    <Border CornerRadius="15" Background="#FF1E1E1E" BorderThickness="1" BorderBrush="#55FFFFFF" Padding="10" SnapsToDevicePixels="True">
        <Grid>
            <!-- Columns: Labels Left, Values Right -->
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="160"/>
                <ColumnDefinition Width="220"/>
            </Grid.ColumnDefinitions>

            <!-- Rows for fields -->
            <Grid.RowDefinitions>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="30"/>
                <RowDefinition Height="60"/>
            </Grid.RowDefinitions>

            <!-- Labels -->
            <Label Content="Computer Name:" Grid.Row="0" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="OS:" Grid.Row="1" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="OS Architecture:" Grid.Row="2" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="OS Version:" Grid.Row="3" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="OS Build:" Grid.Row="4" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="Last Reboot:" Grid.Row="5" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="System Uptime:" Grid.Row="6" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="Logged-in User:" Grid.Row="7" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="Make:" Grid.Row="8" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="Model:" Grid.Row="9" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="Serial #:" Grid.Row="10" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="Memory:" Grid.Row="11" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="Free Space:" Grid.Row="12" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="IP Address:" Grid.Row="13" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="LightGray"/>
            <Label Content="Network Adapter(s):" Grid.Row="14" Grid.Column="0" HorizontalAlignment="Right" VerticalAlignment="Top" Foreground="LightGray"/>

            <!-- TextBoxes -->
            <TextBox x:Name="WPFPCName" Grid.Row="0" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFOSName" Grid.Row="1" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFOSArch" Grid.Row="2" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFOSVersion" Grid.Row="3" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFOSBuild" Grid.Row="4" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFLastReboot" Grid.Row="5" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFSystemUptime" Grid.Row="6" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFLoggedInUser" Grid.Row="7" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFMake" Grid.Row="8" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFModelName" Grid.Row="9" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFSerial" Grid.Row="10" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFMemory" Grid.Row="11" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFFreeSpace" Grid.Row="12" Grid.Column="1" IsReadOnly="True"/>
            <TextBox x:Name="WPFIPAddress" Grid.Row="13" Grid.Column="1" IsReadOnly="True"/>

            <!-- Network DataGrid -->
            <DataGrid x:Name="WPFMACAddress" Grid.Row="14" Grid.ColumnSpan="2" Height="80" IsReadOnly="True"/>

            <!-- Buttons -->
            <StackPanel Grid.Row="15" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10,0,0" Spacing="10">
                <Button x:Name="WPFButton_IPConfig" Content="IP Config" Width="80"/>
                <Button x:Name="WPFButton_PrinterConfig" Content="Printer Cfg" Width="80"/>
                <Button x:Name="WPFButton_Copy" Content="Copy" Width="80"/>
                <Button x:Name="WPFButton_Refresh" Content="Refresh" Width="80"/>
                <Button x:Name="WPFButton_Exit" Content="Exit" Width="80"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

# ==============================
# Load XAML
# ==============================
$reader = New-Object System.Xml.XmlNodeReader ([xml]$inputXML)
try { $Form = [Windows.Markup.XamlReader]::Load($reader) } 
catch { Write-Host "Unable to load XAML."; exit }

# Bind named controls
([xml]$inputXML).SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name $_.Name -Value $Form.FindName($_.Name)
}

# ==============================
# Functions
# ==============================
Function Copy-ToClipboard {
    $ClipBoard = ""
    $fields = @("WPFPCName","WPFOSName","WPFOSArch","WPFOSVersion","WPFOSBuild","WPFLastReboot",
                "WPFSystemUptime","WPFLoggedInUser","WPFMake","WPFModelName","WPFSerial",
                "WPFMemory","WPFFreeSpace","WPFIPAddress")
    foreach ($f in $fields) {
        $val = Get-Variable -Name $f -ErrorAction SilentlyContinue
        if ($val) { $ClipBoard += "$f:`t$($val.Value.Text)`r`n" }
    }
    if ($WPFMACAddress) {
        ForEach($Nic in $WPFMACAddress.ItemsSource){
            $ClipBoard += "Device:`t$($Nic.Name)`r`nMAC:`t$($Nic.MacAddress)`r`n"
        }
    }
    Set-Clipboard -Value $ClipBoard
}

Function Get-PCInfo {
    $cs = Get-CimInstance CIM_ComputerSystem
    $bios = Get-CimInstance CIM_BIOSElement
    $os = Get-CimInstance CIM_OperatingSystem
    $osInfo = Get-ItemProperty  -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    
    $WPFPCName.Text = $cs.Name
    $WPFOSName.Text = $osInfo.ProductName
    $WPFOSArch.Text = $os.OSArchitecture
    $WPFOSVersion.Text = if ($osInfo.DisplayVersion) { $osInfo.DisplayVersion } else { $osInfo.ReleaseID }
    $WPFOSBuild.Text = "$($osInfo.CurrentBuildNumber).$($osInfo.UBR)"
    $WPFLastReboot.Text = $os.LastBootUpTime
    $WPFSystemUptime.Text = (New-TimeSpan -Start $os.LastBootUpTime).ToString("d\.hh\:mm\:ss")
    $WPFLoggedInUser.Text = $env:USERNAME
    $WPFMake.Text = $cs.Manufacturer
    $WPFModelName.Text = $cs.Model
    $WPFSerial.Text = $bios.SerialNumber
    $WPFMemory.Text = "{0:N2} GB" -f ($cs.TotalPhysicalMemory / 1GB)
    $WPFFreeSpace.Text = "{0:N2} GB" -f ((Get-PSDrive C).Free / 1GB)
    $WPFIPAddress.Text = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }).IPAddress -join ", "
    $WPFMACAddress.ItemsSource = @(Get-NetAdapter | Select-Object Name, MacAddress)
}

# ==============================
# Button Actions
# ==============================
$WPFButton_IPConfig.Add_Click({ ipconfig /all 2>&1 | Out-GridView -Title "IP Config /All" })
$WPFButton_PrinterConfig.Add_Click({ Get-CimInstance Cim_Printer | Select Name,Default,Location,Local,PortName,DriverName | Out-GridView -Title "Printer Configuration" })
$WPFButton_Copy.Add_Click({ Copy-ToClipboard })
$WPFButton_Refresh.Add_Click({ Get-PCInfo })
$WPFButton_Exit.Add_Click({ $Form.Close() })

# ==============================
# Populate data on load
# ==============================
Get-PCInfo

# ==============================
# Show Window
# ==============================
$Form.ShowDialog() | Out-Null
