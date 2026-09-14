#requires -Version 5.1
# Offline tests: fake WLAN client; never changes this computer's Wi-Fi or tasks.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Source/OfficeWiFi.psm1') -Force
$script:Passed = 0
$script:Failed = 0
$script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('OfficeWiFi-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:TestRoot)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++; Write-Output "PASS $Name" }
    catch { $script:Failed++; Write-Output "FAIL $Name -- $($_.Exception.Message)" }
}
function New-Config {
    $raw = [ordered]@{
        ConfigurationReady=$true; PolicyVersion='1.1.0'; PreferredSsid='Office-New'; PreferredProfileName=''
        LegacySsids=@('Office-Old'); EnforcementIntervalMinutes=15; LegacySsidAction='Remove'
        ConnectWhenVisible=$false; MinimumSignalQuality=40; ConnectionAttemptCooldownMinutes=30
        ConnectionTimeoutSeconds=5; RequireSuccessfulPreferredConnectionBeforeRemoval=$true
    }
    $path = Join-Path $script:TestRoot ([guid]::NewGuid().ToString('N') + '.json')
    $raw | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
    Read-OfficeConfig -Path $path
}
function New-Profile {
    param([string]$Name, [string[]]$Ssids, [int]$Position=0, [uint32]$Flags=0, [string]$Mode='auto', [bool]$Switch=$false)
    $ssidXml = ($Ssids | ForEach-Object { '<SSID><hex>' + (ConvertTo-SsidHex $_) + '</hex><name>' + [Security.SecurityElement]::Escape($_) + '</name></SSID>' }) -join ''
    $xml = '<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"><name>' + [Security.SecurityElement]::Escape($Name) +
        '</name><SSIDConfig>' + $ssidXml + '</SSIDConfig><connectionType>ESS</connectionType><connectionMode>' + $Mode +
        '</connectionMode><autoSwitch>' + $Switch.ToString().ToLowerInvariant() + '</autoSwitch><MSM><security><authEncryption>' +
        '<authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption>' +
        '<sharedKey><keyType>passPhrase</keyType><protected>true</protected><keyMaterial>ENCRYPTED_TEST_DATA</keyMaterial></sharedKey></security></MSM></WLANProfile>'
    [pscustomobject]@{Name=$Name; Xml=$xml; Flags=$Flags; Position=$Position}
}
function New-Client {
    param([object[]]$Profiles, [string]$CurrentSsid='Office-New', [string]$CurrentProfile='New Display Name')
    $client = [pscustomobject]@{
        Interfaces=@([pscustomobject]@{Id=[guid]'11111111-1111-1111-1111-111111111111'; State=1; Description='Test adapter'})
        Profiles=(New-Object 'System.Collections.Generic.List[object]')
        Operations=(New-Object 'System.Collections.Generic.List[string]')
        Current=[pscustomobject]@{Known=$true; ProfileName=$CurrentProfile; SsidHex=$(if ($CurrentSsid) {ConvertTo-SsidHex $CurrentSsid} else {''})}
        Available=@(); FailConnect=$false; UnknownConnection=$false; FailAvailability=$false
        AvailableCalls=0; ConnectionReads=0; ChangeToHomeOnRead=0
    }
    foreach ($p in $Profiles) { $client.Profiles.Add($p) }
    $client | Add-Member ScriptMethod GetInterfaces { $this.Interfaces }
    $client | Add-Member ScriptMethod GetProfiles { param($id) $this.Profiles.ToArray() }
    $client | Add-Member ScriptMethod GetConnection {
        param($id)
        $this.ConnectionReads++
        if ($this.ChangeToHomeOnRead -gt 0 -and $this.ConnectionReads -ge $this.ChangeToHomeOnRead) {
            $this.Current = [pscustomobject]@{Known=$true; ProfileName='Home'; SsidHex=ConvertTo-SsidHex 'Home'}
        }
        if ($this.UnknownConnection) { throw 'Connection query denied' }
        $this.Current
    }
    $client | Add-Member ScriptMethod GetAvailableNetworks {
        param($id)
        $this.AvailableCalls++
        if ($this.FailAvailability) { throw 'Availability query denied' }
        $this.Available
    }
    $client | Add-Member ScriptMethod SetProfile {
        param($id,$xml,$flags)
        $parsed = [xml]$xml
        $name = $parsed.DocumentElement.SelectSingleNode("./*[local-name()='name']").InnerText
        $p = @($this.Profiles | Where-Object { $_.Name -ceq $name })[0]
        $p.Xml = $xml
        $this.Operations.Add("Set:$name")
    }
    $client | Add-Member ScriptMethod SetFirst {
        param($id,$name)
        $p = @($this.Profiles | Where-Object { $_.Name -ceq $name })[0]
        $before = $p.Position
        foreach ($other in $this.Profiles) { if ($other.Position -lt $before) { $other.Position++ } }
        $p.Position = 0
        $this.Operations.Add("First:$name")
    }
    $client | Add-Member ScriptMethod DeleteProfile {
        param($id,$name)
        $p = @($this.Profiles | Where-Object { $_.Name -ceq $name })[0]
        [void]$this.Profiles.Remove($p)
        $this.Operations.Add("Delete:$name")
    }
    $client | Add-Member ScriptMethod Connect {
        param($id,$name)
        $this.Operations.Add("Connect:$name")
        if ($this.FailConnect) { throw 'Simulated authentication failure' }
        $p = @($this.Profiles | Where-Object { $_.Name -ceq $name })[0]
        $this.Current = [pscustomobject]@{Known=$true; ProfileName=$name; SsidHex=(Get-OfficeProfileFacts $p).SsidHex[0]}
    }
    $client
}
function New-StandardClient {
    param([string]$CurrentSsid='Office-New', [string]$CurrentProfile='New Display Name')
    New-Client -Profiles @((New-Profile 'Old Display Name' @('Office-Old') 0), (New-Profile 'New Display Name' @('Office-New') 1)) -CurrentSsid $CurrentSsid -CurrentProfile $CurrentProfile
}
function New-State { @{ConfigHash='test'; Adapters=@{}} }
function Add-Proof {
    param([hashtable]$State)
    $State.Adapters['11111111-1111-1111-1111-111111111111'] = @{PreferredSeenUtc=[DateTime]::UtcNow.ToString('o'); LastConnectAttemptUtc=''}
}
function Add-VisibleNew {
    param($Client, [int]$Signal=80)
    $Client.Available = @([pscustomobject]@{ProfileName='New Display Name'; SsidHex=ConvertTo-SsidHex 'Office-New'; Connectable=$true; BssidCount=1; SignalQuality=$Signal})
}

try {
    Test-Case 'Unconfigured source is rejected' {
        $raw = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Source/config.json') -Raw | ConvertFrom-Json
        $raw.ConfigurationReady = $false
        $p = Join-Path $script:TestRoot 'unconfigured.json'
        $raw | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding UTF8
        $threw=$false
        try { Read-OfficeConfig $p | Out-Null } catch { $threw=$true }
        Assert-True $threw 'Placeholder configuration unexpectedly accepted'
    }
    Test-Case 'Preferred SSID cannot also be legacy' {
        $c = New-Config
        $raw = Get-Content -LiteralPath (Get-ChildItem $script:TestRoot -File | Sort-Object LastWriteTime | Select-Object -Last 1).FullName -Raw | ConvertFrom-Json
        $raw.LegacySsids = @('Office-New')
        $p=Join-Path $script:TestRoot 'overlap.json'; $raw | ConvertTo-Json | Set-Content $p -Encoding UTF8
        $threw=$false; try { Read-OfficeConfig $p | Out-Null } catch { $threw=$true }
        Assert-True $threw 'Overlapping SSID accepted'
    }
    Test-Case 'Missing preferred profile prevents all changes' {
        $c=New-Config; $client=New-Client @((New-Profile 'Old' @('Office-Old')))
        $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True ($client.Operations.Count -eq 0 -and $r.Adapters[0].Status -eq 'WaitingForPreferredProfile') 'Changes were made without the new profile'
    }
    Test-Case 'SSID matching handles different profile display names' {
        $client=New-StandardClient; $r=Invoke-OfficePolicy $client (New-Config) (New-State)
        Assert-True ($r.Errors -eq 0 -and $client.Operations.Contains('Delete:Old Display Name') -and $client.Operations.Contains('First:New Display Name')) 'SSID-based selection failed'
    }
    Test-Case 'Initial migration waits for successful new connection' {
        $client=New-StandardClient 'Home' 'Home'; $r=Invoke-OfficePolicy $client (New-Config) (New-State)
        Assert-True (-not $client.Operations.Contains('Delete:Old Display Name') -and $r.Adapters[0].Status -eq 'WaitingForPreferredConnection') 'Old profile deleted before migration proof'
    }
    Test-Case 'Previously verified adapter can clean legacy profiles offsite' {
        $client=New-StandardClient 'Home' 'Home'; $state=New-State; Add-Proof $state
        $r=Invoke-OfficePolicy $client (New-Config) $state
        Assert-True $client.Operations.Contains('Delete:Old Display Name') 'Verified offsite cleanup failed'
    }
    Test-Case 'Active legacy profile is retained even with prior proof' {
        $client=New-StandardClient 'Office-Old' 'Old Display Name'; $state=New-State; Add-Proof $state
        $r=Invoke-OfficePolicy $client (New-Config) $state
        Assert-True (-not $client.Operations.Contains('Delete:Old Display Name')) 'Active old profile deleted'
    }
    Test-Case 'Unknown connection state prevents deletion and forced switching' {
        $client=New-StandardClient; $client.UnknownConnection=$true; $state=New-State; Add-Proof $state
        $c=New-Config; $c.ConnectWhenVisible=$true; Add-VisibleNew $client
        $r=Invoke-OfficePolicy $client $c $state
        Assert-True (@($client.Operations | Where-Object { $_ -match '^(Delete|Connect):' }).Count -eq 0) 'Destructive operation with unknown state'
    }
    Test-Case 'Unrelated home and manually configured profiles remain' {
        $client=New-StandardClient
        $client.Profiles.Add((New-Profile 'Home' @('Home') 2))
        $client.Profiles.Add((New-Profile 'Manual' @('Manual') 3 -Mode 'manual'))
        $r=Invoke-OfficePolicy $client (New-Config) (New-State)
        Assert-True (@($client.Profiles | Where-Object Name -eq 'Home').Count -eq 1 -and -not $client.Operations.Contains('Set:Manual')) 'Unrelated profile removed or manual mode changed'
    }
    Test-Case 'Multi-SSID profiles with unrelated networks are retained' {
        $client=New-StandardClient; $client.Profiles.Add((New-Profile 'Mixed' @('Office-Old','Home') 2))
        $r=Invoke-OfficePolicy $client (New-Config) (New-State)
        Assert-True (-not $client.Operations.Contains('Delete:Mixed')) 'Mixed profile deleted'
    }
    Test-Case 'Preferred multi-SSID profile is rejected before modification' {
        $client=New-Client @((New-Profile 'New' @('Office-New','Office-Old')))
        $r=Invoke-OfficePolicy $client (New-Config) (New-State)
        Assert-True ($r.Errors -eq 1 -and $client.Operations.Count -eq 0) 'Ambiguous preferred multi-SSID profile accepted'
    }
    Test-Case 'Wildcard characters in SSIDs are treated literally' {
        $c=New-Config; $c.LegacyHex=@{(ConvertTo-SsidHex 'Old*')=$true}
        $client=New-Client @((New-Profile 'New' @('Office-New')), (New-Profile 'Literal*' @('Old*') 1), (New-Profile 'Other' @('Old123') 2))
        $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True ($client.Operations.Contains('Delete:Literal*') -and -not $client.Operations.Contains('Delete:Other')) 'Wildcard matching escaped its intended SSID'
    }
    Test-Case 'SSID case is preserved' {
        $client=New-StandardClient; $client.Profiles.Add((New-Profile 'Lower' @('office-old') 2))
        $r=Invoke-OfficePolicy $client (New-Config) (New-State)
        Assert-True (-not $client.Operations.Contains('Delete:Lower')) 'Case-sensitive SSIDs were conflated'
    }
    Test-Case 'Duplicate preferred profiles require explicit selection' {
        $client=New-StandardClient; $client.Profiles.Add((New-Profile 'Duplicate' @('Office-New') 2))
        $c=New-Config; $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True ($r.Errors -eq 1 -and $client.Operations.Count -eq 0) 'Duplicate preferred profile silently selected'
        $c.PreferredProfileName='New Display Name'; $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True ($r.Errors -eq 0) 'Explicit preferred name not honored'
    }
    Test-Case 'Group Policy and per-user legacy profiles are retained' {
        $client=New-StandardClient
        $client.Profiles.Add((New-Profile 'GPO' @('Office-Old') 2 1))
        $client.Profiles.Add((New-Profile 'User' @('Office-Old') 3 2))
        $r=Invoke-OfficePolicy $client (New-Config) (New-State)
        Assert-True (-not $client.Operations.Contains('Delete:GPO') -and -not $client.Operations.Contains('Delete:User') -and -not $client.Operations.Contains('Set:GPO')) 'Managed or per-user profile modified'
    }
    Test-Case 'Audit mode makes no WLAN changes' {
        $client=New-StandardClient; $r=Invoke-OfficePolicy $client (New-Config) (New-State) -AuditOnly
        Assert-True ($client.Operations.Count -eq 0 -and $r.AuditOnly) 'Audit modified WLAN settings'
    }
    Test-Case 'Offsite operation never blindly connects' {
        $client=New-StandardClient 'Home' 'Home'; $c=New-Config; $c.ConnectWhenVisible=$true
        $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True (@($client.Operations | Where-Object { $_ -like 'Connect:*' }).Count -eq 0) 'Blind connect attempted'
    }
    Test-Case 'Visible preferred network is connected before legacy cleanup' {
        $client=New-StandardClient 'Office-Old' 'Old Display Name'; Add-VisibleNew $client
        $c=New-Config; $c.ConnectWhenVisible=$true; $state=New-State
        $r=Invoke-OfficePolicy $client $c $state
        Assert-True ($client.Operations.IndexOf('Connect:New Display Name') -ge 0 -and $client.Operations.IndexOf('Delete:Old Display Name') -gt $client.Operations.IndexOf('Connect:New Display Name')) 'Cleanup preceded a confirmed connection'
    }
    Test-Case 'Low signal does not trigger an explicit connect' {
        $client=New-StandardClient 'Office-Old' 'Old Display Name'; Add-VisibleNew $client 10
        $c=New-Config; $c.ConnectWhenVisible=$true; $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True (-not $client.Operations.Contains('Connect:New Display Name')) 'Signal threshold ignored'
    }
    Test-Case 'Availability access denial retains normal priority enforcement' {
        $client=New-StandardClient 'Office-Old' 'Old Display Name'; $client.FailAvailability=$true
        $c=New-Config; $c.ConnectWhenVisible=$true; $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True ($client.Operations.Contains('First:New Display Name') -and -not $client.Operations.Contains('Connect:New Display Name') -and $r.Errors -eq 0) 'Availability error caused unsafe fallback'
    }
    Test-Case 'Connect cooldown suppresses repeated attempts' {
        $client=New-StandardClient 'Office-Old' 'Old Display Name'; Add-VisibleNew $client
        $c=New-Config; $c.ConnectWhenVisible=$true; $state=New-State; Add-Proof $state
        $state.Adapters['11111111-1111-1111-1111-111111111111'].LastConnectAttemptUtc=[DateTimeOffset]::UtcNow.ToString('o')
        $r=Invoke-OfficePolicy $client $c $state
        Assert-True (-not $client.Operations.Contains('Connect:New Display Name')) 'Cooldown ignored'
    }
    Test-Case 'Failed forced connection retains old profile even with prior proof' {
        $client=New-StandardClient 'Office-Old' 'Old Display Name'; Add-VisibleNew $client; $client.FailConnect=$true
        $c=New-Config; $c.ConnectWhenVisible=$true; $state=New-State; Add-Proof $state
        $r=Invoke-OfficePolicy $client $c $state
        Assert-True (-not $client.Operations.Contains('Delete:Old Display Name') -and $r.Adapters[0].Status -eq 'PreferredConnectionFailed') 'Old profile deleted after failed connection'
    }
    Test-Case 'Repeated enforcement is idempotent' {
        $client=New-StandardClient; $c=New-Config; $state=New-State
        $r=Invoke-OfficePolicy $client $c $state
        $client.Operations.Clear(); $r=Invoke-OfficePolicy $client $c $state
        Assert-True ($client.Operations.Count -eq 0) 'Second run unnecessarily changed profiles'
    }
    Test-Case 'Authentication and protected key XML survive connection changes' {
        $p=New-Profile 'New' @('Office-New') 0 -Mode 'manual' -Switch $true
        $before=([xml]$p.Xml).WLANProfile.MSM.OuterXml
        $client=New-Client @($p); $r=Invoke-OfficePolicy $client (New-Config) (New-State)
        $after=([xml]$p.Xml).WLANProfile.MSM.OuterXml
        Assert-True ($before -ceq $after -and $client.Operations.Contains('Set:New')) 'Authentication XML changed'
    }
    Test-Case 'Config changes invalidate saved migration proof' {
        $p=Join-Path $script:TestRoot 'state.json'; $s=New-State; Add-Proof $s
        Write-OfficeJson $p $s
        $loaded=Read-OfficeState $p 'different-config'
        Assert-True ($loaded.Adapters.Count -eq 0) 'Migration proof reused across a different configuration'
    }
    Test-Case 'State JSON survives an atomic replacement' {
        $p=Join-Path $script:TestRoot 'atomic.json'; $s=New-State; Add-Proof $s
        Write-OfficeJson $p $s; Write-OfficeJson $p $s
        $loaded=Read-OfficeState $p 'test'
        Assert-True ($loaded.Adapters.Count -eq 1) 'State did not survive replacement'
    }
    Test-Case 'Disable mode retains legacy credentials and enables preferred automatic connection' {
        $c=New-Config; $c.LegacySsidAction='DisableAutoConnect'
        $old=New-Profile 'Old Display Name' @('Office-Old') 0 -Switch $true
        $new=New-Profile 'New Display Name' @('Office-New') 1 -Mode 'manual'
        $oldSecurity=([xml]$old.Xml).WLANProfile.MSM.OuterXml
        $client=New-Client @($old,$new) 'Home' 'Home'
        $r=Invoke-OfficePolicy $client $c (New-State)
        $oldFacts=Get-OfficeProfileFacts $old; $newFacts=Get-OfficeProfileFacts $new
        Assert-True ($r.Errors -eq 0 -and -not $oldFacts.Automatic -and -not $oldFacts.AutoSwitch -and $newFacts.Automatic) 'Requested connection settings were not enforced'
        Assert-True ($client.Profiles.Count -eq 2 -and ([xml]$old.Xml).WLANProfile.MSM.OuterXml -ceq $oldSecurity) 'Saved legacy profile or credentials changed'
    }
    Test-Case 'Disable-only mode works offsite without connection proof or location queries' {
        $c=New-Config; $c.LegacySsidAction='DisableAutoConnect'
        $client=New-StandardClient 'Home' 'Home'; $client.UnknownConnection=$true
        $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True ($r.Errors -eq 0 -and $client.Operations.Contains('Set:Old Display Name') -and $client.ConnectionReads -eq 0 -and $client.AvailableCalls -eq 0) 'Settings-only mode depended on connection information'
    }
    Test-Case 'Unlisted profiles retain their exact XML and relative order in both actions' {
        foreach ($action in @('DisableAutoConnect','Remove')) {
            $c=New-Config; $c.LegacySsidAction=$action
            $homeProfile=New-Profile 'Home' @('Home') 0
            $hotspot=New-Profile 'Phone' @('Phone-Hotspot') 1 -Switch $true
            $remote=New-Profile 'Remote' @('Remote') 2 -Mode 'manual'
            $original=@{Home=$homeProfile.Xml; Phone=$hotspot.Xml; Remote=$remote.Xml}
            $client=New-Client @($homeProfile,$hotspot,$remote,(New-Profile 'New Display Name' @('Office-New') 3),(New-Profile 'Old Display Name' @('Office-Old') 4))
            $r=Invoke-OfficePolicy $client $c (New-State)
            foreach ($p in @($homeProfile,$hotspot,$remote)) {
                Assert-True ($p.Xml -ceq $original[$p.Name] -and -not $client.Operations.Contains("Set:$($p.Name)") -and -not $client.Operations.Contains("Delete:$($p.Name)")) "Unlisted $($p.Name) changed in $action mode"
            }
            Assert-True ($homeProfile.Position -lt $hotspot.Position -and $hotspot.Position -lt $remote.Position) 'Relative order of unrelated profiles changed'
        }
    }
    Test-Case 'Explicit switching never leaves an unlisted home network even with new SSID visible' {
        foreach ($action in @('DisableAutoConnect','Remove')) {
            $c=New-Config; $c.LegacySsidAction=$action; $c.ConnectWhenVisible=$true
            $client=New-StandardClient 'Home' 'Home'; Add-VisibleNew $client
            $r=Invoke-OfficePolicy $client $c (New-State)
            Assert-True ($client.AvailableCalls -eq 0 -and @($client.Operations | Where-Object { $_ -like 'Connect:*' }).Count -eq 0) "Home connection was disturbed in $action mode"
        }
    }
    Test-Case 'A newly selected home connection is rechecked before a forced switch' {
        $c=New-Config; $c.ConnectWhenVisible=$true
        $client=New-StandardClient 'Office-Old' 'Old Display Name'; Add-VisibleNew $client; $client.ChangeToHomeOnRead=2
        $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True (-not $client.Operations.Contains('Connect:New Display Name') -and $r.Adapters[0].Status -eq 'ConnectionChangedSwitchDeferred') 'A changed home connection was overridden'
    }
    Test-Case 'Disable mode preserves mixed and unmanaged profile XML' {
        $c=New-Config; $c.LegacySsidAction='DisableAutoConnect'
        $mixed=New-Profile 'Mixed' @('Office-Old','Home') 2 -Switch $true
        $gpo=New-Profile 'GPO' @('Office-Old') 3 1
        $user=New-Profile 'User' @('Office-Old') 4 2
        $before=@{Mixed=$mixed.Xml; GPO=$gpo.Xml; User=$user.Xml}
        $client=New-StandardClient
        foreach ($p in @($mixed,$gpo,$user)) { $client.Profiles.Add($p) }
        $r=Invoke-OfficePolicy $client $c (New-State)
        foreach ($p in @($mixed,$gpo,$user)) { Assert-True ($p.Xml -ceq $before[$p.Name]) "Unscoped or unmanaged profile $($p.Name) changed" }
    }
    Test-Case 'Disable mode is idempotent and audit makes no changes' {
        $c=New-Config; $c.LegacySsidAction='DisableAutoConnect'; $client=New-StandardClient; $state=New-State
        $r=Invoke-OfficePolicy $client $c $state -AuditOnly
        Assert-True ($client.Operations.Count -eq 0) 'Disable audit modified a profile'
        $r=Invoke-OfficePolicy $client $c $state
        $client.Operations.Clear(); $r=Invoke-OfficePolicy $client $c $state
        Assert-True ($client.Operations.Count -eq 0) 'Repeated disable run modified compliant settings'
    }
    Test-Case 'Disabled legacy profiles remain manually usable and optional switching stays scoped' {
        $c=New-Config; $c.LegacySsidAction='DisableAutoConnect'; $c.ConnectWhenVisible=$true
        $client=New-StandardClient 'Office-Old' 'Old Display Name'; Add-VisibleNew $client
        $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True ($client.Operations.Contains('Connect:New Display Name') -and -not $client.Operations.Contains('Delete:Old Display Name') -and $client.Profiles.Count -eq 2) 'Disable mode removed a profile or scoped switching failed'
    }
    Test-Case 'Mixed active legacy profile cannot be a forced-switch source' {
        $c=New-Config; $c.ConnectWhenVisible=$true
        $client=New-Client @((New-Profile 'New Display Name' @('Office-New') 0), (New-Profile 'Mixed' @('Office-Old','Home') 1)) 'Office-Old' 'Mixed'
        Add-VisibleNew $client; $r=Invoke-OfficePolicy $client $c (New-State)
        Assert-True (-not $client.Operations.Contains('Connect:New Display Name') -and -not $client.Operations.Contains('Set:Mixed')) 'Mixed active profile was affected'
    }
    Test-Case 'Old broad-scope config is rejected with upgrade guidance' {
        $raw=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Source/config.json') -Raw | ConvertFrom-Json
        $raw | Add-Member NoteProperty EnableAutoSwitchOnOtherAutoProfiles $true
        $p=Join-Path $script:TestRoot 'old-schema.json'; $raw | ConvertTo-Json | Set-Content $p -Encoding UTF8
        $message=''; try { Read-OfficeConfig $p | Out-Null } catch { $message=$_.Exception.Message }
        Assert-True ($message -like '*removed in 1.1.0*') 'Old broad setting did not fail explicitly'
    }
    Test-Case 'Unknown legacy action is rejected before changes' {
        $raw=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Source/config.json') -Raw | ConvertFrom-Json
        $raw.LegacySsidAction='Typo'
        $p=Join-Path $script:TestRoot 'bad-action.json'; $raw | ConvertTo-Json | Set-Content $p -Encoding UTF8
        $message=''; try { Read-OfficeConfig $p | Out-Null } catch { $message=$_.Exception.Message }
        Assert-True ($message -like '*LegacySsidAction must be*') 'Unknown action did not fail explicitly'
    }
} finally { Remove-Item -LiteralPath $script:TestRoot -Recurse -Force }
Write-Output "Result: $script:Passed passed; $script:Failed failed."
if ($script:Failed -gt 0) { exit 1 }
