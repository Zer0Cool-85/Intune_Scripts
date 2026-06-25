<#
.SYNOPSIS
    Example Intune Win32 detection script using a file path and optional minimum version.

.DESCRIPTION
    Use this when the app has a reliable EXE/DLL path. Edit FilePath and MinVersion.
    Intune detection scripts must exit 0 when detected and non-zero when not detected.
#>

[CmdletBinding()]
param(
    [string]$FilePath = "C:\Program Files\Git\cmd\git.exe",
    [string]$MinVersion
)

if (-not (Test-Path -Path $FilePath)) {
    Write-Output "Not detected: $FilePath"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($MinVersion)) {
    Write-Output "Detected: $FilePath"
    exit 0
}

try {
    $File = Get-Item -Path $FilePath -ErrorAction Stop
    $InstalledVersion = [version]$File.VersionInfo.FileVersion
    $RequiredVersion = [version]$MinVersion

    if ($InstalledVersion -ge $RequiredVersion) {
        Write-Output "Detected: $FilePath version $InstalledVersion"
        exit 0
    }

    Write-Output "Detected file, but version $InstalledVersion is lower than required $RequiredVersion"
    exit 1
}
catch {
    Write-Output "Detected file, but version parsing failed. Treating as detected. Path: $FilePath"
    exit 0
}
