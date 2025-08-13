#========================
# PC Info Modern GUI v2.1
#========================

#------------------------
# XAML UI
#------------------------
$inputXML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Information 2.1"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="#DD2D2D30"
        Width="600"
        Height="600"
        ResizeMode="NoResize">

    <Border CornerRadius="12" BorderThickness="1" BorderBrush="#44FFFFFF" Background="#DD2D2D30">
        <Grid Margin="10">
            <Grid.RowDefinitions>
                <RowDefinition Height="50"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="60"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <DockPanel Grid.Row="0">
                <TextBlock Text="💻 PC Information 2.1" 
                           FontSize="20"
                           FontWeight="Bold" 
                           Foreground="White" 
                           VerticalAlignment="Center"/>
            </DockPanel>

            <!-- Main Content -->
            <Grid Grid.Row="1" Margin="0,10,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="200"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="30"/> <!-- PC Name -->
                    <RowDefinition Height="30"/> <!-- OS -->
                    <RowDefinition Height="30"/> <!-- OS Arch -->
                    <RowDefinition Height="30"/> <!-- OS Version -->
                    <RowDefinition Height="30"/> <!-- OS Build -->
                    <RowDefinition Height="30"/> <!-- Last Reboot -->
                    <RowDefinition Height="30"/> <!-- Make -->
                    <RowDefinition Height="30"/> <!-- Model -->
                    <RowDefinition Height="30"/> <!-- Serial -->
                    <RowDefinition Height="30"/> <!-- Memory -->
                    <RowDefinition Height="30"/> <!-- Free Space -->
                    <RowDefinition Height="30"/> <!-- IP Address -->
                    <RowDefinition Height="*"/>  <!-- MAC Address / List -->
                </Grid.RowDefinitions>

                <!-- Labels -->
                <Label Grid.Row="0" Grid.Column="0" Content="Computer Name:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="1" Grid.Column="0" Content="Operating System:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="2" Grid.Column="0" Content="OS Architecture:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="3" Grid.Column="0" Content="OS Version:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="4" Grid.Column="0" Content="OS Build:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="5" Grid.Column="0" Content="Last Reboot:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="6" Grid.Column="0" Content="Make:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="7" Grid.Column="0" Content="Model Name:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="8" Grid.Column="0" Content="Serial Number:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="9" Grid.Column="0" Content="Memory:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="10" Grid.Column="0" Content="Free Space:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="11" Grid.Column="0" Content="IP Address:" Foreground="LightGray" HorizontalAlignment="Right"/>
                <Label Grid.Row="12" Grid.Column="0" Content="Network Adapter(s):" Foreground="LightGray" HorizontalAlignment="Right"/>

                <!-- Textboxes -->
                <TextBox x:Name="PCName" Grid.Row="0" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="OS" Grid.Row="1" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="OSArch" Grid.Row="2" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="OSVersion" Grid.Row="3" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="OSBuild" Grid.Row="4" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="LastReboot" Grid.Row="5" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="Make" Grid.Row="6" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="ModelName" Grid.Row="7" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="Serial" Grid.Row="8" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="Memory" Grid.Row="9" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="FreeSpace" Grid.Row="10" Grid.Column="1" IsReadOnly="True"/>
                <TextBox x:Name="IPAddress" Grid.Row="11" Grid.Column="1" IsReadOnly="True"/>
                
                <!-- MAC Address DataGrid -->
                <DataGrid x:Name="MACAddress" Grid.Row="12" Grid.Column="1" AutoGenerateColumns="True"/>
            </Grid>

            <!-- Footer Buttons -->
            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Spacing="10">
                <Button x:Name="Button_IPConfig" Content="IP Config" Width="100"/>
                <Button x:Name="Button_Copy" Content="Copy" Width="100"/>
                <Button x:Name="Button_Refresh" Content="Refresh" Width="100"/>
                <Button x:Name="Button_Exit" Content="Exit" Width="100"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

#------------------------
# Load XAML in PowerShell
#------------------------
$inputXML = $inputXML -replace 'mc:Ignorable="d"','' -replace "x:N",'N'  -replace '^<Win.*', '<Window'

[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$XAML = $inputXML

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
try { $Form = [Windows.Markup.XamlReader]::Load($reader) }
catch { Write-Host "Unable to load Windows.Markup.XamlReader. Check syntax and .NET installation." }

# Map XAML controls to PowerShell variables
$XAML.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name "WPF$($_.Name)" -Value $Form.FindName($_.Name)
}

# Set Window Icon
$Form.Icon = 'C:\Program Files\PCInfo\PCInfo.ico'

#------------------------
# Functions
#------------------------
Function Copy-ToClipboard {
    $ClipBoard  = "PC Name:`t" + $WPFPCName.Text
    $ClipBoard += "`r`nOS:`t`t" + $WPFOS.Text
    $ClipBoard += "`r`nOS Arch:`t" + $WPFOSArch.Text 
    $ClipBoard += "`r`nOS Version:`t" + $WPFOSVersion.Text  
    $ClipBoard += "`r`nOS Build:`t" + $WPFOSBuild.Text
    $ClipBoard += "`r`nLast Reboot:`t" + $WPFLastReboot.Text
    $ClipBoard += "`r`nMake:`t`t" + $WPFMake.Text
    $ClipBoard += "`r`nModel Name:`t" + $WPFModelName.Text
    $ClipBoard += "`r`nSerial Number:`t" + $WPFSerial.Text
    $ClipBoard += "`r`nMemory:`t`t" + $WPFMemory.Text
    $ClipBoard += "`r`nFree Space:`t" + $WPFFreeSpace.Text
    $ClipBoard += "`r`nIP Address:`t" + $WPFIPAddress.Text

    ForEach ($Nic in $WPFMACAddress.ItemsSource) {
        $ClipBoard += "`r`nDevice:`t`t" + $Nic.Description
        $ClipBoard += "`r`nMAC Address:`t" + $Nic.MacAddress
    }

    Set-Clipboard -Value $ClipBoard
}

Function Get-PCInfo {
    $computerSystem = Get-CimInstance CIM_ComputerSystem
    $computerBIOS = Get-CimInstance CIM_BIOSElement
    $computerOS = Get-CimInstance CIM_OperatingSystem
    $computerOSInfo = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    
    $DNSSuffixSearchList = (Get-DNSClientGlobalSetting).SuffixSearchList
    $computerNetworkAdapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
    
    if ($computerNetworkAdapters.Count -gt 1) {
        $computerIPAddress = ($computerNetworkAdapters | Where-Object { $DNSSuffixSearchList.Contains($_.DNSDomain) }).IPAddress[0]
    } else {
        $computerIPAddress = $computerNetworkAdapters.IPAddress[0]
    }

    $WPFPCName.Text = $computerSystem.Name
    $WPFOS.Text = $computerOSInfo.ProductName
    $WPFOSArch.Text = $computerOS.OSArchitecture

    if ($null -ne $computerOSInfo.DisplayVersion) {
        $WPFOSVersion.Text = $computerOSInfo.DisplayVersion
    } else {
        $WPFOSVersion.Text = $computerOSInfo.ReleaseID
    }

    $WPFOSBuild.Text = $computerOSInfo.CurrentBuildNumber + "." + $computerOSInfo.UBR
    $WPFLastReboot.Text = $computerOS.LastBootUpTime
    $WPFMake.Text = $computerSystem.Manufacturer

    if ($computerSystem.Manufacturer.StartsWith('VMware')) {
        $WPFModelName.Text = ($computerSystem.model -Replace('VMWare', '')).Trim()
    } elseif ($computerSystem.Manufacturer.StartsWith('HP') -or $computerSystem.Manufacturer.StartsWith('Hewlitt-Packard')) {
        $WPFModelName.Text = ($computerSystem.model -Replace($WPFMake.Text, "")).Trim()
    } elseif ($computerSystem.Manufacturer.StartsWith('Lenovo')) {
        $WPFModelName.Text = ($computerSystem.systemfamily -Replace($WPFMake.Text, "")).Trim()
    } else {
        $WPFModelName.Text = ($computerSystem.systemfamily -Replace($WPFMake.Text, "")).Trim()        
    }

    $WPFSerial.Text = $computerBIOS.SerialNumber
    $WPFMemory.Text = ([MATH]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)).ToString() + " GB"
    $WPFFreeSpace.Text = "$(""{0:####.00}"" -f ((Get-PSDrive -Name 'C').Free / 1GB) + ' GB')"
    $WPFIPAddress.Text = $computerIPAddress
    $WPFMACAddress.ItemsSource = @($computerNetworkAdapters | Select-Object -Property Description, MacAddress)
}

#------------------------
# Button Events
#------------------------
$WPFButton_IPConfig.Add_Click({ ipconfig /all 2>&1 | Out-GridView -Title "IPConfig /All" })
$WPFButton_Copy.Add_Click({ Copy-ToClipboard })
$WPFButton_Refresh.Add_Click({ Get-PCInfo })
$WPFButton_Exit.Add_Click({ $Form.Close() })

#------------------------
# Load initial PC info
#------------------------
Get-PCInfo

#------------------------
# Show the form
#------------------------
$Form.ShowDialog() | Out-Null
