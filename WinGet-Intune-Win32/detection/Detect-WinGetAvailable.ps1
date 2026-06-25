<#
.SYNOPSIS
    Optional prerequisite detection script for checking whether winget.exe is available.

.DESCRIPTION
    This is not intended as app detection. It is useful as a separate troubleshooting script,
    proactive remediation detection, or prerequisite validation.
#>

function Get-WinGetPath {
    $Command = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if ($Command -and (Test-Path -Path $Command.Source)) {
        return $Command.Source
    }

    $WindowsAppsPath = Join-Path $env:ProgramFiles "WindowsApps"
    if (-not (Test-Path -Path $WindowsAppsPath)) {
        return $null
    }

    $Selected = Get-ChildItem -Path $WindowsAppsPath `
        -Directory `
        -Filter "Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe" `
        -ErrorAction SilentlyContinue |
        ForEach-Object {
            $Candidate = Join-Path $_.FullName "winget.exe"
            if (Test-Path -Path $Candidate) {
                [pscustomobject]@{
                    Path          = $Candidate
                    DirectoryName = $_.Name
                    LastWriteTime = $_.LastWriteTime
                }
            }
        } |
        Sort-Object LastWriteTime, DirectoryName -Descending |
        Select-Object -First 1

    if ($Selected) {
        return $Selected.Path
    }

    return $null
}

$WingetPath = Get-WinGetPath

if ($WingetPath) {
    Write-Output "Detected winget.exe: $WingetPath"
    exit 0
}

Write-Output "winget.exe not detected. App Installer / Windows Package Manager may not be installed or registered yet."
exit 1
