function Log() {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $false)] [String] $message
	)
	$ts = get-date -f "yyyy/MM/dd HH:mm:ss"
	Write-Output "$ts $message"
}
function IsOOBEcomplete() {
	$TypeDef = @"

	using System;
	using System.Text;
	using System.Collections.Generic;
	using System.Runtime.InteropServices;

	namespace Api
	{
	 public class Kernel32
	 {
	   [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
	   public static extern int OOBEComplete(ref int bIsOOBEComplete);
	 }
	}
"@
	 
	Add-Type -TypeDefinition $TypeDef -Language CSharp
	 
	$IsOOBEComplete = $false
	$null = [Api.Kernel32]::OOBEComplete([ref] $IsOOBEComplete)
	 
	if ($IsOOBEComplete -eq 1) { return $true }
	else { return $false }
}
function Invoke-UnzipAndCopy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SourceZipFilePath,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$DestinationFolder
    )

    try {
        # Ensure the source file exists
        if (-not (Test-Path -Path $SourceZipFilePath)) {
            Write-Error "The source zip file '$SourceZipFilePath' does not exist."
            return
        }

        # Ensure the destination folder exists, create it if not
        if (-not (Test-Path -Path $DestinationFolder)) {
            Write-Verbose "Creating destination folder: $DestinationFolder"
            New-Item -ItemType Directory -Path $DestinationFolder | Out-Null
        }

        # Extract the zip file
        Write-Verbose "Extracting zip file '$SourceZipFilePath' to '$DestinationFolder'"
        Expand-Archive -Path $SourceZipFilePath -DestinationPath $DestinationFolder -Force

        Write-Output "Successfully extracted '$SourceZipFilePath' to '$DestinationFolder'."
    }
    catch {
        Write-Error "An error occurred: $_"
    }
}

# If we are running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64") {
	if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
		& "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy bypass -NoProfile -File "$PSCommandPath"
		Exit $lastexitcode
	}
}

# Check if PC is currently running through autopilot enrollment ESP/OOBE
# Exit script and mark package as installed by creating tag file if NOT in OOBE
$OOBEcheck = IsOOBEcomplete
if ($OOBEcheck -eq 'True') {
	Write-Output 'ESP not running, provisioning completed'
	# Create a tag file just so Intune knows this was installed
	if (-not (Test-Path "$($env:ProgramData)\Microsoft\AutopilotBranding")) {
		Mkdir "$($env:ProgramData)\Microsoft\AutopilotBranding"
	}
	Set-Content -Path "$($env:ProgramData)\Microsoft\AutopilotBranding\AutopilotBranding.ps1.tag" -Value "Installed"
	Exit 0
}
else {
	# Start logging
	Start-Transcript "$($env:ProgramData)\Microsoft\AutopilotBranding\AutopilotBranding.log"
	Log "ESP is currently running, will proceed with branding script."
}

# Get computer info (ci) variables
$ci = Get-ComputerInfo
$osName = $ci.OsName
$winVer = $ci.OsDisplayVersion
$buildNumber = $ci.OsBuildNumber
$osArch = $ci.OsArchitecture
Log "OS: $osName"
Log "Build: $winVer"

# Create a tag file just so Intune knows this was installed
if (-not (Test-Path "$($env:ProgramData)\Microsoft\AutopilotBranding")) {
	Mkdir "$($env:ProgramData)\Microsoft\AutopilotBranding"
}
Set-Content -Path "$($env:ProgramData)\Microsoft\AutopilotBranding\AutopilotBranding.ps1.tag" -Value "Installed"

# PREP: Load the Config.xml
$installFolder = "$PSScriptRoot\"
Log "Install folder: $installFolder"
Log "Loading configuration: $($installFolder)Config.xml"
[Xml]$config = Get-Content "$($installFolder)Config.xml"

# STEP 1: Apply custom start menu layout

if ($buildNumber -le 22000) {
	Log "Importing layout: $($installFolder)Layout.xml"
	Copy-Item "$($installFolder)Layout.xml" "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml" -Force
}
else {
	Log "Importing layout: $($installFolder)Start2.bin"
	MkDir -Path "C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState" -Force -ErrorAction SilentlyContinue | Out-Null
	Copy-Item "$($installFolder)Start2.bin" "C:\Users\Default\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\Start2.bin" -Force
}

# STEP 2: Copy background image and other files that are used by the script to the device
Log "Setting up Autopilot theme"
Mkdir "C:\Windows\Resources\OEM Themes" -Force | Out-Null
Copy-Item "$installFolder\Autopilot.theme" "C:\Windows\Resources\OEM Themes\Autopilot.theme" -Force
Mkdir "C:\Windows\web\wallpaper\Autopilot" -Force | Out-Null
Copy-Item "$installFolder\Wallpaper.jpg" "C:\Windows\web\wallpaper\Autopilot\Wallpaper.jpg" -Force
Copy-Item "$installFolder\Set-Wallpaper.xml" "C:\Programdata\Microsoft\AutopilotBranding\Set-Wallpaper.xml"
Copy-Item "$installFolder\wallpaper.vbs" "C:\Programdata\Microsoft\AutopilotBranding\wallpaper.vbs"
Copy-Item "$installFolder\Set-Wallpaper.ps1" "C:\Programdata\Microsoft\AutopilotBranding\Set-Wallpaper.ps1"

# Apply default theme
Log "Setting Autopilot theme as the new user default."
if ($buildNumber -le 22000) {
	reg.exe load HKLM\TempUser "C:\Users\Default\NTUSER.DAT" | Out-Host
	reg.exe add "HKLM\TempUser\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes" /v InstallTheme /t REG_EXPAND_SZ /d "%SystemRoot%\resources\OEM Themes\Autopilot.theme" /f | Out-Host
	reg.exe unload HKLM\TempUser | Out-Host
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes" /v InstallTheme /t REG_EXPAND_SZ /d "%SystemRoot%\resources\OEM Themes\Autopilot.theme" /f | Out-Host
	}
else {
	# Register scheduled task that sets the wallpaper on first login for any user
	Log "Windows 11 detected..."
	Log "Registering scheduled task to set default wallpaper on user logon."
	$null = Register-ScheduledTask -TaskName "Set-Wallpaper" -xml (Get-Content "$env:ProgramData\Microsoft\AutopilotBranding\Set-Wallpaper.xml" | Out-String) -Force
}

# STEP 3: Identify and set time zone
# Copy and import JSON file with IANA to Windows time zone conversions
Copy-Item "$installFolder\TimeConversion.JSON" "$($env:ProgramData)\Microsoft\AutopilotBranding\TimeConversion.JSON" -Force
$jsonFile = Get-Content "$($env:ProgramData)\Microsoft\AutopilotBranding\TimeConversion.JSON" -Raw
$timeZoneTable = $jsonFile | ConvertFrom-Json | Select-Object -ExpandProperty maptimezones | Select-Object -ExpandProperty mapZone

try {
	## Get IP Address of host
	Log "API: Get public IP"
	$myIP = (Invoke-WebRequest "https://api.ipify.org?format=json" -UseBasicParsing | ConvertFrom-Json).ip
	## Get information on the IP
	Log "API: Get IP information"
	$ipInfo = ((Invoke-WebRequest "http://ip-api.com/json/$myIP" -UseBasicParsing).content | ConvertFrom-JSON)
	## Store IP info into variables for use when renaming computer later
	$targetLatitude = [float]$ipInfo.lat
	$targetLongitude = [float]$ipInfo.lon
	$timezoneID = $ipInfo.timezone
	$country = $ipInfo.countryCode
	$region = $ipInfo.region
	Log "Latitude/Longitude: $targetLatitude , $targetLongitude"
	Log "Country/Region: $country - $region"
	Log "Timezone: $timezoneID"

	if ($null -ne $timezoneID) {
		$winTimeZone = ($timeZoneTable | Where-Object { $_.type -contains $timezoneid }).windows
		Log "Attempting to set timezone to: $winTimeZone"
		set-timezone -id $winTimeZone
		$tzID = (Get-TimeZone).Id
		if ($tzID -eq $winTimeZone) {
			Log "Timezone successfully set to: $winTimeZone"
		}
		else {
			Log "Timezone still set as: $tzID"
		}
	}
}
catch {
	Log "ERROR setting timezone."
}

# STEP 4: Remove specified provisioned apps if they exist
Log "Removing specified in-box provisioned apps"
$apps = Get-AppxProvisionedPackage -online
$config.Config.RemoveApps.App | ForEach-Object {
	$current = $_
	$apps | Where-Object { $_.DisplayName -eq $current } | ForEach-Object {
		try {
			Log "Removing provisioned app: $current"
			$_ | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
		}
		catch { }
	}
}

# STEP 5: Install OneDrive per machine
if ($osArch -like "*ARM*") {
	# OneDrive installer for ARM devices https://oneclient.sfx.ms/Win/Installers/24.226.1110.0004/arm64/OneDriveSetup.exe
	Log "ARM64 Processor detected."
	if ($config.Config.OneDriveSetup) {
		Log "Copying OneDriveSetupARM from install path."
		Invoke-UnzipAndCopy -SourceZipFilePath "$installFolder\OneDriveSetupARM.zip" -DestinationFolder "$($env:ProgramData)\Microsoft\AutopilotBranding"
		$dest = "$($env:ProgramData)\Microsoft\AutopilotBranding\OneDriveSetupARM.exe"
		Log "Installing: $dest"
		$proc = Start-Process $dest -ArgumentList "/allusers" -WindowStyle Hidden -PassThru
		$proc.WaitForExit()
		Log "OneDriveSetup exit code: $($proc.ExitCode)"
	}
}
else {
	if ($config.Config.OneDriveSetup) {
		Log "Copying OneDriveSetup from install path."
		Invoke-UnzipAndCopy -SourceZipFilePath "$installFolder\OneDriveSetup.zip" -DestinationFolder "$($env:ProgramData)\Microsoft\AutopilotBranding"
		$dest = "$($env:ProgramData)\Microsoft\AutopilotBranding\OneDriveSetup.exe"
		Log "Installing: $dest"
		$proc = Start-Process $dest -ArgumentList "/allusers" -WindowStyle Hidden -PassThru
		$proc.WaitForExit()
		Log "OneDriveSetup exit code: $($proc.ExitCode)"
	}
}

# STEP 6: Don't let Edge create a desktop shortcut (roams to OneDrive, creates mess)
Log "Turning off (old) Edge desktop shortcut"
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v DisableEdgeDesktopShortcutCreation /t REG_DWORD /d 1 /f /reg:64 | Out-Host

# STEP 7: Add language packs
Get-ChildItem "$($installFolder)LPs" -Filter *.cab | ForEach-Object {
	Log "Adding language pack: $($_.FullName)"
	Add-WindowsPackage -Online -NoRestart -PackagePath $_.FullName
}

# STEP 8: Change language
if ($config.Config.Language) {
	Log "Configuring language using: $($config.Config.Language)"
	& $env:SystemRoot\System32\control.exe "intl.cpl,,/f:`"$($installFolder)$($config.Config.Language)`""
}

# STEP 9: Add features on demand
$currentWU = (Get-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ErrorAction Ignore).UseWuServer
if ($currentWU -eq 1) {
	Log "Turning off WSUS"
	Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"  -Name "UseWuServer" -Value 0
	Restart-Service wuauserv
}

if ($config.Config.AddFeatures.Feature.Count -gt 0) {
	$config.Config.AddFeatures.Feature | ForEach-Object {
		Log "Adding Windows feature: $_"
		Add-WindowsCapability -Online -Name $_ -ErrorAction SilentlyContinue | Out-Null
	}
} 
if ($currentWU -eq 1) {
	Log "Turning on WSUS"
	Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"  -Name "UseWuServer" -Value 1
	Restart-Service wuauserv
}
#>

# STEP 10: Customize default apps
if ($config.Config.DefaultApps) {
	Log "Setting default apps: $($config.Config.DefaultApps)"
	& Dism.exe /Online /Import-DefaultAppAssociations:`"$($installFolder)$($config.Config.DefaultApps)`"
}

# STEP 11: Generate new PC name
Log "Attempting to rename computer"

## Generate a random string of 6 characters
## Define the character set: letters (uppercase only) and numbers
$chars = 'ABCDEFGHIJKLMNPQRSTUVWXYZ1234567890'

## Initialize the random number generator
$random = New-Object System.Random

## Generate the random string
$randomString = -join ((1..6) | ForEach-Object { $chars[$random.Next($chars.Length)] })

## Generate new PC name based on the information collected using the device IP
$newPCname = $country + "-" + $region + "-" + $randomString
Log "Renaming computer: $newPCname"
Rename-Computer -NewName $newPCname -Force

# STEP 12: Disable network location fly-out
Log "Turning off network location fly-out"
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" /f

# STEP 13: Disable new Edge desktop icon
Log "Turning off Edge desktop icon"
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "CreateDesktopShortcutDefault" /t REG_DWORD /d 0 /f /reg:64 | Out-Host

# STEP 14: Hide recommendations for tips, shortcuts, new apps, and more section from Start Menu 
# And prevent Start Menu from automatically opening when new user logs in
Log "Hiding recommended new apps and more section from Start menu"
reg.exe load HKLM\TempUser "C:\Users\Default\NTUSER.DAT" | Out-Host
reg.exe add "HKLM\TempUser\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Start_IrisRecommendations" /t REG_DWORD /d 0 /f | Out-Host
reg.exe add "HKLM\TempUser\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "StartShownOnUpgrade" /t REG_DWORD /d 1 /f | Out-Host
reg.exe unload HKLM\TempUser | Out-Host

Stop-Transcript

Exit 0

<## ADDITIONAL/TESTING CODE BELOW ##

#
# Funtion to calculate distance between 2 locations using latitude and longitude coordinates
function Get-GreatCircleDistance ( $Lat1, $Long1, $Lat2, $Long2 ) {
	#  Convert decimal degrees to radians
	$Lat1 = $Lat1 * [math]::Pi / 180
	$Long1 = $Long1 * [math]::Pi / 180
	$Lat2 = $Lat2 * [math]::Pi / 180
	$Long2 = $Long2 * [math]::Pi / 180
 
	#  Mean Earth radius (km)
	$R = 6371
   
	#  Haversine formula
	$ArcLength = 2 * $R *
	[math]::Asin(
		[math]::Sqrt(
			[math]::Sin( ( $Lat1 - $Lat2 ) / 2 ) *
			[math]::Sin( ( $Lat1 - $Lat2 ) / 2 ) +
			[math]::Cos( $Lat1 ) *
			[math]::Cos( $Lat2 ) *
			[math]::Sin( ( $Long1 - $Long2 ) / 2 ) *
			[math]::Sin( ( $Long1 - $Long2 ) / 2 ) ) )
	return $ArcLength
}

# Download airport code JSON dataset
Log "API: Get airport codes JSON."
$codeDownload = Invoke-WebRequest "https://data.opendatasoft.com/api/explore/v2.1/catalog/datasets/airports-code@public/exports/json" -UseBasicParsing

## Import the airport code JSON and convert to readable format
$locations = $codeDownload.content | ConvertFrom-Json

# Find closest location within 50 km
$closestLocation = @()
$closestDistance = [int]50
foreach ($location in $locations) {
	$lat = $location.Latitude 
	$long = $location.Longitude
	$distance = Get-GreatCircleDistance $targetLatitude $targetLongitude $lat $long
	if ($distance -ilt $closestDistance) {
		$closestDistance = $distance
		$closestLocation += $location
	}
}

## Check if more than one location are within 50km and choose the closest one
if ($closestLocation.count -gt 1) {
	$locationCompare = [System.Collections.Generic.List[Object]]::new()
	foreach ($loc in $closestLocation) {
		$lat = $loc.Latitude 
		$long = $loc.Longitude
		$distance = Get-GreatCircleDistance $targetLatitude $targetLongitude $lat $long
		$distance = [int]$distance
		$locInfo = [PSCustomObject][ordered]@{
			"AirportCode" = $loc.column_1
			"Distance"    = [int]$distance
		}
		$locationCompare.add($locInfo)
	}
	$minDist = $null
	$minDist = [int]($locationCompare | Measure-Object -Property Distance -Minimum).Minimum
	$closestLocation2 = $locationCompare | Where-Object { $_.Distance -eq $minDist }
	$airport_code = $closestLocation2.AirportCode
}
else {
	$airport_code = $closestLocation.column_1
}
#>