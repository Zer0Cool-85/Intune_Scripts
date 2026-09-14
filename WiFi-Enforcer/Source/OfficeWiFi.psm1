Set-StrictMode -Version 2.0
$script:LogPath = $null

function Get-OfficePaths {
    [pscustomobject]@{
        InstallRoot = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'OfficeWiFiEnforcer'
        DataRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'OfficeWiFiEnforcer'
        TaskName = 'OfficeWiFi-Enforcer'
        RegistryPath = 'HKLM:\SOFTWARE\OfficeWiFiEnforcer'
        PackageVersion = '1.1.0'
    }
}

function ConvertTo-SsidHex {
    param([Parameter(Mandatory)][string]$Ssid)
    [BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($Ssid)).Replace('-', '')
}

function Read-OfficeConfig {
    param([Parameter(Mandatory)][string]$Path)
    $c = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($null -ne $c.PSObject.Properties['EnableAutoSwitchOnOtherAutoProfiles']) {
        throw 'The broad EnableAutoSwitchOnOtherAutoProfiles setting was removed in 1.1.0. Use the new config.json schema with LegacySsidAction.'
    }
    $fields = @('ConfigurationReady','PolicyVersion','PreferredSsid','PreferredProfileName','LegacySsids',
        'EnforcementIntervalMinutes','LegacySsidAction','ConnectWhenVisible',
        'MinimumSignalQuality','ConnectionAttemptCooldownMinutes','ConnectionTimeoutSeconds',
        'RequireSuccessfulPreferredConnectionBeforeRemoval')
    foreach ($field in $fields) {
        if ($null -eq $c.PSObject.Properties[$field]) { throw "Missing config field: $field" }
    }
    foreach ($p in $c.PSObject.Properties) {
        if ($p.Name -notin $fields) { throw "Unknown config field: $($p.Name)" }
    }
    foreach ($field in @('ConfigurationReady','ConnectWhenVisible','RequireSuccessfulPreferredConnectionBeforeRemoval')) {
        if ($c.$field -isnot [bool]) { throw "$field must be a JSON boolean." }
    }
    if ($c.LegacySsidAction -isnot [string] -or $c.LegacySsidAction -cnotin @('DisableAutoConnect','Remove')) {
        throw 'LegacySsidAction must be DisableAutoConnect or Remove.'
    }
    if (-not $c.ConfigurationReady) { throw 'Edit config.json, then set ConfigurationReady to true before packaging or installing.' }
    if ($c.PreferredSsid -isnot [string]) { throw 'PreferredSsid must be one JSON string.' }
    $parsedVersion = $null
    if (-not [version]::TryParse([string]$c.PolicyVersion, [ref]$parsedVersion)) { throw 'PolicyVersion must be a version such as 1.0.0.' }
    if ($c.PreferredProfileName -isnot [string] -or $c.PreferredProfileName.Length -gt 255 -or $c.PreferredProfileName.Contains([string][char]0)) {
        throw 'PreferredProfileName must be a string of up to 255 characters.'
    }
    if ($c.LegacySsids -isnot [array]) { throw 'LegacySsids must be a JSON array, including when it contains only one SSID.' }
    foreach ($ssid in @($c.PreferredSsid) + @($c.LegacySsids)) {
        if ($ssid -isnot [string] -or [string]::IsNullOrEmpty($ssid) -or $ssid.Contains([string][char]0) -or
            [Text.Encoding]::UTF8.GetByteCount($ssid) -gt 32 -or $ssid.StartsWith('CHANGE_ME')) {
            throw 'Replace all placeholder SSIDs with nonempty UTF-8 SSIDs of at most 32 bytes.'
        }
    }
    $ranges = @{
        EnforcementIntervalMinutes = @(5,1440)
        MinimumSignalQuality = @(0,100)
        ConnectionAttemptCooldownMinutes = @(5,1440)
        ConnectionTimeoutSeconds = @(5,60)
    }
    foreach ($field in $ranges.Keys) {
        $value = $c.$field
        if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt $ranges[$field][0] -or $value -gt $ranges[$field][1]) {
            throw "$field must be an integer from $($ranges[$field][0]) through $($ranges[$field][1])."
        }
    }
    $preferredHex = ConvertTo-SsidHex $c.PreferredSsid
    $legacy = @{}
    foreach ($ssid in $c.LegacySsids) {
        $hex = ConvertTo-SsidHex $ssid
        if ($hex -eq $preferredHex) { throw 'The preferred SSID cannot also be in LegacySsids.' }
        $legacy[$hex] = $true
    }
    $c | Add-Member NoteProperty PreferredHex $preferredHex
    $c | Add-Member NoteProperty LegacyHex $legacy
    $c | Add-Member NoteProperty ConfigHash (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $c
}

function Get-OfficeProfileFacts {
    param([Parameter(Mandatory)]$Profile)
    $xml = New-Object System.Xml.XmlDocument
    $xml.XmlResolver = $null
    $xml.LoadXml($Profile.Xml)
    if ($xml.DocumentElement.LocalName -ne 'WLANProfile') { throw 'Unexpected WLAN XML root.' }
    $root = $xml.DocumentElement
    $hexes = @()
    foreach ($ssid in $root.SelectNodes("./*[local-name()='SSIDConfig']/*[local-name()='SSID']")) {
        $hex = $ssid.SelectSingleNode("./*[local-name()='hex']")
        $name = $ssid.SelectSingleNode("./*[local-name()='name']")
        if ($null -ne $hex) {
            if ($hex.InnerText -notmatch '^(?:[0-9a-fA-F]{2}){1,32}$') { throw 'Invalid SSID hex in profile.' }
            $hexes += $hex.InnerText.ToUpperInvariant()
        } elseif ($null -ne $name) { $hexes += ConvertTo-SsidHex $name.InnerText }
    }
    $mode = $root.SelectSingleNode("./*[local-name()='connectionMode']")
    $autoSwitch = $root.SelectSingleNode("./*[local-name()='autoSwitch']")
    $type = $root.SelectSingleNode("./*[local-name()='connectionType']")
    [pscustomobject]@{
        Profile = $Profile
        Xml = $xml
        SsidHex = @($hexes | Select-Object -Unique)
        IsGroupPolicy = (($Profile.Flags -band 1) -ne 0)
        IsPerUser = (($Profile.Flags -band 2) -ne 0)
        IsInfrastructure = ($null -ne $type -and $type.InnerText -eq 'ESS')
        Automatic = ($null -eq $mode -or $mode.InnerText -eq 'auto')
        AutoSwitch = ($null -ne $autoSwitch -and $autoSwitch.InnerText -in @('true','1'))
    }
}

function Set-OfficeConnectionXml {
    param([Parameter(Mandatory)]$Facts, [bool]$AutoSwitch,
        [Parameter(Mandatory)][ValidateSet('auto','manual')][string]$ConnectionMode)
    if ($ConnectionMode -eq 'manual' -and $AutoSwitch) { throw 'Manual profiles require autoSwitch=false.' }
    $root = $Facts.Xml.DocumentElement
    $mode = $root.SelectSingleNode("./*[local-name()='connectionMode']")
    if ($null -eq $mode) {
        $mode = $Facts.Xml.CreateElement('connectionMode', $root.NamespaceURI)
        $type = $root.SelectSingleNode("./*[local-name()='connectionType']")
        if ($null -eq $type) { throw 'Profile is missing connectionType.' }
        [void]$root.InsertAfter($mode, $type)
        $mode.InnerText = 'auto'
    }
    $mode.InnerText = $ConnectionMode
    $node = $root.SelectSingleNode("./*[local-name()='autoSwitch']")
    if ($null -eq $node) {
        $node = $Facts.Xml.CreateElement('autoSwitch', $root.NamespaceURI)
        [void]$root.InsertAfter($node, $mode)
    }
    $node.InnerText = $AutoSwitch.ToString().ToLowerInvariant()
    $Facts.Xml.OuterXml
}

function Test-OfficeLegacyScope {
    param($Facts, $Config)
    if ($Facts.IsGroupPolicy -or $Facts.IsPerUser -or -not $Facts.IsInfrastructure -or
        $Facts.SsidHex.Count -eq 0 -or $Facts.SsidHex -contains $Config.PreferredHex) { return $false }
    # Every SSID in a profile must be explicitly listed before any of its settings can change.
    foreach ($hex in $Facts.SsidHex) {
        if (-not $Config.LegacyHex.ContainsKey($hex)) { return $false }
    }
    return $true
}

function Test-OfficeSwitchSource {
    param($Connection, [object[]]$LegacyFacts)
    if (-not $Connection.Known) { return $false }
    if ([string]::IsNullOrEmpty($Connection.SsidHex)) { return $true }
    # A connected profile must be both identifiable and entirely within the configured legacy list.
    # This also excludes unlisted home/hotspot connections and unknown per-user profiles.
    foreach ($facts in $LegacyFacts) {
        if ($Connection.ProfileName -and $facts.Profile.Name -ceq $Connection.ProfileName -and
            $facts.SsidHex -contains $Connection.SsidHex) { return $true }
    }
    return $false
}

function Initialize-OfficeLog {
    param([string]$Path)
    $script:LogPath = $Path
    if ($Path -and (Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length -ge 5MB) {
        for ($i = 3; $i -ge 1; $i--) {
            $source = if ($i -eq 1) { $Path } else { "$Path.$($i - 1)" }
            if (Test-Path -LiteralPath $source) { Move-Item -LiteralPath $source -Destination "$Path.$i" -Force }
        }
    }
}

function Write-OfficeLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $entry = [ordered]@{Utc = [DateTime]::UtcNow.ToString('o'); Level = $Level; Message = $Message} | ConvertTo-Json -Compress
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $entry -Encoding UTF8 -ErrorAction Stop }
    else { Write-Verbose $entry }
}

function Write-OfficeJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function Read-OfficeState {
    param([string]$Path, [string]$ConfigHash)
    $state = @{ConfigHash = $ConfigHash; Adapters = @{}}
    if (Test-Path -LiteralPath $Path) {
        try {
            $saved = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if ($saved.ConfigHash -eq $ConfigHash) {
                foreach ($p in $saved.Adapters.PSObject.Properties) {
                    $state.Adapters[$p.Name] = @{
                        PreferredSeenUtc = [string]$p.Value.PreferredSeenUtc
                        LastConnectAttemptUtc = [string]$p.Value.LastConnectAttemptUtc
                    }
                }
            }
        } catch { Write-OfficeLog 'State is unreadable; rebuilding it without prior connection proof.' 'WARN' }
    }
    $state
}

function Get-OfficeConnection {
    param($Client, [guid]$InterfaceId)
    try { return $Client.GetConnection($InterfaceId) }
    catch {
        # Microsoft's documented SSID-only alternative when current-connection access is restricted.
        try {
            $profiles = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetConnectionProfiles()
            foreach ($p in $profiles) {
                if ($p.IsWlanConnectionProfile -and $p.NetworkAdapter.NetworkAdapterId -eq $InterfaceId) {
                    $ssid = $p.WlanConnectionProfileDetails.GetConnectedSsid()
                    if (-not [string]::IsNullOrEmpty($ssid)) {
                        return [pscustomobject]@{Known = $true; ProfileName = ''; SsidHex = ConvertTo-SsidHex $ssid}
                    }
                }
            }
        } catch { }
        # Unknown is deliberately distinct from disconnected. Never delete based on this state.
        return [pscustomobject]@{Known = $false; ProfileName = ''; SsidHex = ''}
    }
}

function Invoke-OfficePolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Client, [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][hashtable]$State, [switch]$AuditOnly)
    $results = New-Object 'System.Collections.Generic.List[object]'
    $errors = 0
    foreach ($adapter in $Client.GetInterfaces()) {
        $id = [guid]$adapter.Id
        $key = $id.ToString()
        $status = 'Enforced'
        try {
            $facts = @($Client.GetProfiles($id) | ForEach-Object { Get-OfficeProfileFacts $_ })
            $matches = @($facts | Where-Object {
                $_.SsidHex -contains $Config.PreferredHex -and -not $_.IsPerUser -and
                ([string]::IsNullOrEmpty($Config.PreferredProfileName) -or $_.Profile.Name -ceq $Config.PreferredProfileName)
            })
            if ($matches.Count -eq 0) {
                Write-OfficeLog "[$id] Preferred all-user profile is missing; all changes deferred." 'WARN'
                $results.Add([pscustomobject]@{InterfaceId=$key; Status='WaitingForPreferredProfile'})
                continue
            }
            if ($matches.Count -gt 1) { throw 'Multiple profiles match the new SSID. Set PreferredProfileName to select the intended profile.' }
            $preferred = $matches[0]
            if ($preferred.IsGroupPolicy) { throw 'Preferred profile is managed by Group Policy and cannot be modified here.' }
            if (-not $preferred.IsInfrastructure -or $preferred.SsidHex.Count -ne 1) {
                throw 'The preferred profile must be an infrastructure profile containing only the new SSID.'
            }
            $legacyFacts = @($facts | Where-Object { Test-OfficeLegacyScope -Facts $_ -Config $Config })
            if (-not $State.Adapters.ContainsKey($key)) {
                $State.Adapters[$key] = @{PreferredSeenUtc=''; LastConnectAttemptUtc=''}
            }
            $record = $State.Adapters[$key]
            if (-not $preferred.Automatic -or $preferred.AutoSwitch) {
                Write-OfficeLog "[$id] Set preferred profile to automatic connection and autoSwitch=false. Audit=$AuditOnly"
                if (-not $AuditOnly) {
                    $xml = Set-OfficeConnectionXml -Facts $preferred -AutoSwitch $false -ConnectionMode auto
                    $Client.SetProfile($id, $xml, $preferred.Profile.Flags)
                }
            }
            $gpCount = @($facts | Where-Object IsGroupPolicy).Count
            if ($gpCount -gt 0) {
                Write-OfficeLog "[$id] Group Policy profiles take precedence; remove or update the conflicting GPO." 'WARN'
                $status = 'GroupPolicyPrecedence'
            } elseif ($preferred.Profile.Position -ne 0) {
                Write-OfficeLog "[$id] Move preferred profile to priority 1. Audit=$AuditOnly"
                if (-not $AuditOnly) { $Client.SetFirst($id, $preferred.Profile.Name) }
            }
            if ($Config.LegacySsidAction -ceq 'DisableAutoConnect') {
                foreach ($old in $legacyFacts) {
                    if (-not $old.Automatic -and -not $old.AutoSwitch) { continue }
                    Write-OfficeLog "[$id] Disable automatic connection on listed legacy profile '$($old.Profile.Name)'; retain the saved profile. Audit=$AuditOnly"
                    if (-not $AuditOnly) {
                        $xml = Set-OfficeConnectionXml -Facts $old -AutoSwitch $false -ConnectionMode manual
                        $Client.SetProfile($id, $xml, $old.Profile.Flags)
                    }
                }
                # Settings-only mode neither requires migration proof nor queries the active connection.
                if (-not $Config.ConnectWhenVisible) {
                    $results.Add([pscustomobject]@{InterfaceId=$key; Status=$status; LegacySsidAction=$Config.LegacySsidAction})
                    continue
                }
            }
            $current = Get-OfficeConnection -Client $Client -InterfaceId $id
            $onPreferred = $current.Known -and $current.SsidHex -eq $Config.PreferredHex
            $switchSourceAllowed = Test-OfficeSwitchSource -Connection $current -LegacyFacts $legacyFacts
            if ($Config.ConnectWhenVisible -and -not $onPreferred -and $current.Known -and -not $switchSourceAllowed) {
                Write-OfficeLog "[$id] Preserve the current connection: it is not an eligible listed legacy profile."
                $status = 'UnlistedOrUnmanagedConnectionPreserved'
            }
            if ($Config.ConnectWhenVisible -and -not $onPreferred -and $switchSourceAllowed -and $gpCount -eq 0) {
                $due = $true
                if ($record.LastConnectAttemptUtc) {
                    $lastAttempt = [DateTimeOffset]::Parse($record.LastConnectAttemptUtc)
                    $due = ([DateTimeOffset]::UtcNow - $lastAttempt).TotalMinutes -ge $Config.ConnectionAttemptCooldownMinutes
                }
                if ($due) {
                    $available = @()
                    try { $available = @($Client.GetAvailableNetworks($id)) }
                    catch {
                        Write-OfficeLog "[$id] Available-network query failed; explicit switching deferred. Check Windows location policy and WLAN access. $($_.Exception.Message)" 'WARN'
                        $status = 'AvailabilityQueryUnavailable'
                    }
                    $visible = @($available | Where-Object {
                        $_.SsidHex -eq $Config.PreferredHex -and $_.ProfileName -ceq $preferred.Profile.Name -and
                        $_.Connectable -and $_.BssidCount -gt 0 -and $_.SignalQuality -ge $Config.MinimumSignalQuality
                    })
                    if ($visible.Count -gt 0) {
                        Write-OfficeLog "[$id] Attempt connection to preferred profile. Audit=$AuditOnly"
                        if (-not $AuditOnly) {
                            # Recheck immediately before connecting in case the user selected a home/hotspot network.
                            $current = Get-OfficeConnection -Client $Client -InterfaceId $id
                            if (-not (Test-OfficeSwitchSource -Connection $current -LegacyFacts $legacyFacts)) {
                                Write-OfficeLog "[$id] Connection changed before the switch; preserving it."
                                $results.Add([pscustomobject]@{InterfaceId=$key; Status='ConnectionChangedSwitchDeferred'; LegacySsidAction=$Config.LegacySsidAction})
                                continue
                            }
                            $record.LastConnectAttemptUtc = [DateTimeOffset]::UtcNow.ToString('o')
                            $previousProfile = $current.ProfileName
                            try {
                                $Client.Connect($id, $preferred.Profile.Name)
                                $deadline = [DateTime]::UtcNow.AddSeconds($Config.ConnectionTimeoutSeconds)
                                do {
                                    Start-Sleep -Seconds 1
                                    $current = Get-OfficeConnection -Client $Client -InterfaceId $id
                                    $onPreferred = $current.Known -and $current.SsidHex -eq $Config.PreferredHex
                                } until ($onPreferred -or [DateTime]::UtcNow -ge $deadline)
                                if (-not $onPreferred) { throw 'Preferred connection was not confirmed before timeout.' }
                            } catch {
                                Write-OfficeLog "[$id] Preferred connection failed; legacy profiles retained. $($_.Exception.Message)" 'WARN'
                                $status = 'PreferredConnectionFailed'
                                # Try restoring the previous saved connection only if currently disconnected.
                                $current = Get-OfficeConnection -Client $Client -InterfaceId $id
                                if ($current.Known -and -not $current.SsidHex -and $previousProfile) {
                                    try { $Client.Connect($id, $previousProfile) }
                                    catch { Write-OfficeLog "[$id] Previous connection could not be restored automatically." 'WARN' }
                                }
                                $results.Add([pscustomobject]@{InterfaceId=$key; Status=$status})
                                continue
                            }
                        }
                    }
                }
            }
            if ($onPreferred -and -not $AuditOnly) {
                $record.PreferredSeenUtc = [DateTimeOffset]::UtcNow.ToString('o')
            }
            if ($Config.LegacySsidAction -ceq 'DisableAutoConnect') {
                if (-not $current.Known) { $status = 'ConnectionStateUnavailable' }
                $results.Add([pscustomobject]@{InterfaceId=$key; Status=$status; LegacySsidAction=$Config.LegacySsidAction})
                continue
            }
            $cleanupAllowed = (-not $Config.RequireSuccessfulPreferredConnectionBeforeRemoval) -or
                -not [string]::IsNullOrEmpty($record.PreferredSeenUtc) -or $onPreferred
            if (-not $cleanupAllowed) {
                if ($status -eq 'Enforced') { $status = 'WaitingForPreferredConnection' }
                Write-OfficeLog "[$id] Legacy cleanup waits for a verified connection to the new SSID."
            } else {
                foreach ($old in $legacyFacts) {
                    # Refresh before each deletion; a reconnect can happen between operations.
                    $current = Get-OfficeConnection -Client $Client -InterfaceId $id
                    if (-not $current.Known -or $old.SsidHex -contains $current.SsidHex -or
                        ($current.ProfileName -and $old.Profile.Name -ceq $current.ProfileName)) {
                        Write-OfficeLog "[$id] Retain '$($old.Profile.Name)': it is active or current connection is unknown." 'WARN'
                        $status = 'ActiveLegacyOrUnknownConnection'
                        continue
                    }
                    Write-OfficeLog "[$id] Remove exact legacy profile '$($old.Profile.Name)'. Audit=$AuditOnly"
                    if (-not $AuditOnly) { $Client.DeleteProfile($id, $old.Profile.Name) }
                }
            }
            if (-not $current.Known) { $status = 'ConnectionStateUnavailable' }
            $results.Add([pscustomobject]@{InterfaceId=$key; Status=$status; LegacySsidAction=$Config.LegacySsidAction})
        } catch {
            $errors++
            Write-OfficeLog "[$id] $($_.Exception.Message)" 'ERROR'
            $results.Add([pscustomobject]@{InterfaceId=$key; Status='Error'; Message=$_.Exception.Message})
        }
    }
    [pscustomobject]@{Utc=[DateTime]::UtcNow.ToString('o'); AuditOnly=[bool]$AuditOnly; Errors=$errors; Adapters=$results.ToArray()}
}

Export-ModuleMember -Function Get-OfficePaths,ConvertTo-SsidHex,Read-OfficeConfig,Get-OfficeProfileFacts,Set-OfficeConnectionXml,
    Initialize-OfficeLog,Write-OfficeLog,Write-OfficeJson,Read-OfficeState,Get-OfficeConnection,Invoke-OfficePolicy
