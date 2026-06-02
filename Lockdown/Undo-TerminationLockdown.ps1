<#
.SYNOPSIS
    Rolls back the Windows termination lockdown script.

.DESCRIPTION
    Intended to be used as the Microsoft Intune Win32 uninstall command.

    The script:
    - Reads target SIDs from HKLM:\SOFTWARE\Company\TerminationLockdown.
    - Removes those SIDs from:
        SeDenyInteractiveLogonRight
        SeDenyRemoteInteractiveLogonRight
    - Also removes protected local admin SIDs, such as WINADMIN, from deny rights.
    - Restores CachedLogonsCount.
    - Optionally restores local group memberships removed by the install script.
    - Optionally removes TPM+PIN BitLocker protectors and restores TPM-only.
    - Clears the lockdown detection registry key.

.NOTES
    Restoring local group membership is optional and off by default to avoid accidentally
    re-granting admin or RDP access.
#>

[CmdletBinding()]
param(
    [string[]]$AllowedLocalAdminAccounts = @(
        'WINADMIN'
    ),

    # Optional manual SID list if registry TargetSids is missing.
    [string[]]$ManualTargetSids = @(),

    [switch]$RestoreCachedDomainLogons,

    # Default Windows cached domain logon count is commonly 10.
    # Change this if your org enforces a different value.
    [string]$CachedLogonsCountValue = '10',

    # Optional. Off by default to avoid accidentally restoring admin/RDP access.
    [switch]$RestoreRemovedLocalGroupMembership,

    # Restores TPM-only protector if missing.
    [switch]$RestoreBitLockerTpmProtector,

    # Optional. Only use if you intentionally want to remove TPM+PIN protectors.
    [switch]$RemoveTpmPinProtectors,

    # Remove the detection registry key entirely.
    [switch]$RemoveDetectionRegistryKey
)

$BootstrapLogPath = 'C:\Windows\Temp\Undo-TerminationLockdown-Bootstrap.log'

try {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Rollback script started. Running as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)" |
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
$LogPath  = Join-Path $BasePath 'Rollback.log'
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

function ConvertFrom-SecEditEntry {
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

function Remove-SidsFromUserRight {
    param(
        [Parameter(Mandatory)]
        [string]$RightName,

        [Parameter(Mandatory)]
        [string[]]$SidsToRemove
    )

    $cleanSidsToRemove = @(
        $SidsToRemove |
            Where-Object { $_ } |
            ForEach-Object { $_ -replace '^\*', '' } |
            Select-Object -Unique
    )

    if ($cleanSidsToRemove.Count -eq 0) {
        Write-Log "No SIDs supplied for removal from $($RightName). Skipping."
        return
    }

    $workPath   = Join-Path $BasePath "Rollback-SecEdit-$RightName"
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

    if ($existingEntries.Count -eq 0) {
        Write-Log "$RightName has no existing entries. Nothing to remove."
        return
    }

    $finalEntries = foreach ($entry in $existingEntries) {
        $entrySid = ConvertFrom-SecEditEntry -Entry $entry

        if ($cleanSidsToRemove -contains $entrySid) {
            Write-Log "Removing SID from $($RightName): $entrySid"
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

    Write-Log "Applying updated $($RightName) entries: $($finalEntries -join ',')"
    & secedit.exe /configure /db $dbPath /cfg $importPath /areas USER_RIGHTS | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "secedit failed while updating $($RightName). Exit code: $LASTEXITCODE"
    }
}

function Get-TargetSidsFromRegistry {
    $targetSids = @()

    try {
        $lockdownState = Get-ItemProperty -Path $RegPath -ErrorAction Stop

        if (-not [string]::IsNullOrWhiteSpace($lockdownState.TargetSids)) {
            $targetSids += $lockdownState.TargetSids -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ }
        }
    }
    catch {
        Write-Log "Could not read TargetSids from registry. Error: $($_.Exception.Message)"
    }

    return @($targetSids | Select-Object -Unique)
}

function Restore-CachedDomainLogons {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

    Write-Log "Restoring CachedLogonsCount to $Value"

    New-ItemProperty `
        -Path $winlogonPath `
        -Name 'CachedLogonsCount' `
        -Value $Value `
        -PropertyType String `
        -Force | Out-Null
}

function Restore-RemovedLocalGroupMembership {
    if (-not (Test-Path $GroupMembershipBackupPath)) {
        Write-Log "Group membership backup not found at $GroupMembershipBackupPath. Nothing to restore."
        return
    }

    try {
        $entries = @(Get-Content -Path $GroupMembershipBackupPath -Raw | ConvertFrom-Json)
    }
    catch {
        Write-Log "Failed to read group membership backup. Error: $($_.Exception.Message)"
        return
    }

    foreach ($entry in $entries) {
        if ([string]::IsNullOrWhiteSpace($entry.GroupName) -or [string]::IsNullOrWhiteSpace($entry.SID)) {
            continue
        }

        try {
            $existingMembers = @(Get-LocalGroupMember -Group $entry.GroupName -ErrorAction Stop)

            if ($existingMembers.SID.Value -contains $entry.SID) {
                Write-Log "SID $($entry.SID) is already a member of $($entry.GroupName). Skipping restore."
                continue
            }

            Write-Log "Attempting to restore SID $($entry.SID) to local group $($entry.GroupName)."
            Add-LocalGroupMember -Group $entry.GroupName -Member $entry.SID -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to restore SID $($entry.SID) to local group $($entry.GroupName). Error: $($_.Exception.Message)"
        }
    }
}

function Restore-BitLockerTpmOnlyProtector {
    param(
        [string]$MountPoint = 'C:',

        [switch]$RemoveTpmPin
    )

    Write-Log "Checking BitLocker TPM protector state for rollback on $MountPoint."

    try {
        Import-Module BitLocker -ErrorAction Stop
        $bitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    }
    catch {
        Write-Log "Unable to read BitLocker state during rollback. Error: $($_.Exception.Message)"
        return
    }

    if ($bitLockerVolume.VolumeStatus -eq 'FullyDecrypted') {
        Write-Log "$MountPoint is not BitLocker encrypted. Skipping TPM protector restore."
        return
    }

    if ($RemoveTpmPin) {
        $tpmPinProtectors = @(
            $bitLockerVolume.KeyProtector |
                Where-Object { $_.KeyProtectorType -in @('TpmPin', 'TpmAndPin') }
        )

        foreach ($protector in $tpmPinProtectors) {
            try {
                Write-Log "Removing TPM+PIN protector: $($protector.KeyProtectorId)"
                Remove-BitLockerKeyProtector `
                    -MountPoint $MountPoint `
                    -KeyProtectorId $protector.KeyProtectorId `
                    -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Log "Failed to remove TPM+PIN protector $($protector.KeyProtectorId). Error: $($_.Exception.Message)"
            }
        }

        $bitLockerVolume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    }

    $tpmProtectors = @(
        $bitLockerVolume.KeyProtector |
            Where-Object { $_.KeyProtectorType -eq 'Tpm' }
    )

    if ($tpmProtectors.Count -gt 0) {
        Write-Log "TPM-only protector already exists. Skipping add."
        return
    }

    try {
        Write-Log "Adding TPM-only protector back to $MountPoint."
        Add-BitLockerKeyProtector `
            -MountPoint $MountPoint `
            -TpmProtector `
            -ErrorAction Stop | Out-Null

        Write-Log "TPM-only protector restored."
    }
    catch {
        Write-Log "Failed to restore TPM-only protector. Error: $($_.Exception.Message)"
    }
}

function Clear-LockdownRegistryState {
    if ($RemoveDetectionRegistryKey) {
        if (Test-Path $RegPath) {
            Write-Log "Removing lockdown detection registry key: $RegPath"
            Remove-Item -Path $RegPath -Recurse -Force
        }

        return
    }

    New-Item -Path $RegPath -Force | Out-Null

    New-ItemProperty `
        -Path $RegPath `
        -Name 'State' `
        -Value 'Unlocked' `
        -PropertyType String `
        -Force | Out-Null

    New-ItemProperty `
        -Path $RegPath `
        -Name 'UnlockedOn' `
        -Value (Get-Date).ToString('o') `
        -PropertyType String `
        -Force | Out-Null

    Write-Log "Updated lockdown registry state to Unlocked."
}

try {
    Write-Log "========== Termination lockdown rollback started =========="

    $registryTargetSids = @(Get-TargetSidsFromRegistry)

    $allowedAdminSidMap = @(Get-AllowedLocalAdminSidMap -AccountNames $AllowedLocalAdminAccounts)
    $allowedAdminSids = @($allowedAdminSidMap.SID | Where-Object { $_ } | Select-Object -Unique)

    if ($allowedAdminSidMap.Count -gt 0) {
        Write-Log "Protected local admin accounts to ensure are not denied:"
        foreach ($entry in $allowedAdminSidMap) {
            Write-Log " - $($entry.Name) | $($entry.SID)"
        }
    }

    $sidsToRemove = @(
        $registryTargetSids
        $ManualTargetSids
        $allowedAdminSids
    ) |
        Where-Object { $_ } |
        ForEach-Object { $_ -replace '^\*', '' } |
        Select-Object -Unique

    if ($sidsToRemove.Count -eq 0) {
        Write-Log "No target SIDs found in registry or manual input. Nothing to remove from deny rights."
    }
    else {
        Write-Log "SIDs to remove from deny rights:"
        foreach ($sid in $sidsToRemove) {
            Write-Log " - $sid"
        }

        Remove-SidsFromUserRight `
            -RightName 'SeDenyInteractiveLogonRight' `
            -SidsToRemove $sidsToRemove

        Remove-SidsFromUserRight `
            -RightName 'SeDenyRemoteInteractiveLogonRight' `
            -SidsToRemove $sidsToRemove
    }

    if ($RestoreCachedDomainLogons) {
        Restore-CachedDomainLogons -Value $CachedLogonsCountValue
    }

    if ($RestoreRemovedLocalGroupMembership) {
        Restore-RemovedLocalGroupMembership
    }

    if ($RestoreBitLockerTpmProtector -or $RemoveTpmPinProtectors) {
        Restore-BitLockerTpmOnlyProtector `
            -MountPoint 'C:' `
            -RemoveTpmPin:$RemoveTpmPinProtectors
    }

    Clear-LockdownRegistryState

    Write-Log "========== Termination lockdown rollback completed =========="
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "========== Termination lockdown rollback failed =========="
    exit 1
}
