# Load WPF assemblies
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationcore')
[void][System.Reflection.Assembly]::LoadWithPartialName('windowsbase')

# Define Modern Windows 11 Style XAML
$inputXML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Information"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="#CC1E1E1E"
        Width="600" Height="500"
        ResizeMode="NoResize">
    <Border CornerRadius="12" BorderThickness="1" BorderBrush="#44FFFFFF" Background="#DD2D2D30">
        <Grid Margin="10">
            <Grid.RowDefinitions>
                <RowDefinition Height="50"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="50"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <DockPanel Grid.Row="0">
                <TextBlock Text="💻 PC Information"
                           FontSize="20"
                           Foreground="White"
                           FontWeight="Bold"
                           VerticalAlignment="Center"/>
            </DockPanel>

            <!-- Content -->
            <StackPanel Grid.Row="1" Margin="10" VerticalAlignment="Top">
                <TextBlock Text="Computer Name:" Foreground="LightGray" FontSize="14"/>
                <TextBox Name="PCName" Margin="0,0,0,10" FontSize="14" IsReadOnly="True"/>

                <TextBlock Text="Operating System:" Foreground="LightGray" FontSize="14"/>
                <TextBox Name="OSName" Margin="0,0,0,10" FontSize="14" IsReadOnly="True"/>

                <TextBlock Text="CPU:" Foreground="LightGray" FontSize="14"/>
                <TextBox Name="CPUName" Margin="0,0,0,10" FontSize="14" IsReadOnly="True"/>

                <TextBlock Text="RAM:" Foreground="LightGray" FontSize="14"/>
                <TextBox Name="RAMAmount" Margin="0,0,0,10" FontSize="14" IsReadOnly="True"/>
            </StackPanel>

            <!-- Footer -->
            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                <Button Name="Button_Exit" Content="Close" Width="80" Margin="0,0,10,0"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

# Clean up XAML safely

$inputXML = $inputXML -replace 'mc:Ignorable="d"','' -replace "x:N",'N'  -replace '^<Win.*', '<Window'

[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$XAML = $inputXML

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
try { $Form = [Windows.Markup.XamlReader]::Load($reader) }
catch { Write-Host "Unable to load Windows.Markup.XamlReader. Check syntax and .NET installation." }

# Map all controls with a Name into PowerShell variables like $WPFPCName
$XAML.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name "WPF$($_.Name)" -Value $Form.FindName($_.Name)
}

# Set Window Icon
$Form.Icon = 'C:\Program Files\PCInfo\PCInfo.ico'

#-------------------------
# FUNCTIONS
#-------------------------
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

#-------------------------
# BUTTON EVENTS
#-------------------------
$WPFButton_IPConfig.Add_Click({ ipconfig /all 2>&1 | Out-GridView -Title "IPConfig /All" })
$WPFButton_Copy.Add_Click({ Copy-ToClipboard })
$WPFButton_Refresh.Add_Click({ Get-PCInfo })
$WPFButton_Exit.Add_Click({ $Form.Close() })

# Load initial info
Get-PCInfo

# Show the form
$Form.ShowDialog() | Out-Null
