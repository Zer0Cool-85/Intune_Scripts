function Repair-AllowLogonLocally {
    [CmdletBinding()]
    param (
        [string]$WorkingDirectory = "$env:ProgramData\IntuneMigration\UserRights",

        # Recommended: removes BUILTIN\Users from Deny log on locally if it is present.
        [switch]$RemoveUsersFromDenyLogonLocally
    )

    $ErrorActionPreference = 'Stop'

    # SIDs used by local security policy INF files require the leading *
    $BuiltInUsersSid = '*S-1-5-32-545'

    # Optional default fallback if the right is missing entirely
    $DefaultAllowLocalLogon = @(
        '*S-1-5-32-544', # BUILTIN\Administrators
        '*S-1-5-32-551', # BUILTIN\Backup Operators
        '*S-1-5-32-545'  # BUILTIN\Users
    )

    New-Item -Path $WorkingDirectory -ItemType Directory -Force | Out-Null

    $ExportPath = Join-Path $WorkingDirectory 'UserRights-Before.cfg'
    $InfPath    = Join-Path $WorkingDirectory 'Repair-AllowLogonLocally.inf'
    $DbPath     = Join-Path $WorkingDirectory 'Repair-AllowLogonLocally.sdb'
    $VerifyPath = Join-Path $WorkingDirectory 'UserRights-After.cfg'
    $LogPath    = Join-Path $WorkingDirectory 'Repair-AllowLogonLocally.log'

    function Write-RepairLog {
        param ([string]$Message)
        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        "$Timestamp $Message" | Tee-Object -FilePath $LogPath -Append
    }

    function Get-UserRightAssignment {
        param (
            [string[]]$ConfigContent,
            [string]$RightName
        )

        $Line = $ConfigContent | Where-Object {
            $_ -match "^\s*$([regex]::Escape($RightName))\s*="
        } | Select-Object -First 1

        if (-not $Line) {
            return @()
        }

        $Value = ($Line -split '=', 2)[1].Trim()

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return @()
        }

        return @(
            $Value -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
    }

    Write-RepairLog "Starting Allow log on locally repair."

    Write-RepairLog "Exporting current user-rights assignments to $ExportPath"
    secedit.exe /export /cfg "$ExportPath" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "secedit export failed with exit code $LASTEXITCODE"
    }

    $ConfigContent = Get-Content -Path $ExportPath

    $AllowLocal = @(Get-UserRightAssignment -ConfigContent $ConfigContent -RightName 'SeInteractiveLogonRight')
    $DenyLocal  = @(Get-UserRightAssignment -ConfigContent $ConfigContent -RightName 'SeDenyInteractiveLogonRight')

    Write-RepairLog "Current SeInteractiveLogonRight: $($AllowLocal -join ',')"
    Write-RepairLog "Current SeDenyInteractiveLogonRight: $($DenyLocal -join ',')"

    if ($AllowLocal.Count -eq 0) {
        Write-RepairLog "SeInteractiveLogonRight was empty or missing. Applying default workstation values."
        $AllowLocal = $DefaultAllowLocalLogon
    }
    elseif ($AllowLocal -notcontains $BuiltInUsersSid) {
        Write-RepairLog "BUILTIN\Users is missing from Allow log on locally. Adding $BuiltInUsersSid."
        $AllowLocal += $BuiltInUsersSid
    }
    else {
        Write-RepairLog "BUILTIN\Users is already present in Allow log on locally."
    }

    $DenyLocalWasModified = $false

    if ($RemoveUsersFromDenyLogonLocally -and ($DenyLocal -contains $BuiltInUsersSid)) {
        Write-RepairLog "BUILTIN\Users is present in Deny log on locally. Removing $BuiltInUsersSid."
        $DenyLocal = @($DenyLocal | Where-Object { $_ -ne $BuiltInUsersSid })
        $DenyLocalWasModified = $true
    }

    $InfLines = @(
        '[Unicode]'
        'Unicode=yes'
        ''
        '[Version]'
        'signature="$CHICAGO$"'
        'Revision=1'
        ''
        '[Privilege Rights]'
        "SeInteractiveLogonRight = $($AllowLocal -join ',')"
    )

    if ($DenyLocalWasModified) {
        $InfLines += "SeDenyInteractiveLogonRight = $($DenyLocal -join ',')"
    }

    Write-RepairLog "Writing repair INF to $InfPath"
    $InfLines | Set-Content -Path $InfPath -Encoding Unicode

    Write-RepairLog "Applying user-rights assignment repair."
    secedit.exe /configure /db "$DbPath" /cfg "$InfPath" /areas USER_RIGHTS | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "secedit configure failed with exit code $LASTEXITCODE"
    }

    Write-RepairLog "Exporting updated user-rights assignments to $VerifyPath"
    secedit.exe /export /cfg "$VerifyPath" | Out-Null

    $VerifyContent = Get-Content -Path $VerifyPath
    $VerifyAllowLocal = @(Get-UserRightAssignment -ConfigContent $VerifyContent -RightName 'SeInteractiveLogonRight')
    $VerifyDenyLocal  = @(Get-UserRightAssignment -ConfigContent $VerifyContent -RightName 'SeDenyInteractiveLogonRight')

    Write-RepairLog "Updated SeInteractiveLogonRight: $($VerifyAllowLocal -join ',')"
    Write-RepairLog "Updated SeDenyInteractiveLogonRight: $($VerifyDenyLocal -join ',')"

    if ($VerifyAllowLocal -notcontains $BuiltInUsersSid) {
        throw "Verification failed. BUILTIN\Users is still missing from Allow log on locally."
    }

    if ($VerifyDenyLocal -contains $BuiltInUsersSid) {
        throw "Verification failed. BUILTIN\Users is still present in Deny log on locally."
    }

    Write-RepairLog "Allow log on locally repair completed successfully."
    return $true
}
