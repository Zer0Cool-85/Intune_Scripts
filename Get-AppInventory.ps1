#Requires -Version 5.1

<#
.SYNOPSIS
    Uses Microsoft Graph to evaluate Intune discovered application inventory
    and add matching Entra devices to security groups.

.DESCRIPTION
    Supports rules for:
        - Application PRESENT
        - Application MISSING

    Application matching is performed against Intune detectedApps.

    Intune managed device IDs are mapped to Entra device objects by:
        managedDevice.AzureAdDeviceId
            ->
        device.DeviceId
            ->
        device.Id

    The Entra device object ID is then added to the configured security group.

.NOTES
    Microsoft Graph modules required:
        Microsoft.Graph.Authentication
        Microsoft.Graph.DeviceManagement
        Microsoft.Graph.Identity.DirectoryManagement
        Microsoft.Graph.Groups
#>

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$LogPath = "$env:ProgramData\AppInventoryGroupSync\AppInventoryGroupSync.log"

# Only evaluate devices that have synced with Intune within this many days.
# Set to 0 to disable the LastSyncDateTime filter.
$MaxDeviceSyncAgeDays = 14

# Only evaluate corporate-owned devices.
$CorporateDevicesOnly = $true

# Dry run mode.
# No group memberships are changed when $true.
$DryRun = $true


# ------------------------------------------------------------
# Application Rules
# ------------------------------------------------------------

$AppRules = @(

    [PSCustomObject]@{
        RuleName       = "7-Zip Installed"
        AppNameRegex    = "^7-Zip"
        PublisherRegex  = $null
        DesiredState    = "Present"
        GroupId         = "00000000-0000-0000-0000-000000000000"
    }

    [PSCustomObject]@{
        RuleName       = "Cisco Secure Client Missing"
        AppNameRegex    = "^Cisco Secure Client"
        PublisherRegex  = "^Cisco"
        DesiredState    = "Missing"
        GroupId         = "11111111-1111-1111-1111-111111111111"
    }

    [PSCustomObject]@{
        RuleName       = "Google Chrome Installed"
        AppNameRegex    = "^Google Chrome$"
        PublisherRegex  = "^Google"
        DesiredState    = "Present"
        GroupId         = "22222222-2222-2222-2222-222222222222"
    }

)


# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

function Write-Log {

    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet(
            "INFO",
            "WARNING",
            "ERROR",
            "SUCCESS"
        )]
        [string]$Level = "INFO"
    )

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $LogMessage = "[$TimeStamp] [$Level] $Message"

    Write-Host $LogMessage

    try {

        $LogDirectory = Split-Path -Path $LogPath -Parent

        if (-not (Test-Path -Path $LogDirectory)) {

            New-Item `
                -Path $LogDirectory `
                -ItemType Directory `
                -Force | Out-Null

        }

        Add-Content `
            -Path $LogPath `
            -Value $LogMessage

    }
    catch {

        Write-Warning "Unable to write to log file: $($_.Exception.Message)"

    }

}


# ------------------------------------------------------------
# Validate Graph Modules
# ------------------------------------------------------------

$RequiredModules = @(

    "Microsoft.Graph.Authentication"
    "Microsoft.Graph.DeviceManagement"
    "Microsoft.Graph.Identity.DirectoryManagement"
    "Microsoft.Graph.Groups"

)

foreach ($Module in $RequiredModules) {

    if (-not (Get-Module -ListAvailable -Name $Module)) {

        throw "Required PowerShell module [$Module] is not installed."

    }

    Import-Module `
        -Name $Module `
        -ErrorAction Stop

}


# ------------------------------------------------------------
# Connect to Microsoft Graph
# ------------------------------------------------------------

$RequiredScopes = @(

    "DeviceManagementManagedDevices.Read.All"
    "Device.Read.All"
    "GroupMember.ReadWrite.All"

)

try {

    $GraphContext = Get-MgContext

    if (-not $GraphContext) {

        Write-Log "Connecting to Microsoft Graph."

        Connect-MgGraph `
            -Scopes $RequiredScopes `
            -NoWelcome `
            -ErrorAction Stop

    }
    else {

        Write-Log "Using existing Microsoft Graph connection for [$($GraphContext.Account)]."

    }

}
catch {

    Write-Log `
        -Message "Unable to connect to Microsoft Graph: $($_.Exception.Message)" `
        -Level "ERROR"

    throw

}


# ------------------------------------------------------------
# Retrieve Intune Managed Devices
# ------------------------------------------------------------

Write-Log "Retrieving Intune managed devices."

try {

    $ManagedDevices = @(

        Get-MgDeviceManagementManagedDevice `
            -All `
            -Property @(
                "id"
                "deviceName"
                "azureADDeviceId"
                "operatingSystem"
                "managedDeviceOwnerType"
                "lastSyncDateTime"
            ) `
            -ErrorAction Stop

    )

}
catch {

    Write-Log `
        -Message "Unable to retrieve Intune managed devices: $($_.Exception.Message)" `
        -Level "ERROR"

    throw

}

Write-Log "Retrieved [$($ManagedDevices.Count)] Intune managed devices."


# ------------------------------------------------------------
# Filter Eligible Devices
# ------------------------------------------------------------

$EligibleDevices = @(

    $ManagedDevices |
        Where-Object {

            $Device = $_

            # Windows only

            if ($Device.OperatingSystem -ne "Windows") {

                return $false

            }


            # Must have an Entra device ID

            if ([string]::IsNullOrWhiteSpace($Device.AzureAdDeviceId)) {

                return $false

            }


            # Corporate devices only

            if (
                $CorporateDevicesOnly -and
                "$($Device.ManagedDeviceOwnerType)" -ne "company"
            ) {

                return $false

            }


            # Last Intune sync age

            if ($MaxDeviceSyncAgeDays -gt 0) {

                $MinimumSyncDate = (Get-Date).AddDays(
                    -$MaxDeviceSyncAgeDays
                )

                if ($Device.LastSyncDateTime -lt $MinimumSyncDate) {

                    return $false

                }

            }


            return $true

        }

)

Write-Log "[$($EligibleDevices.Count)] devices are eligible for application evaluation."


# ------------------------------------------------------------
# Create Intune Device Lookup
# ------------------------------------------------------------

$EligibleDeviceLookup = @{}

foreach ($Device in $EligibleDevices) {

    $EligibleDeviceLookup[$Device.Id] = $Device

}


# ------------------------------------------------------------
# Retrieve Entra Devices
# ------------------------------------------------------------

Write-Log "Retrieving Entra device objects."

try {

    $EntraDevices = @(

        Get-MgDevice `
            -All `
            -Property @(
                "id"
                "deviceId"
                "displayName"
                "accountEnabled"
            ) `
            -ErrorAction Stop

    )

}
catch {

    Write-Log `
        -Message "Unable to retrieve Entra devices: $($_.Exception.Message)" `
        -Level "ERROR"

    throw

}

Write-Log "Retrieved [$($EntraDevices.Count)] Entra device objects."


# ------------------------------------------------------------
# Create Entra Device Lookup
# ------------------------------------------------------------

$EntraDeviceLookup = @{}

foreach ($Device in $EntraDevices) {

    if (
        -not [string]::IsNullOrWhiteSpace(
            $Device.DeviceId
        )
    ) {

        $EntraDeviceLookup[
            $Device.DeviceId.ToLowerInvariant()
        ] = $Device

    }

}


# ------------------------------------------------------------
# Retrieve Intune Detected Apps
# ------------------------------------------------------------

Write-Log "Retrieving Intune detected application inventory."

try {

    $DetectedApps = @(

        Get-MgDeviceManagementDetectedApp `
            -All `
            -Property @(
                "id"
                "displayName"
                "version"
                "publisher"
                "platform"
                "deviceCount"
            ) `
            -ErrorAction Stop

    )

}
catch {

    Write-Log `
        -Message "Unable to retrieve detected apps: $($_.Exception.Message)" `
        -Level "ERROR"

    throw

}

Write-Log "Retrieved [$($DetectedApps.Count)] detected application records."


# ------------------------------------------------------------
# Process Application Rules
# ------------------------------------------------------------

foreach ($Rule in $AppRules) {

    Write-Log "------------------------------------------------------------"

    Write-Log "Processing rule [$($Rule.RuleName)]."

    Write-Log "Application regex: [$($Rule.AppNameRegex)]."

    Write-Log "Desired state: [$($Rule.DesiredState)]."

    Write-Log "Target group: [$($Rule.GroupId)]."


    # --------------------------------------------------------
    # Validate Rule
    # --------------------------------------------------------

    if (
        $Rule.DesiredState -notin @(
            "Present",
            "Missing"
        )
    ) {

        Write-Log `
            -Message "Invalid DesiredState [$($Rule.DesiredState)]. Skipping rule." `
            -Level "ERROR"

        continue

    }


    # --------------------------------------------------------
    # Find Matching Applications
    # --------------------------------------------------------

    $MatchingApps = @(

        $DetectedApps |
            Where-Object {

                if (
                    $_.DisplayName -notmatch $Rule.AppNameRegex
                ) {

                    return $false

                }

                if (
                    -not [string]::IsNullOrWhiteSpace(
                        $Rule.PublisherRegex
                    )
                ) {

                    if (
                        $_.Publisher -notmatch $Rule.PublisherRegex
                    ) {

                        return $false

                    }

                }

                return $true

            }

    )


    Write-Log "Found [$($MatchingApps.Count)] matching detected application records."


    foreach ($App in $MatchingApps) {

        Write-Log "Matched app [$($App.DisplayName)] version [$($App.Version)] publisher [$($App.Publisher)]."

    }


    # --------------------------------------------------------
    # Determine Devices With Application Installed
    # --------------------------------------------------------

    $InstalledDeviceIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )


    foreach ($App in $MatchingApps) {

        Write-Log "Retrieving devices for app [$($App.DisplayName)] version [$($App.Version)]."

        try {

            $AppDevices = @(

                Get-MgDeviceManagementDetectedAppManagedDevice `
                    -DetectedAppId $App.Id `
                    -All `
                    -Property @(
                        "id"
                    ) `
                    -ErrorAction Stop

            )


            foreach ($Device in $AppDevices) {

                [void]$InstalledDeviceIds.Add(
                    $Device.Id
                )

            }

        }
        catch {

            Write-Log `
                -Message "Unable to retrieve devices for app [$($App.DisplayName)]: $($_.Exception.Message)" `
                -Level "ERROR"

        }

    }


    Write-Log "Application detected on [$($InstalledDeviceIds.Count)] unique Intune devices."


    # --------------------------------------------------------
    # Determine Target Devices
    # --------------------------------------------------------

    switch ($Rule.DesiredState) {

        "Present" {

            $TargetDevices = @(

                $EligibleDevices |
                    Where-Object {

                        $InstalledDeviceIds.Contains(
                            $_.Id
                        )

                    }

            )

        }


        "Missing" {

            $TargetDevices = @(

                $EligibleDevices |
                    Where-Object {

                        -not $InstalledDeviceIds.Contains(
                            $_.Id
                        )

                    }

            )

        }

    }


    Write-Log "[$($TargetDevices.Count)] devices match rule [$($Rule.RuleName)]."


    # --------------------------------------------------------
    # Retrieve Existing Group Members
    # --------------------------------------------------------

    try {

        $ExistingMembers = @(

            Get-MgGroupMember `
                -GroupId $Rule.GroupId `
                -All `
                -ErrorAction Stop

        )

    }
    catch {

        Write-Log `
            -Message "Unable to retrieve members of group [$($Rule.GroupId)]: $($_.Exception.Message)" `
            -Level "ERROR"

        continue

    }


    $ExistingMemberIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )


    foreach ($Member in $ExistingMembers) {

        [void]$ExistingMemberIds.Add(
            $Member.Id
        )

    }


    # --------------------------------------------------------
    # Add Matching Devices
    # --------------------------------------------------------

    $AddedCount   = 0
    $SkippedCount = 0
    $ErrorCount   = 0


    foreach ($IntuneDevice in $TargetDevices) {

        $AzureAdDeviceId = $IntuneDevice.AzureAdDeviceId.ToLowerInvariant()


        # ----------------------------------------------------
        # Map Intune Device to Entra Device
        # ----------------------------------------------------

        if (
            -not $EntraDeviceLookup.ContainsKey(
                $AzureAdDeviceId
            )
        ) {

            Write-Log `
                -Message "Unable to locate Entra device object for [$($IntuneDevice.DeviceName)] AzureAdDeviceId [$($IntuneDevice.AzureAdDeviceId)]." `
                -Level "WARNING"

            $ErrorCount++

            continue

        }


        $EntraDevice = $EntraDeviceLookup[$AzureAdDeviceId]


        # ----------------------------------------------------
        # Check Existing Membership
        # ----------------------------------------------------

        if (
            $ExistingMemberIds.Contains(
                $EntraDevice.Id
            )
        ) {

            Write-Log "Device [$($IntuneDevice.DeviceName)] is already a member of the target group."

            $SkippedCount++

            continue

        }


        # ----------------------------------------------------
        # Dry Run
        # ----------------------------------------------------

        if ($DryRun) {

            Write-Log `
                -Message "DRY RUN: Would add device [$($IntuneDevice.DeviceName)] to group [$($Rule.GroupId)]." `
                -Level "SUCCESS"

            $AddedCount++

            continue

        }


        # ----------------------------------------------------
        # Add Device to Group
        # ----------------------------------------------------

        try {

            $BodyParameter = @{

                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($EntraDevice.Id)"

            }


            New-MgGroupMemberByRef `
                -GroupId $Rule.GroupId `
                -BodyParameter $BodyParameter `
                -ErrorAction Stop


            [void]$ExistingMemberIds.Add(
                $EntraDevice.Id
            )


            Write-Log `
                -Message "Added device [$($IntuneDevice.DeviceName)] to group [$($Rule.GroupId)]." `
                -Level "SUCCESS"


            $AddedCount++

        }
        catch {

            Write-Log `
                -Message "Unable to add device [$($IntuneDevice.DeviceName)] to group: $($_.Exception.Message)" `
                -Level "ERROR"


            $ErrorCount++

        }

    }


    # --------------------------------------------------------
    # Rule Summary
    # --------------------------------------------------------

    Write-Log "Rule [$($Rule.RuleName)] complete."

    Write-Log "Matching devices: [$($TargetDevices.Count)]."

    Write-Log "Added: [$AddedCount]."

    Write-Log "Already members: [$SkippedCount]."

    Write-Log "Errors: [$ErrorCount]."

}


# ------------------------------------------------------------
# Complete
# ------------------------------------------------------------

Write-Log "------------------------------------------------------------"

Write-Log `
    -Message "Application inventory group processing complete." `
    -Level "SUCCESS"

Disconnect-MgGraph | Out-Null
