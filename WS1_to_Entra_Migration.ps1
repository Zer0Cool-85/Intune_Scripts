#region script functions
# Add PresentationFramework Assembly before loading functions
Add-Type -AssemblyName PresentationFramework
function Write-Log() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [Alias('LogPath')]
        [string]$Path = "$env:ProgramData\Company_Logs\Migration.log",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warn", "Info")]
        [string]$Level = "Info"
    )
    Begin {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process {
        if (Test-Path $Path) {
            $LogSize = (Get-Item -Path $Path).Length / 1MB
            $MaxLogSize = 5
        }
        # Check for file size of the log. If greater than 5MB, it will create a new one and delete the old.
        if ((Test-Path $Path) -AND $LogSize -gt $MaxLogSize) {
            Write-Host "Log file $Path already exists and file exceeds maximum file size. Deleting the log and starting fresh." -ForegroundColor Red
            Remove-Item $Path -Force
            $null = New-Item $Path -Force -ItemType File
        }
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (-NOT(Test-Path $Path)) {
            Write-Host "Creating $Path." -ForegroundColor Yellow
            $null = New-Item $Path -Force -ItemType File
        }
        else {
            # Nothing to see here yet.
        }
        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Host $Message -ForegroundColor Red
                $LevelText = 'ERROR:'
            }
            'Warn' {
                Write-Host $Message -ForegroundColor Yellow
                $LevelText = 'WARNING:'
            }
            'Info' {
                Write-Host $Message
                $LevelText = 'INFO:'
            }
        }
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}
function Get-AdministratorStatus {
    $adminUser = Get-LocalUser -Name "Administrator"
    return $adminUser.Enabled
}
function Enable-AdministratorAccount {
    Enable-LocalUser -Name "Administrator"
    Start-Sleep -Seconds 3
}
function Set-AdministratorPassword {
    $password = ConvertTo-SecureString "ADIPVTit@24!5$#@!" -AsPlainText -Force
    Set-LocalUser -Name "Administrator" -Password $password
}
function Get-InstalledApplications {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [String]$Name
    )
    $uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $AllApps = @()
    foreach ($key in $uninstallKeys) {
        $app = Get-ItemProperty $key | Where-Object { $_.DisplayName -and $_.UninstallString } | Select-Object DisplayName, DisplayVersion, UninstallString
        $AllApps += $app
    }

    $AllApps | Where-Object { $_.DisplayName -like "*$($Name)*" }
}
function Get-dsregstatus {
    $dsregcmd = dsregcmd /status
    $obj = New-Object -TypeName PSObject
    $dsregcmd | Select-String -Pattern " *[A-z]+ : [A-z]+ *" | ForEach-Object {
        Add-Member -InputObject $obj -MemberType NoteProperty -Name (([String]$_).Trim() -split " : ")[0] -Value (([String]$_).Trim() -split " : ")[1] -Force
    }
    return $obj
}
function Get-FrequentUser {
    $newest = 20
    $ComputerName = $env:computername

    $UserProperty = @{n = "User"; e = { ((New-Object System.Security.Principal.SecurityIdentifier $_.ReplacementStrings[1]).Translate([System.Security.Principal.NTAccount])).ToString() } }
    $logs = Get-EventLog System -Source Microsoft-Windows-Winlogon -ComputerName $ComputerName -newest $newest | Select-Object $UserProperty
    
    $topuser = $logs | Group-Object user | Sort Count | Select-Object -First 1
    return $topuser.Name
}
function Get-CurrentUser {
    $userInfo = (Get-WmiObject -ClassName Win32_process -Filter "Name = 'explorer.exe'").getowner()
    return "$($userInfo.Domain)\$($userInfo.User)"
}
function Show-ConfirmPopup() {
    # Last update: 5/13/2024
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [String]$CurrentAccount,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [String]$NewAccount
    )

    # Define XAML for the custom message box
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Confirmation"
        Icon="$PSScriptRoot\icon.ico"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        Topmost="True"
        SizeToContent="WidthAndHeight">
        <Border BorderBrush="#35297F" BorderThickness="7,7,7,7">
        <Border BorderBrush="#6F1C67" BorderThickness="5,5,5,5">
        <Border BorderBrush="#F40EA4" BorderThickness="3,3,3,3">
        <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Image Grid.Row="0" Source="$PSScriptRoot\logo.png" Width="175" Height="125" HorizontalAlignment="Center" Margin="0,10,0,0"/>
        <TextBlock Grid.Row="1" TextWrapping="Wrap" HorizontalAlignment="Center" FontSize="24" FontFamily="Arial" FontWeight="Bold" Text="Ready to migrate account!"/>
        <TextBlock Grid.Row="2" TextWrapping="Wrap" HorizontalAlignment="Center" FontSize="18" FontFamily="Arial" Margin="10,20,10,10" Text="Please confirm user account information is accurate."/>               
        <TextBlock Grid.Row="3" TextWrapping="Wrap" HorizontalAlignment="Center" FontSize="18" FontFamily="Arial" Margin="10,20,10,20">
            <Run FontWeight="Bold">Current Account Name: </Run> $($CurrentAccount)
            <LineBreak/>
            <Run FontWeight="Bold">New Account Name: </Run> $($NewAccount)
        </TextBlock>
        <TextBlock Grid.Row="4" TextWrapping="Wrap" FontSize="18" FontFamily="Arial" Margin="10">
            If the current account and new account match your information, click 'Yes' to proceed.
            <LineBreak/>
            <LineBreak/>
            If it does not match your information, click 'No' and contact IT support for assistance.
         </TextBlock>
        <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,20,0,0">
            <Button x:Name="btnYes" Content="Yes" Height="50" Width="125" Margin="10" FontSize="18"/>
            <Button x:Name="btnNo" Content="No" Height="50" Width="125" Margin="10" FontSize="18"/>
        </StackPanel>
    </Grid>
    </Border>
    </Border>
    </Border>
</Window>
"@

    # Load XAML
    $window = [Windows.Markup.XamlReader]::Parse($xaml)

    # Find buttons by name
    $btnYes = $window.FindName("btnYes")
    $btnNo = $window.FindName("btnNo")

    # Define event handlers
    $btnYes.Add_Click({
            $window.DialogResult = $true
            $window.Close()
        })

    $btnNo.Add_Click({
            $window.DialogResult = $false
            $window.Close()
        })
        try{
            # Show the window
            $result = $window.ShowDialog()
            # Return the result to perform actions according to user interaction
            return $result
        }catch{
            $error1 = $_
            write-log -message "$error1"
        }
}
function Show-InfoPopup() {
    # Last update: 5/13/2024
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [String]$Title,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [String]$Message
    )
    <# Can format message variable with anything that can be included inside a textblock like this:
    $message = @"
        <TextBlock TextDecorations="Underline" FontSize="24" FontWeight="Bold" Margin="25,0,0,20" Text="Starting migration process!"/>
        <LineBreak/>
        Please close all open applications and save your work.
        <LineBreak/><LineBreak/>
        Click Yes when you are ready to proceed.
        "@
    #>
  
    # Define XAML for the custom message box
    # Window will appear with no title bar or option to resize
    # Will appear with a 3 layered colorful border

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" SizeToContent="WidthAndHeight"
        Icon="$PSScriptRoot\icon.ico"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        Topmost="True">
        <Border BorderBrush="#35297F" BorderThickness="7,7,7,7">
        <Border BorderBrush="#6F1C67" BorderThickness="5,5,5,5">
        <Border BorderBrush="#F40EA4" BorderThickness="3,3,3,3">
        <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Image Grid.Row="0" Source="$PSScriptRoot\logo.png" Width="150" Height="100" HorizontalAlignment="Center" Margin="0,10,0,0"/>
            $message
        <StackPanel Grid.Row="3"  Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,10,0,0">
            <Button x:Name="btnYes" Content="Yes" Height="50" Width="125" Margin="10" FontSize="18"/>
            <Button x:Name="btnNo" Content="No" Height="50" Width="125" Margin="10" FontSize="18"/>
        </StackPanel>
    </Grid>
    </Border>
    </Border>
    </Border>
</Window>
"@

    # Load XAML
    $window = [Windows.Markup.XamlReader]::Parse($xaml)

    # Find buttons by name
    $btnYes = $window.FindName("btnYes")
    $btnNo = $window.FindName("btnNo")

    # Define event handlers
    $btnYes.Add_Click({
            $window.DialogResult = $true
            $window.Close()
        })

    $btnNo.Add_Click({
            $window.DialogResult = $false
            $window.Close()
        })

    # Show the window
    $result = $window.ShowDialog()

    # Check the result and perform actions accordingly
    return $result
}
function Show-EmailConfirm() {
    # Last update: 5/13/2024
    # Define XAML for the custom message box
    # Window will appear with no title bar or option to resize
    # Will appear with a 3 layered colorful border

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Email confirmation" SizeToContent="WidthAndHeight"
        Icon="$PSScriptRoot\icon.ico"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        Topmost="True">
        <Border BorderBrush="#35297F" BorderThickness="7,7,7,7">
        <Border BorderBrush="#6F1C67" BorderThickness="5,5,5,5">
        <Border BorderBrush="#F40EA4" BorderThickness="3,3,3,3">
        <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Image Grid.Row="0" Source="$PSScriptRoot\logo.png" Width="150" Height="100" HorizontalAlignment="Center" Margin="0,10,0,0"/>
        <TextBlock Grid.Row="1" TextDecorations="Underline" FontSize="24" FontWeight="Bold" HorizontalAlignment="Center" Text="Company Account Confirmation" Margin="0,0,0,10"/>
        <TextBlock Grid.Row="2" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Top" FontSize="18" Margin="10">
        Please confirm that you have reset the password for your new Company email address.
        </TextBlock>
        <TextBlock Grid.Row="3" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Top" FontSize="18" Margin="10">
        If you have not reset your password, please click the following link and follow the steps to reset. 
        </TextBlock>
        <Label Grid.Row="4" x:Name="Link1" Width="Auto" FontSize='24' FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Top" ToolTip='Microsoft Online Password Reset'>
            <Hyperlink NavigateUri="https://passwordreset.microsoftonline.com/">Password Reset Portal</Hyperlink>
        </Label>
        <TextBlock Grid.Row="5" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Top" FontSize="18" Margin="10">
        If you have already reset your account click Yes to proceed with the migration.
        </TextBlock>
        <StackPanel Grid.Row="6"  Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,10,0,0">
            <Button x:Name="btnYes" Content="Yes" Height="50" Width="125" Margin="10" FontSize="18"/>
            <Button x:Name="btnNo" Content="No" Height="50" Width="125" Margin="10" FontSize="18"/>
        </StackPanel>
    </Grid>
    </Border>
    </Border>
    </Border>
</Window>
"@

    # Load XAML
    $window = [Windows.Markup.XamlReader]::Parse($xaml)

    # Find buttons by name
    $btnYes = $window.FindName("btnYes")
    $btnNo = $window.FindName("btnNo")
    $Link1 = $window.FindName("Link1")

    # Define event handlers
    $btnYes.Add_Click({
            $window.DialogResult = $true
            $window.Close()
        })

    $btnNo.Add_Click({
            $window.DialogResult = $false
            $window.Close()
        })

    $Link1.Add_PreviewMouseDown({
            $window.DialogResult = $false
            [system.Diagnostics.Process]::start('https://passwordreset.microsoftonline.com/')
            $window.Close()
        })

    # Show the window
    $result = $window.ShowDialog()

    # Check the result and perform actions accordingly
    return $result
}
function Show-EmailPopup {
    # Last update: 5/13/2024
    $isValidEmail = $false
    $email = ""

    # Run while loop to continuously prompt end user to enter correct email address
    while (-not $isValidEmail) {
        # Define XAML for the custom message box
        $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Confirmation"
        Icon="$PSScriptRoot\icon.ico"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        SizeToContent="WidthAndHeight"
        Topmost="True">
        <Border BorderBrush="#35297F" BorderThickness="7,7,7,7">
        <Border BorderBrush="#6F1C67" BorderThickness="5,5,5,5">
        <Border BorderBrush="#F40EA4" BorderThickness="3,3,3,3">
        <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Image Grid.Row="0" Source="$PSScriptRoot\logo.png" Width="175" Height="125" HorizontalAlignment="Center"/>
        <TextBlock Grid.Row="1" TextDecorations="Underline" FontWeight="Bold" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Top" FontSize="22" FontFamily="Arial" Margin="10" Text="Email address required"/>
        <TextBlock Grid.Row="2" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Top" FontSize="18" FontFamily="Arial" Margin="10" Text="Please enter your Company.com email address:"/>
        <TextBox Grid.Row="3" x:Name="txtEmail" Width="300" Height="30" FontSize="18" HorizontalAlignment="Center" Margin="10"/>
            <TextBlock Grid.Row="4" Text="Click OK to proceed with migration or Cancel to exit." FontSize="18" FontFamily="Arial" Margin="20,10,20,20"/>
            <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Center" >
                <Button x:Name="btnYes" Content="OK" Height="50" Width="125" Margin="10" FontSize="18"/>
                <Button x:Name="btnNo" Content="Cancel" Height="50" Width="125" Margin="10" FontSize="18"/>
            </StackPanel>
    </Grid>
    </Border>
    </Border>
    </Border>
</Window>
"@

        # Load XAML
        $window = [Windows.Markup.XamlReader]::Parse($xaml)

        # Find controls by name
        $txtEmail = $window.FindName("txtEmail")
        $btnYes = $window.FindName("btnYes")
        $btnNo = $window.FindName("btnNo")

        # Set focus to the email TextBox
        $txtEmail.Focus()
 
        # Add key press event handler to the email TextBox
        $txtEmail.Add_KeyDown({
                param($sender, $e)
                if ($e.Key -eq "Enter") {
                    $window.Close()
                }
            })

        # Define event handlers for buttons
        $btnYes.Add_Click({
                $window.Close()
            })

        $btnNo.Add_Click({
                $window.Close()
            })

        # Show the window
        $window.ShowDialog()

        $email = $txtEmail.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($email) -and $email -like "*@Company.com") {
            $isValidEmail = $true
        }
        elseif ([System.Windows.MessageBox]::Show("Invalid email or empty email. Please enter a valid email address ending with '@Company.com'. Would you like to try again?", "Invalid Email", "YesNo", [System.Windows.MessageBoxImage]::Warning) -eq "No") {
            return $null
        }
    }
    $email
}
function Show-MigrationProgress {
    <#
   .DESCRIPTION
   Create a WPF window in a separate thread to display a marquee style progress ellipse with a custom message that can be updated.
   The status message supports line breaks.
   #>
   
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [String]$StatusMessage = 'Starting Endpoint Migration...',
        [Parameter(Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [Boolean]$TopMost = $true,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [String]$windowTitle = 'Migration Status Updates'
    )
   
    Begin {
        
    }
    Process {
   
        If ($envHost.Name -match 'PowerGUI') {
            Write-Log -Level Warn -Message "$($envHost.Name) is not a supported host for WPF multi-threading. Progress dialog with message [$statusMessage] will not be displayed."
            Return
        }
   
        ## Check if the progress thread is running before invoking methods on it
        If ($script:ProgressSyncHash.Window.Dispatcher.Thread.ThreadState -ne 'Running') {

            #  Create a synchronized hashtable to share objects between runspaces
            $script:ProgressSyncHash = [Hashtable]::Synchronized(@{ })

            #  Create a new runspace for the progress bar
            $script:ProgressRunspace = [runspacefactory]::CreateRunspace()
            $script:ProgressRunspace.ApartmentState = 'STA'
            $script:ProgressRunspace.ThreadOptions = 'ReuseThread'
            $script:ProgressRunspace.Open()

            #  Add the sync hash to the runspace
            $script:ProgressRunspace.SessionStateProxy.SetVariable('progressSyncHash', $script:ProgressSyncHash)

            #  Add other variables from the parent thread required in the progress runspace
            $script:ProgressRunspace.SessionStateProxy.SetVariable('windowTitle', $windowTitle)
            $script:ProgressRunspace.SessionStateProxy.SetVariable('topMost', $topMost.ToString())
            $script:ProgressRunspace.SessionStateProxy.SetVariable('ProgressStatusMessage', $statusMessage)
            $script:ProgressRunspace.SessionStateProxy.SetVariable('RsPSScriptRoot', $PSScriptRoot)
            
            # $script:ProgressRunspace.SessionStateProxy.SetVariable('LogoBanner', $LogoBanner)
            # $script:ProgressRunspace.SessionStateProxy.SetVariable('LogoIcon', $LogoIcon)

            #  Add the script block to be executed in the progress runspace
            $progressCmd = [PowerShell]::Create().AddScript({
                    [String]$xamlProgressString = @'
                <Window
                xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                x:Name="Window" Title="Migration Status"
                Padding="0,0,0,0" Margin="0,0,0,0"
                WindowStartupLocation="Manual"
                Icon=""
                Top="0"
                Left="0"
                Topmost="True"
                WindowStyle="None"
                ResizeMode="NoResize"
                ShowInTaskbar="True" VerticalContentAlignment="Center" HorizontalContentAlignment="Center" SizeToContent="WidthAndHeight">
                    <Window.Resources>
                    <Storyboard x:Key="Storyboard1" RepeatBehavior="Forever">
                    <DoubleAnimationUsingKeyFrames BeginTime="00:00:00" Storyboard.TargetName="ellipse" Storyboard.TargetProperty="(UIElement.RenderTransform).(TransformGroup.Children)[2].(RotateTransform.Angle)">
                        <SplineDoubleKeyFrame KeyTime="00:00:02" Value="360"/>
                    </DoubleAnimationUsingKeyFrames>
                    </Storyboard>
                    </Window.Resources>
                    <Window.Triggers>
                    <EventTrigger RoutedEvent="FrameworkElement.Loaded">
                    <BeginStoryboard Storyboard="{StaticResource Storyboard1}"/>
                    </EventTrigger>
                    </Window.Triggers>
                    <Border BorderBrush="#2E1869" BorderThickness="10">
                    <Grid Background="#F0F0F0" MinWidth="450" MaxWidth="750" Width="600">
                    <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition MinWidth="50" MaxWidth="75" Width="75"></ColumnDefinition>
                        <ColumnDefinition MinWidth="350" Width="*"></ColumnDefinition>
                    </Grid.ColumnDefinitions>
                    <Image x:Name="ProgressBanner" Grid.ColumnSpan="2" Margin="0" Source="" Grid.Row="0"/>
                    <TextBlock x:Name="ProgressText" Grid.Row="1" Grid.Column="1" Margin="-10,10,10,10" Text="" FontSize="22" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" Padding="10,0,10,0" TextWrapping="Wrap"/>
                    <Ellipse x:Name="ellipse" Grid.Row="1" Grid.Column="0" Margin="0,0,0,0" StrokeThickness="5" RenderTransformOrigin="0.5,0.5" Height="45" Width="45" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <Ellipse.RenderTransform>
                        <TransformGroup>
                            <ScaleTransform/>
                            <SkewTransform/>
                            <RotateTransform/>
                        </TransformGroup>
                    </Ellipse.RenderTransform>
                    <Ellipse.Stroke>
                        <LinearGradientBrush EndPoint="0.445,0.997" StartPoint="0.555,0.003">
                            <GradientStop Color="White" Offset="0"/>
                            <GradientStop Color="#0078d4" Offset="1"/>
                        </LinearGradientBrush>
                    </Ellipse.Stroke>
                    </Ellipse>
                    </Grid>
                    </Border>
                </Window>
'@
                    [Xml.XmlDocument]$xamlProgress = New-Object -TypeName 'System.Xml.XmlDocument'
                    $xamlProgress.LoadXml($xamlProgressString)
                    ## Set the configurable values using variables added to the runspace from the parent thread
                    $xamlProgress.Window.TopMost = $topMost
                    $xamlProgress.Window.Icon = "$RsPSScriptRoot\icon.ico"
                    $xamlProgress.Window.Border.Grid.Image.Source = "$RsPSScriptRoot\banner.png"
                    $xamlProgress.Window.Border.Grid.TextBlock.Text = $ProgressStatusMessage
                    $xamlProgress.Window.Title = $windowTitle
                    #  Parse the XAML
                    $progressReader = New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList ($xamlProgress)
                    $script:ProgressSyncHash.Window = [Windows.Markup.XamlReader]::Load($progressReader)
                    #  Calculate the position on the screen where the progress dialog should be placed
                    $script:ProgressSyncHash.Window.add_Loaded({
                            [Int32]$screenWidth = [System.Windows.SystemParameters]::WorkArea.Width
                            [Int32]$screenHeight = [System.Windows.SystemParameters]::WorkArea.Height
                            [Int32]$script:screenCenterWidth = $screenWidth - $script:ProgressSyncHash.Window.ActualWidth
                            [Int32]$script:screenCenterHeight = $screenHeight - $script:ProgressSyncHash.Window.ActualHeight
                            #  Set the start position of the Window based on the screen size
                            #  Put the window in the top center
                            $script:ProgressSyncHash.Window.Left = [Double](($screenWidth - $script:ProgressSyncHash.Window.ActualWidth) / 2)
                            $script:ProgressSyncHash.Window.Top = [Double](($screenHeight - $script:ProgressSyncHash.Window.ActualHeight) / 50)
                        })
                    #  Prepare the ProgressText variable so we can use it to change the text in the text area
                    $script:ProgressSyncHash.ProgressText = $script:ProgressSyncHash.Window.FindName('ProgressText')
                    #  Add an action to the Window.Closing event handler to disable the close button
                    $script:ProgressSyncHash.Window.Add_Closing({ $_.Cancel = $true })
                    #  Allow the window to be dragged by clicking on it anywhere
                    $script:ProgressSyncHash.Window.Add_MouseLeftButtonDown({ $script:ProgressSyncHash.Window.DragMove() })
                    $null = $script:ProgressSyncHash.Window.ShowDialog()
                    $script:ProgressSyncHash.Error = $Error
                })

            $progressCmd.Runspace = $script:ProgressRunspace
            Write-Log -Level Info -Message  "Creating the progress dialog in a separate thread with message: [$statusMessage]." 
            #  Invoke the progress runspace
            $null = $progressCmd.BeginInvoke()
            #  Allow the thread to be spun up safely before invoking actions against it.
            Start-Sleep -Seconds 1
            If ($script:ProgressSyncHash.Error) {
		        $error1 = $script:ProgressSyncHash.Error
                Write-Log -Level Error -Message  "Failure while displaying progress dialog: $error1"
            }
        }
        ## Check if the progress thread is running before invoking methods on it
        ElseIf ($script:ProgressSyncHash.Window.Dispatcher.Thread.ThreadState -eq 'Running') {
            Try {
                #  Update the progress text
                $script:ProgressSyncHash.Window.Dispatcher.Invoke([Windows.Threading.DispatcherPriority]::Send, [Windows.Input.InputEventHandler] { $script:ProgressSyncHash.ProgressText.Text = $statusMessage }, $null, $null)
                #  Calculate the position on the screen where the progress dialog should be placed
                $script:ProgressSyncHash.Window.Dispatcher.Invoke([Windows.Threading.DispatcherPriority]::Send, [Windows.Input.InputEventHandler] {
                        [Int32]$screenWidth = [System.Windows.SystemParameters]::WorkArea.Width
                        [Int32]$screenHeight = [System.Windows.SystemParameters]::WorkArea.Height
                        #  Set the start position of the Window based on the screen size
                        #  Put the window in the top center
                        $script:ProgressSyncHash.Window.Left = [Double](($screenWidth - $script:ProgressSyncHash.Window.ActualWidth) / 2)
                        $script:ProgressSyncHash.Window.Top = [Double](($screenHeight - $script:ProgressSyncHash.Window.ActualHeight) / 50)
                    }, $null, $null)

                Write-Log -Level Info -Message  "Updated the progress message: [$statusMessage]."
            }
            Catch {
                Write-Log -Level Error "Unable to update the progress message: $_"
            }
        }
    } End {
    }
}
function Close-MigrationProgress {
    <#
   .DESCRIPTION
   Kills the migration progress window and cleans up the runspace/hash
   #>
    # If the thread is running, stop it
    If ((-not ($script:ProgressSyncHash.Window.Dispatcher.Thread.ThreadState -band [System.Threading.ThreadState]::Stopped)) -and (-not ($script:ProgressSyncHash.Window.Dispatcher.Thread.ThreadState -band [System.Threading.ThreadState]::Unstarted))) {
        $script:ProgressSyncHash.Window.Dispatcher.InvokeShutdown()
    }
    # If the runspace is opened, close it
    If ($script:ProgressRunspace.RunspaceStateInfo.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
        $script:ProgressRunspace.Close()
    }
    # Clear sync hash
    If ($script:ProgressSyncHash) {
        $script:ProgressSyncHash.Clear()
    }
}
function Show-MigrationComplete() {
    # Last update: 5/13/2024
    # Define XAML for the custom message box
    $xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Migration Complete" SizeToContent="WidthAndHeight"
            Icon="$PSScriptRoot\icon.ico"
            WindowStartupLocation="CenterScreen"
            WindowStyle="None"
            ResizeMode="NoResize"
            Topmost="True">
            <Border BorderBrush="#35297F" BorderThickness="7,7,7,7">
            <Border BorderBrush="#6F1C67" BorderThickness="5,5,5,5">
                <Border BorderBrush="#F40EA4" BorderThickness="3,3,3,3">
                    <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                        <Image Grid.Row="0" Source="$PSScriptRoot\LoginScreen10.png" Width="800" Height="500" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="5"/>
                        <TextBlock Grid.Row="1" TextAlignment="Center" FontSize="16" FontWeight="medium" FontFamily="Arial" Padding="10">
                            <Run FontSize="18" FontWeight="Bold">Migration Complete, your PC will reboot in a moment.</Run>
                            <LineBreak/>
                            <LineBreak/>
                            When you get back to the login screen click <Run FontWeight="Bold">'Other User'</Run> in the bottom left.
                            <LineBreak/>
                            Sign in using your new @Company.com email address and password.
                            <LineBreak/><LineBreak/>
                            Should you run into issues please contact the IT support team. 
                        </TextBlock>
                        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,10,0,0">
                            <Button x:Name="btnYes" Content="Click to Reboot PC Now" FontFamily="Arial" Background="#FFB1FF" Foreground="Black" Height="40" Width="225" Margin="0,0,0,10" FontSize="18" FontWeight="Bold" BorderBrush="Black" BorderThickness="2"/>
                        </StackPanel>
                    </Grid>
                </Border>
            </Border>
        </Border>
    </Window>
"@  
    # Load XAML
    $window = [Windows.Markup.XamlReader]::Parse($xaml)
    $window.add_KeyDown{
        param(
            [Parameter(Mandatory)][Object]$sender,
            [Parameter(Mandatory)][Windows.Input.KeyEventArgs]$e
        )
        if ($e.Key -eq "Enter") {
            $window.DialogResult = $true
            $timer.Stop()
            $window.Close()
            Restart-Computer -Force
        }
    }

    # Find buttons by name
    $btnYes = $window.FindName("btnYes")

    # Define event handlers
    $btnYes.Add_Click({
            $window.DialogResult = $true
            $timer.Stop()
            $window.Close()
            Restart-Computer -Force
        })
    # Start a timer for 90 seconds
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(90)
    $timer.Add_Tick({
            # Automatically click the "Yes" button and close the window when the timer elapses
            $btnYes.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
            $window.Close()
            $timer.Stop()
            Restart-Computer -Force
        })
    $timer.Start()

    # Show the window
    $result = $window.ShowDialog()

    # Check the result and perform actions accordingly
    return $result
}
function Exit-Error{
    # Tasks to complete when exiting script due to error or user cancellation
    Clear-Content "$env:ProgramData\MigrationPkg\LocalMigration\UserLookup.csv"
    Clear-Content "$PSScriptRoot\UserLookup.csv"
    $shell.UndoMinimizeAll()
    Close-MigrationProgress
    Exit 1
}
#endregion

# Check if admin account is enabled. If its not enabled, enable and set password. If enabled, set the password
$adminStatus = Get-AdministratorStatus
if ($adminStatus -eq $false) {
    Enable-AdministratorAccount
    Write-Log -Level Info -Message "Administrator account was disabled. Will enable account."
    Set-AdministratorPassword
    Write-Log -Level Info -Message "Password for Administrator account has been set."
} else {
    Write-Log -Level Info -Message "Administrator account is already enabled."
    Set-AdministratorPassword
    Write-Log -Level Info -Message "Password for Administrator account has been set."
}

#Create shell objects
$shell = New-Object -ComObject "Shell.Application"
$Prompt = New-Object -ComObject wscript.shell

# Give script a couple seconds between popups to reduce delayed opening
Start-Sleep -Seconds 3

# Use shell application object to force all open windows to minimize when script begins
$shell.MinimizeAll()

# Start persistent migration progress popup in separate thread
Show-MigrationProgress

# XAML config stored in variable for InfoPopup message content (See function Show-InfoPopup)
$messageStart = @"
<TextBlock Grid.Row="1" TextDecorations="Underline" FontSize="24" FontWeight="Bold" HorizontalAlignment="Center" Text="Endpoint Migration!"/>
<TextBlock Grid.Row="2" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Top" FontSize="18" Margin="10">
Please close all open applications and save your work.
<LineBreak/><LineBreak/>
Click Yes when you are ready to proceed.
</TextBlock>
"@
Start-Sleep -Seconds 5
# Call migration start popup message
$startMigration = Show-InfoPopup -Title "Endpoint Migration" -Message $messageStart
if ($startMigration -eq $true) {
    Write-Log -Level Info -Message "Initiating migration script..."
} else {
    Write-Log -Level Error -Message  "User clicked no, exiting script."
    Exit-Error
}

# Get local user information
$currentUser = Get-CurrentUser
$frequentUser = Get-FrequentUser
$userVerify = $currentUser.Split("\")[1]

Write-Log -Level Info -Message "Current User: $currentUser"
Write-Log -Level Info -Message "Most frequent User: $frequentUser"

if ($currentUser -ne $frequentUser) {
    Write-Log -Level Error -Message "Current logged in user is not most frequent user of this PC."
    Write-Log -Level Warn -Message "Prompting user to confirm account migration of $currentUser"
    Show-MigrationProgress -StatusMessage "Verify user account information..."
    $Prompt = New-Object -comobject wscript.shell
    $Answer = $Prompt.Popup("Current logged in user: $currentUser`nDoes not match most frequent user: $frequentUser`n`nDo you wish to continue with the migration `nof $($currentUser)?", 120, "Computer Migration", 4096 + 32 + 4)
    Switch ($Answer) {
        # YES #
        { $Answer -eq 6 } { 
            Write-Log -Level Warn -Message "User confirmed, will proceed with migrating: $currentUser" 
        }
    
        # NO #
        { $Answer -eq 7 } {
            Write-Log -Level Error -Message "User declined. Please review logs and try again."
            $null = $Prompt.Popup("Error: Please contact IT support for review.", 60, "Computer Migration", 4096 + 16 + 0)
            Exit-Error
        }
    
        # Timeout #
        { $Answer -eq -1 } {
            Write-Log -Level Error -Message "Prompt timed out. Please review logs and try again."
            $null = $Prompt.Popup("Error: Please contact IT support for review.", 60, "Computer Migration", 4096 + 16 + 0) 
            Exit-Error
        }
    }
}
else {
    Write-Log -Level Info -Message "Current user is also most frequent user."
}

# Import user lookup csv and check that the logged in user is located in the file
$userLookup = @()
$userLookupImport = "$PSScriptRoot\UserLookup.csv"
$userLookup += Import-csv $userLookupImport -Header A, B
$userLookupConfirm = $userLookup | Where-Object { $_.A -eq $userVerify }

if ($userLookupConfirm) {
    Write-Log -Level Info -Message "User account found in lookup file."
    Write-Log -Level Info -Message "Will migrate user account $($userLookupConfirm.A) to $($userLookupConfirm.B)"
}
else {
    Show-MigrationProgress -StatusMessage "User account information required..."
    Write-Log -Level Info -Message "User account was NOT found in lookup file."
    $email = Show-EmailPopup
    $emailAddress = $email | Select-Object -Last 1
    # Check if an email was provided
    if ($emailAddress -notlike "*@company.com") {
        if ($emailAddress -like "*False*") {
            $emailAddress = "<NO ENTRY>"
        }
        Write-Log -Level Info -Message "Email entered: $emailAddress"
        Write-Log -Level Error -Message "Migration canceled. User clicked Cancel or email was invalid..Review logs."
        Exit-Error
    }
    $newRow = [PSCustomObject]@{
        A = $userVerify
        B = $emailAddress
    }
    $userLookup += $newRow
    $userLookup | ConvertTo-Csv -NoTypeInformation -Delimiter "," | Select-Object -Skip 1 | ForEach-Object { $_ -replace '"', "" } | Out-File $userLookupImport -Force
    Show-MigrationProgress -StatusMessage "Adding $emailAddress to UserLookup file..."
    Start-Sleep -Seconds 3
    Copy-Item -Path $userLookupImport -Destination "$env:ProgramData\MigrationPkg\LocalMigration\UserLookup.csv" -Force
    $userLookup = Import-csv $userLookupImport -Header A, B
    $userLookupConfirm = $userLookup | Where-Object { $_.A -eq $userVerify }
    if ($userLookupConfirm) {
        Write-Log -Level Info -Message "User account found in lookup file."
        Write-Log -Level Info -Message "Will migrate user account $($userLookupConfirm.A) to $($userLookupConfirm.B)"    
    }
    else {
        $null = $Prompt.Popup("Error: User information did not update in the lookup file.`n`nPlease contact IT support for review.", 120, "Computer Migration", 4096 + 16 + 0)
        Exit-Error
    }
}
Show-MigrationProgress -StatusMessage "Confirming user account information..."

# Import and read the XML file content
$xmlFilePath = "$PSScriptRoot\ForensiTEntraID.xml"
[xml]$xmlContent = Get-Content -Path $xmlFilePath
# Search for the email address provided by the user and capture the element
$user = $xmlContent.ForensiTEntraID.User | Where-Object { $_.UserPrincipalName -eq $emailAddress }
# Check if the user was found in the XML and capture the ObjectId
if ($null -ne $user) {
    $userObjId = $($user.ObjectId)
} else {
    Write-Log -Level Warn -Message "Migration failed: User email address was not found in the ForensiTEntraID.xml file."
    $null = $Prompt.Popup("Error: Migration failed.`n`nEmail address not found in XML. `n`nPlease contact IT to review logs.", 60, "Computer Migration", 4096 + 16 + 0)
    Exit-Error
}

$RegistryPath = 'HKLM:\Software\Company'
$RegKey       = 'UserObjID'
$RegKey2      = 'Email'
$RegKey3      = 'Serial'
$Value        = $userObjId
$Value2       = $emailAddress
$Value3       = (Get-WmiObject -Class Win32_BIOS).SerialNumber
if(-Not (Test-Path $RegistryPath)){
    New-Item -Path $RegistryPath
} 
$null = New-ItemProperty -Path $RegistryPath -Name $RegKey -Value $Value -Force
$null = New-ItemProperty -Path $RegistryPath -Name $RegKey2 -Value $Value2 -Force
$null = New-ItemProperty -Path $RegistryPath -Name $RegKey3 -Value $Value3 -Force

$verfifyAccount = Show-EmailConfirm
if ($verfifyAccount -eq $true) {
    Write-Log -Level Info -Message "User confirmed they reset their account password. Proceeding with migration..."
} else {
    Write-Log -Level Error -Message "User has to reset their password. Migration canceled."
    Exit-Error
}

# Prompt user to confirm the account migration
$verifyMigration = Show-ConfirmPopup -CurrentAccount $($userLookupConfirm.A) -NewAccount $($userLookupConfirm.B)
if ($verifyMigration -eq $true) {
    Write-Log -Level Info -Message "User confirmed account information. Proceeding with migration..."
} else {
    Write-Log -Level Error -Message "User declined account information. Migration canceled."
    Exit-Error
}

$regStatus = Get-dsregstatus
$AADJoin = $regStatus.AzureAdJoined
$DomainJoin = $regStatus.DomainJoined
Write-Log -Level Info -Message "Check if PC is joined to AzureAD."

if ($AADJoin -eq "YES") {
    write-Log -Level Warn -Message "PC already joined to AAD tenant: $($regStatus.TenantName)"
    write-Log -Level Warn -Message "UserName: $($regStatus.'User Identity')"
    $null = $Prompt.Popup("Error: PC already connected to Azure tenant: $($regStatus.TenantName)`nPlease contact IT support for review.", 120, "Computer Migration", 4096 + 16 + 0)
    Exit-Error
}
else {
    Write-Log -Level Info -Message "PC is not currently AzureAD Joined."
}

Show-MigrationProgress -StatusMessage "Migrating user account: $($userLookupConfirm.A)..."
# Set with NOREBOOT param as true in config file so it doesn't reboot after migration.
# Will then proceed with uninstall/unenroll of WsOne after the profile migration completes.
Write-Log -Level Info -Message "Starting ForensIT Profile Migration Wizard."
if (($DomainJoin -eq "YES") -and ($currentUser -like "*COMPANY\*")) {
    write-Log -Level Warn -Message "PC is bound to domain name: $($regStatus.DomainName)"
    Start-Process -FilePath "$env:ProgramData\MigrationPkg\Profwiz.exe" -NoNewWindow -RedirectStandardOutput "$env:ProgramData\MigrationPkg\process_output.txt" -Wait
}
else {
    if ($DomainJoin -eq "YES") {
        Write-Log -Level Info -Message "PC is bound to domain but logged in with local account. Will migrate local user account(s)."
        write-Log -Level Warn -Message  "Attempting force removal from domain prior to migration."
        Remove-Computer -Force
        Start-Sleep -Seconds 5

        $regStatus = Get-dsregstatus
        $DomainJoinVerify = $regStatus.DomainJoined
        if ($DomainJoinVerify -eq "YES") {
            Write-Log -Level Error -Message "PC unbind failed..."
            $null = $Prompt.Popup("Error: Migration failed at domain unbind step.`n`nPlease contact IT to review logs.", 30, "Computer Migration", 4096 + 48 + 1)    
            Exit-Error
        }
        else {
            Write-Log -Level Info -Message "PC unbind was successful!"
        }
    }
    else {
        Write-Log -Level Info -Message "PC is not bound to domain. Migrating local user account(s)."
    }
    Start-Process -FilePath "$env:ProgramData\MigrationPkg\LocalMigration\Profwiz.exe" -NoNewWindow -RedirectStandardOutput "$env:ProgramData\MigrationPkg\process_output.txt" -Wait
}

$forensITLogPath = "C:\Users\Public\Documents\Migrate.Log"
$forensitlog = Get-Content $forensITLogPath
$forensitlog >> "$env:ProgramData\Company_Logs\Migration.log"

# Get last line of Profwiz log
# Check that log said "Migration Complete"; Exit-Error if not
$logLastLine = Get-Content $forensITLogPath -Tail 1
$logError = (Get-Content $forensITLogPath -Tail 2)[0] -replace "\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}.\d{3} ", ""

if ($logLastLine -like "*Migration Complete*") {
    Write-Log -Level Info -Message "Success, continue with Workspace One unenrollment."
    Show-MigrationProgress -StatusMessage "User account migration successful"
    Start-Sleep -Seconds 3
}
else {
    Write-Log -Level Warn -Message "Migration failed: $logError"
    $null = $Prompt.Popup("Error: Migration failed.`n`n$logError `n`nPlease contact IT to review logs.", 60, "Computer Migration", 4096 + 16 + 0)
    Exit-Error
}

# Check if PC is still bound to domain, if so, remove it
if ($DomainJoin -eq "YES") {
    Write-Log -Level Info -Message "Checking if PC is still bound to AD domain"
    $regStatus = Get-dsregstatus
    $DomainJoinCheck = $regStatus.DomainJoined
    if ($DomainJoinCheck -eq "YES") {
        Write-Log -Level Warn -Message "Device still bound to AD!"
        Write-Log -Level Warn -Message  "Attempting force removal..."
        Remove-Computer -Force
        Start-Sleep -Seconds 5

        $regStatus = Get-dsregstatus
        $DomainJoinVerify = $regStatus.DomainJoined
        if ($DomainJoinVerify -eq "YES") {
            Write-Log -Level Error -Message "PC unbind failed..."
        }
        else {
            Write-Log -Level Info -Message "PC unbind was successful!"
        }
    }
    else {
        Write-Log -Level Info -Message "PC is no longer bound to domain."
    }
}
Show-MigrationProgress -StatusMessage "Unenrolling device from Workspace One..."
# Rename XML app manifests to stop apps from uninstalling when unenrolling from WsOne
Write-Log -Level Info -Message "Getting Workspace One managed app information"

$appmanifestpath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\AirWatchMDM\AppDeploymentAgent\AppManifests"
$appmanifestsearchpath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\AirWatchMDM\AppDeploymentAgent\AppManifests\*"

$Apps = (Get-ItemProperty -Path "$appmanifestsearchpath" -ErrorAction SilentlyContinue).PSChildname
$appCount = $Apps.count
Write-Log -Level Info -Message "$appCount Workspace One managed apps found."
$i = 1
foreach ($App in $Apps) {
    $apppath = $appmanifestpath + "\" + $App
    $appName = (Get-ItemProperty -Path $apppath -ErrorAction SilentlyContinue).Name
    Write-Log -Level Info -Message "Processing app $($i): $appName"
    $null = Rename-ItemProperty -Path $apppath -Name "DeploymentManifestXML" -NewName "DeploymentManifestXML_BAK"
    $null = New-ItemProperty -Path $apppath -Name "DeploymentManifestXML"
    $i++
}

# Begin WsOne Hub and Assist app uninstalls, this action will unenroll the device from WsOne
Write-Log -Level Info -Message "Running uninstall of Workspace One Intelligent Hub"
$ws1Hub = Get-WmiObject -Class win32_product -Filter "Name like 'Workspace ONE Intelligent%'" -ErrorAction SilentlyContinue

if ($null -ne $ws1Hub) {
    $hubUninstall = $ws1Hub.Uninstall()

    # Verify that the WMI Uninstall command was successful
    # In the event that the uninstall fails, retry using the uninstall string from the registry
    if ($hubUninstall.returnvalue -eq 0) {
        Write-Log -Level Info -Message "Workspace One Hub uninstall successful"
    }
    else {
        Write-Log -Level Warn -Message "Workspace One Hub uninstall failed..retry with msiexec uninstall string."
        $app = "Workspace ONE Intelligent"
        $appUninstall = (Get-InstalledApplications -Name $app).UninstallString
        $appUninstall = $appUninstall + " /qn" -replace "/X", "/X "
        Write-Log -Level Info -Message "Running uninstall command: $appUninstall"
        cmd.exe /c $appUninstall
    }
}
else {
    Write-Log -Level Info -Message "Workspace One Hub app not detected"
}

Write-Log -Level Info -Message "Running uninstall of Workspace One Assist"
$ws1Assist = Get-WmiObject -Class win32_product -Filter "Name like 'Workspace ONE Assist%'" -ErrorAction SilentlyContinue
if ($null -ne $ws1Assist) {
    $assistUninstall = $ws1Assist.Uninstall()

    # Verify that the WMI Uninstall command was successful
    # In the event that the uninstall fails, retry using the uninstall string from the registry
    if ($assistUninstall.returnvalue -eq 0) {
        Write-Log -Level Info -Message "Workspace One Assist uninstall successful"
    }
    else {
        Write-Log -Level Warn -Message "Workspace One Assist uninstall failed..retry with msiexec uninstall string."
        $app = "Workspace ONE Assist"
        $appUninstall = (Get-InstalledApplications -Name $app).UninstallString
        $appUninstall = $appUninstall + " /qn" -replace "/X", "/X "
        Write-Log -Level Info -Message "Running uninstall command: $appUninstall"
        cmd.exe /c $appUninstall
    }
}
else {
    Write-Log -Level Info -Message "Workspace One Assist app not detected"
}

Write-Log "Running uninstall of Workspace One Appx Package(s)"
$appxpackages = Get-AppxPackage -AllUsers -Name "*AirwatchLLC*"
foreach ($appx in $appxpackages) {
    Remove-AppxPackage -AllUsers -Package $appx.PackageFullName -Confirm:$false
}
$appxpackages = Get-AppxPackage -AllUsers -Name "*AirwatchLLC*"

if ($null -eq $appxpackages) {
    Write-Log -Level Info -Message "Workspace One AppxPackages removed successfully."
}
else {
    Write-Log -Level Warn -Message "Workspace One AppxPackages removal failed."
}

# Cleanup WsOne registry keys

Write-Log -Level Info -Message "Removing Workspace One Registry keys"

$null = Remove-Item -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\AirWatch" -Recurse -Force -ErrorAction SilentlyContinue
$null = Remove-Item -Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\AirWatchMDM" -Recurse -Force -ErrorAction SilentlyContinue

Show-MigrationProgress -StatusMessage "Unenroll from Workspace One successful"
Start-Sleep -Seconds 3

# Register scheduled task that sets the wallpaper on first login for any user
Write-Log -Level Info -Message "Registering scheduled task to set default wallpaper on user logon."
$null = Register-ScheduledTask -TaskName "Set-Wallpaper" -xml (Get-Content "$env:ProgramData\MigrationPkg\Set-Wallpaper.xml" | Out-String) -Force

Write-log -Level Info -Message "Starting installation of Intune Provisioning Package."

Show-MigrationProgress -StatusMessage "Enrolling device in Intune..."

$provPkg = Install-ProvisioningPackage -PackagePath "$env:ProgramData\MigrationPkg\provPackage.ppkg" -ForceInstall -QuietInstall -LogsDirectoryPath "$env:windir\Logs\MigrationLog.log"
Write-Log -Level Info -Message "Provisioning package results:"
$provPkgResults = $provPkg.result.ProvxmlResults
foreach ($result in $provPkgResults) {
    Write-Log -Level Info -Message "$($result.category) - $($result.lastresult) - $($result.message)"
    Show-MigrationProgress -StatusMessage "Intune $($result.category): $($result.lastresult)"
    Start-Sleep -Seconds 3
}

Write-Log -Level Info -Message "Migration is complete! Alerting user of upcoming reboot."
Close-MigrationProgress
Show-MigrationComplete