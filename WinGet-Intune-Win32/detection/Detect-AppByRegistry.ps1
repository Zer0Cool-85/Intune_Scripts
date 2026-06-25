<#
.SYNOPSIS
    Example Intune Win32 detection script using HKLM uninstall registry keys.

.DESCRIPTION
    Use this for machine-wide apps. Edit DisplayNameMatch and MinVersion for the target app.
    Intune detection scripts must exit 0 when detected and non-zero when not detected.
#>

[CmdletBinding()]
param(
    [string]$DisplayNameMatch = "Git",
    [string]$MinVersion,
    [switch]$ExactDisplayName
)

$ErrorActionPreference = "SilentlyContinue"

$UninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$Apps = Get-ItemProperty -Path $UninstallPaths | Where-Object {
    if ($ExactDisplayName) {
        $_.DisplayName -eq $DisplayNameMatch
    }
    else {
        $_.DisplayName -like "*$DisplayNameMatch*"
    }
}

if (-not $Apps) {
    Write-Output "Not detected: $DisplayNameMatch"
    exit 1
}

$App = $Apps | Sort-Object DisplayVersion -Descending | Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($MinVersion)) {
    Write-Output "Detected: $($App.DisplayName) $($App.DisplayVersion)"
    exit 0
}

try {
    $InstalledVersion = [version]$App.DisplayVersion
    $RequiredVersion = [version]$MinVersion

    if ($InstalledVersion -ge $RequiredVersion) {
        Write-Output "Detected: $($App.DisplayName) $($App.DisplayVersion)"
        exit 0
    }

    Write-Output "Detected $($App.DisplayName), but version $InstalledVersion is lower than required $RequiredVersion"
    exit 1
}
catch {
    Write-Output "Detected $($App.DisplayName), but version parsing failed. Treating as detected. Version: $($App.DisplayVersion)"
    exit 0
}
