# Load WPF assemblies
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationcore')
[void][System.Reflection.Assembly]::LoadWithPartialName('windowsbase')

# Define Windows 11-style XAML with rounded corners and shadow
$inputXML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Information"
        WindowStartupLocation="CenterScreen"
        Width="650" Height="650"
        ResizeMode="NoResize"
        WindowStyle="None"
        Background="Transparent">

    <Border CornerRadius="16" Background="#FF1E1E1E" BorderBrush="#66FFFFFF" BorderThickness="1">
        <Border.Effect>
            <DropShadowEffect Color="#000000" Direction="270" ShadowDepth="0" BlurRadius="20" Opacity="0.4"/>
        </Border.Effect>
        <Grid Margin="15">
            <Grid.RowDefinitions>
                <RowDefinition Height="60"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="70"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <DockPanel Grid.Row="0">
                <TextBlock Text="💻 PC Information" FontSize="22" FontWeight="Bold" Foreground="White" VerticalAlignment="Center"/>
            </DockPanel>

            <!-- Content -->
            <ScrollViewer Grid.Row="1">
            <StackPanel Margin="0,10,0,0">
                <TextBlock Text="Computer Name:" Foreground="LightGray"/>
                <TextBox Name="PCName" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="Operating System:" Foreground="LightGray"/>
                <TextBox Name="OSName" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="OS Architecture:" Foreground="LightGray"/>
                <TextBox Name="OSArch" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="OS Version:" Foreground="LightGray"/>
                <TextBox Name="OSVersion" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="OS Build:" Foreground="LightGray"/>
                <TextBox Name="OSBuild" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="Last Reboot:" Foreground="LightGray"/>
                <TextBox Name="LastReboot" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="Make:" Foreground="LightGray"/>
                <TextBox Name="Make" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="Model:" Foreground="LightGray"/>
                <TextBox Name="ModelName" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="Serial #:" Foreground="LightGray"/>
                <TextBox Name="Serial" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="Physical Memory:" Foreground="LightGray"/>
                <TextBox Name="Memory" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="C: Drive Free Space:" Foreground="LightGray"/>
                <TextBox Name="FreeSpace" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="IP Address:" Foreground="LightGray"/>
                <TextBox Name="IPAddress" IsReadOnly="True" Margin="0,0,0,10"/>

                <TextBlock Text="Network Adapter(s):" Foreground="LightGray"/>
                <DataGrid Name="MACAddress" Height="100" Margin="0,0,0,10" AutoGenerateColumns="True" CanUserAddRows="False"/>
            </StackPanel>
            </ScrollViewer>

            <!-- Footer Buttons -->
            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,10,0,0">
                <Button Name="Button_IPConfig" Content="IP Config" Width="80" Margin="0,0,10,0"/>
                <Button Name="Button_PrinterConfig" Content="Printer Cfg" Width="100" Margin="0,0,10,0"/>
                <Button Name="Button_Copy" Content="Copy" Width="80" Margin="0,0,10,0"/>
                <Button Name="Button_Refresh" Content="Refresh" Width="80" Margin="0,0,10,0"/>
                <Button Name="Button_Exit" Content="Exit" Width="80"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

# Load XAML
$reader = New-Object System.Xml.XmlNodeReader ([xml]$inputXML)
try {
    $Form = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Host "Unable to load Windows.Markup.XamlReader. Check syntax and .NET installation."
    exit
}

# Map controls
([xml]$inputXML).SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name "WPF$($_.Name)" -Value $Form.FindName($_.Name)
}

# Set icon
$Form.Icon = 'C:\Program Files\PCInfo\PCInfo.ico'

# -----------------------------
# Functions (same as before)
# -----------------------------
Function Copy-ToClipboard {
    $ClipBoard = ""
    If ($WPFPCName) { $ClipBoard += "PC Name:`t$($WPFPCName.Text)`r`n" }
    If ($WPFOSName) { $ClipBoard += "OS:`t$($WPFOSName.Text)`r`n" }
    If ($WPFOSArch) { $ClipBoard += "OS Arch:`t$($WPFOSArch.Text)`r`n" }
    If ($WPFOSVersion) { $ClipBoard += "OS Version:`t$($WPFOSVersion.Text)`r`n" }
    If ($WPFOSBuild) { $ClipBoard += "OS Build:`t$($WPFOSBuild.Text)`r`n" }
    If ($WPFLastReboot) { $ClipBoard += "Last Reboot:`t$($WPFLastReboot.Text)`r`n" }
    If ($WPFMake) { $ClipBoard += "Make:`t$($WPFMake.Text)`r`n" }
    If ($WPFModelName) { $ClipBoard += "Model:`t$($WPFModelName.Text)`r`n" }
    If ($WPFSerial) { $ClipBoard += "Serial:`t$($WPFSerial.Text)`r`n" }
    If ($WPFMemory) { $ClipBoard += "Memory:`t$($WPFMemory.Text)`r`n" }
    If ($WPFFreeSpace) { $ClipBoard += "Free Space:`t$($WPFFreeSpace.Text)`r`n" }
    If ($WPFIPAddress) { $ClipBoard += "IP Address:`t$($WPFIPAddress.Text)`r`n" }
    If ($WPFMACAddress) {
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
    $WPFMake.Text = $cs.Manufacturer
    $WPFModelName.Text = $cs.Model
    $WPFSerial.Text = $bios.SerialNumber
    $WPFMemory.Text = "{0:N2} GB" -f ($cs.TotalPhysicalMemory / 1GB)
    $WPFFreeSpace.Text = "{0:N2} GB" -f ((Get-PSDrive C).Free / 1GB)
    $WPFIPAddress.Text = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" }).IPAddress -join ", "
    $WPFMACAddress.ItemsSource = @(Get-NetAdapter | Select-Object Name, MacAddress)
}

# -----------------------------
# Button Actions
# -----------------------------
$WPFButton_IPConfig.Add_Click({ ipconfig /all | Out-GridView -Title "IP Config" })
$WPFButton_PrinterConfig.Add_Click({ Get-CimInstance Cim_Printer | Select-Object Name, Default, Location, Local, PortName, DriverName | Out-GridView -Title "Printer Configuration" })
$WPFButton_Copy.Add_Click({ Copy-ToClipboard })
$WPFButton_Refresh.Add_Click({ Get-PCInfo })
$WPFButton_Exit.Add_Click({ $Form.Close() })

# Initial population
Get-PCInfo

# Show Window
$Form.ShowDialog() | Out-Null
