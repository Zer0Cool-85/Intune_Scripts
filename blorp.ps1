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
$inputXML = $inputXML -replace 'mc:Ignorable="d"', '' -replace 'x:N', 'N'

# Load XAML Window
$reader = New-Object System.Xml.XmlNodeReader ([xml]$inputXML)
try {
    $Form = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Host "Unable to load Windows.Markup.XamlReader. Check .NET installation."
    exit
}

# Get named elements
([xml]$inputXML).SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name "WPF$($_.Name)" -Value $Form.FindName($_.Name)
}

# Set Icon
$Form.Icon = 'C:\Program Files\PCInfo\PCInfo.ico'

# Populate data
$WPFPCName.Text = $env:COMPUTERNAME
$WPFOSName.Text = (Get-CimInstance Win32_OperatingSystem).Caption
$WPFCPUName.Text = (Get-CimInstance Win32_Processor).Name
$WPFRAMAmount.Text = "{0:N0} MB" -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)

# Button actions
$WPFButton_Exit.Add_Click({ $Form.Close() })

# Show Window
$Form.ShowDialog() | Out-Null
