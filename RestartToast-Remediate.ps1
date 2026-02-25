<#
.SYNOPSIS
    Create nice toast notifications for the logged on user in Windows 10.

.DESCRIPTION
    Everything is customizeable through config-toast.xml.
    Config-toast.xml can be locally, hosted online in blob storage or set to an UNC path with the -Config parameter.
    This way you can quickly modify the configuration without the need to push new files to the computer running the toast.
    Can be used for improving the numbers in Windows Servicing as well as kindly reminding users of pending reboots (and a bunch of other use cases as well).
    All actions are logged to a local log file in AppData\Roaming\ToastNotificationScript\New-ToastNotification.log.

.PARAMETER Config
    Specify the path for the config.xml. If none is specified, the script uses the local config.xml

.NOTES
    NewFilename: RestartToast-Remediate
    Edited by: Dale Lute
    Last update: 10/24/2023
    OriginalFilename: New-ToastNotification.ps1
    Version: 4.0.1
    OriginalAuthor: Martin Bengtsson
    Blog: www.imab.dk

    Updates:
    7/4/2023 - 4.0.1
        Updated script version variable
        Commented out lines 1162 and 1177 since they are not used
    
    10/24/2023 - 4.1.0
        Updated script version variable
        Updated custom script directory location

    08/22/2024 - 5.0.0
        Updated script version variable
        Updated hero/logo images       


.LINK
    https://www.imab.dk/windows-10-toast-notification-script/
#> 


## THIS PARAMETER IS NOT NEEDED FOR THIS SCRIPT SINCE ITS RUNNING VIA PROACTIVE REMEDIATION AND HAS THE XML VARIABLES IN THE SCRIPT
<#[CmdletBinding()]
param(
    [Parameter(HelpMessage='Path to XML Configuration File')]
    [string]$Config
)
#>

#region Functions
# Create Write-Log function
function Write-Log() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [Alias('LogPath')]
        [string]$Path = "$env:APPDATA\Script_Logs\RestartToast\RestartToast.log",
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
            Write-Error "Log file $Path already exists and file exceeds maximum file size. Deleting the log and starting fresh."
            Remove-Item $Path -Force
            $NewLogFile = New-Item $Path -Force -ItemType File
        }
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (-NOT(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
        }
        else {
            # Nothing to see here yet.
        }
        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
            }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
            }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
            }
        }
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}

## Create function to test if Zoom, Teams or Skype meetings are active
function Get-CallInfo() {
    Write-Log -Message "Checking for active Zoom or Teams call" -Level Info
    If (get-process | Where-Object { $_.Name -match "zoom$|teams$" }) {
        If (((Get-NetUDPEndpoint -OwningProcess (get-process | Where-Object { $_.Name -match "zoom$|teams$" }).Id -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -ne '127.0.0.1' -and $_.LocalAddress -ne '::' } | Measure-Object).count) -gt 0) {
            Write-Log -Message "Active Zoom or Teams call detected. Exiting script and trying again on next schedule" -Level Warn
            break
        }
        else {
            Write-Log -Message "No active Zoom or Teams call detected." -Level Info
        }
    }
}

# Create Pending Reboot function for registry
function Test-PendingRebootRegistry() {
    Write-Log -Message "Running Test-PendingRebootRegistry function"
    $CBSRebootKey = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction Ignore
    $WURebootKey = Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction Ignore
    $FileRebootKey = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction Ignore
    if (($null -ne $CBSRebootKey) -OR ($null -ne $WURebootKey) -OR ($null -ne $FileRebootKey)) {
        Write-Log -Message "Check returned TRUE on ANY of the registry checks: Reboot is pending!"
        $true
    }
    else {
        Write-Log -Message "Check returned FALSE on ANY of the registry checks: Reboot is NOT pending!"
        $false
    }
}

# Create Get Device Uptime function
function Get-DeviceUptime() {
    Write-Log -Message "Running Get-DeviceUptime function"
    $Last_reboot = Get-ciminstance Win32_OperatingSystem | Select-Object -Exp LastBootUpTime
    $Check_FastBoot = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ea silentlycontinue).HiberbootEnabled 
    If (($null -eq $Check_FastBoot) -or ($Check_FastBoot -eq 0)) {
        $Boot_Event = Get-WinEvent -ProviderName 'Microsoft-Windows-Kernel-Boot' | Where-Object { $_.ID -eq 27 -and $_.message -like "*0x0*" }
        If ($null -ne $Boot_Event) {
            $Last_boot = $Boot_Event[0].TimeCreated
        }
    }
    ElseIf ($Check_FastBoot -eq 1) {
        $Boot_Event = Get-WinEvent -ProviderName 'Microsoft-Windows-Kernel-Boot' | Where-Object { $_.ID -eq 27 -and $_.message -like "*0x1*" }
        If ($null -ne $Boot_Event) {
            $Last_boot = $Boot_Event[0].TimeCreated
        }
    }		
			
    If ($null -eq $Last_boot) {
        $Uptime = $Uptime = $Last_reboot
    }
    Else {
        If ($Last_reboot -ge $Last_boot) {
            $Uptime = $Last_reboot
        }
        Else {
            $Uptime = $Last_boot
        }
    }
		
    $Current_Date = get-date
    $Diff_boot_time = $Current_Date - $Uptime
    $Boot_Uptime_Days = $Diff_boot_time.Days	
    $Boot_Uptime_Days
}

# Create Get GivenName function
function Get-GivenName() {
    Write-Log -Message "Running Get-GivenName function"
    <#try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $PrincipalContext = [System.DirectoryServices.AccountManagement.PrincipalContext]::new([System.DirectoryServices.AccountManagement.ContextType]::Domain, [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain())
        $GivenName = ([System.DirectoryServices.AccountManagement.Principal]::FindByIdentity($PrincipalContext,[System.DirectoryServices.AccountManagement.IdentityType]::SamAccountName,[Environment]::UserName)).GivenName
        $PrincipalContext.Dispose()
    }
    catch [System.Exception] {
        Write-Log -Level Error -Message "$_"
    }#>
    if (-NOT[string]::IsNullOrEmpty($GivenName)) {
        Write-Log -Message "Given name retrieved from Active Directory: $GivenName"
        $GivenName
    }
    # This is the last resort of trying to find a given name. This part will be used if device is not joined to a local AD, and is not having the configmgr client installed
    elseif ([string]::IsNullOrEmpty($GivenName)) {
        Write-Log -Message "Given name not found in AD or no local AD is available. Continuing looking for given name elsewhere"
        $RegKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
        if ((Get-ItemProperty $RegKey).LastLoggedOnDisplayName) {
            $LoggedOnUserDisplayName = Get-Itemproperty -Path $RegKey -Name "LastLoggedOnDisplayName" | Select-Object -ExpandProperty LastLoggedOnDisplayName
            if (-NOT[string]::IsNullOrEmpty($LoggedOnUserDisplayName)) {
                $DisplayName = $LoggedOnUserDisplayName.Split(" ")
                $GivenName = $DisplayName[0]
                Write-Log -Message "Given name found directly in registry: $GivenName"
                $GivenName
            }
            else {
                Write-Log -Message "Given name not found in registry. Using nothing as placeholder"
                $GivenName = $null
            }
        }
        else {
            Write-Log -Message "Given name not found in registry. Using nothing as placeholder"
            $GivenName = $null
        }
    }
}

# Create Get-WindowsVersion function
# This is used to determine if the script is running on Windows 10 or not
function Get-WindowsVersion() {
    $OS = Get-CimInstance Win32_OperatingSystem
    if (($OS.Version -like "10.0.*") -AND ($OS.ProductType -eq 1)) {
        Write-Log -Message "Running supported version of Windows. Windows 10 and workstation OS detected"
        $true
    }
    elseif ($OS.Version -notlike "10.0.*") {
        Write-Log -Level Error -Message "Not running supported version of Windows"
        $false
    }
    else {
        Write-Log -Level Error -Message "Not running supported version of Windows"
        $false
    }
}

# Create Windows Push Notification function.
# This is testing if toast notifications generally are disabled within Windows 10
function Test-WindowsPushNotificationsEnabled() {
    $ToastEnabledKey = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name ToastEnabled -ErrorAction Ignore).ToastEnabled
    if ($ToastEnabledKey -eq "1") {
        Write-Log -Message "Toast notifications for the logged on user are enabled in Windows"
        $true
    }
    elseif ($ToastEnabledKey -eq "0") {
        Write-Log -Level Error -Message "Toast notifications for the logged on user are not enabled in Windows. The script will try to enable toast notifications for the logged on user"
        $false
    }
}

# Create Enable-WindowsPushNotifications
# This is used to re-enable toast notifications if the user disabled them generally in Windows
function Enable-WindowsPushNotifications() {
    $ToastEnabledKeyPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"
    Write-Log -Message "Trying to enable toast notifications for the logged on user"
    try {
        Set-ItemProperty -Path $ToastEnabledKeyPath -Name ToastEnabled -Value 1 -Force
        Get-Service -Name WpnUserService** | Restart-Service -Force
        Write-Log -Message "Successfully enabled toast notifications for the logged on user"
    }
    catch {
        Write-Log -Level Error -Message "Failed to enable toast notifications for the logged on user. Toast notifications will probably not be displayed"
    }
}

function Get-SnoozedToasts() {
    $timeStamp = Get-Date -Format "MM/dd/yyyy HH:mm"
    $LastRunTime = (Get-ItemProperty $global:RegistryPath -Name LastRunTime -ErrorAction Ignore).LastRunTime
    $Difference = ([datetime]$timeStamp - ([datetime]$LastRunTime)) 
    $MinutesSinceLastRunTime = [math]::Round($Difference.TotalMinutes)
    if ($MinutesSinceLastRunTime -ge 2880) {
        Clear-Content "$env:APPDATA\Script_Logs\RestartToast\SnoozedAlertSchedule.log" -ErrorAction SilentlyContinue
    }
    $toasts = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app)
    $notifications = $toasts.GetScheduledToastNotifications()
    $snoozedTimes = $notifications.deliverytime | Where-Object { $_.localdatetime -ge (get-date) } | Select-Object -ExpandProperty localdatetime | Sort-Object
    $null = "[" + $timeStamp + "]: Displayed reboot notification to user." | Out-File -FilePath "$env:APPDATA\Script_Logs\RestartToast\SnoozedAlertSchedule.log" -Append
    if ($null -ne $snoozedTimes) {
        $null = "[" + $timeStamp + "]: Found snoozed toast notifications. Toast will be displayed again at the following time(s)." | Out-File -FilePath "$env:APPDATA\Script_Logs\RestartToast\SnoozedAlertSchedule.log" -Append
        $null = $snoozedTimes | Out-File -FilePath "$env:APPDATA\Script_Logs\RestartToast\SnoozedAlertSchedule.log" -Append #-ErrorAction SilentlyContinue
    }
}

# Create Display-ToastNotification function
# Updated in version 2.2.0
function Display-ToastNotification() {
    try {
        if ($isSystem -eq $true) {
            Write-Log -Message "Confirmed SYSTEM context before displaying toast"
            # is running under SYSTEM context
            # show notification to all logged on users
            & (Join-Path -Path $global:CustomScriptsPath -ChildPath "InvokePSScriptAsUser.ps1") "$PSCommandPath" "$Config"
        } 
        else {
            Write-Log -Message "Confirmed USER context before displaying toast"
            # is running under user context
            $Load = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
            $Load = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
            # Load the notification into the required format
            $ToastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
            $ToastXml.LoadXml($Toast.OuterXml)
            # Display the toast notification
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($App).Show($ToastXml)
        }
        Write-Log -Message "All good. Toast notification was displayed"
        # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
        Write-Output "All good. Toast notification was displayed"
        if ($CustomAudio -eq "True") {
            Invoke-Command -ScriptBlock {
                Add-Type -AssemblyName System.Speech
                $speak = New-Object System.Speech.Synthesis.SpeechSynthesizer
                Start-Sleep 1.25
                $speak.SelectVoiceByHints("female", 65)
                $speak.Speak($CustomAudioTextToSpeech)
                $speak.Dispose()
            }    
        }
        # Saving time stamp of when toast notification was run into registry
        Save-NotificationLastRunTime
        Start-Sleep 5
        Get-SnoozedToasts
        Exit 0
    }
    catch { 
        Write-Log -Message "Something went wrong when displaying the toast notification" -Level Error
        Write-Log -Message "Make sure the script is running as the logged on user" -Level Error
        # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
        Write-Output "Something went wrong when displaying the toast notification. Make sure the script is running as the logged on user"
        Exit 1 
    }
}

# Create Test-NTSystem function
# Testing to see if the script is being run as SYSTEM
# Updated in version 2.2.0
function Test-NTSystem() {  
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($currentUser.IsSystem -eq $true) {
        Write-Log -Message "Script is initially running in SYSTEM context. Please be vary, that this has limitations and may not work!"
        $true  
    }
    elseif ($currentUser.IsSystem -eq $false) {
        Write-Log -Message "Script is initially running in USER context"
        $false
    }
}

# Create Write-CustomActionRegistry function
# This function creates custom protocols for the logged on user in HKCU. 
# This will remove the need to create the protocols outside of the toast notification script
# HUGE shout-out to Chad Brower // @Brower_Cha on Twitter
# Added in version 2.0.0
function Write-CustomActionRegistry() {
    [CmdletBinding()]
    param (
        [Parameter(Position = "0")]
        [ValidateSet("ToastRunApplicationID", "ToastRunPackageID", "ToastRunUpdateID", "ToastReboot", "ToastDismiss")]
        [string]$ActionType,
        [Parameter(Position = "1")]
        [string]$RegCommandPath = $global:CustomScriptsPath
    )
    Write-Log -Message "Running Write-CustomActionRegistry function: $ActionType"
    switch ($ActionType) {
        ToastReboot { 
            # Build out registry for custom action for rebooting the device via the action button
            try { 
                New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                $RegCommandValue = $RegCommandPath + '\' + "$($ActionType).cmd"
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-Log -Level Error "Failed to create the $ActionType custom protocol in HKCU\Software\Classes. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
        ToastDismiss { 
            # Build out registry for custom action for rebooting the device via the action button
            try { 
                New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                $RegCommandValue = $RegCommandPath + '\' + "$($ActionType).cmd"
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-Log -Level Error "Failed to create the $ActionType custom protocol in HKCU\Software\Classes. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }

        ToastRunUpdateID { 
            # Build out registry for custom action for running software update via the action button
            try { 
                New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                $RegCommandValue = $RegCommandPath + '\' + "$($ActionType).cmd"
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-Log -Level Error "Failed to create the $ActionType custom protocol in HKCU\Software\Classes. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
        ToastRunPackageID { 
            # Build out registry for custom action for running packages and task sequences via the action button
            try { 
                New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                $RegCommandValue = $RegCommandPath + '\' + "$($ActionType).cmd"
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-Log -Level Error "Failed to create the $ActionType custom protocol in HKCU\Software\Classes. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
        ToastRunApplicationID { 
            # Build out registry for custom action for running applications via the action button
            try { 
                New-Item "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)" -Name '(default)' -Value "URL:$($ActionType) Protocol" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
                $RegCommandValue = $RegCommandPath + '\' + "$($ActionType).cmd"
                New-ItemProperty -LiteralPath "HKCU:\Software\Classes\$($ActionType)\shell\open\command" -Name '(default)' -Value $RegCommandValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                Write-Log -Level Error "Failed to create the $ActionType custom protocol in HKCU\Software\Classes. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
    }
}

# Create Write-CustomActionScript function
# This function creates the custom scripts in ProgramData\ToastNotificationScript which is used to carry out custom protocol actions
# HUGE shout-out to Chad Brower // @Brower_Cha on Twitter
# Added in version 2.0.0
# Updated in version 2.2.0
function Write-CustomActionScript() {
    [CmdletBinding()]
    param (
        [Parameter(Position = "0")]
        [ValidateSet("ToastRunApplicationID", "ToastRunPackageID", "ToastRunUpdateID", "ToastReboot", "ToastDismiss", "InvokePSScriptAsUser")]
        [string]$Type,
        [Parameter(Position = "1")]
        [String]$Path = $global:CustomScriptsPath
    )
    Write-Log -Message "Running Write-CustomActionScript function: $Type"
    switch ($Type) {
        # Create custom scripts for running software updates via the action button
        ToastRunUpdateID {
            try {
                $CMDFileName = $Type + '.cmd'
                $CMDFilePath = $Path + '\' + $CMDFileName
                try {
                    New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File `"$global:CustomScriptsPath\ToastRunUpdateID.ps1`""
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            try {
                $PS1FileName = $Type + '.ps1'
                $PS1FilePath = $Path + '\' + $PS1FileName
                try {
                    New-item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = @'
$RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript"
$UpdateID = (Get-ItemProperty -Path $RegistryPath -Name "RunUpdateID").RunUpdateID
$TestUpdateID = Get-WmiObject -Namespace ROOT\ccm\ClientSDK -Query "SELECT * FROM CCM_SoftwareUpdate WHERE UpdateID = '$UpdateID'"
if (-NOT[string]::IsNullOrEmpty($TestUpdateID)) {
    Invoke-WmiMethod -Namespace ROOT\ccm\ClientSDK -Class CCM_SoftwareUpdatesManager -Name InstallUpdates -ArgumentList (,$TestUpdateID)
    if (Test-Path -Path "$env:windir\CCM\ClientUX\SCClient.exe") { Start-Process -FilePath "$env:windir\CCM\ClientUX\SCClient.exe" -ArgumentList "SoftwareCenter:Page=Updates" -WindowStyle Maximized }
}
exit 0
'@
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            # Do not run another type; break
            Break
        }
        # Create dismiss button action to write log if users click dismiss button
        ToastDismiss {
            try {
                $CMDFileName = $Type + '.cmd'
                $CMDFilePath = $Path + '\' + $CMDFileName
                try {
                    New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                }
                catch {
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"              
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    #[String]$Script = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File `"$global:CustomScriptsPath\ToastDismiss.ps1`""
                    [String]$Script = "echo User clicked the dismiss button on %date% at %time% >> %appdata%\Script_Logs\RestartToast\UserDismissed.log"
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            try {
                $PS1FileName = $Type + '.ps1'
                $PS1FilePath = $Path + '\' + $PS1FileName
                try {
                    New-item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = @'
$timeStamp = Get-Date -Format "MM/dd/yyyy HH:mm"
$DismissLogFile = "$env:appdata\Script_Logs\RestartToast\UserDismissed.log"
$null = "[" + $timeStamp + "]: User clicked the dismiss button." | Out-File -FilePath $DismissLogFile -Append
exit 0
'@
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }#>
            # Do not run another type; break
            Break
        }
       
        # Create custom script for rebooting the device directly from the action button #>
        ToastReboot {
            try {
                $CMDFileName = $Type + '.cmd'
                $CMDFilePath = $Path + '\' + $CMDFileName
                try {
                    New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                }
                catch {
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"              
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = 'shutdown /r /t 120 /d p:0:0'
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            # Do not run another type; break
            Break
        }
        # Script output updated in 2.0.1 to dynamically pick up the Program ID. 
        # Previously this was hard coded to '*', making it work for task sequences only. Now also works for regular packages (only one program).
        # Create custom scripts to run packages and task sequences directly from the action button
        ToastRunPackageID {
            try {
                $CMDFileName = $Type + '.cmd'
                $CMDFilePath = $Path + '\' + $CMDFileName
                try {
                    New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File `"$global:CustomScriptsPath\ToastRunPackageID.ps1`""
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            try {
                $PS1FileName = $Type + '.ps1'
                $PS1FilePath = $Path + '\' + $PS1FileName
                try {
                    New-item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = @'
$RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript"
$PackageID = (Get-ItemProperty -Path $RegistryPath -Name "RunPackageID").RunPackageID
$TestPackageID = Get-WmiObject -Namespace ROOT\ccm\ClientSDK -Query "SELECT * FROM CCM_Program where PackageID = '$PackageID'"
if (-NOT[string]::IsNullOrEmpty($TestPackageID)) {
    $ProgramID = $TestPackageID.ProgramID
    ([wmiclass]'ROOT\ccm\ClientSDK:CCM_ProgramsManager').ExecuteProgram($ProgramID,$PackageID)
    if (Test-Path -Path "$env:windir\CCM\ClientUX\SCClient.exe") { Start-Process -FilePath "$env:windir\CCM\ClientUX\SCClient.exe" -ArgumentList "SoftwareCenter:Page=OSD" -WindowStyle Maximized }
}
exit 0
'@
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            # Do not run another type; break
            Break
        }
        # Create custom scripts to run applications directly from the action button
        ToastRunApplicationID {
            try {
                $CMDFileName = $Type + '.cmd'
                $CMDFilePath = $Path + '\' + $CMDFileName    
                try {
                    New-item -Path $Path -Name $CMDFileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = "powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -WindowStyle Hidden -File `"$global:CustomScriptsPath\ToastRunApplicationID.ps1`""
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }

            }
            catch {
                Write-Log -Level Error "Failed to create the custom .cmd script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            try {
                $PS1FileName = $Type + '.ps1'
                $PS1FilePath = $Path + '\' + $PS1FileName
                try {
                    New-item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
                }
                catch { 
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = @'
$RegistryPath = "HKCU:\SOFTWARE\ToastNotificationScript"
$ApplicationID = (Get-ItemProperty -Path $RegistryPath -Name "RunApplicationID").RunApplicationID
$TestApplicationID = Get-CimInstance -ClassName CCM_Application -Namespace ROOT\ccm\ClientSDK | Where-Object {$_.Id -eq $ApplicationID}
$AppArguments = @{
    Id = $TestApplicationID.Id
    IsMachineTarget = $TestApplicationID.IsMachineTarget
    Revision = $TestApplicationID.Revision
}
if (-NOT[string]::IsNullOrEmpty($TestApplicationID)) {
    if ($TestApplicationID.InstallState -eq "NotInstalled") { Invoke-CimMethod -Namespace "ROOT\ccm\clientSDK" -ClassName CCM_Application -MethodName Install -Arguments $AppArguments }
    elseif ($TestApplicationID.InstallState -eq "Installed") { Invoke-CimMethod -Namespace "ROOT\ccm\clientSDK" -ClassName CCM_Application -MethodName Repair -Arguments $AppArguments }
    elseif ($TestApplicationID.InstallState -eq "NotUpdated") { Invoke-CimMethod -Namespace "ROOT\ccm\clientSDK" -ClassName CCM_Application -MethodName Install -Arguments $AppArguments }
    if (Test-Path -Path "$env:windir\CCM\ClientUX\SCClient.exe") { Start-Process -FilePath "$env:windir\CCM\ClientUX\SCClient.exe" -ArgumentList "SoftwareCenter:Page=InstallationStatus" -WindowStyle Maximized }
}
exit 0
'@
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                }
                catch {
                    Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
            }
            catch {
                Write-Log -Level Error "Failed to create the custom .ps1 script for $Type. Action button might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
            # Do not run another type; break
            Break
        }
        InvokePSScriptAsUser {
            # create ps1 script that can invoke another script under all logged users (if started as SYSTEM)
            try {
                $PS1FileName = 'InvokePSScriptAsUser.ps1'
                try {
                    New-Item -Path $Path -Name $PS1FileName -Force -OutVariable PathInfo | Out-Null
                } 
                catch {
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }
                try {
                    $GetCustomScriptPath = $PathInfo.FullName
                    [String]$Script = @'
param($File, $argument)

$Source = @"
using System;
using System.Runtime.InteropServices;

namespace Runasuser
{
    public static class ProcessExtensions
    {
        #region Win32 Constants

        private const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const int CREATE_NO_WINDOW = 0x08000000;

        private const int CREATE_NEW_CONSOLE = 0x00000010;

        private const uint INVALID_SESSION_ID = 0xFFFFFFFF;
        private static readonly IntPtr WTS_CURRENT_SERVER_HANDLE = IntPtr.Zero;

        #endregion

        #region DllImports

        [DllImport("advapi32.dll", EntryPoint = "CreateProcessAsUser", SetLastError = true, CharSet = CharSet.Ansi, CallingConvention = CallingConvention.StdCall)]
        private static extern bool CreateProcessAsUser(
            IntPtr hToken,
            String lpApplicationName,
            String lpCommandLine,
            IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes,
            bool bInheritHandle,
            uint dwCreationFlags,
            IntPtr lpEnvironment,
            String lpCurrentDirectory,
            ref STARTUPINFO lpStartupInfo,
            out PROCESS_INFORMATION lpProcessInformation);

        [DllImport("advapi32.dll", EntryPoint = "DuplicateTokenEx")]
        private static extern bool DuplicateTokenEx(
            IntPtr ExistingTokenHandle,
            uint dwDesiredAccess,
            IntPtr lpThreadAttributes,
            int TokenType,
            int ImpersonationLevel,
            ref IntPtr DuplicateTokenHandle);

        [DllImport("userenv.dll", SetLastError = true)]
        private static extern bool CreateEnvironmentBlock(ref IntPtr lpEnvironment, IntPtr hToken, bool bInherit);

        [DllImport("userenv.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hSnapshot);

        [DllImport("kernel32.dll")]
        private static extern uint WTSGetActiveConsoleSessionId();

        [DllImport("Wtsapi32.dll")]
        private static extern uint WTSQueryUserToken(uint SessionId, ref IntPtr phToken);

        [DllImport("wtsapi32.dll", SetLastError = true)]
        private static extern int WTSEnumerateSessions(
            IntPtr hServer,
            int Reserved,
            int Version,
            ref IntPtr ppSessionInfo,
            ref int pCount);

        #endregion

        #region Win32 Structs

        private enum SW
        {
            SW_HIDE = 0,
            SW_SHOWNORMAL = 1,
            SW_NORMAL = 1,
            SW_SHOWMINIMIZED = 2,
            SW_SHOWMAXIMIZED = 3,
            SW_MAXIMIZE = 3,
            SW_SHOWNOACTIVATE = 4,
            SW_SHOW = 5,
            SW_MINIMIZE = 6,
            SW_SHOWMINNOACTIVE = 7,
            SW_SHOWNA = 8,
            SW_RESTORE = 9,
            SW_SHOWDEFAULT = 10,
            SW_MAX = 10
        }

        private enum WTS_CONNECTSTATE_CLASS
        {
            WTSActive,
            WTSConnected,
            WTSConnectQuery,
            WTSShadow,
            WTSDisconnected,
            WTSIdle,
            WTSListen,
            WTSReset,
            WTSDown,
            WTSInit
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        private enum SECURITY_IMPERSONATION_LEVEL
        {
            SecurityAnonymous = 0,
            SecurityIdentification = 1,
            SecurityImpersonation = 2,
            SecurityDelegation = 3,
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFO
        {
            public int cb;
            public String lpReserved;
            public String lpDesktop;
            public String lpTitle;
            public uint dwX;
            public uint dwY;
            public uint dwXSize;
            public uint dwYSize;
            public uint dwXCountChars;
            public uint dwYCountChars;
            public uint dwFillAttribute;
            public uint dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        private enum TOKEN_TYPE
        {
            TokenPrimary = 1,
            TokenImpersonation = 2
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WTS_SESSION_INFO
        {
            public readonly UInt32 SessionID;

            [MarshalAs(UnmanagedType.LPStr)]
            public readonly String pWinStationName;

            public readonly WTS_CONNECTSTATE_CLASS State;
        }

        #endregion

        // Gets the user token from the currently active session
        private static bool GetSessionUserToken(ref IntPtr phUserToken)
        {
            var bResult = false;
            var hImpersonationToken = IntPtr.Zero;
            var activeSessionId = INVALID_SESSION_ID;
            var pSessionInfo = IntPtr.Zero;
            var sessionCount = 0;

            // Get a handle to the user access token for the current active session.
            if (WTSEnumerateSessions(WTS_CURRENT_SERVER_HANDLE, 0, 1, ref pSessionInfo, ref sessionCount) != 0)
            {
                var arrayElementSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
                var current = pSessionInfo;

                for (var i = 0; i < sessionCount; i++)
                {
                    var si = (WTS_SESSION_INFO)Marshal.PtrToStructure((IntPtr)current, typeof(WTS_SESSION_INFO));
                    current += arrayElementSize;

                    if (si.State == WTS_CONNECTSTATE_CLASS.WTSActive)
                    {
                        activeSessionId = si.SessionID;
                    }
                }
            }

            // If enumerating did not work, fall back to the old method
            if (activeSessionId == INVALID_SESSION_ID)
            {
                activeSessionId = WTSGetActiveConsoleSessionId();
            }

            if (WTSQueryUserToken(activeSessionId, ref hImpersonationToken) != 0)
            {
                // Convert the impersonation token to a primary token
                bResult = DuplicateTokenEx(hImpersonationToken, 0, IntPtr.Zero,
                    (int)SECURITY_IMPERSONATION_LEVEL.SecurityImpersonation, (int)TOKEN_TYPE.TokenPrimary,
                    ref phUserToken);

                CloseHandle(hImpersonationToken);
            }

            return bResult;
        }

        public static bool StartProcessAsCurrentUser(string appPath, string cmdLine = null, string workDir = null, bool visible = true)
        {
            var hUserToken = IntPtr.Zero;
            var startInfo = new STARTUPINFO();
            var procInfo = new PROCESS_INFORMATION();
            var pEnv = IntPtr.Zero;
            int iResultOfCreateProcessAsUser;

            startInfo.cb = Marshal.SizeOf(typeof(STARTUPINFO));

            try
            {
                if (!GetSessionUserToken(ref hUserToken))
                {
                    throw new Exception("StartProcessAsCurrentUser: GetSessionUserToken failed.");
                }

                uint dwCreationFlags = CREATE_UNICODE_ENVIRONMENT | (uint)(visible ? CREATE_NEW_CONSOLE : CREATE_NO_WINDOW);
                startInfo.wShowWindow = (short)(visible ? SW.SW_SHOW : SW.SW_HIDE);
                startInfo.lpDesktop = "winsta0\\default";

                if (!CreateEnvironmentBlock(ref pEnv, hUserToken, false))
                {
                    throw new Exception("StartProcessAsCurrentUser: CreateEnvironmentBlock failed.");
                }

                if (!CreateProcessAsUser(hUserToken,
                    appPath, // Application Name
                    cmdLine, // Command Line
                    IntPtr.Zero,
                    IntPtr.Zero,
                    false,
                    dwCreationFlags,
                    pEnv,
                    workDir, // Working directory
                    ref startInfo,
                    out procInfo))
                {
                    iResultOfCreateProcessAsUser = Marshal.GetLastWin32Error();
                    throw new Exception("StartProcessAsCurrentUser: CreateProcessAsUser failed.  Error Code -" + iResultOfCreateProcessAsUser);
                }

                iResultOfCreateProcessAsUser = Marshal.GetLastWin32Error();
            }
            finally
            {
                CloseHandle(hUserToken);
                if (pEnv != IntPtr.Zero)
                {
                    DestroyEnvironmentBlock(pEnv);
                }
                CloseHandle(procInfo.hThread);
                CloseHandle(procInfo.hProcess);
            }

            return true;
        }

    }
}
"@

# Load the custom type
Add-Type -ReferencedAssemblies 'System', 'System.Runtime.InteropServices' -TypeDefinition $Source -Language CSharp -ErrorAction Stop

# Run PS as user to display the message box
[Runasuser.ProcessExtensions]::StartProcessAsCurrentUser("$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe", " -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$File`" $argument") | Out-Null
'@
                    if (-NOT[string]::IsNullOrEmpty($Script)) {
                        Out-File -FilePath $GetCustomScriptPath -InputObject $Script -Encoding ASCII -Force
                    }
                } 
                catch {
                    Write-Log -Level Error "Failed to create the .ps1 script for $Type. Show notification if run under SYSTEM might not work"
                    $ErrorMessage = $_.Exception.Message
                    Write-Log -Level Error -Message "Error message: $ErrorMessage"
                }

            } 
            catch {
                Write-Log -Level Error "Failed to create the .ps1 script for $Type. Show notification if run under SYSTEM might not work"
                $ErrorMessage = $_.Exception.Message
                Write-Log -Level Error -Message "Error message: $ErrorMessage"
            }
        }
    }
}

# Create function to retrieve the last run time of the notification
# Added in version 2.2.0
function Get-NotificationLastRunTime() {
    $LastRunTime = (Get-ItemProperty $global:RegistryPath -Name LastRunTime -ErrorAction Ignore).LastRunTime
    $CurrentTime = Get-Date -Format s
    if (-NOT[string]::IsNullOrEmpty($LastRunTime)) {
        $Difference = ([datetime]$CurrentTime - ([datetime]$LastRunTime)) 
        $MinutesSinceLastRunTime = [math]::Round($Difference.TotalMinutes)
        Write-Log -Message "Toast notification was previously displayed $MinutesSinceLastRunTime minutes ago"
        $MinutesSinceLastRunTime
    }
}

# Create function to store the timestamp of the notification execution
# Added in version 2.2.0
function Save-NotificationLastRunTime() {
    $RunTime = Get-Date -Format s
    if (-NOT(Get-ItemProperty -Path $global:RegistryPath -Name LastRunTime -ErrorAction Ignore)) {
        New-ItemProperty -Path $global:RegistryPath -Name LastRunTime -Value $RunTime -Force | Out-Null
    }
    else {
        Set-ItemProperty -Path $global:RegistryPath -Name LastRunTime -Value $RunTime -Force | Out-Null
    }
}

# Create function to register custom notification app
# Added in version 2.3.0
# Bits and pieces kindly borrowed from Mr. Trevor Jones: smsagent.blog
function Register-CustomNotificationApp($fAppID, $fAppDisplayName) {
    Write-Log -Message "Running Register-NotificationApp function"
    $AppID = $fAppID
    $AppDisplayName = $fAppDisplayName
    # This removes the option to disable to toast notification
    [int]$ShowInSettings = 0
    # Adds an icon next to the display name of the notifyhing app
    [int]$IconBackgroundColor = 0
    $IconUri = "%SystemRoot%\ImmersiveControlPanel\images\logo.png"
    # Moved this into HKCU, in order to modify this directly from the toast notification running in user context
    $AppRegPath = "HKCU:\Software\Classes\AppUserModelId"
    $RegPath = "$AppRegPath\$AppID"
    try {
        if (-NOT(Test-Path $RegPath)) {
            New-Item -Path $AppRegPath -Name $AppID -Force | Out-Null
        }
        $DisplayName = Get-ItemProperty -Path $RegPath -Name DisplayName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
        if ($DisplayName -ne $AppDisplayName) {
            New-ItemProperty -Path $RegPath -Name DisplayName -Value $AppDisplayName -PropertyType String -Force | Out-Null
        }
        $ShowInSettingsValue = Get-ItemProperty -Path $RegPath -Name ShowInSettings -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ShowInSettings -ErrorAction SilentlyContinue
        if ($ShowInSettingsValue -ne $ShowInSettings) {
            New-ItemProperty -Path $RegPath -Name ShowInSettings -Value $ShowInSettings -PropertyType DWORD -Force | Out-Null
        }
        $IconUriValue = Get-ItemProperty -Path $RegPath -Name IconUri -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IconUri -ErrorAction SilentlyContinue
        if ($IconUriValue -ne $IconUri) {
            New-ItemProperty -Path $RegPath -Name IconUri -Value $IconUri -PropertyType ExpandString -Force | Out-Null
        }
        $IconBackgroundColorValue = Get-ItemProperty -Path $RegPath -Name IconBackgroundColor -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IconBackgroundColor -ErrorAction SilentlyContinue
        if ($IconBackgroundColorValue -ne $IconBackgroundColor) {
            New-ItemProperty -Path $RegPath -Name IconBackgroundColor -Value $IconBackgroundColor -PropertyType ExpandString -Force | Out-Null
        }
        Write-Log "Created registry entries for custom notification app: $fAppDisplayName"
    }
    catch {
        Write-Log -Message "Failed to create one or more registry entries for the custom notification app" -Level Error
        Write-Log -Message "Toast Notifications are usually not displayed if the notification app does not exist" -Level Error
    }
}
#endregion

#region Variables
# Setting global script version
$global:ScriptVersion = "5.0.0"
# Setting executing directory
#$global:ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
# Setting global custom action script location
$global:CustomScriptsPath = "$env:ProgramData\MDM_Scripts\RestartToast"
# Setting global registry path
$global:RegistryPath = "HKCU:\SOFTWARE\MDMRestartToast"
# Get running OS build
$RunningOS = try { Get-CimInstance -Class Win32_OperatingSystem | Select-Object BuildNumber } catch { Write-Log -Level Error -Message "Failed to get running OS build. This is used with the OSUpgrade option, which now might not work properly" }
# Get user culture for multilanguage support
$userCulture = try { (Get-Culture).Name } catch { Write-Log -Level Error -Message "Failed to get users local culture. This is used with the multilanguage option, which now might not work properly" }
# Setting the default culture to en-US. This will be the default language if MultiLanguageSupport is not enabled in the config
$defaultUserCulture = "en-US"
# Temporary location for images if images are hosted online on blob storage or similar
$LogoImageTemp = "$env:TEMP\ToastLogoImage.jpg"
$HeroImageTemp = "$env:TEMP\ToastHeroImage.jpg"
# Setting path to local images
#$ImagesPath = "file:///$global:ScriptPath/Images"

# Create a directory for writing logs at the user level
# Some of this script runs as the logged on user therefore we need a directory to write to with user permissions
$UserLog = "$env:APPDATA\Script_Logs\RestartToast"
if (test-path $UserLog) {
}
else {
    $null = New-Item -ItemType Directory $UserLog
}

# The UserDismissed and SnoozeLog are the only logs written to this location
$UserDismissLog = "$env:APPDATA\Script_Logs\RestartToast\UserDismissed.log"
$SnoozeLog = "$env:APPDATA\Script_Logs\RestartToast\SnoozedAlertSchedule.log"

# Create these log files if they don't already exist
if (test-path $SnoozeLog) {
}
else {
    $null = New-Item -ItemType File $SnoozeLog
}

if (test-path $UserDismissLog) {
}
else {
    $null = New-Item -ItemType File $UserDismissLog
}

#endregion

#region Main Process

# Check if the screen is currently locked and if so exit the script and it will try on its next cycle
if (Get-Process -name logonui -ErrorAction SilentlyContinue) {
    Write-Log -Message "Computer is currently locked" -Level Warn
    Write-Log -Message "Exiting script and will try again..." -Level Warn
    # Using write-output to send to remediations log in Intune
    Write-Output "Computer was locked.."
    Exit 0
}
else {
    Write-Log -Message "Computer unlocked and logged in with the following user profile: $env:USERNAME"
    # Check for active Teams or Zoom call before running toast notification
    if (Get-CallInfo) {
        Write-Log -Message "User is in an active Zoom or Teams call...will not display toast" -Level Warn
        # Using write-output to send to remediations log in Intune
        Write-Output "User is in an active Zoom or Teams call..."
        Exit 0
    }
    else {}
}

# If no config file is set as parameter, use the following. 
if (-NOT($Config)) {
    Write-Log -Message "No config file set as parameter. Using config file in script."
    $Embedded = "True"
    [xml]$Xml = @"
<Configuration>
	<Feature Name="Toast" Enabled="True" /> <!-- Enables or disables the entire toast notification -->
	<Feature Name="PendingRebootUptime" Enabled="True" />	<!-- Enables the toast for reminding users of restarting their device if it exceeds the uptime defined in MaxUptimeDays -->
	<Option Name="MaxUptimeDays" Value="0" />	<!-- When using the toast for checking for pending reboots. A reboot is considered pending if computer uptime exceeds the value set here -->
	<Option Name="PendingRebootUptimeText" Enabled="False" />	<!-- Adds an additional group to the toast with text about the uptime of the computer -->
	<Option Name="CreateScriptsAndProtocols" Enabled="True" /> <!-- Automatically create the needed custom scripts and protocols. This removes the need to do scripts and protocols outside of the script -->
	<Option Name="LimitToastToRunEveryMinutes" Enabled="False" Value="5" /> <!-- Prevents the toast notification from being displayed again within the defined value (in minutes) -->
	<Option Name="CustomNotificationApp" Enabled="True" Value="Action Required"/>	<!-- The app in Windows doing the actual notification - can't be both SoftwareCenter and Powershell -->
	<Option Name="LogoImageName" Value="" />  <!-- File name of the image shown as logo in the toast notoification  -->
	<Option Name="HeroImageName" Value="" /> <!-- File name of the image shown in the top of the toast notification -->	
	<Option Name="ActionButton1" Enabled="True" />	<!-- Enables or disables the action button. -->
	<Option Name="ActionButton2" Enabled="False" />	<!-- Enables or disables the action button. -->
	<Option Name="DismissButton" Enabled="False" />	<!-- Enables or disables the dismiss button. -->
	<Option Name="SnoozeButton" Enabled="True" /> <!-- Enabling this option will always enable action button and dismiss button -->
	<Option Name="Scenario" Type="reminder" />	<!-- Possible values are: reminder | short | long -->
	<Option Name="Action1" Value="ToastReboot:" />	<!-- Action taken when using the Action button. Can be any protocol in Windows -->
	<Option Name="Action2" Value="" />	<!-- Action taken when using the Action button. Can be any protocol in Windows -->
	<Option Name="Action3" Value="ToastDismiss:" />	<!-- Action taken when using an Action button. Can be any protocol in Windows -->
    <Text Option="GreetGivenName" Enabled="True" />	<!-- Displays the toast with a personal greeting using the users given name retrieved from AD. Will try retrieval from WMI of no local AD -->
	<en-US> <!-- Default fallback language. This language will be used if MultiLanguageSupport is set to False or if no matching language is found -->
        <Text Name="PendingRebootUptimeText">Your computer is required to restart due to having exceeded the maximum allowed uptime.</Text> <!-- Text used if the PendingRebootUptimeText Option is enabled -->
        <Text Name="CustomAudioTextToSpeech">Hey you - wake up. Your computer needs to restart. Do it now.</Text> <!-- Text to speech used if the CustomAudioTextToSpeech Option is enabled -->
        <Text Name="ActionButton1">Restart now</Text>  <!-- Text on the ActionButton if enabled -->
		<Text Name="ActionButton2">Learn More</Text>  <!-- Text on the ActionButton if enabled -->
        <Text Name="DismissButton">Dismiss</Text> <!-- Text on the DismissButton if enabled -->
        <Text Name="SnoozeButton">Snooze</Text> <!-- Text on the SnoozeButton if enabled -->
        <Text Name="AttributionText">IT Department</Text>
        <Text Name="HeaderText">Helpdesk kindly reminds you...</Text>
        <Text Name="TitleText">Restart Notification!</Text>
        <Text Name="BodyText1">For security and stability reasons, we recommend you restart your computer as soon as possible. Your device has been up for</Text>
        <Text Name="BodyText2">A restart will be enforced in</Text>
        <Text Name="SnoozeText">Click snooze to be reminded again in:</Text>
        <Text Name="GreetMorningText">Good morning</Text>
        <Text Name="GreetAfternoonText">Good afternoon</Text>
        <Text Name="GreetEveningText">Good evening</Text>
        <Text Name="MinutesText">Minutes</Text>
        <Text Name="HourText">Hour</Text>
        <Text Name="HoursText">Hours</Text>
        <Text Name="ComputerUptimeText">Computer uptime:</Text>
        <Text Name="ComputerUptimeDaysText">days</Text>
    </en-US>
</Configuration>
"@
}

# Create the global registry path for the toast notification script
if (-NOT(Test-Path -Path $global:RegistryPath)) {
    Write-Log -Message "ToastNotificationScript registry path not found. Creating it: $global:RegistryPath"
    try {
        New-Item -Path $global:RegistryPath -Force | Out-Null
    }
    catch { 
        Write-Log -Message "Failed to create the ToastNotificationScript registry path: $global:RegistryPath" -Level Error
        Write-Log -Message "This is required. Script will now exit" -Level Error
        Exit 1
    }
}

# Create the global path for the custom action scipts used by the custom action protocols
if (-NOT(Test-Path -Path $global:CustomScriptsPath)) {
    Write-Log -Message "CustomScriptPath not found. Creating it: $global:CustomScriptsPath"
    try {
        New-item -Path $global:CustomScriptsPath -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Log -Level Error -Message "Failed to create the CustomScriptPath folder: $global:CustomScriptsPath"
        Write-Log -Message "This is required. Script will now exit" -Level Error
        Exit 1
    }
}

# Testing for prerequisites
# Test if the script is being run on a supported version of Windows. Windows 10 AND workstation OS is required
$SupportedWindowsVersion = Get-WindowsVersion
if ($SupportedWindowsVersion -eq $False) {
    Write-Log -Message "Aborting script" -Level Error
    Exit 1
}

# Testing if script is being run as SYSTEM.
$isSystem = Test-NTSystem
if ($isSystem -eq $true) {
    Write-Log -Message "The toast notification script is being run as SYSTEM. This is not recommended, but can be required in certain situations"
    Write-Log -Message "Scripts and log file are now located in: C:\Windows\System32\config\systemprofile\AppData\Roaming\ToastNotificationScript"
}

# Testing for blockers of toast notifications in Windows
$WindowsPushNotificationsEnabled = Test-WindowsPushNotificationsEnabled
if ($WindowsPushNotificationsEnabled -eq $False) {
    Enable-WindowsPushNotifications
}

# Load config.xml
# Catering for when config.xml is hosted online on blob storage or similar
<# Loading the config.xml file here is relevant for when used with Endpoint Analytics in Intune
if (($Config.StartsWith("https://")) -OR ($Config.StartsWith("http://"))) {
    Write-Log -Message "Specified config file seems hosted [online]. Treating it accordingly"
    try { $testOnlineConfig = Invoke-WebRequest -Uri $Config -UseBasicParsing } catch { <# nothing to see here. Used to make webrequest silent }
<#    if ($testOnlineConfig.StatusDescription -eq "OK") {
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Encoding = [System.Text.Encoding]::UTF8
            $Xml = [xml]$webClient.DownloadString($Config)
            Write-Log -Message "Successfully loaded $Config"
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Log -Message "Error, could not read $Config" -Level Error
            Write-Log -Message "Error message: $ErrorMessage" -Level Error
            # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
            Write-Output "Error, could not read $Config. Error message: $ErrorMessage"
            Exit 1
        }
    }
    else {
        Write-Log -Level Error -Message "The provided URL to the config does not reply or does not come back OK"
        # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
        Write-Output "The provided URL to the config does not reply or does not come back OK"
        Exit 1
    }
}

# Catering for when config.xml is hosted locally or on fileshare
elseif (-NOT($Config.StartsWith("https://")) -OR (-NOT($Config.StartsWith("http://")))) {
    Write-Log -Message "Specified config file seems hosted [locally or fileshare]. Treating it accordingly"
    if($Embedded){
        Write-Log -Message "XML is embedded in script"

    }else{
    if (Test-Path -Path $Config) {
        try { 
            $Xml = [xml](Get-Content -Path $Config -Encoding UTF8)
            Write-Log -Message "Successfully loaded $Config"
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Write-Log -Message "Error, could not read $Config" -Level Error
            Write-Log -Message "Error message: $ErrorMessage" -Level Error
            Exit 1
        }
    }
    else {
        Write-Log -Level Error -Message "No config file found on the specified location [locally or fileshare]"
        Exit 1
    }
}}
else {
    Write-Log -Level Error -Message "Something about the config file is completely off"
    # Using Write-Output for sending status to IME log when used with Endpoint Analytics in Intune
    Write-Output "Something about the config file is completely off"
    Exit 1
}#>

# Load xml content into variables
if (-NOT[string]::IsNullOrEmpty($Xml)) {
    try {
        Write-Log -Message "Loading xml content into variables"
        # Load Toast Notification features 
        $ToastEnabled = $Xml.Configuration.Feature | Where-Object { $_.Name -like 'Toast' } | Select-Object -ExpandProperty 'Enabled'
        $PendingRebootUptime = $Xml.Configuration.Feature | Where-Object { $_.Name -like 'PendingRebootUptime' } | Select-Object -ExpandProperty 'Enabled'
        # Load Toast Notification options   
        $PendingRebootUptimeTextEnabled = $Xml.Configuration.Option | Where-Object { $_.Name -like 'PendingRebootUptimeText' } | Select-Object -ExpandProperty 'Enabled'
        $MaxUptimeDays = $Xml.Configuration.Option | Where-Object { $_.Name -like 'MaxUptimeDays' } | Select-Object -ExpandProperty 'Value'
        # Creating Scripts and Protocols
        # Added in version 2.0.0
        $CreateScriptsProtocolsEnabled = $Xml.Configuration.Option | Where-Object { $_.Name -like 'CreateScriptsAndProtocols' } | Select-Object -ExpandProperty 'Enabled'
        # Added in version 2.2.0
        $LimitToastToRunEveryMinutesEnabled = $Xml.Configuration.Option | Where-Object { $_.Name -like 'LimitToastToRunEveryMinutes' } | Select-Object -ExpandProperty 'Enabled'
        $LimitToastToRunEveryMinutesValue = $Xml.Configuration.Option | Where-Object { $_.Name -like 'LimitToastToRunEveryMinutes' } | Select-Object -ExpandProperty 'Value'
        # Custom app doing the notification
        # Added in version 2.3.0
        $CustomAppEnabled = $Xml.Configuration.Option | Where-Object { $_.Name -like 'CustomNotificationApp' } | Select-Object -ExpandProperty 'Enabled'
        $CustomAppValue = $Xml.Configuration.Option | Where-Object { $_.Name -like 'CustomNotificationApp' } | Select-Object -ExpandProperty 'Value'
        $CustomAudio = $Xml.Configuration.Option | Where-Object { $_.Name -like 'CustomAudio' } | Select-Object -ExpandProperty 'Enabled'
        $LogoImageFileName = $Xml.Configuration.Option | Where-Object { $_.Name -like 'LogoImageName' } | Select-Object -ExpandProperty 'Value'
        $HeroImageFileName = $Xml.Configuration.Option | Where-Object { $_.Name -like 'HeroImageName' } | Select-Object -ExpandProperty 'Value'
        # Rewriting image variables to cater for images being hosted online, as well as being hosted locally. 
        # Needed image including path in one variable
        if ((-NOT[string]::IsNullOrEmpty($LogoImageFileName)) -OR (-NOT[string]::IsNullOrEmpty($HeroImageFileName))) {
            $LogoImage = $ImagesPath + "/" + $LogoImageFileName
            $HeroImage = $ImagesPath + "/" + $HeroImageFileName
        }
        $Scenario = $Xml.Configuration.Option | Where-Object { $_.Name -like 'Scenario' } | Select-Object -ExpandProperty 'Type'
        $Action1 = $Xml.Configuration.Option | Where-Object { $_.Name -like 'Action1' } | Select-Object -ExpandProperty 'Value'
        $Action2 = $Xml.Configuration.Option | Where-Object { $_.Name -like 'Action2' } | Select-Object -ExpandProperty 'Value'
        $Action3 = $Xml.Configuration.Option | Where-Object { $_.Name -like 'Action3' } | Select-Object -ExpandProperty 'Value'
        $GreetGivenName = $Xml.Configuration.Text | Where-Object { $_.Option -like 'GreetGivenName' } | Select-Object -ExpandProperty 'Enabled'
        $MultiLanguageSupport = $Xml.Configuration.Text | Where-Object { $_.Option -like 'MultiLanguageSupport' } | Select-Object -ExpandProperty 'Enabled'
        # Load Toast Notification buttons
        $ActionButton1Enabled = $Xml.Configuration.Option | Where-Object { $_.Name -like 'ActionButton1' } | Select-Object -ExpandProperty 'Enabled'
        $ActionButton2Enabled = $Xml.Configuration.Option | Where-Object { $_.Name -like 'ActionButton2' } | Select-Object -ExpandProperty 'Enabled'
        $DismissButtonEnabled = $Xml.Configuration.Option | Where-Object { $_.Name -like 'DismissButton' } | Select-Object -ExpandProperty 'Enabled'
        $SnoozeButtonEnabled = $Xml.Configuration.Option | Where-Object { $_.Name -like 'SnoozeButton' } | Select-Object -ExpandProperty 'Enabled'
        # Multi language support
        if ($MultiLanguageSupport -eq "True") {
            Write-Log -Message "MultiLanguageSupport set to True. Current language culture is $userCulture. Checking for language support"
            # Check config xml if language support is added for the users culture
            if (-NOT[string]::IsNullOrEmpty($xml.Configuration.$userCulture)) {
                Write-Log -Message "Support for the users language culture found, localizing text using $userCulture"
                $XmlLang = $xml.Configuration.$userCulture
            }
            # Else fallback to using default language "en-US"
            elseif (-NOT[string]::IsNullOrEmpty($xml.Configuration.$defaultUserCulture)) {
                Write-Log -Message "No support for the users language culture found, using $defaultUserCulture as default fallback language"
                $XmlLang = $xml.Configuration.$defaultUserCulture
            }
        }
        # If multilanguagesupport is set to False use default language "en-US"
        elseif ($MultiLanguageSupport -eq "False") {
            $XmlLang = $xml.Configuration.$defaultUserCulture
        }
        # Regardless of whatever might happen, always use "en-US" as language
        else {
            $XmlLang = $xml.Configuration.$defaultUserCulture
        }
        # Load Toast Notification text
        $PendingRebootUptimeTextValue = $XmlLang.Text | Where-Object { $_.Name -like 'PendingRebootUptimeText' } | Select-Object -ExpandProperty '#text'
        $CustomAudioTextToSpeech = $XmlLang.Text | Where-Object { $_.Name -like 'CustomAudioTextToSpeech' } | Select-Object -ExpandProperty '#text'
        $ActionButton1Content = $XmlLang.Text | Where-Object { $_.Name -like 'ActionButton1' } | Select-Object -ExpandProperty '#text'
        $ActionButton2Content = $XmlLang.Text | Where-Object { $_.Name -like 'ActionButton2' } | Select-Object -ExpandProperty '#text'
        $ActionButton3Content = $XmlLang.Text | Where-Object { $_.Name -like 'ActionButton3' } | Select-Object -ExpandProperty '#text'
        $DismissButtonContent = $XmlLang.Text | Where-Object { $_.Name -like 'DismissButton' } | Select-Object -ExpandProperty '#text'
        $SnoozeButtonContent = $XmlLang.Text | Where-Object { $_.Name -like 'SnoozeButton' } | Select-Object -ExpandProperty '#text'
        $AttributionText = $XmlLang.Text | Where-Object { $_.Name -like 'AttributionText' } | Select-Object -ExpandProperty '#text'
        $HeaderText = $XmlLang.Text | Where-Object { $_.Name -like 'HeaderText' } | Select-Object -ExpandProperty '#text'
        $TitleText = $XmlLang.Text | Where-Object { $_.Name -like 'TitleText' } | Select-Object -ExpandProperty '#text'
        $BodyText1 = $XmlLang.Text | Where-Object { $_.Name -like 'BodyText1' } | Select-Object -ExpandProperty '#text'
        $BodyText2 = $XmlLang.Text | Where-Object { $_.Name -like 'BodyText2' } | Select-Object -ExpandProperty '#text'
        $SnoozeText = $XmlLang.Text | Where-Object { $_.Name -like 'SnoozeText' } | Select-Object -ExpandProperty '#text'
        $GreetMorningText = $XmlLang.Text | Where-Object { $_.Name -like 'GreetMorningText' } | Select-Object -ExpandProperty '#text'
        $GreetAfternoonText = $XmlLang.Text | Where-Object { $_.Name -like 'GreetAfternoonText' } | Select-Object -ExpandProperty '#text'
        $GreetEveningText = $XmlLang.Text | Where-Object { $_.Name -like 'GreetEveningText' } | Select-Object -ExpandProperty '#text'
        $MinutesText = $XmlLang.Text | Where-Object { $_.Name -like 'MinutesText' } | Select-Object -ExpandProperty '#text'
        $HourText = $XmlLang.Text | Where-Object { $_.Name -like 'HourText' } | Select-Object -ExpandProperty '#text'
        $HoursText = $XmlLang.Text | Where-Object { $_.Name -like 'HoursText' } | Select-Object -ExpandProperty '#text'
        $ComputerUptimeText = $XmlLang.Text | Where-Object { $_.Name -like 'ComputerUptimeText' } | Select-Object -ExpandProperty '#text'
        $ComputerUptimeDaysText = $XmlLang.Text | Where-Object { $_.Name -like 'ComputerUptimeDaysText' } | Select-Object -ExpandProperty '#text'
        Write-Log -Message "Successfully loaded xml content from $Config"     
    }
    catch {
        Write-Log -Message "Xml content from $Config was not loaded properly"
        Exit 1
    }
}

# Check if toast is enabled in config.xml
if ($ToastEnabled -ne "True") {
    Write-Log -Message "Toast notification is not enabled. Please check $Config file"
    Exit 1
}

#region conflict checks 
#New checks for conflicting selections. Trying to prevent combinations which will make the toast render without buttons
# Added in version 2.1.0
if (($ActionButton2Enabled -eq "True") -AND ($SnoozeButtonEnabled -eq "True")) {
    Write-Log -Level Error -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Error -Message "You can't have ActionButton2 enabled and SnoozeButton enabled at the same time"
    Write-Log -Level Error -Message "That will result in too many buttons. Check your config"
    Exit 1
}
if (($SnoozeButtonEnabled -eq "True") -AND ($PendingRebootUptimeTextEnabled -eq "True")) {
    Write-Log -Level Error -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Error -Message "You can't have SnoozeButton enabled and have PendingRebootUptimeText enabled at the same time"
    Write-Log -Level Error -Message "That will result in too much text and the toast notification will render without buttons. Check your config"
    Exit 1
}
if (($SnoozeButtonEnabled -eq "True") -AND ($PendingRebootCheckTextEnabled -eq "True")) {
    Write-Log -Level Error -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Error -Message "You can't have SnoozeButton enabled and have PendingRebootCheckText enabled at the same time"
    Write-Log -Level Error -Message "That will result in too much text and the toast notification will render without buttons. Check your config"
    Exit 1
}
if (($SnoozeButtonEnabled -eq "True") -AND ($ADPasswordExpirationTextEnabled -eq "True")) {
    Write-Log -Level Error -Message "Error. Conflicting selection in the $Config file" 
    Write-Log -Level Error -Message "You can't have SnoozeButton enabled and have ADPasswordExpirationText enabled at the same time"
    Write-Log -Level Error -Message "That will result in too much text and the toast notification will render without buttons. Check your config"
    Exit 1
}
#endregion

# Added in 2.3.0
# This option enables you to create a custom app doing the notification. 
# This also completely prevents the user from disabling the toast from within the UI (can be done with registry editing, if one knows how)
if ($CustomAppEnabled -eq "True") {
    # Hardcoding the AppID. Only the display name is interesting, thus this comes from the config.xml
    $App = "Toast.Custom.App"
    Register-CustomNotificationApp -fAppID $App -fAppDisplayName $CustomAppValue
}

<# Added in version 2.2.0
# This option is able to prevent multiple toast notification from being displayed in a row
if ($LimitToastToRunEveryMinutesEnabled -eq "True") {
    $LastRunTimeOutput = Get-NotificationLastRunTime
    if (-NOT[string]::IsNullOrEmpty($LastRunTimeOutput)) {
        if ($LastRunTimeOutput -lt $LimitToastToRunEveryMinutesValue) {
            Write-Log -Level Error -Message "Toast notification was displayed too recently"
            Write-Log -Level Error -Message "Toast notification was displayed $LastRunTimeOutput minutes ago and the config.xml is configured to allow $LimitToastToRunEveryMinutesValue minutes intervals"
            Write-Log -Level Error -Message "This is done to prevent ConfigMgr catching up on missed schedules, and thus display multiple toasts of the same appearance in a row"
            break   
        }    
    }
}#>

# Downloading images into user's temp folder if images are hosted online
if (($LogoImageFileName.StartsWith("https://")) -OR ($LogoImageFileName.StartsWith("http://"))) {
    Write-Log -Message "ToastLogoImage appears to be hosted online. Will need to download the file"
    # Testing to see if image at the provided URL indeed is available
    try { $testOnlineLogoImage = Invoke-WebRequest -Uri $LogoImageFileName -UseBasicParsing } catch { <# nothing to see here. Used to make webrequest silent #> }
    if ($testOnlineLogoImage.StatusDescription -eq "OK") {
        try {
            Invoke-WebRequest -Uri $LogoImageFileName -OutFile $LogoImageTemp
            # Replacing image variable with the image downloaded locally
            $LogoImage = $LogoImageTemp
            Write-Log -Message "Successfully downloaded $LogoImageTemp from $LogoImageFileName"
        }
        catch { 
            Write-Log -Level Error -Message "Failed to download the $LogoImageTemp from $LogoImageFileName"
        }
    }
    else {
        Write-Log -Level Error -Message "The picture supposedly located on $LogoImageFileName is not available"
    }
}
if (($HeroImageFileName.StartsWith("https://")) -OR ($HeroImageFileName.StartsWith("http://"))) {
    Write-Log -Message "ToastHeroImage appears to be hosted online. Will need to download the file"
    # Testing to see if image at the provided URL indeed is available
    try { $testOnlineHeroImage = Invoke-WebRequest -Uri $HeroImageFileName -UseBasicParsing } catch { <# nothing to see here. Used to make webrequest silent #> }
    if ($testOnlineHeroImage.StatusDescription -eq "OK") {
        try {
            Invoke-WebRequest -Uri $HeroImageFileName -OutFile $HeroImageTemp
            # Replacing image variable with the image downloaded locally
            $HeroImage = $HeroImageTemp
            Write-Log -Message "Successfully downloaded $HeroImageTemp from $HeroImageFileName"
        }
        catch { 
            Write-Log -Level Error -Message "Failed to download the $HeroImageTemp from $HeroImageFileName"
        }
    }
    else {
        Write-Log -Level Error -Message "The image supposedly located on $HeroImageFileName is not available"
    }
}

# Creating custom scripts and protocols if enabled in the config
if ($CreateScriptsProtocolsEnabled -eq "True") {
    $RegistryName = "ScriptsAndProtocolsVersion"
    Write-Log -Message "CreateScriptsAndProtocols set to True. Will allow creation of scripts and protocols"
    # Testing to see if the global registry path exist. It should, because it was created earlier
    if (Test-Path -Path $global:RegistryPath) {
        # Creating the registry key used to determine if scripts and protocols should be created
        # If it does not exist already, create the key with a value of '0'
        if (((Get-Item -Path $global:RegistryPath -ErrorAction SilentlyContinue).Property -contains $RegistryName) -ne $true) {
            New-ItemProperty -Path $global:RegistryPath -Name $RegistryName -Value "0" -PropertyType "String" -Force | Out-Null
        }
        if (((Get-Item -Path $global:RegistryPath -ErrorAction SilentlyContinue).Property -contains $RegistryName) -eq $true) {
            # If the registry key exist, but has a value less than the script version, go ahead and create scripts and protocols
            if ((Get-ItemProperty -Path $global:RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue).$RegistryName -lt $global:ScriptVersion) {
                Write-Log -Message "Registry value of $RegistryName does not match Script version: $global:ScriptVersion"
                try {
                    Write-Log -Message "Creating scripts and protocols for the logged on user"
                    Write-CustomActionRegistry -ActionType ToastReboot
                    Write-CustomActionRegistry -ActionType ToastDismiss
                    Write-CustomActionRegistry -ActionType ToastRunApplicationID
                    Write-CustomActionRegistry -ActionType ToastRunPackageID
                    Write-CustomActionRegistry -ActionType ToastRunUpdateID
                    Write-CustomActionScript -Type ToastReboot
                    Write-CustomActionScript -Type ToastDismiss
                    Write-CustomActionScript -Type ToastRunApplicationID
                    Write-CustomActionScript -Type ToastRunPackageID
                    Write-CustomActionScript -Type ToastRunUpdateID
                    Write-CustomActionScript -Type InvokePSScriptAsUser
                    New-ItemProperty -Path $global:RegistryPath -Name $RegistryName -Value $global:ScriptVersion -PropertyType "String" -Force | Out-Null
                }
                catch { 
                    Write-Log -Level Error -Message "Something failed during creation of custom scripts and protocols"
                }
            }
            elseif ((Get-ItemProperty -Path $global:RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue).$RegistryName -ge $global:ScriptVersion) {
                Write-Log -Message "Script version: $global:ScriptVersion matches value of $RegistryName in registry. Not creating custom scripts and protocols"
            }
        }
    }
}

# Check current device uptime
if ($PendingRebootUptime -eq "True") {
    $Uptime = Get-DeviceUptime
    Write-Log -Message "PendingRebootUptime set to True. Checking for device uptime. Current uptime is: $Uptime days"
}

# Check for required entries in registry for when using Custom App as application for the toast
if ($CustomAppEnabled -eq "True") {
    # Path to the notification app doing the actual toast
    $RegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    # For clarity, declaring the App variables once again
    $App = "Toast.Custom.App"
    # Creating registry entries if they don't exists
    if (-NOT(Test-Path -Path $RegPath\$App)) {
        New-Item -Path $RegPath\$App -Force
        New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 0 -PropertyType "DWORD"
        New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
        New-ItemProperty -Path $RegPath\$App -Name "SoundFile" -PropertyType "STRING" -Force
    }
    # Make sure the app used with the action center is enabled
    if ((Get-ItemProperty -Path $RegPath\$App -Name "Enabled" -ErrorAction SilentlyContinue).Enabled -ne "1") {
        New-ItemProperty -Path $RegPath\$App -Name "Enabled" -Value 1 -PropertyType "DWORD" -Force
    }    
    if ((Get-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -ErrorAction SilentlyContinue).ShowInActionCenter -ne "0") {
        New-ItemProperty -Path $RegPath\$App -Name "ShowInActionCenter" -Value 0 -PropertyType "DWORD" -Force
    }
    # Added to not play any sounds when notification is displayed with scenario: alarm
    if (-NOT(Get-ItemProperty -Path $RegPath\$App -Name "SoundFile" -ErrorAction SilentlyContinue)) {
        New-ItemProperty -Path $RegPath\$App -Name "SoundFile" -PropertyType "STRING" -Force
    }
}

# Checking if running toast with personal greeting with given name
if ($GreetGivenName -eq "True") {
    Write-Log -Message "Greeting with given name selected. Replacing HeaderText"
    $Hour = (Get-Date).TimeOfDay.Hours
    if (($Hour -ge 0) -AND ($Hour -lt 12)) {
        Write-Log -Message "Greeting with $GreetMorningText"
        $Greeting = $GreetMorningText
    }
    elseif (($Hour -ge 12) -AND ($Hour -lt 16)) {
        Write-Log -Message "Greeting with $GreetAfternoonText"
        $Greeting = $GreetAfternoonText
    }
    else {
        Write-Log -Message "Greeting with personal greeting: $GreetEveningText"
        $Greeting = $GreetEveningText
    }
    $GivenName = Get-GivenName
    $HeaderText = "$Greeting $GivenName"
}

# Formatting the toast notification XML
# Create the default toast notification XML with action button and dismiss button
if (($ActionButton1Enabled -eq "True") -AND ($DismissButtonEnabled -eq "True")) {
    Write-Log -Message "Creating the xml for action button and dismiss button"
    [xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="protocol" arguments="$Action1" content="$ActionButton1Content" />
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# NO action button and NO dismiss button
if (($ActionButton1Enabled -ne "True") -AND ($DismissButtonEnabled -ne "True")) {
    Write-Log -Message "Creating the xml for no action button and no dismiss button"
    [xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
    </actions>
</toast>
"@
}

# Action button and NO dismiss button
if (($ActionButton1Enabled -eq "True") -AND ($DismissButtonEnabled -ne "True")) {
    Write-Log -Message "Creating the xml for no dismiss button"
    [xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="protocol" arguments="$Action1" content="$ActionButton1Content" />
    </actions>
</toast>
"@
}

## Get uptime difference
$rebootDaysLeft = 8 - $Uptime

# Dismiss button and NO action button
if (($ActionButton1Enabled -ne "True") -AND ($DismissButtonEnabled -eq "True")) {
    Write-Log -Message "Creating the xml for no action button"
    [xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# Action button2 - this option will always enable both actionbutton1, actionbutton2 and dismiss button regardless of config settings
if ($ActionButton2Enabled -eq "True") {
    Write-Log -Message "Creating the xml for displaying the second action button: actionbutton2"
    Write-Log -Message "This will always enable both action buttons and the dismiss button" -Level Warn
    Write-Log -Message "Replacing any previous formatting of the toast xml" -Level Warn
    [xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <action activationType="protocol" arguments="$Action1" content="$ActionButton1Content" />
        <action activationType="protocol" arguments="$Action2" content="$ActionButton2Content" />
        <action activationType="system" arguments="dismiss" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# Snooze button - this option will always enable actionbutton1, snooze button and dismiss button regardless of config settings
if ($SnoozeButtonEnabled -eq "True") {
    Write-Log -Message "Creating the xml for displaying the snooze button"
    Write-Log -Message "This will always enable the action button as well as the dismiss button" -Level Warn
    Write-Log -Message "Replacing any previous formatting of the toast xml" -Level Warn
    [xml]$Toast = @"
<toast scenario="$Scenario">
    <visual>
    <binding template="ToastGeneric">
        <image placement="hero" src="$HeroImage"/>
        <image id="1" placement="appLogoOverride" hint-crop="circle" src="$LogoImage"/>
        <text placement="attribution">$AttributionText</text>
        <text>$HeaderText</text>
        <group>
            <subgroup>
                <text hint-style="title" hint-wrap="true">$TitleText</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText1 $uptime days.</text>
            </subgroup>
        </group>
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true">$BodyText2 $rebootDaysLeft days.</text>
            </subgroup>
        </group>
    </binding>
    </visual>
    <actions>
        <input id="snoozeTime" type="selection" title="$SnoozeText" defaultInput="15">
            <selection id="15" content="15 $MinutesText"/>
            <selection id="30" content="30 $MinutesText"/>
            <selection id="60" content="1 $HourText"/>
            <selection id="240" content="4 $HoursText"/>
            <selection id="480" content="8 $HoursText"/>
        </input>
        <action activationType="protocol" arguments="$Action1" content="$ActionButton1Content" />
        <action activationType="system" arguments="snooze" hint-inputId="snoozeTime" content="$SnoozeButtonContent"/>
        <action activationType="protocol" arguments="$Action3" content="$DismissButtonContent"/>
    </actions>
</toast>
"@
}

# Add an additional group and text to the toast xml used for notifying about computer uptime. Only add this if the computer uptime exceeds MaxUptimeDays.
if (($PendingRebootUptimeTextEnabled -eq "True") -AND ($Uptime -gt $MaxUptimeDays)) {
    $UptimeGroup = @"
        <group>
            <subgroup>     
                <text hint-style="body" hint-wrap="true" >$PendingRebootUptimeTextValue</text>
            </subgroup>
        </group>
        <group>
            <subgroup>
                <text hint-style="base" hint-align="left">$ComputerUptimeText $Uptime $ComputerUptimeDaysText</text>
            </subgroup>
        </group>
"@
    $Toast.toast.visual.binding.InnerXml = $Toast.toast.visual.binding.InnerXml + $UptimeGroup
}

# Toast used for PendingReboot check and considering OS uptime
if (($PendingRebootUptime -eq "True") -AND ($Uptime -gt $MaxUptimeDays)) {
    Write-Log -Message "Toast notification is used in regards to pending reboot. Uptime count is greater than $MaxUptimeDays"
    Display-ToastNotification
    # Stopping script. No need to accidently run further toasts
    break
}
else {
    Write-Log -Level Warn -Message "Conditions for displaying toast notifications for pending reboot uptime are not fulfilled"
}

# Toast not used for either OS upgrade or Pending reboot OR ADPasswordExpiration. Run this if all features are set to false in config.xml
if (($UpgradeOS -ne "True") -AND ($PendingRebootCheck -ne "True") -AND ($PendingRebootUptime -ne "True") -AND ($ADPasswordExpiration -ne "True")) {
    Write-Log -Message "Toast notification is not used in regards to OS upgrade OR Pending Reboots OR ADPasswordExpiration. Displaying default toast"
    Display-ToastNotification
    # Stopping script. No need to accidently run further toasts
    break
}
else {
    Write-Log -Level Warn -Message "Conditions for displaying default toast notification are not fulfilled"
}

#endregion
