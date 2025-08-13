<#
.SYNOPSIS
    PCInfo in PowerShell form

.DESCRIPTION
    This script displays a GUI window with some useful
    information that the ERC frequently asks a caller 
    to provide.
 
#>

#region variables

#region Gui
$inputXML = @"
<Window x:Class="WpfApplication3.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Information 2.1" Height="580" Width="370" Background="#FFDAD6D6" WindowStyle="ThreeDBorderWindow" ResizeMode="CanMinimize"
 >
    
    <Window.Resources>
        <Style TargetType="{x:Type TextBox}">
            <Setter Property="CharacterCasing" Value="Upper"/>
        </Style>
        <Style x:Key="ButtonFocusVisual">
            <Setter Property="Control.Template">
                <Setter.Value>
                    <ControlTemplate>
                        <Border>
                            <Rectangle SnapsToDevicePixels="true" Margin="4" Stroke="Black" StrokeDashArray="1 2" StrokeThickness="1"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="RoundedButton" TargetType="{x:Type Button}">
            <Setter Property="FocusVisualStyle" Value="{StaticResource ButtonFocusVisual}"/>
            <Setter Property="Background" Value="{DynamicResource {x:Static SystemColors.ControlBrushKey}}"/>
            <Setter Property="Foreground" Value="{DynamicResource {x:Static SystemColors.ControlTextBrushKey}}"/>
            <Setter Property="BorderThickness" Value="3"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Padding" Value="0,0,1,1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type Button}">
                        <ControlTemplate.Resources>
                            <Storyboard x:Key="ShowShine">
                                <DoubleAnimationUsingKeyFrames BeginTime="00:00:00" Storyboard.TargetName="Shine" Storyboard.TargetProperty="(UIElement.Opacity)">
                                    <SplineDoubleKeyFrame KeyTime="00:00:00.5000000" Value=".15"/>
                                </DoubleAnimationUsingKeyFrames>
                            </Storyboard>
                            <Storyboard x:Key="HideShine">
                                <DoubleAnimationUsingKeyFrames BeginTime="00:00:00" Storyboard.TargetName="Shine" Storyboard.TargetProperty="(UIElement.Opacity)">
                                    <SplineDoubleKeyFrame KeyTime="00:00:00.3000000" Value="0"/>
                                </DoubleAnimationUsingKeyFrames>
                            </Storyboard>
                        </ControlTemplate.Resources>
                        <Border CornerRadius="5,5,5,5" BorderThickness="1,1,1,1" RenderTransformOrigin="0.5,0.5" x:Name="border" BorderBrush="#FFFFFFFF">
                            <Border.RenderTransform>
                                <TransformGroup>
                                    <ScaleTransform ScaleX="1" ScaleY="1"/>
                                    <SkewTransform AngleX="0" AngleY="0"/>
                                    <RotateTransform Angle="0"/>
                                    <TranslateTransform X="0" Y="0"/>
                                </TransformGroup>
                            </Border.RenderTransform>
                            <Border Background="{TemplateBinding Background}" CornerRadius="5,5,5,5" x:Name="border1">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="0.5*"/>
                                        <RowDefinition Height="0.5*"/>
                                    </Grid.RowDefinitions>
                                    <Border Grid.Row="0" CornerRadius="5,5,0,0">
                                        <Border.Background>
                                            <LinearGradientBrush EndPoint="0.5,1" StartPoint="0.5,0">
                                                <GradientStop Color="#00FFFFFF" Offset="0"/>
                                                <GradientStop Color="#7EFFFFFF" Offset="1"/>
                                            </LinearGradientBrush>
                                        </Border.Background>
                                    </Border>
                                    <Border Grid.Row="1" Opacity="0" x:Name="Shine" Width="Auto" Height="Auto" CornerRadius="0,0,5,5" Margin="1,0,-1,0" Background="{TemplateBinding BorderBrush}"/>
                                    <ContentPresenter VerticalAlignment="Center"  Grid.RowSpan="2" HorizontalAlignment="Center" x:Name="contentPresenter"/>
                                </Grid>
                            </Border>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" TargetName="border1" Value="0.5"/>
                                <Setter Property="Opacity" TargetName="border" Value="1"/>
                                <Setter Property="Opacity" TargetName="contentPresenter" Value="0.5"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="RenderTransform" TargetName="border">
                                    <Setter.Value>
                                        <TransformGroup>
                                            <ScaleTransform ScaleX="0.9" ScaleY="0.9"/>
                                            <SkewTransform AngleX="0" AngleY="0"/>
                                            <RotateTransform Angle="0"/>
                                            <TranslateTransform X="0" Y="0"/>
                                        </TransformGroup>
                                    </Setter.Value>
                                </Setter>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Trigger.ExitActions>
                                    <BeginStoryboard Storyboard="{StaticResource HideShine}" x:Name="HideShine_BeginStoryboard"/>
                                </Trigger.ExitActions>
                                <Trigger.EnterActions>
                                    <BeginStoryboard x:Name="ShowShine_BeginStoryboard" Storyboard="{StaticResource ShowShine}"/>
                                </Trigger.EnterActions>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="Link" TargetType="Button">
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="HorizontalAlignment" Value="Center"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="Blue"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <TextBlock TextDecorations="Underline" 
                            Text="{TemplateBinding Content}"
                            Background="{TemplateBinding Background}"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Foreground" Value="Red"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>


    <Grid>
        <Grid HorizontalAlignment="Left" Height="500" VerticalAlignment="Top" Width="360"/>
        <Label Content="Computer Name:" Grid.Row="0" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="Operating System:" Grid.Row="1" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="OS Architecture:" Grid.Row="2" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="OS Version:" Grid.Row="3" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="OS Build:" Grid.Row="4" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="Last Reboot:" Grid.Row="5" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="Make:" Grid.Row="6" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="Model:" Grid.Row="7" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="Serial #:" Grid.Row="8" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="Physical Memory:" Grid.Row="9" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>
        <Label Content="C: Drive Free Space:" Grid.Row="10" Grid.Column="0" VerticalAlignment="Center" HorizontalAlignment="Right" FontWeight="Bold"/>   
        <Button x:Name="Button_IPConfig" Content="IP Address:" HorizontalAlignment="Center" Grid.Row="11" Grid.Column="0" VerticalAlignment="Center" Margin="105,0,0,0" FontWeight="Bold" Style="{DynamicResource Link}" />
        <Label Content="Network Adapter(s):" Grid.Row="12" Grid.Column="0" VerticalAlignment="Center" FontWeight="Bold"/>
        
        <TextBox x:Name="PCName" Grid.Column="1" Grid.Row="0" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True" />
        <TextBox x:Name="OS" Grid.Column="1" Grid.Row="1" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="OSArch" Grid.Column="1" Grid.Row="2" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="OSVersion" Grid.Column="1" Grid.Row="3" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="OSBuild" Grid.Column="1" Grid.Row="4" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="LastReboot" Grid.Column="1" Grid.Row="5" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="Make" Grid.Column="1" Grid.Row="6" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="ModelName" Grid.Column="1" Grid.Row="7" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="Serial" Grid.Column="1" Grid.Row="8" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="Memory" Grid.Column="1" Grid.Row="9" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="FreeSpace" Grid.Column="1" Grid.Row="10" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <TextBox x:Name="IPAddress" Grid.Column="1" Grid.Row="11" HorizontalAlignment="Left" VerticalAlignment="Center" TextWrapping="NoWrap" Width="160" IsReadOnly="True"/>
        <DataGrid x:Name="MACAddress" Grid.ColumnSpan="2" HorizontalAlignment="Left" Margin="10,10,0,0" Grid.Row="13" Grid.RowSpan="5" VerticalAlignment="Top" Width="330" MaxColumnWidth="220"/>
        <Button x:Name="Button_PrinterConfig" Content="Printer Cfg" HorizontalAlignment="Left" Margin="10,7,0,0" Grid.Row="16" Grid.Column="0" VerticalAlignment="Top" Width="75" Height="35" FontWeight="Bold" Style="{DynamicResource RoundedButton}" />
        <Button x:Name="Button_Copy" Content="Copy" HorizontalAlignment="Left" Margin="95,7,0,0" Grid.Row="16" Grid.Column="0" VerticalAlignment="Top" Width="75" Height="35" FontWeight="Bold" Style="{DynamicResource RoundedButton}" />
        <Button x:Name="Button_Refresh" Content="Refresh" HorizontalAlignment="Left" Margin="0,7,0,0" Grid.Row="16" Grid.Column="1" VerticalAlignment="Top" Width="75" Height="35" FontWeight="Bold" Style="{DynamicResource RoundedButton}" />
        <Button x:Name="Button_Exit" Content="Exit" HorizontalAlignment="Center" Margin="65,7,0,0" Grid.Row="16" Grid.Column="1" VerticalAlignment="Top" Width="75" Height="35" FontWeight="Bold" Style="{DynamicResource RoundedButton}" />



        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="180" />
            <ColumnDefinition Width="180" />
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="30" />
            <RowDefinition Height="80" />
        </Grid.RowDefinitions>
    </Grid>
</Window>
"@       
 
$inputXML = $inputXML -replace 'mc:Ignorable="d"','' -replace "x:N",'N'  -replace '^<Win.*', '<Window'
 
[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$XAML = $inputXML
#Read XAML

$reader=(New-Object System.Xml.XmlNodeReader $xaml)
try{$Form=[Windows.Markup.XamlReader]::Load( $reader )}
catch{Write-Host "Unable to load Windows.Markup.XamlReader. Double-check syntax and ensure .net is installed."}
 
#===========================================================================
# Load XAML Objects In PowerShell
#===========================================================================
 
$xaml.SelectNodes("//*[@Name]") | ForEach-Object{Set-Variable -Name "WPF$($_.Name)" -Value $Form.FindName($_.Name)}

#endregion
 
#===========================================================================
# Actually make the objects work
#===========================================================================

Function Copy-ToClipboard{
    $ClipBoard += "PC Name:`t" + $WPFPCName.Text
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
    ForEach($Nic in $WPFMACAddress.ItemsSource){
        $ClipBoard += "`r`nDevice:`t`t" + $Nic.Description
        $ClipBoard += "`r`nMAC Address:`t" + $Nic.MacAddress
    }
    Set-Clipboard -value $ClipBoard
}


Function Get-PCInfo{
    $computerSystem = Get-CimInstance CIM_ComputerSystem
    $computerBIOS = Get-CimInstance CIM_BIOSElement
    $computerOS = Get-CimInstance CIM_OperatingSystem
    $computerOSInfo = Get-ItemProperty  -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    
    $DNSSuffixSearchList = (Get-DNSClientGlobalSetting).SuffixSearchList
    $computerNetworkAdapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object{$_.IPEnabled}
    If($computerNetworkAdapters.Count -gt 1){
        $computerIPAddress = ($computerNetworkAdapters | Where-Object{$DNSSuffixSearchList.Contains($_.DNSDomain)}).IPAddress[0]
    }Else{
        $computerIPAddress = $computerNetworkAdapters.IPAddress[0]
    }

    $WPFPCName.Text = $computerSystem.Name
    $WPFOS.Text = $computerOSInfo.ProductName
    $WPFOSArch.Text = $computerOS.OSArchitecture
    If($Null -ne $computerOSInfo.DisplayVersion){
        $WPFOSVersion.Text = $computerOSInfo.DisplayVersion
    }Else{
        $WPFOSVersion.Text = $computerOSInfo.ReleaseID
    }
    $WPFOSBuild.Text = $computerOSInfo.CurrentBuildNumber + "." + $computerOSInfo.UBR
    $WPFLastReboot.Text = $computerOS.LastBootUpTime
    $WPFMake.Text = $computerSystem.Manufacturer
    If($computerSystem.Manufacturer.StartsWith('VMware')){
        $WPFModelName.Text = ($computerSystem.model -Replace('VMWare','')).Trim()
    }ElseIf($computerSystem.Manufacturer.StartsWith('HP') -or $computerSystem.Manufacturer.StartsWith('Hewlitt-Packard')){
        $WPFModelName.Text = ($computerSystem.model -Replace($WPFMake.Text,"")).Trim()
    }ElseIf($computerSystem.Manufacturer.StartsWith('Lenovo')){
        $WPFModelName.Text = ($computerSystem.systemfamily -Replace($WPFMake.Text,"")).Trim()
    }Else{
        $WPFModelName.Text = ($computerSystem.systemfamily -Replace($WPFMake.Text,"")).Trim()        
    }

    $WPFSerial.Text = $computerBIOS.SerialNumber
    $WPFMemory.Text = ([MATH]::Round($computerSystem.TotalPhysicalMemory / 1GB,2)).ToString() + " GB"
    $WPFFreeSpace.Text = "$(""{0:####.00}"" -f ((Get-PSDrive -Name ""c"").Free / 1GB) + "" GB"")"
    $WPFIPAddress.Text = $computerIPAddress

    $WPFMACAddress.ItemsSource = @($computerNetworkAdapters | Select-Object -Property Description, MacAddress)
}

$Form.Icon = 'C:\Program Files\PCInfo\PCInfo.ico'

$WPFButton_IPConfig.Add_Click({ipconfig /all 2>&1 | Out-GridView -Title "IPConfig /All"})
$WPFButton_PrinterConfig.Add_Click({Get-CimInstance Cim_Printer | Select-Object Name, Default, Location, Local, PortName, DriverName | out-gridview -Title "Printer Configuration"})
$WPFButton_Copy.Add_Click({Copy-ToClipboard})
$WPFButton_Refresh.Add_Click({Get-PCInfo})
$WPFButton_Exit.Add_Click({$Form.Close()})

Get-PCInfo
 
#===========================================================================
# Shows the form
#===========================================================================
$Form.ShowDialog() | Out-Null
