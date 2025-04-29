<#
.SYNOPSIS
    Get-EntraIDGroupAssignments.ps1 retrieves information about EntraID groups,
    their members, assigned Enterprise Applications, and Intune Policies.
.DESCRIPTION
    Using the Microsoft Graph API, this script retrieves information about EntraID groups.     
.PARAMETER <Parameter_Name>
    ClientId: The Client ID for the EntraID app registration.
    TenantId: The Tenant ID for the EntraID app registration.
    ClientSecret: The Client Secret for the EntraID app registration.
.INPUTS
    None
.OUTPUTS
    Excel file with information about EntraID groups, their members, assigned Enterprise Applications, and Intune Policies.
.EXAMPLE
    Get-EntraIDGroupAssignments.ps1 -ClientId 'xyz123' -TenantId 'xyz123' -ClientSecret 'xyz123'
.NOTES
    Any additional information or considerations.
#>
[CmdletBinding()]
param(
    # Define the Client ID for the Azure AD app
    [string]$ClientId = '',
  
    # Define the Tenant ID for the Azure AD app
    [string]$TenantId = '',
  
    # Define the Client Secret for the Azure AD app
    [string]$ClientSecret = ''
)
#-------------------------------------------------------------------------------------#
#region script functions
function Connect-MSGraphPowershell {
    param (
        [string]$ClientId,
        [string]$TenantId,
        [string]$ClientSecret
    )
    
    # Define script variables for token and expiration
    if (-not $script:expiresDateTime -or (Get-Date).AddMinutes(5) -ge $script:expiresDateTime) {
        # Token needs to be renewed
        Write-Host "Getting access token..." -ForegroundColor Yellow
    
        # Request body for token
        $body = @{
            grant_type    = 'client_credentials'
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = 'https://graph.microsoft.com/.default'
        }
    
        try {
            # Get the token
            $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body
            $token = $response.access_token
            $expiresIn = [double]$response.expires_in
    
            # Save expiration time
            $script:expiresDateTime = (Get-Date).AddSeconds($expiresIn)
            $date = get-date
    
            # Set script headers for API calls
            $script:header = @{
                'Content-Type'  = 'application/json'
                'Authorization' = "Bearer $token"
            }
    
            Write-Host "Successfully retrieved access token: $date" -ForegroundColor Green
            Write-Host "Token Expiration Date/Time: $script:expiresDateTime" -ForegroundColor Magenta
    
            # Attempt to connect to Microsoft Graph
            try {
                Connect-MgGraph -AccessToken (ConvertTo-SecureString -String $token -AsPlainText -Force) -NoWelcome -ErrorAction Stop
                Write-Host "Successfully connected to Microsoft Graph PowerShell!`n" -ForegroundColor Green
            }
            catch {
                $err = $_.exception.message
                if ($err -like "*PII is hidden*") {
                    try {
                        Connect-MgGraph -AccessToken $token -NoWelcome
                    }
                    catch {
                        Write-Error "Failed to connect to Microsoft Graph PowerShell. Error: $($_.Exception.Message)" 
                    }
                }
            }
        }
        catch {
            Write-Host "Error retrieving access token: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        # Token is still valid
        $remainingMinutes = ($script:expiresDateTime - (Get-Date)).TotalMinutes
        Write-Host "You are still connected to Microsoft Graph PowerShell." -ForegroundColor Green
        Write-Host "Your token will expire in $([math]::Floor($remainingMinutes)) minutes." -ForegroundColor Yellow
    }
} 
function Get-AllEntraIDgroups {
    # Initialize an array to store groups
    $groups = @()
    $uri = "https://graph.microsoft.com/beta/groups?`$expand=members"
    
    # Fetch all pages of groups
    try {
        do {
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
            $groups += $result.value
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    }
    catch {
        Write-Error "Failed to retrieve Entra ID groups: $_"
    }
    
    return $groups
}
function Get-EntraIDGroupInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array] $groups
    )
    
    $groupReport = @()  # Initialize the report array
    $count = $groups.Count
    $num = 1

    # Get all Conditional Access Policy groups
    try {
        $uri = 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies'
        $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
        $conditonalAccessGroups += $result.value.conditions.users.excludeGroups | Select-Object -Unique
        $conditonalAccessGroups += $result.value.conditions.users.includeGroups | Select-Object -Unique
    }
    catch {
        $null
    }
    
    foreach ($group in $groups) {
        # Check if the token is about to expire
        if ((Get-Date).AddMinutes(3) -ge $script:expiresDateTime) {
            Write-Host "Token is about to expire. Attempting to reconnect to Microsoft Graph..." -ForegroundColor Yellow
            try {
                Connect-MSGraphPowershell -ClientId $ClientId -TenantId $TenantId -ClientSecret $ClientSecret
            }
            catch {
                Write-Host "Failed to reconnect to Microsoft Graph. Exiting..." -ForegroundColor Red
                return
            }
        }
    
        Write-Host "Processing group $num of $count" -ForegroundColor Yellow -NoNewline
    
        # Determine membership type
        $membershipType = if ($group.membershipRule) { "Dynamic" } else { "Assigned" }
    
        # Get group owners
        $uri = "https://graph.microsoft.com/beta/groups/$($group.id)/owners"
        try {
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
            $groupOwners = $result.value.mail -join ", "
        }
        catch {
            $groupOwners = "Error retrieving owners"
        }
    
        # Get groups assigned to target group
        $groupGroups = $group.Members | Where-Object { $_.'@odata.type' -match "group" }
        $assignedGroups = $groupGroups.displayName -join ", "
    
        # Get group member count
        $groupCount = @()  # Initialize group count array
        $uri = "https://graph.microsoft.com/beta/groups/$($group.id)/members?`$top=999"
        do {
            try {
                $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
                $groupCount += $result.value
                $uri = $result.'@odata.nextLink'
                Start-Sleep -Milliseconds 500  # Avoid throttling
            }
            catch {
                Write-Host "Error retrieving members for group $($group.id)" -ForegroundColor Red
                break
            }
        } while ($uri)
    
        # Count the number of users and groups
        $memberCount = ($groupCount | Where-Object { $_.'@odata.type' -match "user" }).Count
        $groupsCount = ($groupCount | Where-Object { $_.'@odata.type' -match "group" }).Count
    
        # Determine the group type
        $type = if ($group.groupTypes[0] -eq "Unified") { "Microsoft 365" } 
        elseif ($group.securityEnabled) { "Security" }
        else { "Distribution" }

        # Check if group is a MS Teams Team
        try {
            $uri = 'https://graph.microsoft.com/beta/groups/$($group.id)/team'
            $result = Invoke-RestMethod -Method Get -Uri $uriTest -Headers $script:header
            $teams = "Yes"
        }
        catch {
            $teams = "No"
        }

        # Check if group is assigned to Conditional Access Policy
        $conditonalAccess = if ($conditonalAccessGroups -contains $group.id) { "Yes" } else { "No" }
    
        # Create the group report object
        $groupInfo = [PSCustomObject][ordered]@{
            "GroupID"           = $group.id
            "GroupName"         = $group.displayName
            "GroupType"         = $type
            "TeamsTeam/Channel" = $teams
            "CAPolicyAssigned" = $conditonalAccess
            "MembershipType"    = $membershipType
            "UserMemberCount"   = $memberCount
            "GroupMemberCount"  = $groupsCount
            "AssignedGroups"    = if ($assignedGroups) { $assignedGroups } else { $null }
            "GroupEmail"        = $group.mail
            "CreatedOn"         = $group.createdDateTime
            "Owner"             = $groupOwners
            "Description"       = $group.description
        }
    
        $groupReport += $groupInfo
    
        # Clear the line after displaying
        if ($num -lt $count) {
            Write-Host "`r" -NoNewline
        }
    
        $num++
    }
    
    return $groupReport
}
function Get-EntraIDEnterpriseAppAssignments {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array] $groups
    )
    
    $entApps = @()
    $num = 1
    $count = $groups.Count
    
    foreach ($group in $groups) {
          
        if ((Get-Date).AddMinutes(3) -ge $script:expiresDateTime) {
            Write-Host "Token is about to expire. Attempting to reconnect to Microsoft Graph..." -ForegroundColor Yellow
            try {
                Connect-MSGraphPowerShell -ClientId $ClientId -TenantId $TenantId -ClientSecret $ClientSecret
            }
            catch {
                Write-Host "Failed to reconnect to Microsoft Graph. Exiting..." -ForegroundColor Red
                return
            }
        }
  
        Write-Host "Processing group $num of $count" -ForegroundColor Yellow -NoNewline
        try {
            $uri = "https://graph.microsoft.com/beta/groups/$($group.id)/appRoleAssignments"
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
            $groupSPs = $result.value | Where-Object { $_.principalType -eq 'Group' } |
            Select-Object principalId, principalDisplayName, resourceDisplayName
        }
        catch {
            Write-Host "`nError processing group: $($group.displayName)" -ForegroundColor Red
            $groupSPs = $null
        }
    
        if ($groupSPs) {
            $entApps += $groupSPs | ForEach-Object {
                [PSCustomObject]@{
                    GroupName = $_.principalDisplayName
                    GroupID   = $_.principalId
                    AppName   = $_.resourceDisplayName -join ", "
                }
            }
        }
    
        # Clear the line after displaying
        if ($num -lt $count) {
            Write-Host "`r" -NoNewline
        }
        $num++
    }
    
    Write-Host "`n"
    Write-Host "Found groups assigned to $($entApps.Count) Enterprise Applications.`n" -ForegroundColor Green
    return $entApps
}
function Get-IntuneSettingsCatalogPolicies {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    }
    catch {
        Write-Error "Failed to retrieve configuration profiles: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntuneDeviceConfigurations {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$expand=groupAssignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntuneAdminTemplatePolicies {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/grouppolicyconfigurations?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntunePowershellScripts {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntuneDeviceCompliancePolicies {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntuneDeviceFeatureUpdatePolicies {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntuneDeployedApplications {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntuneRemediationScripts {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntuneSecurityPolicies {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/intents?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    
        foreach ($policy in $policies) {
            $uri = "https://graph.microsoft.com/beta/deviceManagement/intents/$($policy.id)?`$expand=assignments"
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
            $assignments = $result.assignments
            # Add the assignments to the policy object
            $policy | Add-Member -MemberType NoteProperty -Name assignments -Value $assignments -Force
        }
    
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntuneAutopilotProfiles {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntuneAutopilotConfigurations {
    # Initialize an array to store policies
    $policies = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments"
    
    # Fetch all pages of configuration policies
    try {
        do {
            # Fetch data from the API
            $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:header
    
            # Add the current page's policies to the array
            $policies += $result.value
    
            # Get the next page URI, if available
            $uri = $result.'@odata.nextLink'
    
            # Add a delay to avoid throttling
            Start-Sleep -Milliseconds 500
        } while ($uri)
    
    }
    catch {
        Write-Error "Failed to retrieve device configurations: $_"
    }
    
    # Return all policies
    return $policies
}
function Get-IntunePolicyGroupInfo {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        $deviceConfig,
          
        [Parameter(Mandatory = $true)]
        $Groups
    )
    begin {
        # Static group IDs for "All Devices" and "All Users"
        $allDevices = 'adadadad-808e-44e2-905a-0b7873a8a531'
        $allUsers = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'
        $configGroup = @()
    }
    
    process {
        foreach ($config in $deviceConfig) {
            # Handle variation in name property
            $name = if ($config.PSObject.Properties['displayName']) {
                $config.displayName
            }
            elseif ($config.PSObject.Properties['name']) {
                $config.name
            }
            else {
                "Unknown Name"
            }
    
            # Determine the Type property
            $rawType = if ($config.PSObject.Properties['@odata.type']) {
                $config.'@odata.type'.trim("#microsoft.graph.")
            }
            elseif ($null -eq $config.PSObject.Properties['@odata.type']) {
                $null
            }
    
            # Determine friendlyType based on available data
            $friendlyType = if ($rawType) {
                switch ($rawType) {
                    "eSuiteA" { "Microsoft 365 Apps (Windows 10 and later)" }
                    "win32LobA" { "Windows app (Win32)" }
                    "windowsStoreApp" { "Microsoft Store app (legacy)" }
                    "windowsMicrosoftEdgeApp" { "Microsoft Edge (Windows 10 and later)" }
                    "windowsMicrosoftEdgeA" { "Microsoft Edge (Windows 10 and later)" }
                    "windowsOfficeSuiteApp" { "Microsoft 365 Apps (Windows 10 and later)" }
                    "win32LobApp" { "Windows app (Win32)" }
                    "windowsMobileMSI" { "Windows MSI line-of-business app" }
                    "winGetApp" { "Microsoft Store app (new)" }
                    "winGetA" { "Microsoft Store app (new)" }
                    "windows10CustomConfiguration" { "Windows Custom Configuration" }
                    "windows10EndpointProtectionConfiguration" { "Windows Endpoint Protection Configuration" }
                    "windowsIdentityProtectionConfiguration" { "Windows Identity Protection Configuration" }
                    "windows81TrustedRootCertificate" { "Windows Trusted Root Certificate" }
                    "windows10GeneralConfiguration" { "Windows General Configuration" }
                    "windowsWifiConfiguration" { "Windows Wi-Fi Configuration" }
                    "windows81SCEPCertificateProfile" { "Windows SCEP Certificate Profile" }
                    "windowsWifiEnterpriseEAPConfiguration" { "Windows Wi-Fi Enterprise EAP Configuration" }
                    "windowsWiredNetworkConfiguration" { "Windows Wired Network Configuration" }
                    "windowsUpdateForBusinessConfiguration" { "Windows Update for Business Configuration" }
                    "windowsHealthMonitoringConfiguration" { "Windows Health Monitoring Configuration" }
                    "editionUpgradeConfiguration" { "Edition Upgrade Configuration" }
                    "androidCompliancePolicy" { "Android Compliance Policy" }
                    "ndroidCompliancePolicy" { "Android Compliance Policy" }
                    "windows10CompliancePolicy" { "Windows Compliance Policy" }
                    "macOSCompliancePolicy" { "macOS Compliance Policy" }
                    "OSCompliancePolicy" { "macOS Compliance Policy" }
                    "iosCompliancePolicy" { "iOS Compliance Policy" }
                    "CompliancePolicy" { "iOS Compliance Policy" }
                    "azureADWindowsAutopilotDeploymentProfile" { "Windows Autopilot Deployment Profile" }
                    "zureADWindowsAutopilotDeploymentProfile" { "Windows Autopilot Deployment Profile" }
                    "deviceEnrollmentLimitConfiguration" { "Device Enrollment Limit Configuration" }
                    "deviceEnrollmentPlatformRestrictionsConfiguration" { "Device Enrollment Platform Restrictions Configuration" }
                    "deviceEnrollmentWindowsHelloForBusinessConfiguration" { "Device Enrollment Windows Hello for Business Configuration" }
                    "windows10EnrollmentCompletionPageConfiguration" { "Windows Enrollment Completion Page Configuration" }
                    "deviceEnrollmentPlatformRestrictionConfiguration" { "Device Enrollment Platform Restriction Configuration" }
                    default { $rawType } # Fallback to raw type if no match
                }
            }
            elseif ($config.PSObject.Properties['assignments@odata.context'] -and 
                $config.'assignments@odata.context' -match "deviceManagement/configurationPolicies") {
                "Settings Catalog"
            }
            elseif ($config.PSObject.Properties['assignments@odata.context'] -and 
                $config.'assignments@odata.context' -match "deviceManagement/groupPolicyConfigurations") {
                "Administrative Templates"
            }
            elseif ($config.PSObject.Properties['assignments@odata.context'] -and 
                $config.'assignments@odata.context' -match "deviceManagement/deviceManagementScripts") {
                "Powershell Scripts"
            }
            elseif ($config.PSObject.Properties['assignments@odata.context'] -and 
                $config.'assignments@odata.context' -match "deviceManagement/deviceHealthScripts") {
                "Remediation Scripts"
            }
            elseif ($config.PSObject.Properties['assignments@odata.context'] -and 
                $config.'assignments@odata.context' -match "deviceManagement/intents") {
                "Endpoint Security"
            }
            elseif ($config.PSObject.Properties['assignments@odata.context'] -and 
                $config.'assignments@odata.context' -match "deviceManagement/windowsFeatureUpdateProfiles") {
                "Feature Updates"
            }
            else {
                "N/A"
            }
    
            # Handle variations in group assignments
            $groupAssignments = if ($config.PSObject.Properties['groupAssignments']) {
                $config.groupAssignments | Select-Object targetGroupID, excludeGroup
            }
            elseif ($config.PSObject.Properties['assignments']) {
                $config.assignments.target | Select-Object groupID, '@odata.type'
            }
            else {
                $null
            }
    
            if ($groupAssignments) {
                foreach ($assignment in $groupAssignments) {
                    # Handle variations in assignment data structure
                    $groupID = if ($assignment.PSObject.Properties['targetGroupID']) {
                        $assignment.targetGroupID
                    }
                    elseif ($assignment.PSObject.Properties['groupID']) {
                        $assignment.groupID
                    }
                    else {
                        $null
                    }
    
                    # Check if the group is "All Devices" or "All Users" and set the $groupID accordingly
                    if (($groupID -eq $allDevices) -or ($assignment.'@odata.type' -like "*allDevicesAssignment*")) {
                        $groupID = $allDevices
                    }
                    elseif (($groupID -eq $allUsers) -or ($assignment.'@odata.type' -like "*allLicensedUsersAssignment*")) {
                        $groupID = $allUsers
                    }
    
                    $groupName = if (($groupID -eq $allDevices) -or ($assignment.'@odata.type' -like "*allDevicesAssignment*")) {
                        "All Devices"
                    }
                    elseif (($groupID -eq $allUsers) -or ($assignment.'@odata.type' -like "*allLicensedUsersAssignment*")) {
                        "All Users"
                    }
                    else {
                          ($Groups | Where-Object { $_.id -eq $groupID }).displayName
                    }
    
                    $groupAssignmentType = if ($assignment.PSObject.Properties['excludeGroup']) {
                        if ($assignment.excludeGroup -eq $true) {
                            "Excluded"
                        }
                        else {
                            "Included"
                        }
                    }
                    elseif ($assignment.PSObject.Properties['@odata.type']) {
                        if ($assignment.'@odata.type' -notlike "*exclusion*") {
                            "Included"
                        }
                        else {
                            "Excluded"
                        }
                    }
                    else {
                        "Unknown"
                    }
    
                    $configGroup += [PSCustomObject][ordered]@{
                        "GroupName"        = $groupName
                        "GroupAssignment"  = $groupAssignmentType
                        "GroupID"          = $groupID  
                        "IntuneAssignment" = $name
                        "Type"             = $friendlyType
                    }
                }
            }
            else {
                $configGroup += [PSCustomObject][ordered]@{
                    "GroupName"        = $null
                    "GroupAssignment"  = $null
                    "GroupID"          = $null  
                    "IntuneAssignment" = $name
                    "Type"             = $friendlyType
                }
            }
        }
    }
    end {
        return $configGroup
    }
      
}
function Confirm-ImportExcelModule {
    # Check if the ImportExcel module is available
    if (-not (Get-Module -ListAvailable -Name "ImportExcel")) {
        Write-Host "ImportExcel module not found. Installing..." -ForegroundColor Yellow

        try {
            # Install the ImportExcel module
            Install-Module -Name "ImportExcel" -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "ImportExcel module installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to install ImportExcel module. Error: $_" -ForegroundColor Red
            throw
        }
    }
    else {
        Write-Host "ImportExcel module is already installed." -ForegroundColor Green
    }
}
#endregion
#-------------------------------------------------------------------------------------#

# Connect to Graph and create script header variable for API calls
Connect-MSGraphPowershell -ClientId $ClientId -TenantId $TenantId -ClientSecret $ClientSecret
    
# Get time that the script started
$startTime = Get-Date
   
# Get all Entra ID groups
$groups = @()
$groups += Get-AllEntraIDgroups
  
# Get all Entra ID group information
$groupReport = @()
$groupReport += Get-EntraIDGroupInfo -groups $groups
  
# Get all Enterprise Applications assigned to Entra ID groups
$entApps = @()
$entApps += Get-EntraIDEnterpriseAppAssignments -groups $groups
  
# Initialize an empty master array for Intune Policies
$allIntunePolicyGroups = @()
  
# Get all Intune policy groups and add to master array
$allIntunePolicyGroups += Get-IntuneSettingsCatalogPolicies | Get-IntunePolicyGroupInfo -Groups $groups
$allIntunePolicyGroups += Get-IntuneDeviceConfigurations | Get-IntunePolicyGroupInfo -Groups $groups
$allIntunePolicyGroups += Get-IntuneAdminTemplatePolicies | Get-IntunePolicyGroupInfo -Groups $groups
$allIntunePolicyGroups += Get-IntunePowershellScripts | Get-IntunePolicyGroupInfo -Groups $groups
$allIntunePolicyGroups += Get-IntuneDeviceCompliancePolicies | Get-IntunePolicyGroupInfo -Groups $groups
$allIntunePolicyGroups += Get-IntuneDeviceFeatureUpdatePolicies | Get-IntunePolicyGroupInfo -Groups $groups
$deployedApps = Get-IntuneDeployedApplications | Where-Object { $_.'@odata.type' -notlike "*ios*" -and $_.'@odata.type' -notlike "*android*" }
$allIntunePolicyGroups += $deployedApps | Get-IntunePolicyGroupInfo -Groups $groups
$allIntunePolicyGroups += Get-IntuneRemediationScripts | Get-IntunePolicyGroupInfo -Groups $groups
$allIntunePolicyGroups += Get-IntuneSecurityPolicies | Get-IntunePolicyGroupInfo -Groups $groups
$allIntunePolicyGroups += Get-IntuneAutopilotProfiles | Get-IntunePolicyGroupInfo -Groups $groups
$allIntunePolicyGroups += Get-IntuneAutopilotConfigurations | Get-IntunePolicyGroupInfo -Groups $groups

# Set variable for file name
$fileName = "$(Get-Date -Format 'yyyy-MM-dd')_EntraGroupInfo.xlsx"

# Import the ImportExcel module
Confirm-ImportExcelModule

# Export the data to an Excel file
$groupReport | Sort-Object -Property { $_.GroupName } | Export-Excel -Path "$fileName" -WorksheetName "All EntraID Groups" -AutoSize -AutoFilter -BoldTopRow
$allIntunePolicyGroups | Sort-Object -Property { $_.GroupName } | Export-Excel -Path "$fileName" -Append -WorksheetName "Intune Assignments" -AutoSize -AutoFilter -BoldTopRow
$entApps | Sort-Object -Property { $_.GroupName } | Export-Excel -Path "$fileName" -Append -WorksheetName "Enterprise App Assignments" -AutoSize -AutoFilter -BoldTopRow
    
# Display completion message
$endTime = Get-Date
$totalTime = New-TimeSpan -Start $startTime -End $endTime
Write-Host "`nOperation completed in $($totalTime.Hours) hours and $($totalTime.Minutes) minutes." -ForegroundColor Green
