# ----------------------------
# Helpers: start/stop AWS client
# ----------------------------
function Start-AwsVpnClient {
    param(
        [string]$ExePath = "C:\Program Files\Amazon\AWS VPN Client\AWSVPNClient.exe"
    )
    if (-not (Test-Path $ExePath)) {
        throw "AWS VPN Client exe not found at: $ExePath"
    }
    & $ExePath | Out-Null
}

function Stop-AwsVpnClient {
    Get-Process -Name "AWSVPNClient" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# ----------------------------
# Core: Add/Update a VPN profile + write the .ovpn
# ----------------------------
function Set-AwsVpnProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName,

        # e.g. cvpn-endpoint-0123456789abcdef
        [Parameter(Mandatory)]
        [string]$CvpnEndpointId,

        # e.g. us-east-1
        [Parameter(Mandatory)]
        [string]$CvpnEndpointRegion,

        # Full .ovpn file contents (including cert blocks)
        [Parameter(Mandatory)]
        [string]$OvpnConfigContent,

        # Optional override if you don't want "<ProfileName>.ovpn"
        [string]$OvpnFileName = ($ProfileName -replace '[^\w\.-]', '_') + ".ovpn",

        [int]$FederatedAuthType = 1,
        [string]$CompatibilityVersion = "2"
    )

    $roamingRoot   = Join-Path $env:APPDATA "AWSVPNClient"
    $profilesPath  = Join-Path $roamingRoot "ConnectionProfiles"
    $configsFolder = Join-Path $roamingRoot "OpenVpnConfigs"
    $ovpnPath      = Join-Path $configsFolder $OvpnFileName

    # Make sure folders exist
    New-Item -ItemType Directory -Path $roamingRoot   -Force | Out-Null
    New-Item -ItemType Directory -Path $configsFolder -Force | Out-Null

    # If ConnectionProfiles doesn't exist yet, create a valid base object
    $profilesObj = $null
    if (Test-Path $profilesPath) {
        $raw = Get-Content -Path $profilesPath -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try {
                $profilesObj = $raw | ConvertFrom-Json -ErrorAction Stop
            } catch {
                throw "ConnectionProfiles exists but isn't valid JSON. Path: $profilesPath. Error: $($_.Exception.Message)"
            }
        }
    }

    if (-not $profilesObj) {
        $profilesObj = [pscustomobject]@{
            Version = "1"
            LastSelectedProfileIndex = 0
            ConnectionProfiles = @()
        }
    }

    if (-not $profilesObj.ConnectionProfiles) {
        $profilesObj | Add-Member -MemberType NoteProperty -Name ConnectionProfiles -Value @() -Force
    }

    # Ensure the .ovpn content is written
    Set-Content -Path $ovpnPath -Value $OvpnConfigContent -Encoding ascii -Force

    # Add/update profile entry
    $existing = $profilesObj.ConnectionProfiles | Where-Object { $_.ProfileName -eq $ProfileName } | Select-Object -First 1

    $profileEntry = [pscustomobject]@{
        ProfileName         = $ProfileName
        OvpnConfigFilePath  = $ovpnPath.Replace('\', '\\')  # AWS file uses escaped backslashes
        CvpnEndpointId      = $CvpnEndpointId
        CvpnEndpointRegion  = $CvpnEndpointRegion
        CompatibilityVersion = $CompatibilityVersion
        FederatedAuthType   = $FederatedAuthType
    }

    if ($existing) {
        # Update fields in-place
        foreach ($p in $profileEntry.PSObject.Properties) {
            $existing.$($p.Name) = $p.Value
        }
    } else {
        # Append new profile
        $profilesObj.ConnectionProfiles += $profileEntry
        # Optional: keep last selected index sane if this is the first profile
        if ($profilesObj.ConnectionProfiles.Count -eq 1) {
            $profilesObj.LastSelectedProfileIndex = 0
        }
    }

    # Write back JSON
    $json = $profilesObj | ConvertTo-Json -Depth 10 -Compress
    Set-Content -Path $profilesPath -Value $json -Encoding utf8 -Force
}

# ----------------------------
# Example usage
# ----------------------------

# 1) Launch once to let it create roaming files (if needed), then close it
Start-AwsVpnClient
Start-Sleep -Seconds 2
Stop-AwsVpnClient

# 2) Define your .ovpn contents (example: paste your full file here)
$ovpncert = @"
client

dev tun

proto udp

remote cvpn-endpoint-*ENDPOINT ID*

remote-random-hostname

resolv-retry infinite

nobind

remote-cert-tls server

cipher AES-256-GCM

verb 3

<ca>
-----BEGIN CERTIFICATE-----
*Long string cert here*
-----END CERTIFICATE-----
</ca>

auth-user-pass
auth-retry interact
auth-nocache
reneg-sec 0
"@

# 3) Create/update a profile
Set-AwsVpnProfile `
    -ProfileName "My AWS VPN" `
    -CvpnEndpointId "cvpn-endpoint-*ENDPOINT ID*" `
    -CvpnEndpointRegion "us-east-1" `
    -OvpnConfigContent $ovpncert `
    -OvpnFileName "MyAwsVpn.ovpn"

# 4) Add another profile? Just call it again with different values
# Set-AwsVpnProfile -ProfileName "My AWS VPN 2" -CvpnEndpointId "cvpn-endpoint-..." -CvpnEndpointRegion "us-west-2" -OvpnConfigContent $ovpncert2 -OvpnFileName "MyAwsVpn2.ovpn"

# 5) Restart the client to apply changes
Start-AwsVpnClient
