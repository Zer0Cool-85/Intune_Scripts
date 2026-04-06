function Save-PopupDeferralState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$PopupName,

        [Parameter(Mandatory)]
        [pscustomobject]$PopupResult
    )

    $folder = Split-Path -Path $Path -Parent
    if (-not (Test-Path $folder)) {
        [void](New-Item -Path $folder -ItemType Directory -Force)
    }

    $state = @{}

    if (Test-Path $Path) {
        try {
            $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $jsonObject = $raw | ConvertFrom-Json -ErrorAction Stop

                foreach ($property in $jsonObject.PSObject.Properties) {
                    $state[$property.Name] = $property.Value
                }
            }
        }
        catch {
            $state = @{}
        }
    }

    $state[$PopupName] = [ordered]@{
        HasDeferred = $true
        DeferredAt  = $PopupResult.Timestamp
        DeferHours  = $PopupResult.DeferHours
        DeferUntil  = $PopupResult.DeferUntil
    }

    $state | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}



function Get-PopupDeferralState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return @{}
    }

    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @{}
        }

        $jsonObject = $raw | ConvertFrom-Json -ErrorAction Stop
        $state = @{}

        foreach ($property in $jsonObject.PSObject.Properties) {
            $state[$property.Name] = $property.Value
        }

        return $state
    }
    catch {
        return @{}
    }
}



function Remove-PopupDeferralState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$PopupName
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $state = Get-PopupDeferralState -Path $Path

    if ($state.ContainsKey($PopupName)) {
        $state.Remove($PopupName)
        $state | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
    }
}



$popupName = 'EndpointMigration'
$statePath = "$env:ProgramData\Company\PopupDeferrals.json"

$result = Show-InfoPopup `
    -Title 'Endpoint Migration' `
    -HeaderText 'Starting migration process' `
    -MessageText 'Please close all open applications and save your work before continuing.' `
    -DialogMode Defer



if ($result.Action -eq 'Defer') {
    Save-PopupDeferralState -Path $statePath -PopupName $popupName -PopupResult $result
}



if ($result.Action -eq 'Primary') {
    Remove-PopupDeferralState -Path $statePath -PopupName $popupName
}



$state = Get-PopupDeferralState -Path $statePath

if ($state.ContainsKey($popupName)) {
    $existing = $state[$popupName]

    if ($existing.DeferUntil -and ((Get-Date) -lt [datetime]$existing.DeferUntil)) {
        Write-Host "Still deferred until $($existing.DeferUntil)"
        return
    }

    $disableDefer = $true
}
else {
    $disableDefer = $false
}
