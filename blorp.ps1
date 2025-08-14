# =========================================================
# PC Info - Windows 11 Styled WPF (PowerShell)
# Fixed-size; see ResizeMode comment below to enable resizing
# =========================================================

# -- Assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# -- XAML
$inputXML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Information"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        Width="720" Height="620"
        ResizeMode="NoResize">  <!-- Change to CanResize (or CanResizeWithGrip) to allow resizing -->

    <Border CornerRadius="14" Background="#EE1E1E1E" BorderBrush="#40FFFFFF" BorderThickness="1">
        <Border.Effect>
            <DropShadowEffect Color="#000000" Direction="270" ShadowDepth="0" BlurRadius="20" Opacity="0.4"/>
        </Border.Effect>

        <DockPanel LastChildFill="True">

            <!-- Header / Title bar -->
            <Grid Height="48" Background="#2D2D2D" DockPanel.Dock="Top">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock Text="💻 PC Information"
                           Foreground="White"
                           FontSize="18"
                           FontWeight="Bold"
                           VerticalAlignment="Center"
                           Margin="12,0,0,0"/>
                <!-- Minimize -->
                <Button x:Name="BtnMin" Grid.Column="1" Content="—" Width="42" Height="28"
                        Margin="0,10,4,10" Background="Transparent" Foreground="#DDFFFFFF" BorderThickness="0" Cursor="Hand">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Background" Value="Transparent"/>
                            <Setter Property="Foreground" Value="#DDFFFFFF"/>
                            <Setter Property="Template">
                                <Setter.Value>
                                    <ControlTemplate TargetType="Button">
                                        <Border Background="{TemplateBinding Background}" CornerRadius="6">
                                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter Property="Background" Value="#22FFFFFF"/>
                                            </Trigger>
                                            <Trigger Property="IsPressed" Value="True">
                                                <Setter Property="Background" Value="#33FFFFFF"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Setter.Value>
                            </Setter>
                        </Style>
                    </Button.Style>
                </Button>
                <!-- Close -->
                <Button x:Name="BtnClose" Grid.Column="2" Content="✕" Width="42" Height="28"
                        Margin="0,10,10,10" Background="Transparent" Foreground="#DDFFFFFF" BorderThickness="0" Cursor="Hand">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Background" Value="Transparent"/>
                            <Setter Property="Foreground" Value="#DDFFFFFF"/>
                            <Setter Property="Template">
                                <Setter.Value>
                                    <ControlTemplate TargetType="Button">
                                        <Border Background="{TemplateBinding Background}" CornerRadius="6">
                                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter Property="Background" Value="#33E81123"/>
                                            </Trigger>
                                            <Trigger Property="IsPressed" Value="True">
                                                <Setter Property="Background" Value="#55E81123"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Setter.Value>
                            </Setter>
                        </Style>
                    </Button.Style>
                </Button>

                <!-- drag anywhere on header -->
                <Grid.InputBindings>
                    <MouseBinding MouseAction="LeftClick" Command="{x:Static ApplicationCommands.NotACommand}"/>
                </Grid.InputBindings>
            </Grid>

            <!-- Content -->
            <Grid Margin="18" DockPanel.Dock="Top">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="220"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- 17 rows for all fields + spacer -->
                <Grid.RowDefinitions>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="32"/>
                    <RowDefinition Height="12"/>
                </Grid.RowDefinitions>

                <!-- Labels (left) -->
                <TextBlock Text="Computer Name:"   Grid.Row="0"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="Logged-in User:"  Grid.Row="1"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="Operating System:"Grid.Row="2"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="OS Architecture:" Grid.Row="3"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="OS Version:"      Grid.Row="4"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="OS Build:"        Grid.Row="5"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="Last Reboot:"     Grid.Row="6"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="Uptime:"          Grid.Row="7"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="Make:"            Grid.Row="8"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="Model:"           Grid.Row="9"  Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="Serial #:"        Grid.Row="10" Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="Physical Memory:" Grid.Row="11" Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="C: Free Space:"   Grid.Row="12" Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="IP Address:"      Grid.Row="13" Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>
                <TextBlock Text="Network Adapter(s):" Grid.Row="14" Grid.Column="0" Foreground="#DDFFFFFF" VerticalAlignment="Center"/>

                <!-- Values (right) -->
                <TextBox x:Name="PCName"      Grid.Row="0"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="LoggedInUser"Grid.Row="1"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="OSName"      Grid.Row="2"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="OSArch"      Grid.Row="3"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="OSVersion"   Grid.Row="4"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="OSBuild"     Grid.Row="5"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="LastReboot"  Grid.Row="6"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="Uptime"      Grid.Row="7"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="Make"        Grid.Row="8"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="ModelName"   Grid.Row="9"  Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="Serial"      Grid.Row="10" Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="Memory"      Grid.Row="11" Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="FreeSpace"   Grid.Row="12" Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>
                <TextBox x:Name="IPAddress"   Grid.Row="13" Grid.Column="1" IsReadOnly="True" Margin="0,2" Background="#292929" Foreground="White" BorderBrush="#444" BorderThickness="1" Padding="6"/>

                <!-- DataGrid -->
                <DataGrid x:Name="MACAddress"
                          Grid.Row="15" Grid.ColumnSpan="2"
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
                          BorderBrush="#444" BorderThickness="1"/>

            </Grid>

            <!-- Footer Buttons -->
            <Grid Height="64" DockPanel.Dock="Bottom" Margin="12,0,12,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel.Resources>
                    <!-- Fluent Button Style (hover + pressed) -->
                    <Style x:Key="FluentButton" TargetType="Button">
                        <Setter Property="Background" Value="#3A3A3A"/>
                        <Setter Property="Foreground" Value="White"/>
                        <Setter Property="BorderBrush" Value="#555"/>
                        <Setter Property="BorderThickness" Value="1"/>
                        <Setter Property="Padding" Value="8,6"/>
                        <Setter Property="MinWidth" Value="90"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="Button">
                                    <Border Background="{TemplateBinding Background}"
                                            BorderBrush="{TemplateBinding BorderBrush}"
                                            BorderThickness="{TemplateBinding BorderThickness}">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="6,2"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter Property="Background" Value="#505050"/>
                                            <Setter Property="BorderBrush" Value="#777"/>
                                        </Trigger>
                                        <Trigger Property="IsPressed" Value="True">
                                            <Setter Property="Background" Value="#686868"/>
                                            <Setter Property="BorderBrush" Value="#999"/>
                                        </Trigger>
                                        <Trigger Property="IsEnabled" Value="False">
                                            <Setter Property="Opacity" Value="0.6"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>

                    <Style x:Key="ExitButton" TargetType="Button" BasedOn="{StaticResource FluentButton}">
                        <Setter Property="Background" Value="#E81123"/>
                        <Setter Property="BorderBrush" Value="#B71C1C"/>
                        <Setter Property="Foreground" Value="White"/>
                        <Setter Property="MinWidth" Value="84"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="Button">
                                    <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="6,2"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter Property="Background" Value="#F1707A"/>
                                            <Setter Property="BorderBrush" Value="#C62828"/>
                                        </Trigger>
                                        <Trigger Property="IsPressed" Value="True">
                                            <Setter Property="Background" Value="#B71C1C"/>
                                            <Setter Property="BorderBrush" Value="#7F1A1A"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </StackPanel.Resources>

                <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" >
                    <Button x:Name="Button_IPConfig"     Content="IP Config"   Style="{StaticResource FluentButton}" Margin="0,0,8,0"/>
                    <Button x:Name="Button_PrinterConfig" Content="Printer Cfg" Style="{StaticResource FluentButton}" Margin="0,0,8,0"/>
                    <Button x:Name="Button_Copy"         Content="Copy"        Style="{StaticResource FluentButton}" Margin="0,0,8,0"/>
                    <Button x:Name="Button_Refresh"      Content="Refresh"     Style="{StaticResource FluentButton}" Margin="0,0,8,0"/>
                    <Button x:Name="Button_Exit"         Content="Exit"        Style="{StaticResource ExitButton}"/>
                </StackPanel>
            </Grid>

        </DockPanel>
    </Border>
</Window>
"@

# -- Load XAML
[xml]$XAML = $inputXML
$reader = New-Object System.Xml.XmlNodeReader $XAML
try { $Form = [Windows.Markup.XamlReader]::Load($reader) } catch {
    Write-Host "Unable to load Windows.Markup.XamlReader. Check XAML syntax and .NET install."
    return
}

# -- Make draggable (clicking header area or empty background)
$Form.Add_MouseLeftButtonDown({ $Form.DragMove() })

# -- Map named elements as $WPF<name>
$XAML.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name "WPF$($_.Name)" -Value $Form.FindName($_.Name)
}

# -- Header buttons
$WPFBtnClose.Add_Click({ $Form.Close() })
$WPFBtnMin.Add_Click({ $Form.WindowState = 'Minimized' })

# -----------------------------
# Functions (integrated)
# -----------------------------
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

    # Basic info
    $WPFPCName.Text       = $cs.Name
    $WPFLoggedInUser.Text = "{0}\{1}" -f $env:USERDOMAIN,$env:USERNAME
    $WPFOSName.Text       = $osInfo.ProductName
    $WPFOSArch.Text       = $os.OSArchitecture
    $WPFOSVersion.Text    = if ($osInfo.DisplayVersion) { $osInfo.DisplayVersion } else { $osInfo.ReleaseID }
    $WPFOSBuild.Text      = "$($osInfo.CurrentBuildNumber).$($osInfo.UBR)"
    $WPFLastReboot.Text   = $os.LastBootUpTime

    # Uptime: X days, HH:mm:ss
    $uptime = (Get-Date) - $os.LastBootUpTime
    $WPFUptime.Text = "{0} days, {1:hh\:mm\:ss}" -f [Math]::Floor($uptime.TotalDays), $uptime

    $WPFMake.Text         = $cs.Manufacturer
    $WPFModelName.Text    = $cs.Model
    $WPFSerial.Text       = $bios.SerialNumber
    $WPFMemory.Text       = "{0:N2} GB" -f ($cs.TotalPhysicalMemory / 1GB)

    # Free space C:
    try {
        $WPFFreeSpace.Text = "{0:N2} GB" -f ((Get-PSDrive -Name C).Free / 1GB)
    } catch {
        $WPFFreeSpace.Text = "N/A"
    }

    # IP v4s (non-loopback)
    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
               Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -ne $null } |
               Select-Object -ExpandProperty IPAddress
        $WPFIPAddress.Text = ($ips -join ", ")
    } catch {
        $WPFIPAddress.Text = "N/A"
    }

    # NICs
    try {
        $WPFMACAddress.ItemsSource = @( Get-NetAdapter | Select-Object Name, MacAddress )
    } catch {
        $WPFMACAddress.ItemsSource = @()
    }
}

# -- Button handlers
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

# -- Optional: set a custom icon (comment out if you don't have this path)
# $Form.Icon = 'C:\Program Files\PCInfo\PCInfo.ico'

# -- Fade-in animation (subtle)
$Form.Opacity = 0
$Form.Loaded.Add({
    $fadeAnim = New-Object Windows.Media.Animation.DoubleAnimation(0,1,[TimeSpan]::FromMilliseconds(400))
    $Form.BeginAnimation([Windows.UIElement]::OpacityProperty, $fadeAnim)
})

# -- Initial load
Get-PCInfo

# -- Show
$Form.ShowDialog() | Out-Null
