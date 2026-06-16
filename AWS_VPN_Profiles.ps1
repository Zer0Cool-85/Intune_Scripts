# ----------------------------
# Helpers: start/stop AWS client
# ----------------------------
function Start-AwsVpnClient {
    param(
        [string]$ExePath = "C:\Program Files\Amazon\AWS VPN Client\AWSVPNClient.exe"
    )
    if (-not (Test-Path $ExePath)) {
        throw "AWS VPN Client exe not found at: $ExePath"
    }
    & $ExePath | Out-Null
}

function Stop-AwsVpnClient {
    Get-Process -Name "AWSVPNClient" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Invoke-AWSVPNClientFirstLaunch {
    param (
        [int]$WaitForAppDataSeconds = 20,
        [int]$PostLaunchDelaySeconds = 5
    )

    $AwsVpnExe = 'C:\Program Files\Amazon\AWS VPN Client\AWSVPNClient.exe'
    $AwsVpnAppDataRoot = Join-Path $env:APPDATA 'AWSVPNClient'

    Write-Log 'Starting AWS VPN Client first-launch initialization check.'
    Write-Log "Expected AWS VPN Client EXE path: $AwsVpnExe"
    Write-Log "Expected AWS VPN Client AppData path: $AwsVpnAppDataRoot"

    if (Test-Path $AwsVpnAppDataRoot) {
        Write-Log 'AWS VPN Client AppData directory already exists. First-launch step is not required.'
        return $true
    }

    if (-not (Test-Path $AwsVpnExe)) {
        Write-Log "AWS VPN Client executable was not found at [$AwsVpnExe]. Skipping first-launch step." 'WARN'
        return $false
    }

    try {
        # Track any AWS VPN Client processes that were already running so we do not close a user's existing session.
        $ExistingProcessIds = @(
            Get-Process -Name 'AWSVPNClient' -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Id
        )

        Write-Log "Existing AWSVPNClient process IDs before launch: $($ExistingProcessIds -join ', ')"

        Write-Log 'Launching AWS VPN Client.'
        $StartedProcess = Start-Process -FilePath $AwsVpnExe -PassThru -WindowStyle Minimized

        Write-Log "Started AWS VPN Client process ID: $($StartedProcess.Id)"

        $Deadline = (Get-Date).AddSeconds($WaitForAppDataSeconds)

        do {
            if (Test-Path $AwsVpnAppDataRoot) {
                Write-Log "AWS VPN Client AppData directory was created: $AwsVpnAppDataRoot"
                break
            }

            Start-Sleep -Seconds 1
        }
        while ((Get-Date) -lt $Deadline)

        if (-not (Test-Path $AwsVpnAppDataRoot)) {
            Write-Log "AWS VPN Client AppData directory was not created within [$WaitForAppDataSeconds] seconds." 'WARN'
        }

        Write-Log "Waiting [$PostLaunchDelaySeconds] additional second(s) before closing AWS VPN Client."
        Start-Sleep -Seconds $PostLaunchDelaySeconds

        # Close only AWSVPNClient processes that appeared after this script launched the app.
        $NewAwsVpnProcesses = @(
            Get-Process -Name 'AWSVPNClient' -ErrorAction SilentlyContinue |
                Where-Object { $_.Id -notin $ExistingProcessIds }
        )

        foreach ($Process in $NewAwsVpnProcesses) {
            Write-Log "Attempting graceful close of AWSVPNClient process ID [$($Process.Id)]."

            try {
                if ($Process.MainWindowHandle -ne 0) {
                    $null = $Process.CloseMainWindow()
                    Start-Sleep -Seconds 3
                    $Process.Refresh()
                }

                if (-not $Process.HasExited) {
                    Write-Log "AWSVPNClient process ID [$($Process.Id)] did not close gracefully. Stopping process." 'WARN'
                    Stop-Process -Id $Process.Id -Force -ErrorAction Stop
                }
                else {
                    Write-Log "AWSVPNClient process ID [$($Process.Id)] closed gracefully."
                }
            }
            catch {
                Write-Log "Failed while closing AWSVPNClient process ID [$($Process.Id)]. Error: $($_.Exception.Message)" 'WARN'
            }
        }

        if ($NewAwsVpnProcesses.Count -eq 0) {
            Write-Log 'No new AWSVPNClient process was found to close. The app may have exited on its own or reused an existing process.'
        }

        if (Test-Path $AwsVpnAppDataRoot) {
            Write-Log 'AWS VPN Client first-launch initialization completed successfully.'
            return $true
        }
        else {
            Write-Log 'AWS VPN Client first-launch initialization completed, but AppData directory still does not exist.' 'WARN'
            return $false
        }
    }
    catch {
        Write-Log "AWS VPN Client first-launch initialization failed. Error: $($_.Exception.Message)" 'ERROR'
        Write-Log "Script stack trace: $($_.ScriptStackTrace)" 'ERROR'
        return $false
    }
}

# Trigger first-run initialization if AWSVPNClient AppData does not already exist.
$FirstLaunchResult = Invoke-AWSVPNClientFirstLaunch `
    -WaitForAppDataSeconds 20 `
    -PostLaunchDelaySeconds 5

Write-Log "AWS VPN Client first-launch result: $FirstLaunchResult"

# Continue either way because the script can create the folders itself.
$AwsRoot = Join-Path $env:APPDATA 'AWSVPNClient'
$OpenVpnConfigRoot = Join-Path $AwsRoot 'OpenVpnConfigs'
$ConnectionProfilesPath = Join-Path $AwsRoot 'ConnectionProfiles'

New-Item -Path $AwsRoot -ItemType Directory -Force | Out-Null
New-Item -Path $OpenVpnConfigRoot -ItemType Directory -Force | Out-Null

# AWS VPN Client profile configuration
# Intended to run in USER context from Intune

$ErrorActionPreference = 'Stop'

#===========================================================
# Logging
#===========================================================

$CompanyName = 'YourCompany'
$LogRoot = Join-Path $env:LOCALAPPDATA "$CompanyName\Logs"
$LogPath = Join-Path $LogRoot 'AWSVPNProfiles-Configure.log'

function Initialize-Log {
    try {
        New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
    }
    catch {
        $script:LogRoot = $env:TEMP
        $script:LogPath = Join-Path $script:LogRoot 'AWSVPNProfiles-Configure.log'
    }
}

function Write-Log {
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    try {
        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $Line = "$Timestamp [$Level] [$Identity] $Message"

        Add-Content -Path $LogPath -Value $Line -Encoding UTF8
    }
    catch {
        # Avoid breaking the deployment if logging fails.
    }
}

Initialize-Log

Write-Log '============================================================'
Write-Log 'Starting AWS VPN profile configuration.'
Write-Log "Running as user: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "USERPROFILE: $env:USERPROFILE"
Write-Log "APPDATA: $env:APPDATA"
Write-Log "LOCALAPPDATA: $env:LOCALAPPDATA"
Write-Log "Log path: $LogPath"

try {
    #===========================================================
    # AWS VPN profile content
    #===========================================================

    # Do not log these values because profile content may contain sensitive details.

    #region East
    $vpn1 = @'
PASTE EAST OVPN CONTENT HERE
'@
    #endregion

    #region East 2
    $vpn2 = @'
PASTE EAST 2 OVPN CONTENT HERE
'@
    #endregion

    #region West
    $vpn3 = @'
PASTE WEST OVPN CONTENT HERE
'@
    #endregion

    #region Central
    $vpn4 = @'
PASTE CENTRAL OVPN CONTENT HERE
'@
    #endregion

    #===========================================================
    # Paths
    #===========================================================

    $AwsRoot = Join-Path $env:APPDATA 'AWSVPNClient'
    $OpenVpnConfigRoot = Join-Path $AwsRoot 'OpenVpnConfigs'
    $ConnectionProfilesPath = Join-Path $AwsRoot 'ConnectionProfiles'

    Write-Log "AWS root path: $AwsRoot"
    Write-Log "OpenVPN config path: $OpenVpnConfigRoot"
    Write-Log "ConnectionProfiles path: $ConnectionProfilesPath"

    New-Item -Path $AwsRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $OpenVpnConfigRoot -ItemType Directory -Force | Out-Null

    Write-Log 'AWS VPN Client profile directories created or already exist.'

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    #===========================================================
    # Define managed VPN profiles
    #===========================================================

    $ManagedProfiles = @(
        [PSCustomObject]@{
            ProfileName          = 'East'
            FileName             = 'East'
            OvpnContent          = $vpn1
            CvpnEndpointId       = ''
            CvpnEndpointRegion   = ''
            CompatibilityVersion = '2'
            FederatedAuthType    = 1
        },
        [PSCustomObject]@{
            ProfileName          = 'East 2'
            FileName             = 'East2'
            OvpnContent          = $vpn2
            CvpnEndpointId       = ''
            CvpnEndpointRegion   = ''
            CompatibilityVersion = '2'
            FederatedAuthType    = 1
        },
        [PSCustomObject]@{
            ProfileName          = 'West'
            FileName             = 'West'
            OvpnContent          = $vpn3
            CvpnEndpointId       = ''
            CvpnEndpointRegion   = ''
            CompatibilityVersion = '2'
            FederatedAuthType    = 1
        },
        [PSCustomObject]@{
            ProfileName          = 'Central'
            FileName             = 'Central'
            OvpnContent          = $vpn4
            CvpnEndpointId       = ''
            CvpnEndpointRegion   = ''
            CompatibilityVersion = '2'
            FederatedAuthType    = 1
        }
    )

    Write-Log "Managed profile count: $($ManagedProfiles.Count)"

    #===========================================================
    # Read existing ConnectionProfiles JSON
    #===========================================================

    if ((Test-Path $ConnectionProfilesPath) -and ((Get-Item $ConnectionProfilesPath).Length -gt 0)) {
        Write-Log 'Existing ConnectionProfiles file found. Attempting to parse JSON.'

        try {
            $Config = Get-Content -Path $ConnectionProfilesPath -Raw | ConvertFrom-Json
            Write-Log 'Existing ConnectionProfiles JSON parsed successfully.'
        }
        catch {
            $BackupPath = "$ConnectionProfilesPath.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"

            Write-Log "Existing ConnectionProfiles file could not be parsed. Creating backup at: $BackupPath" 'WARN'
            Copy-Item -Path $ConnectionProfilesPath -Destination $BackupPath -Force

            $Config = [PSCustomObject]@{
                Version                  = '1'
                LastSelectedProfileIndex = 0
                ConnectionProfiles       = @()
            }

            Write-Log 'Created new default ConnectionProfiles object after invalid JSON backup.'
        }
    }
    else {
        Write-Log 'No existing ConnectionProfiles file found, or file is empty. Creating new configuration object.'

        $Config = [PSCustomObject]@{
            Version                  = '1'
            LastSelectedProfileIndex = 0
            ConnectionProfiles       = @()
        }
    }

    $ExistingProfiles = @($Config.ConnectionProfiles)
    Write-Log "Existing profile count before cleanup: $($ExistingProfiles.Count)"

    #===========================================================
    # Remove old managed profiles so the script is idempotent
    #===========================================================

    $ManagedProfileNames = @($ManagedProfiles.ProfileName)

    $PreservedProfiles = @(
        $ExistingProfiles | Where-Object {
            $_.ProfileName -notin $ManagedProfileNames
        }
    )

    Write-Log "Preserved non-managed profile count: $($PreservedProfiles.Count)"
    Write-Log 'Managed profiles will be replaced with current packaged values.'

    #===========================================================
    # Write OVPN files and rebuild managed profile objects
    #===========================================================

    $NewManagedProfileObjects = foreach ($Profile in $ManagedProfiles) {
        $OvpnFilePath = Join-Path $OpenVpnConfigRoot $Profile.FileName

        Write-Log "Writing OVPN file for profile [$($Profile.ProfileName)] to [$OvpnFilePath]."

        [System.IO.File]::WriteAllText(
            $OvpnFilePath,
            $Profile.OvpnContent,
            $Utf8NoBom
        )

        if (Test-Path $OvpnFilePath) {
            Write-Log "Successfully wrote OVPN file for profile [$($Profile.ProfileName)]."
        }
        else {
            Write-Log "OVPN file was not found after write attempt for profile [$($Profile.ProfileName)]." 'WARN'
        }

        [PSCustomObject]@{
            ProfileName          = $Profile.ProfileName
            OvpnConfigFilePath   = $OvpnFilePath
            CvpnEndpointId       = $Profile.CvpnEndpointId
            CvpnEndpointRegion   = $Profile.CvpnEndpointRegion
            CompatibilityVersion = $Profile.CompatibilityVersion
            FederatedAuthType    = $Profile.FederatedAuthType
        }
    }

    #===========================================================
    # Build final ConnectionProfiles JSON
    #===========================================================

    $FinalProfiles = @($PreservedProfiles) + @($NewManagedProfileObjects)

    $FinalConfig = [PSCustomObject]@{
        Version                  = '1'
        LastSelectedProfileIndex = 0
        ConnectionProfiles       = @($FinalProfiles)
    }

    Write-Log "Final profile count: $($FinalProfiles.Count)"

    $Json = $FinalConfig | ConvertTo-Json -Depth 10

    [System.IO.File]::WriteAllText(
        $ConnectionProfilesPath,
        $Json,
        $Utf8NoBom
    )

    Write-Log "ConnectionProfiles file written successfully to [$ConnectionProfilesPath]."

    # Validate final JSON
    try {
        $Validation = Get-Content -Path $ConnectionProfilesPath -Raw | ConvertFrom-Json
        Write-Log "Validation successful. ConnectionProfiles contains [$(@($Validation.ConnectionProfiles).Count)] profile(s)."
    }
    catch {
        Write-Log "Validation failed after writing ConnectionProfiles. Error: $($_.Exception.Message)" 'ERROR'
        exit 1
    }

    Write-Log 'AWS VPN profile configuration completed successfully.'
    exit 0
}
catch {
    Write-Log "AWS VPN profile configuration failed. Error: $($_.Exception.Message)" 'ERROR'
    Write-Log "Script stack trace: $($_.ScriptStackTrace)" 'ERROR'
    exit 1
}

# ----------------------------
# Example usage
# ----------------------------

# 1) Launch once to let it create roaming files (if needed), then close it
Start-AwsVpnClient
Start-Sleep -Seconds 2
Stop-AwsVpnClient

# ----------------------------
# DETECTION
# ----------------------------

# AWS VPN Client profile detection
# Intended to run in USER context from Intune

$ErrorActionPreference = 'Stop'

#===========================================================
# Logging
#===========================================================

$CompanyName = 'YourCompany'
$LogRoot = Join-Path $env:LOCALAPPDATA "$CompanyName\Logs"
$LogPath = Join-Path $LogRoot 'AWSVPNProfiles-Detection.log'

function Initialize-Log {
    try {
        New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
    }
    catch {
        $script:LogRoot = $env:TEMP
        $script:LogPath = Join-Path $script:LogRoot 'AWSVPNProfiles-Detection.log'
    }
}

function Write-Log {
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    try {
        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $Line = "$Timestamp [$Level] [$Identity] $Message"

        Add-Content -Path $LogPath -Value $Line -Encoding UTF8
    }
    catch {
        # Avoid breaking detection if logging fails.
    }
}

Initialize-Log

Write-Log '============================================================'
Write-Log 'Starting AWS VPN profile detection.'
Write-Log "Running as user: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "USERPROFILE: $env:USERPROFILE"
Write-Log "APPDATA: $env:APPDATA"
Write-Log "LOCALAPPDATA: $env:LOCALAPPDATA"
Write-Log "Log path: $LogPath"

try {
    #===========================================================
    # Expected paths
    #===========================================================

    $AwsRoot = Join-Path $env:APPDATA 'AWSVPNClient'
    $OpenVpnConfigRoot = Join-Path $AwsRoot 'OpenVpnConfigs'
    $ConnectionProfilesPath = Join-Path $AwsRoot 'ConnectionProfiles'

    $RequiredProfiles = @(
        [PSCustomObject]@{
            ProfileName = 'East'
            FileName    = 'East'
        },
        [PSCustomObject]@{
            ProfileName = 'East 2'
            FileName    = 'East2'
        },
        [PSCustomObject]@{
            ProfileName = 'West'
            FileName    = 'West'
        },
        [PSCustomObject]@{
            ProfileName = 'Central'
            FileName    = 'Central'
        }
    )

    Write-Log "AWS root path: $AwsRoot"
    Write-Log "OpenVPN config path: $OpenVpnConfigRoot"
    Write-Log "ConnectionProfiles path: $ConnectionProfilesPath"
    Write-Log "Required profile count: $($RequiredProfiles.Count)"

    #===========================================================
    # Validate ConnectionProfiles file
    #===========================================================

    if (-not (Test-Path $ConnectionProfilesPath)) {
        Write-Log "ConnectionProfiles file not found: $ConnectionProfilesPath" 'ERROR'
        exit 1
    }

    Write-Log 'ConnectionProfiles file exists.'

    if ((Get-Item $ConnectionProfilesPath).Length -le 0) {
        Write-Log 'ConnectionProfiles file exists but is empty.' 'ERROR'
        exit 1
    }

    try {
        $Config = Get-Content -Path $ConnectionProfilesPath -Raw | ConvertFrom-Json
        Write-Log 'ConnectionProfiles JSON parsed successfully.'
    }
    catch {
        Write-Log "Failed to parse ConnectionProfiles JSON. Error: $($_.Exception.Message)" 'ERROR'
        exit 1
    }

    $DetectedProfileNames = @($Config.ConnectionProfiles.ProfileName)

    Write-Log "Detected profile names: $($DetectedProfileNames -join ', ')"

    #===========================================================
    # Validate required profiles and OVPN files
    #===========================================================

    foreach ($Profile in $RequiredProfiles) {
        Write-Log "Checking profile [$($Profile.ProfileName)]."

        if ($Profile.ProfileName -notin $DetectedProfileNames) {
            Write-Log "Required profile missing from ConnectionProfiles JSON: [$($Profile.ProfileName)]" 'ERROR'
            exit 1
        }

        Write-Log "Profile found in ConnectionProfiles JSON: [$($Profile.ProfileName)]."

        $ExpectedOvpnPath = Join-Path $OpenVpnConfigRoot $Profile.FileName

        if (-not (Test-Path $ExpectedOvpnPath)) {
            Write-Log "Required OVPN file missing for profile [$($Profile.ProfileName)]: $ExpectedOvpnPath" 'ERROR'
            exit 1
        }

        $FileLength = (Get-Item $ExpectedOvpnPath).Length

        if ($FileLength -le 0) {
            Write-Log "OVPN file exists but is empty for profile [$($Profile.ProfileName)]: $ExpectedOvpnPath" 'ERROR'
            exit 1
        }

        Write-Log "OVPN file found for profile [$($Profile.ProfileName)]. Size: $FileLength bytes."
    }

    #===========================================================
    # Success
    #===========================================================

    Write-Log 'AWS VPN profile detection completed successfully.'

    # Intune custom detection requires exit 0 and STDOUT.
    Write-Output 'AWS VPN profiles detected.'
    exit 0
}
catch {
    Write-Log "AWS VPN profile detection failed. Error: $($_.Exception.Message)" 'ERROR'
    Write-Log "Script stack trace: $($_.ScriptStackTrace)" 'ERROR'
    exit 1
}


%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ".\Set-AWSVPNProfiles.ps1"
