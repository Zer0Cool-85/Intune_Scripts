<#
.SYNOPSIS
    Locks down a Windows device for terminated-user containment while preserving IT access
    through a LAPS-managed local admin account.

.DESCRIPTION
    Intended to run as SYSTEM from Intune Win32 app.

    The script:
    - Finds existing user profiles on the device
    - Excludes built-in profiles and approved local admin accounts, such as WINADMIN
    - Adds remaining user SIDs to:
        SeDenyInteractiveLogonRight
        SeDenyRemoteInteractiveLogonRight
    - Removes target users from local Administrators and Remote Desktop Users
    - Optionally disables cached domain logons
    - Logs off active non-allowed interactive sessions
    - Writes a detection registry key for Intune

.NOTES
    Test before production.
    Deny logon rights override group membership, including local Administrators.
#>

[CmdletBinding()]
param(
    # Built-in/system profile folders to ignore
    [string[]]$AllowedProfileNames = @(
        'Administrator',
        'Default',
        'Default User',
        'Public',
        'All Users',
        'WDAGUtilityAccount',
        'WINADMIN'
    ),

    # Local accounts that must retain access after lockdown
    [string[]]$AllowedLocalAdminAccounts = @(
        'WINADMIN'
    ),

    # Set cached domain logons to 0
    [bool]$DisableCachedDomainLogons = $true,

    # Log off active user sessions after lockdown
    [bool]$LogoffInteractiveSessions = $true,

    # Restart after applying lockdown
    [bool]$RestartAfterLockdown = $false,

    # Restart countdown
    [int]$RestartDelaySeconds = 60
)

$ErrorActionPreference = 'Stop'

$BasePath = Join-Path $env:ProgramData 'Company\TerminationLockdown'
$LogPath  = Join-Path $BasePath 'Lockdown.log'
$RegPath  = 'HKLM:\SOFTWARE\Company\TerminationLockdown'

New-Item -Path $BasePath -ItemType Directory -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $line = '{0} - {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogPath -Value $line
}

function Get-AllowedLocalAdminSidMap {
    param(
        [Parameter(Mandatory)]
        [string[]]$AccountNames
    )

    $results = foreach ($accountName in $AccountNames) {
        try {
            $account = Get-LocalUser -Name $accountName -ErrorAction Stop

            [pscustomobject]@{
                Name = $account.Name
                SID  = $account.SID.Value
            }
        }
        catch {
            Write-Log "Allowed local admin account '$accountName' was not found. Continuing."
        }
    }

    return @($results | Where-Object { $_.SID } | Sort-Object SID -Unique)
}

function ConvertTo-SecEditSidEntry {
    param(
        [Parameter(Mandatory)]
        [string]$Sid
    )

    if ($Sid -match '^\*') {
        return $Sid
    }

    return "*$Sid"
}

function ConvertFrom-SecEditSidEntry {
    param(
        [Parameter(Mandatory)]
        [string]$Entry
    )

    return ($Entry.Trim() -replace '^\*', '')
}

function Get-ExistingUserRightEntries {
    param(
        [Parameter(Mandatory)]
        [string]$RightName,

        [Parameter(Mandatory)]
        [string]$ExportPath
    )

    $content = Get-Content -Path $ExportPath -ErrorAction Stop
    $line = $content |
        Where-Object { $_ -match "^\s*$([regex]::Escape($RightName))\s*=" } |
        Select-Object -First 1

    if (-not $line) {
        return @()
    }

    $value = ($line -split '=', 2)[1].Trim()

    if ([string]::IsNullOrWhiteSpace($value)) {
        return @()
    }

    return @(
        $value -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

function Update-UserRightMembership {
    param(
        [Parameter(Mandatory)]
        [string]$RightName,

        [string[]]$SidsToAdd = @(),

        [string[]]$SidsToAlwaysExclude = @()
    )

    $workPath   = Join-Path $BasePath "SecEdit-$RightName"
    $exportPath = Join-Path $workPath 'export.inf'
    $importPath = Join-Path $workPath 'import.inf'
    $dbPath     = Join-Path $workPath 'secedit.sdb'

    New-Item -Path $workPath -ItemType Directory -Force | Out-Null

    Write-Log "Exporting current security policy for $RightName"
    & secedit.exe /export /cfg $exportPath | Out-Null

    if (-not (Test-Path $exportPath)) {
        throw "Failed to export local security policy for $RightName."
    }

    $existingEntries = @(Get-ExistingUserRightEntries -RightName $RightName -ExportPath $exportPath)

    $entriesToAdd = @(
        $SidsToAdd |
            Where-Object { $_ } |
            ForEach-Object { ConvertTo-SecEditSidEntry -Sid $_ }
    )

    $excludeSidValues = @(
        $SidsToAlwaysExclude |
            Where-Object { $_ } |
            ForEach-Object { $_ -replace '^\*', '' }
    )

    $combinedEntries = @($existingEntries + $entriesToAdd) |
        Where-Object { $_ } |
        Select-Object -Unique

    # Critical protection:
    # make sure allowed local admin SIDs, such as WINADMIN, are not present in deny rights
    $finalEntries = foreach ($entry in $combinedEntries) {
        $entrySidValue = ConvertFrom-SecEditSidEntry -Entry $entry

        if ($excludeSidValues -contains $entrySidValue) {
            Write-Log "Excluding protected SID from $RightName: $entrySidValue"
            continue
        }

        $entry
    }

    $finalEntries = @($finalEntries | Where-Object { $_ } | Select-Object -Unique)

    if ($finalEntries.Count -gt 0) {
        $rightLine = "$RightName = $($finalEntries -join ',')"
    }
    else {
        $rightLine = "$RightName ="
    }

    $inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
$rightLine
"@

    Set-Content -Path $importPath -Value $inf -Encoding Unicode -Force

    Write-Log "Applying $RightName with entries: $($finalEntries -join ',')"
    & secedit.exe /configure /db $dbPath /cfg $importPath /areas USER_RIGHTS | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "secedit failed while applying $RightName. Exit code: $LASTEXITCODE"
    }
}

function Get-TargetUserProfiles {
    param(
        [string[]]$AllowedSidValues = @()
    )

    $profileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

    Get-ChildItem -Path $profileListPath -ErrorAction SilentlyContinue | ForEach-Object {
        $sid = $_.PSChildName

        # Skip allowed local admin SID, such as WINADMIN
        if ($AllowedSidValues -contains $sid) {
            Write-Log "Skipping protected local admin SID: $sid"
            return
        }

        # Include local/domain SIDs and Entra/AAD user SIDs.
        # Exclude service/system SIDs.
        if ($sid -notmatch '^(S-1-5-21-|S-1-12-1-)') {
            return
        }

        try {
            $profile = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
        }
        catch {
            return
        }

        if ([string]::IsNullOrWhiteSpace($profile.ProfileImagePath)) {
            return
        }

        $profilePath = [Environment]::ExpandEnvironmentVariables($profile.ProfileImagePath)

        if ($profilePath -notlike "$env:SystemDrive\Users\*") {
            return
        }

        $profileName = Split-Path -Path $profilePath -Leaf

        if ($AllowedProfileNames -contains $profileName) {
            Write-Log "Skipping allowed profile name: $profileName"
            return
        }

        [pscustomobject]@{
            Sid         = $sid
            ProfileName = $profileName
            ProfilePath = $profilePath
        }
    }
}

function Remove-TargetsFromLocalGroups {
    param(
        [Parameter(Mandatory)]
        [object[]]$Targets,

        [string[]]$AllowedSidValues = @()
    )

    $groups = @(
        'Administrators',
        'Remote Desktop Users'
    )

    foreach ($group in $groups) {
        try {
            $members = @(Get-LocalGroupMember -Group $group -ErrorAction Stop)
        }
        catch {
            Write-Log "Unable to read local group '$group'. Error: $($_.Exception.Message)"
            continue
        }

        foreach ($target in $Targets) {
            if ($AllowedSidValues -contains $target.Sid) {
                Write-Log "Skipping protected SID while checking local group '$group': $($target.Sid)"
                continue
            }

            $matchingMembers = $members | Where-Object {
                $_.SID -and $_.SID.Value -eq $target.Sid
            }

            foreach ($member in $matchingMembers) {
                try {
                    Write-Log "Removing $($member.Name) / $($target.Sid) from local group '$group'"
                    Remove-LocalGroupMember -Group $group -Member $member -ErrorAction Stop
                }
                catch {
                    Write-Log "Failed to remove $($target.Sid) from '$group'. Error: $($_.Exception.Message)"
                }
            }
        }
    }
}

function Disable-CachedDomainLogons {
    $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

    Write-Log "Setting CachedLogonsCount to 0"
    New-ItemProperty `
        -Path $winlogonPath `
        -Name 'CachedLogonsCount' `
        -Value '0' `
        -PropertyType String `
        -Force | Out-Null
}

function Get-InteractiveSessions {
    $raw = & query.exe user 2>$null

    if (-not $raw) {
        return @()
    }

    $sessions = foreach ($line in ($raw | Select-Object -Skip 1)) {
        $cleanLine = ($line -replace '^\s*>', '' -replace '\s+', ' ').Trim()

        if ([string]::IsNullOrWhiteSpace($cleanLine)) {
            continue
        }

        $parts = $cleanLine -split ' '

        $idIndex = $null
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -match '^\d+$') {
                $idIndex = $i
                break
            }
        }

        if ($null -eq $idIndex) {
            continue
        }

        [pscustomobject]@{
            UserName  = $parts[0]
            SessionId = [int]$parts[$idIndex]
        }
    }

    return @($sessions)
}

function Logoff-InteractiveSessions {
    param(
        [string[]]$AllowedAccountNames = @()
    )

    $sessions = @(Get-InteractiveSessions)

    foreach ($session in $sessions) {
        $sessionUser = $session.UserName
        $shortName = ($sessionUser -split '\\')[-1]

        if ($AllowedAccountNames -contains $shortName) {
            Write-Log "Skipping logoff for protected local admin session: $sessionUser / Session ID $($session.SessionId)"
            continue
        }

        try {
            Write-Log "Logging off interactive session $sessionUser / Session ID $($session.SessionId)"
            & logoff.exe $session.SessionId /V
        }
        catch {
            Write-Log "Failed to log off session $($session.SessionId). Error: $($_.Exception.Message)"
        }
    }
}

try {
    Write-Log "========== Termination lockdown started =========="

    $allowedAdminSidMap = @(Get-AllowedLocalAdminSidMap -AccountNames $AllowedLocalAdminAccounts)
    $allowedAdminSids = @($allowedAdminSidMap.SID | Where-Object { $_ } | Select-Object -Unique)

    if ($allowedAdminSidMap.Count -gt 0) {
        Write-Log "Protected local admin accounts:"
        foreach ($entry in $allowedAdminSidMap) {
            Write-Log " - $($entry.Name) | $($entry.SID)"
        }
    }
    else {
        Write-Log "WARNING: No protected local admin accounts were resolved."
    }

    $targets = @(Get-TargetUserProfiles -AllowedSidValues $allowedAdminSids)

    if ($targets.Count -eq 0) {
        Write-Log "No target user profiles found."
    }
    else {
        Write-Log "Target profiles:"
        foreach ($target in $targets) {
            Write-Log " - $($target.ProfileName) | $($target.ProfilePath) | $($target.Sid)"
        }

        Remove-TargetsFromLocalGroups `
            -Targets $targets `
            -AllowedSidValues $allowedAdminSids
    }

    $targetSids = @($targets.Sid | Where-Object { $_ } | Select-Object -Unique)

    # Apply deny logon rights to targeted users only.
    # Also explicitly remove/protect WINADMIN or other allowed local admin SIDs from deny rights.
    Update-UserRightMembership `
        -RightName 'SeDenyInteractiveLogonRight' `
        -SidsToAdd $targetSids `
        -SidsToAlwaysExclude $allowedAdminSids

    Update-UserRightMembership `
        -RightName 'SeDenyRemoteInteractiveLogonRight' `
        -SidsToAdd $targetSids `
        -SidsToAlwaysExclude $allowedAdminSids

    if ($DisableCachedDomainLogons) {
        Disable-CachedDomainLogons
    }

    New-Item -Path $RegPath -Force | Out-Null

    New-ItemProperty `
        -Path $RegPath `
        -Name 'State' `
        -Value 'Locked' `
        -PropertyType String `
        -Force | Out-Null

    New-ItemProperty `
        -Path $RegPath `
        -Name 'LockedOn' `
        -Value (Get-Date).ToString('o') `
        -PropertyType String `
        -Force | Out-Null

    New-ItemProperty `
        -Path $RegPath `
        -Name 'TargetSids' `
        -Value ($targetSids -join ',') `
        -PropertyType String `
        -Force | Out-Null

    New-ItemProperty `
        -Path $RegPath `
        -Name 'ProtectedLocalAdmins' `
        -Value (($allowedAdminSidMap | ForEach-Object { "$($_.Name):$($_.SID)" }) -join ',') `
        -PropertyType String `
        -Force | Out-Null

    Write-Log "Detection registry state written."

    if ($LogoffInteractiveSessions) {
        Logoff-InteractiveSessions -AllowedAccountNames $AllowedLocalAdminAccounts
    }

    if ($RestartAfterLockdown) {
        Write-Log "Restart scheduled in $RestartDelaySeconds seconds."
        & shutdown.exe /r /t $RestartDelaySeconds /f /c "This device has been restricted by IT."
    }

    Write-Log "========== Termination lockdown completed =========="
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "========== Termination lockdown failed =========="
    exit 1
}




# DETECTION

$RegPath = 'HKLM:\SOFTWARE\Company\TerminationLockdown'

try {
    $state = Get-ItemProperty -Path $RegPath -Name State -ErrorAction Stop

    if ($state.State -eq 'Locked') {
        exit 0
    }
}
catch {
    exit 1
}

exit 1
