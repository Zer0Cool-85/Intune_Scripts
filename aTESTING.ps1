function Get-PopupDeferralRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$PopupName
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }

    if ($json.PSObject.Properties.Name -notcontains $PopupName) {
        return $null
    }

    $record = $json.$PopupName

    [pscustomobject]@{
        HasDeferred = [bool]$record.HasDeferred
        DeferredAt  = if ($record.DeferredAt)  { [datetime]$record.DeferredAt }  else { $null }
        DeferHours  = if ($record.DeferHours)  { [int]$record.DeferHours }       else { $null }
        DeferUntil  = if ($record.DeferUntil)  { [datetime]$record.DeferUntil }  else { $null }
    }
}



function Get-InteractiveShellInfo {
    [CmdletBinding()]
    param()

    $explorer = Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue |
        Where-Object {
            $_.SessionId -ne 0 -and
            $_.UserName -and
            $_.UserName -notmatch '^(NT AUTHORITY|Window Manager|Font Driver Host)'
        } |
        Sort-Object StartTime -Descending |
        Select-Object -First 1

    if (-not $explorer) {
        return $null
    }

    [pscustomobject]@{
        UserName  = $explorer.UserName
        SessionId = $explorer.SessionId
        ProcessId = $explorer.Id
    }
}



function Test-SessionProbablyLocked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SessionId
    )

    $logonUi = Get-CimInstance Win32_Process -Filter "Name='LogonUI.exe'" -ErrorAction SilentlyContinue

    if (-not $logonUi) {
        return $false
    }

    return [bool]($logonUi | Where-Object { $_.SessionId -eq $SessionId })
}



function Test-MigrationPromptGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PopupName,

        [Parameter(Mandatory)]
        [string]$StatePath,

        [Parameter()]
        [string]$MigrationCompleteMarkerPath
    )

    $now = Get-Date

    # 1. Migration already complete?
    if ($MigrationCompleteMarkerPath -and (Test-Path $MigrationCompleteMarkerPath)) {
        return [pscustomobject]@{
            ShouldPrompt = $false
            Reason       = 'Migration already completed.'
            DisableDefer = $true
            SessionId    = $null
            UserName     = $null
            Deferral     = $null
        }
    }

    # 2. Read deferral state
    $deferral = Get-PopupDeferralRecord -Path $StatePath -PopupName $PopupName
    $disableDefer = $false

    if ($deferral -and $deferral.HasDeferred) {
        $disableDefer = $true
    }

    if ($deferral -and $deferral.DeferUntil -and $now -lt $deferral.DeferUntil) {
        return [pscustomobject]@{
            ShouldPrompt = $false
            Reason       = "Still deferred until $($deferral.DeferUntil)."
            DisableDefer = $disableDefer
            SessionId    = $null
            UserName     = $null
            Deferral     = $deferral
        }
    }

    # 3. Require an interactive user shell
    $shell = Get-InteractiveShellInfo
    if (-not $shell) {
        return [pscustomobject]@{
            ShouldPrompt = $false
            Reason       = 'No interactive user shell found.'
            DisableDefer = $disableDefer
            SessionId    = $null
            UserName     = $null
            Deferral     = $deferral
        }
    }

    # 4. Best-effort lock screen detection
    if (Test-SessionProbablyLocked -SessionId $shell.SessionId) {
        return [pscustomobject]@{
            ShouldPrompt = $false
            Reason       = "User session $($shell.SessionId) appears to be locked or at the sign-in screen."
            DisableDefer = $disableDefer
            SessionId    = $shell.SessionId
            UserName     = $shell.UserName
            Deferral     = $deferral
        }
    }

    # 5. Good to show prompt
    return [pscustomobject]@{
        ShouldPrompt = $true
        Reason       = 'Interactive unlocked user session detected.'
        DisableDefer = $disableDefer
        SessionId    = $shell.SessionId
        UserName     = $shell.UserName
        Deferral     = $deferral
    }
}



$popupName   = 'EndpointMigration'
$statePath   = "$env:ProgramData\Company\PopupDeferrals.json"
$doneMarker  = "$env:ProgramData\Company\MigrationComplete.tag"

$gate = Test-MigrationPromptGate `
    -PopupName $popupName `
    -StatePath $statePath `
    -MigrationCompleteMarkerPath $doneMarker

Write-Host "[MigrationGate] $($gate.Reason)"

if (-not $gate.ShouldPrompt) {
    return
}



$result = Show-InfoPopup `
    -Title 'Endpoint Migration' `
    -HeaderText 'Starting migration process' `
    -MessageText 'Please close all open applications and save your work before continuing.' `
    -DialogMode Defer `
    -DisableDefer:$gate.DisableDefer


switch ($result.Action) {
    'Primary' {
        Write-Host 'User chose Continue'
        # Start migration
    }

    'Defer' {
        Save-PopupDeferralState -Path $statePath -PopupName $popupName -PopupResult $result
        Write-Host "User deferred until $($result.DeferUntil)"
        return
    }

    'Secondary' {
        Write-Host 'User cancelled'
        return
    }

    'Closed' {
        Write-Host 'User closed the popup'
        return
    }
}
