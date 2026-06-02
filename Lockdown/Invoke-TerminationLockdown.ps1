<#
.SYNOPSIS
    Locks down a Windows device for terminated-user containment while preserving IT access
    through a LAPS-managed local admin account.

.DESCRIPTION
    Intended to run as SYSTEM from Microsoft Intune as a Win32 app.

    The script:
    - Finds existing user profiles on the device.
    - Excludes built-in profiles and approved local admin accounts, such as WINADMIN.
    - Adds remaining user SIDs to:
        SeDenyInteractiveLogonRight
        SeDenyRemoteInteractiveLogonRight
    - Removes target users from local Administrators and Remote Desktop Users.
    - Optionally disables cached domain logons.
    - Optionally forces BitLocker recovery on next boot.
    - Optionally adds TPM+PIN BitLocker pre-boot auth.
    - Logs off active non-allowed interactive sessions.
    - Writes a detection registry key for Intune.

.NOTES
    Test before production.
    Deny logon rights override group membership, including local Administrators.
#>

[CmdletBinding()]
param(
    [string[]]$AllowedProfileNames = @(
        'Administrator',
        'Default',
        'Default User',
        'Public',
        'All Users',
        'WDAGUtilityAccount',
        'WINADMIN'
    ),

    [string[]]$AllowedLocalAdminAccounts = @(
        'WINADMIN'
    ),

    [switch]$DisableCachedDomainLogons,

    [switch]$LogoffInteractiveSessions,

    [switch]$RestartAfterLockdown,

    [int]$RestartDelaySeconds = 60,

    # Recommended BitLocker option for terminations.
    # Forces BitLocker recovery on the next boot.
    [switch]$ForceBitLockerRecoveryOnNextBoot,

    # Optional TPM+PIN mode.
    # Only use this when IT has a secure way to escrow/retrieve the PIN.
    [switch]$EnableBitLockerTpmPin,

    # Required when -EnableBitLockerTpmPin is used.
    [string]$PreBootPin,

    # Removes TPM-only protector after adding TPM+PIN.
    # This is what actually enforces PIN entry at boot.
    [switch]$RemoveTpmOnlyProtector,

    # Attempts to back up recovery password protectors to Entra ID.
    [switch]$BackupBitLockerRecoveryKeyToAAD
)

$BootstrapLogPath = 'C:\Windows\Temp\Invoke-TerminationLockdown-Bootstrap.log'

try {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Script started. Running as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)" |
        Out-File -FilePath $BootstrapLogPath -Append -Encoding UTF8

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PowerShell: $($PSVersionTable.PSVersion) | ProcessArch: $env:PROCESSOR_ARCHITECTURE | OSArch: $env:PROCESSOR_ARCHITEW6432" |
        Out-File -FilePath $BootstrapLogPath -Append -Encoding UTF8

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Script path: $PSCommandPath" |
        Out-File -FilePath $BootstrapLogPath -Append -Encoding UTF8
}
catch {
    # Bootstrap logging is best effort only.
}

$ErrorActionPreference = 'Stop'

$BasePath = Join-Path $env:ProgramData 'Company\TerminationLockdown'
$LogPath  = Join-Path $BasePath 'Lockdown.log'
$RegPath  = 'HKLM:\SOFTWARE\Company\TerminationLockdown'
$GroupMembershipBackupPath = Join-Path $BasePath 'RemovedLocalGroupMembership.json'

try {
    New-Item -Path $BasePath -ItemType Directory -Force -ErrorAction Stop | Out-Null

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Created/confirmed log directory: $BasePath" |
        Out-File -FilePath $BootstrapLogPath -Append -Encoding UTF8
}
catch {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FAILED to create log directory $BasePath. Error: $($_.Exception.Message)" |
        Out-File -FilePath $BootstrapLogPath -Append -Encoding UTF8

    exit 1
}

$script:RemovedGroupMembership = @()

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
    # Make sure allowed local admin SIDs, such as WINADMIN, are not present in deny rights.
    $finalEntries = foreach ($entry in $combinedEntries) {
        $entrySidValue = ConvertFrom-SecEditSidEntry -Entry $entry

        if ($excludeSidValues -contains $entrySidValue) {
            Write-Log "Excluding protected SID from $($RightName): $entrySidValue"
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

    Write-Log "Applying $($RightName) with entries: $($finalEntries -join ',')"
    & secedit.exe /configure /db $dbPath /cfg $importPath /areas USER_RIGHTS | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "secedit failed while applying $($RightName). Exit code: $LASTEXITCODE"
    }
}

function Get-TargetUserProfiles {
    param(
        [string[]]$AllowedSidValues = @()
    )

    $profileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

    Get-ChildItem -Path $profileListPath -ErrorAction SilentlyContinue | ForEach-Object {
        $sid = $_.PSChildName

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
            $profileReg = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
        }
        catch {
            return
        }

        if ([string]::IsNullOrWhiteSpace($profileReg.ProfileImagePath)) {
            return
        }

        $profilePath = [Environment]::ExpandEnvironmentVariables($profileReg.ProfileImagePath)

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
                    Write-Log "Backing up and removing $($member.Name) / $($target.Sid) from local group '$group'"

                    $script:RemovedGroupMembership += [pscustomobject]@{
                        GroupName  = $group
                        MemberName = $member.Name
                        SID        = $target.Sid
                        ObjectClass = $member.ObjectClass
                        RemovedOn  = (Get-Date).ToString('o')
                    }

                    Remove-LocalGroupMember -Group $group -Member $member -ErrorAction Stop
                }
                catch {
                    Write-Log "Failed to remove $($target.Sid) from '$group'. Error: $($_.Exception.Message)"
                }
            }
        }
    }
}

function Save-RemovedGroupMembershipBackup {
    if ($script:RemovedGroupMembership.Count -eq 0) {
        Write-Log "No local group membership removals were captured."
        return
    }

    try {
        $script:RemovedGroupMembership |
            ConvertTo-Json -Depth 5 |
            Set-Content -Path $GroupMembershipBackupPath -Encoding UTF8 -Force

        Write-Log "Saved removed local group membership backup to $GroupMembershipBackupPath"
    }
    catch {
        Write-Log "Failed to save group membership backup. Error: $($_.Exception.Message)"
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

function Invoke-BitLockerPreBootLockdown {
    param(
        [string]$MountPoint = 'C:',

        [switch]$ForceRecoveryOnNextBoot,

        [switch]$EnableTpmPin,

        [string]$Pin,

        [switch]$RemoveTpmOnly,

        [switch]$BackupRecoveryKeyToAAD
    )

    $result = [ordered]@{
        Ran                         = $true
        MountPoint                  = $MountPoint
        ForceRecoveryOnNextBoot     = [bool]$ForceRecoveryOnNextBoot
        EnableTpmPin                = [bool]$EnableTpmPin
        AddedTpmPinProtectorIds     = @()
        RemovedTpmOnlyProtectorIds  = @()
        Error                       = $null
    }

    Write-Log "Starting BitLocker pre-boot lockdown checks for $MountPoint"

    try {
        Import-Module BitLocker -ErrorAction Stop
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Log "BitLocker PowerShell module could not be imported. Error: $($_.Exception.Message)"
        return [pscustomobject]$result
    }

    try {
        $bitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Log "Unable to read BitLocker status for $MountPoint. Error: $($_.Exception.Message)"
        return [pscustomobject]$result
    }

    Write-Log "BitLocker status for $MountPoint - VolumeStatus: $($bitLockerVolume.VolumeStatus), ProtectionStatus: $($bitLockerVolume.ProtectionStatus), EncryptionPercentage: $($bitLockerVolume.EncryptionPercentage)"

    if ($bitLockerVolume.VolumeStatus -eq 'FullyDecrypted') {
        Write-Log "$MountPoint is not BitLocker encrypted. Skipping BitLocker pre-boot lockdown."
        return [pscustomobject]$result
    }

    if ($bitLockerVolume.ProtectionStatus -eq 'Off') {
        try {
            Write-Log "BitLocker protection is Off. Attempting to resume protection on $MountPoint."
            Resume-BitLocker -MountPoint $MountPoint -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to resume BitLocker protection on $MountPoint. Error: $($_.Exception.Message)"
        }
    }

    $bitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop

    $recoveryPasswordProtectors = @(
        $bitLockerVolume.KeyProtector |
            Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    )

    if ($recoveryPasswordProtectors.Count -eq 0) {
        try {
            Write-Log "No RecoveryPassword protector found. Adding one before BitLocker lockdown."
            Add-BitLockerKeyProtector -MountPoint $MountPoint -RecoveryPasswordProtector -ErrorAction Stop | Out-Null
            $bitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
            $recoveryPasswordProtectors = @(
                $bitLockerVolume.KeyProtector |
                    Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
            )
        }
        catch {
            Write-Log "Failed to add RecoveryPassword protector. Error: $($_.Exception.Message)"
        }
    }

    if ($BackupRecoveryKeyToAAD) {
        foreach ($protector in $recoveryPasswordProtectors) {
            try {
                Write-Log "Attempting to back up recovery protector to Entra ID: $($protector.KeyProtectorId)"
                BackupToAAD-BitLockerKeyProtector `
                    -MountPoint $MountPoint `
                    -KeyProtectorId $protector.KeyProtectorId `
                    -ErrorAction Stop
            }
            catch {
                Write-Log "Failed to back up recovery protector $($protector.KeyProtectorId) to Entra ID. Error: $($_.Exception.Message)"
            }
        }
    }

    if ($EnableTpmPin) {
        if ([string]::IsNullOrWhiteSpace($Pin)) {
            throw "EnableTpmPin was specified, but no PreBootPin was provided."
        }

        if ($Pin -notmatch '^\d{6,20}$') {
            throw "PreBootPin must be numeric and between 6 and 20 digits for this script."
        }

        $bitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop

        $existingTpmPinProtectors = @(
            $bitLockerVolume.KeyProtector |
                Where-Object { $_.KeyProtectorType -in @('TpmPin', 'TpmAndPin') }
        )

        if ($existingTpmPinProtectors.Count -gt 0) {
            Write-Log "TPM+PIN protector already exists on $MountPoint. Skipping add."
        }
        else {
            try {
                Write-Log "Adding TPM+PIN protector to $MountPoint."

                $beforeIds = @($bitLockerVolume.KeyProtector.KeyProtectorId)
                $securePin = ConvertTo-SecureString -String $Pin -AsPlainText -Force

                Add-BitLockerKeyProtector `
                    -MountPoint $MountPoint `
                    -Pin $securePin `
                    -TpmAndPinProtector `
                    -ErrorAction Stop | Out-Null

                $afterVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
                $newProtectors = @(
                    $afterVolume.KeyProtector |
                        Where-Object {
                            $_.KeyProtectorId -notin $beforeIds -and
                            $_.KeyProtectorType -in @('TpmPin', 'TpmAndPin')
                        }
                )

                $result.AddedTpmPinProtectorIds = @($newProtectors.KeyProtectorId)
                Write-Log "TPM+PIN protector added to $MountPoint. New protector IDs: $($result.AddedTpmPinProtectorIds -join ',')"
            }
            catch {
                Write-Log "Failed to add TPM+PIN protector. Error: $($_.Exception.Message)"
                throw
            }
        }

        if ($RemoveTpmOnly) {
            $bitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop

            $tpmOnlyProtectors = @(
                $bitLockerVolume.KeyProtector |
                    Where-Object { $_.KeyProtectorType -eq 'Tpm' }
            )

            foreach ($protector in $tpmOnlyProtectors) {
                try {
                    Write-Log "Removing TPM-only protector to enforce pre-boot PIN: $($protector.KeyProtectorId)"
                    Remove-BitLockerKeyProtector `
                        -MountPoint $MountPoint `
                        -KeyProtectorId $protector.KeyProtectorId `
                        -ErrorAction Stop | Out-Null

                    $result.RemovedTpmOnlyProtectorIds += $protector.KeyProtectorId
                }
                catch {
                    Write-Log "Failed to remove TPM-only protector $($protector.KeyProtectorId). Error: $($_.Exception.Message)"
                }
            }
        }
    }

    if ($ForceRecoveryOnNextBoot) {
        try {
            Write-Log "Forcing BitLocker recovery on next boot for $MountPoint."
            & manage-bde.exe -forcerecovery $MountPoint | Out-Null

            if ($LASTEXITCODE -ne 0) {
                throw "manage-bde -forcerecovery failed with exit code $LASTEXITCODE"
            }

            Write-Log "BitLocker recovery has been forced for next boot on $MountPoint."
        }
        catch {
            Write-Log "Failed to force BitLocker recovery on $MountPoint. Error: $($_.Exception.Message)"
            throw
        }
    }

    Write-Log "BitLocker pre-boot lockdown checks completed for $MountPoint."
    return [pscustomobject]$result
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

        Save-RemovedGroupMembershipBackup
    }

    $targetSids = @($targets.Sid | Where-Object { $_ } | Select-Object -Unique)

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

    $bitLockerResult = $null

    if ($ForceBitLockerRecoveryOnNextBoot -or $EnableBitLockerTpmPin) {
        $bitLockerResult = Invoke-BitLockerPreBootLockdown `
            -MountPoint 'C:' `
            -ForceRecoveryOnNextBoot:$ForceBitLockerRecoveryOnNextBoot `
            -EnableTpmPin:$EnableBitLockerTpmPin `
            -Pin $PreBootPin `
            -RemoveTpmOnly:$RemoveTpmOnlyProtector `
            -BackupRecoveryKeyToAAD:$BackupBitLockerRecoveryKeyToAAD
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

    if ($bitLockerResult) {
        New-ItemProperty `
            -Path $RegPath `
            -Name 'BitLockerForceRecoveryOnNextBoot' `
            -Value ([string]$bitLockerResult.ForceRecoveryOnNextBoot) `
            -PropertyType String `
            -Force | Out-Null

        New-ItemProperty `
            -Path $RegPath `
            -Name 'BitLockerAddedTpmPinProtectorIds' `
            -Value (($bitLockerResult.AddedTpmPinProtectorIds) -join ',') `
            -PropertyType String `
            -Force | Out-Null

        New-ItemProperty `
            -Path $RegPath `
            -Name 'BitLockerRemovedTpmOnlyProtectorIds' `
            -Value (($bitLockerResult.RemovedTpmOnlyProtectorIds) -join ',') `
            -PropertyType String `
            -Force | Out-Null
    }

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
