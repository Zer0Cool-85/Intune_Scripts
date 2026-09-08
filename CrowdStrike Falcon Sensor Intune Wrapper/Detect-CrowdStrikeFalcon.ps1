#Requires -Version 5.1

# Keep this value identical to PackageRevision in Config.json. Increment both
# whenever a new Intune payload is published, even if the sensor version is unchanged.
$ExpectedPackageRevision = '2026.09.08.1'

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$StatePath = Join-Path $env:ProgramData 'CrowdStrikeFalconIntune\InstallState.json'

function Get-NormalizedVersion {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Match = [regex]::Match($Value, '(?<!\d)\d+(?:\.\d+){2,5}(?!\d)')
    if (-not $Match.Success) { throw "Unable to read a numeric version from '$Value'." }

    $Parts = @($Match.Value.Split('.') | ForEach-Object { [uint64]$_ })
    return ($Parts -join '.')
}

function Compare-VersionString {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $LeftVersion = Get-NormalizedVersion -Value $Left
    $RightVersion = Get-NormalizedVersion -Value $Right
    $LeftParts = @($LeftVersion.Split('.') | ForEach-Object { [uint64]$_ })
    $RightParts = @($RightVersion.Split('.') | ForEach-Object { [uint64]$_ })
    $PartCount = [Math]::Max($LeftParts.Count, $RightParts.Count)

    for ($Index = 0; $Index -lt $PartCount; $Index++) {
        $LeftPart = if ($Index -lt $LeftParts.Count) { $LeftParts[$Index] } else { [uint64]0 }
        $RightPart = if ($Index -lt $RightParts.Count) { $RightParts[$Index] } else { [uint64]0 }
        if ($LeftPart -gt $RightPart) { return 1 }
        if ($LeftPart -lt $RightPart) { return -1 }
    }

    return 0
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($Sha256.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $Sha256.Dispose()
    }
}

function Get-InstalledCid {
    $Locations = @(
        'SYSTEM\CrowdStrike\{9b03c1d9-3138-44ed-9fae-d9f4c034b88d}\{16e0423f-7058-48c9-a204-725362b67639}\Default',
        'SYSTEM\CurrentControlSet\Services\CSAgent\Sim'
    )

    $BaseKey = $null
    try {
        $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )

        foreach ($Location in $Locations) {
            $Key = $null
            try {
                $Key = $BaseKey.OpenSubKey($Location)
                if ($null -eq $Key) { continue }

                $Value = $Key.GetValue('CU', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($Value -is [byte[]]) {
                    $HexValue = (($Value | ForEach-Object { $_.ToString('x2') }) -join '')
                    if ($HexValue.Length -ge 32) {
                        return $HexValue.Substring(0, 32).ToLowerInvariant()
                    }
                }
                elseif ($null -ne $Value) {
                    $HexValue = ([string]$Value) -replace '[^A-Fa-f0-9]', ''
                    if ($HexValue.Length -ge 32) {
                        return $HexValue.Substring(0, 32).ToLowerInvariant()
                    }
                }
            }
            finally {
                if ($null -ne $Key) { $Key.Dispose() }
            }
        }
    }
    finally {
        if ($null -ne $BaseKey) { $BaseKey.Dispose() }
    }

    return $null
}

function Get-ServiceExecutablePath {
    param([Parameter(Mandatory = $true)][string]$ServiceName)

    $BaseKey = $null
    $ServiceKey = $null
    try {
        $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $ServiceKey = $BaseKey.OpenSubKey(('SYSTEM\CurrentControlSet\Services\{0}' -f $ServiceName))
        if ($null -eq $ServiceKey) { return $null }

        $ImagePath = [string]$ServiceKey.GetValue('ImagePath', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ([string]::IsNullOrWhiteSpace($ImagePath)) { return $null }

        $ExpandedPath = [Environment]::ExpandEnvironmentVariables($ImagePath.Trim())
        if ($ExpandedPath.StartsWith('\??\', [StringComparison]::Ordinal)) {
            $ExpandedPath = $ExpandedPath.Substring(4)
        }
        if ($ExpandedPath -match '(?i)^\\SystemRoot\\') {
            $ExpandedPath = Join-Path $env:SystemRoot $ExpandedPath.Substring(12)
        }
        if ($ExpandedPath -match '^"([^"]+\.exe)"') { return $Matches[1] }
        if ($ExpandedPath -match '^(.*?\.exe)(?:\s|$)') { return $Matches[1].Trim() }
    }
    finally {
        if ($null -ne $ServiceKey) { $ServiceKey.Dispose() }
        if ($null -ne $BaseKey) { $BaseKey.Dispose() }
    }

    return $null
}

function Get-InstalledSensorVersion {
    $BinaryPath = Get-ServiceExecutablePath -ServiceName 'CSFalconService'
    if (-not [string]::IsNullOrWhiteSpace($BinaryPath) -and (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        $VersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($BinaryPath)
        foreach ($Candidate in @([string]$VersionInfo.ProductVersion, [string]$VersionInfo.FileVersion)) {
            if ([string]::IsNullOrWhiteSpace($Candidate)) { continue }
            try { return Get-NormalizedVersion -Value $Candidate } catch { continue }
        }
    }

    $Versions = @()
    $UninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($View in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        $BaseKey = $null
        $UninstallKey = $null
        try {
            $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $View)
            $UninstallKey = $BaseKey.OpenSubKey($UninstallPath)
            if ($null -eq $UninstallKey) { continue }

            foreach ($SubKeyName in $UninstallKey.GetSubKeyNames()) {
                $ProductKey = $null
                try {
                    $ProductKey = $UninstallKey.OpenSubKey($SubKeyName)
                    if ($null -eq $ProductKey) { continue }
                    $DisplayName = [string]$ProductKey.GetValue('DisplayName')
                    $Publisher = [string]$ProductKey.GetValue('Publisher')
                    $IsFalconSensor = (
                        $DisplayName -match '(?i)^CrowdStrike (?:(?:Falcon|Windows) )?Sensor(?: Platform)?(?:\s.*)?$' -or
                        ($Publisher -match '(?i)CrowdStrike' -and $DisplayName -match '(?i)^(?:Falcon|Windows) Sensor(?:\s.*)?$')
                    )
                    if (-not $IsFalconSensor) { continue }

                    $DisplayVersion = [string]$ProductKey.GetValue('DisplayVersion')
                    if ([string]::IsNullOrWhiteSpace($DisplayVersion)) { continue }
                    try { $Versions += Get-NormalizedVersion -Value $DisplayVersion } catch { continue }
                }
                finally {
                    if ($null -ne $ProductKey) { $ProductKey.Dispose() }
                }
            }
        }
        finally {
            if ($null -ne $UninstallKey) { $UninstallKey.Dispose() }
            if ($null -ne $BaseKey) { $BaseKey.Dispose() }
        }
    }

    $HighestVersion = $null
    foreach ($Version in $Versions) {
        if ($null -eq $HighestVersion -or (Compare-VersionString -Left $Version -Right $HighestVersion) -gt 0) {
            $HighestVersion = $Version
        }
    }
    return $HighestVersion
}

try {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { exit 1 }

    $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if ([int]$State.SchemaVersion -ne 1) { exit 1 }
    if ([string]$State.PackageRevision -ne $ExpectedPackageRevision) { exit 1 }
    if ([string]::IsNullOrWhiteSpace([string]$State.MinimumSensorVersion)) { exit 1 }

    $InstalledVersion = Get-InstalledSensorVersion
    if ([string]::IsNullOrWhiteSpace($InstalledVersion)) { exit 1 }
    if ((Compare-VersionString -Left $InstalledVersion -Right ([string]$State.MinimumSensorVersion)) -lt 0) { exit 1 }

    $RequiredServices = @($State.RequiredServices)
    if ($RequiredServices.Count -lt 1) { exit 1 }
    foreach ($ServiceName in $RequiredServices) {
        $Service = Get-Service -Name ([string]$ServiceName) -ErrorAction SilentlyContinue
        if ($null -eq $Service) { exit 1 }
        if ([bool]$State.RequireRunningServices -and
            $Service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) { exit 1 }
    }

    $BinaryPath = Get-ServiceExecutablePath -ServiceName 'CSFalconService'
    if ([string]::IsNullOrWhiteSpace($BinaryPath) -or -not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) { exit 1 }

    if ([bool]$State.RequireTenantMatch) {
        if ([string]::IsNullOrWhiteSpace([string]$State.CidSha256)) { exit 1 }
        $InstalledCid = Get-InstalledCid
        if ([string]::IsNullOrWhiteSpace($InstalledCid)) { exit 1 }
        if ((Get-TextSha256 -Value $InstalledCid) -ne [string]$State.CidSha256) { exit 1 }
    }

    Write-Output "CrowdStrike Falcon Sensor wrapper $ExpectedPackageRevision detected; installed version $InstalledVersion (minimum $($State.MinimumSensorVersion))."
    exit 0
}
catch {
    exit 1
}
