# Requires ImportExcel if you want .xlsx output:
# Install-Module ImportExcel -Scope CurrentUser

param(
    [Parameter(Mandatory = $true)]
    [string]$OktaOrgUrl, # Example: https://company.okta.com

    [Parameter(Mandatory = $true)]
    [string]$ApiToken,

    [string]$OutputPath = "$env:TEMP\Okta-Device-Report.xlsx"
)

$OktaOrgUrl = $OktaOrgUrl.TrimEnd('/')

$Headers = @{
    Authorization = "SSWS $ApiToken"
    Accept        = "application/json"
}

function Get-NextLink {
    param(
        [Parameter(Mandatory = $true)]
        $Headers
    )

    $linkHeader = $Headers['Link']
    if (-not $linkHeader) {
        return $null
    }

    $linkHeaderValue = ($linkHeader -join ',')

    foreach ($link in ($linkHeaderValue -split ',')) {
        if ($link -match '<([^>]+)>;\s*rel="next"') {
            return $matches[1]
        }
    }

    return $null
}

function Invoke-OktaPagedRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    do {
        Write-Host "Querying: $Uri"

        try {
            $response = Invoke-WebRequest `
                -Uri $Uri `
                -Headers $Headers `
                -Method Get `
                -UseBasicParsing `
                -ErrorAction Stop
        }
        catch {
            throw "Okta API request failed. $($_.Exception.Message)"
        }

        if ($response.Content) {
            $items = $response.Content | ConvertFrom-Json

            foreach ($item in @($items)) {
                $item
            }
        }

        $Uri = Get-NextLink -Headers $response.Headers

    } while ($Uri)
}

function Get-SafeValue {
    param(
        [object]$Object,
        [string[]]$PropertyNames
    )

    if (-not $Object) {
        return $null
    }

    foreach ($propertyName in $PropertyNames) {
        if ($Object.PSObject.Properties.Name -contains $propertyName) {
            $value = $Object.$propertyName

            if ($null -ne $value -and "$value".Trim() -ne '') {
                return $value
            }
        }
    }

    return $null
}

function Normalize-ManagementStatus {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'UNKNOWN'
    }

    switch -Regex ($Value.Trim()) {
        '^(?i)not[\s_-]?managed$' { return 'NOT_MANAGED' }
        '^(?i)unmanaged$'         { return 'NOT_MANAGED' }
        '^(?i)managed$'           { return 'MANAGED' }
        default                   { return $Value.Trim() }
    }
}

$deviceUri = "$OktaOrgUrl/api/v1/devices?limit=200&expand=user"
$devices = @(Invoke-OktaPagedRequest -Uri $deviceUri)

$detailRows = foreach ($device in $devices) {
    $deviceUsers = @()

    if (
        $device.PSObject.Properties.Name -contains '_embedded' -and
        $device._embedded.PSObject.Properties.Name -contains 'users' -and
        $device._embedded.users
    ) {
        $deviceUsers = @($device._embedded.users)
    }

    # Keep devices with no embedded users visible in the report.
    if ($deviceUsers.Count -eq 0) {
        [pscustomobject]@{
            DeviceId          = $device.id
            DeviceName        = $device.profile.displayName
            Platform          = $device.profile.platform
            Registered        = $device.profile.registered
            SerialNumber      = $device.profile.serialNumber
            DeviceStatus      = $device.status
            DeviceCreated     = $device.created
            DeviceLastUpdated = $device.lastUpdated

            UserId            = $null
            UserLogin         = $null
            UserEmail         = $null
            UserDisplayName   = $null
            UserStatus        = $null
            ManagementStatus  = 'NO_ASSOCIATED_USER'
            ScreenLockType    = $null
            EnrollmentDate    = $null
        }

        continue
    }

    foreach ($deviceUser in $deviceUsers) {
        # Okta response shapes can vary slightly depending on endpoint/expansion.
        # This handles the common cases:
        # - $deviceUser is the user object
        # - $deviceUser.user contains the user object
        # - $deviceUser._embedded.user contains the user object
        $userObject = $null

        if ($deviceUser.PSObject.Properties.Name -contains 'user') {
            $userObject = $deviceUser.user
        }
        elseif (
            $deviceUser.PSObject.Properties.Name -contains '_embedded' -and
            $deviceUser._embedded.PSObject.Properties.Name -contains 'user'
        ) {
            $userObject = $deviceUser._embedded.user
        }
        else {
            $userObject = $deviceUser
        }

        $managementStatus = Get-SafeValue `
            -Object $deviceUser `
            -PropertyNames @('managementStatus', 'deviceManagementStatus')

        $screenLockType = Get-SafeValue `
            -Object $deviceUser `
            -PropertyNames @('screenLockType', 'screenLock')

        $enrollmentDate = Get-SafeValue `
            -Object $deviceUser `
            -PropertyNames @('created', 'enrollmentDate', 'enrolled', 'registered')

        $firstName = $userObject.profile.firstName
        $lastName  = $userObject.profile.lastName
        $displayName = (($firstName, $lastName) | Where-Object { $_ }) -join ' '

        [pscustomobject]@{
            DeviceId          = $device.id
            DeviceName        = $device.profile.displayName
            Platform          = $device.profile.platform
            Registered        = $device.profile.registered
            SerialNumber      = $device.profile.serialNumber
            DeviceStatus      = $device.status
            DeviceCreated     = $device.created
            DeviceLastUpdated = $device.lastUpdated

            UserId            = $userObject.id
            UserLogin         = $userObject.profile.login
            UserEmail         = $userObject.profile.email
            UserDisplayName   = $displayName
            UserStatus        = $userObject.status
            ManagementStatus  = Normalize-ManagementStatus -Value $managementStatus
            ScreenLockType    = $screenLockType
            EnrollmentDate    = $enrollmentDate
        }
    }
}

$summaryRows = foreach ($group in ($detailRows | Group-Object DeviceId)) {
    $rows = @($group.Group)
    $first = $rows[0]

    $realStatuses = @(
        $rows.ManagementStatus |
            Where-Object { $_ -and $_ -ne 'NO_ASSOCIATED_USER' } |
            Sort-Object -Unique
    )

    $overallManagementStatus = if ($realStatuses.Count -eq 0) {
        'NO_ASSOCIATED_USER'
    }
    elseif ($realStatuses.Count -eq 1) {
        $realStatuses[0]
    }
    else {
        'MIXED'
    }

    $managedUsers = @(
        $rows |
            Where-Object { $_.ManagementStatus -eq 'MANAGED' } |
            ForEach-Object { $_.UserLogin } |
            Where-Object { $_ }
    )

    $notManagedUsers = @(
        $rows |
            Where-Object { $_.ManagementStatus -eq 'NOT_MANAGED' } |
            ForEach-Object { $_.UserLogin } |
            Where-Object { $_ }
    )

    $userBreakdown = @(
        $rows |
            Where-Object { $_.UserLogin } |
            ForEach-Object { "$($_.UserLogin) [$($_.ManagementStatus)]" }
    ) -join '; '

    [pscustomobject]@{
        DeviceId                = $first.DeviceId
        DeviceName              = $first.DeviceName
        Platform                = $first.Platform
        Registered              = $first.Registered
        SerialNumber            = $first.SerialNumber
        DeviceStatus            = $first.DeviceStatus
        DeviceCreated           = $first.DeviceCreated
        DeviceLastUpdated       = $first.DeviceLastUpdated

        OverallManagementStatus = $overallManagementStatus
        AssociatedUserCount     = @($rows | Where-Object { $_.UserLogin }).Count
        ManagedUserCount        = $managedUsers.Count
        NotManagedUserCount     = $notManagedUsers.Count
        ManagedUsers            = $managedUsers -join '; '
        NotManagedUsers         = $notManagedUsers -join '; '
        UserStatusBreakdown     = $userBreakdown
    }
}

if (Get-Module -ListAvailable -Name ImportExcel) {
    $detailRows |
        Sort-Object DeviceName, UserLogin |
        Export-Excel `
            -Path $OutputPath `
            -WorksheetName 'DeviceUserDetail' `
            -TableName 'DeviceUserDetail' `
            -AutoSize `
            -AutoFilter `
            -FreezeTopRow `
            -BoldTopRow `
            -ClearSheet

    $summaryRows |
        Sort-Object DeviceName |
        Export-Excel `
            -Path $OutputPath `
            -WorksheetName 'DeviceSummary' `
            -TableName 'DeviceSummary' `
            -AutoSize `
            -AutoFilter `
            -FreezeTopRow `
            -BoldTopRow `
            -Append

    Write-Host "Excel report created: $OutputPath"
}
else {
    $detailCsv = [System.IO.Path]::ChangeExtension($OutputPath, '.DeviceUserDetail.csv')
    $summaryCsv = [System.IO.Path]::ChangeExtension($OutputPath, '.DeviceSummary.csv')

    $detailRows |
        Sort-Object DeviceName, UserLogin |
        Export-Csv -Path $detailCsv -NoTypeInformation -Encoding UTF8

    $summaryRows |
        Sort-Object DeviceName |
        Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8

    Write-Warning "ImportExcel module not found. Exported CSV files instead:"
    Write-Host $detailCsv
    Write-Host $summaryCsv
}
