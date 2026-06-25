<#
.SYNOPSIS
    Installs a WinGet package from Microsoft Intune Win32 app deployments.

.DESCRIPTION
    This wrapper is designed for Intune Management Extension / SYSTEM-context installs.
    It resolves winget.exe from WindowsApps, runs with exact package IDs, accepts agreements,
    disables interactivity, writes wrapper and WinGet logs to ProgramData, retries failures,
    and exits with the native WinGet exit code so Intune receives accurate results.

.PARAMETER AppId
    The exact WinGet package ID, for example Git.Git or 7zip.7zip.

.PARAMETER Version
    Optional exact version to install.

.PARAMETER Source
    WinGet source to use. Common values are winget or msstore.

.PARAMETER Scope
    Requested install scope. Use machine when the package supports machine-wide installs.
    Use none when the package does not support scope selection and should use the installer default.

.PARAMETER Retries
    Number of retry attempts after the first failed install attempt.

.PARAMETER RetryDelaySeconds
    Base retry delay. The delay is multiplied by the attempt number.

.PARAMETER LogRoot
    Folder for wrapper and WinGet logs.

.PARAMETER SkipSourceUpdate
    Skip winget source update before install.

.EXAMPLE
    .\Install-WinGetApp.ps1 -AppId "Git.Git" -Source winget -Scope machine

.EXAMPLE
    .\Install-WinGetApp.ps1 -AppId "Microsoft.PowerToys" -Version "0.82.1" -Source winget -Scope machine

.EXAMPLE
    .\Install-WinGetApp.ps1 -AppId "SomeVendor.SomeApp" -Scope none
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [string]$Version,

    [ValidateSet("winget", "msstore")]
    [string]$Source = "winget",

    [ValidateSet("machine", "user", "none")]
    [string]$Scope = "machine",

    [int]$Retries = 2,

    [int]$RetryDelaySeconds = 30,

    [string]$LogRoot = "$env:ProgramData\Company\Logs\WinGet",

    [switch]$SkipSourceUpdate
)

$ErrorActionPreference = "Stop"

function New-SafeFileName {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value -replace '[\\/:*?"<>|]', '_')
}

$SafeAppId = New-SafeFileName -Value $AppId
New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null

$ScriptLog = Join-Path $LogRoot "$SafeAppId-install-wrapper.log"
$WinGetLog = Join-Path $LogRoot "$SafeAppId-winget-install.log"

function Write-Log {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message)
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $ScriptLog -Value $Line
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Write-Log "Running: `"$FilePath`" $($Arguments -join ' ')"
    $Output = & $FilePath @Arguments 2>&1
    $ExitCode = $LASTEXITCODE

    foreach ($Line in $Output) {
        Write-Log ([string]$Line)
    }

    Write-Log "Exit code: $ExitCode"

    return [pscustomobject]@{
        ExitCode = $ExitCode
        Output   = $Output
    }
}

function Get-WinGetPath {
    $Command = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if ($Command -and (Test-Path -Path $Command.Source)) {
        return $Command.Source
    }

    $WindowsAppsPath = Join-Path $env:ProgramFiles "WindowsApps"
    $PossiblePaths = @()

    if (Test-Path -Path $WindowsAppsPath) {
        $PossiblePaths = Get-ChildItem -Path $WindowsAppsPath `
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
            }
    }

    $Selected = $PossiblePaths |
        Sort-Object LastWriteTime, DirectoryName -Descending |
        Select-Object -First 1

    if ($Selected) {
        return $Selected.Path
    }

    throw "winget.exe was not found. App Installer / Windows Package Manager may not be installed or registered for this device yet."
}

try {
    Write-Log "========== WinGet install wrapper started =========="
    Write-Log "User context: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Log "AppId: $AppId"
    Write-Log "Version: $Version"
    Write-Log "Source: $Source"
    Write-Log "Scope: $Scope"
    Write-Log "Retries: $Retries"
    Write-Log "RetryDelaySeconds: $RetryDelaySeconds"

    $WinGetExe = Get-WinGetPath
    Write-Log "Resolved winget.exe: $WinGetExe"

    $VersionResult = Invoke-NativeCommand -FilePath $WinGetExe -Arguments @("--version")

    if (-not $SkipSourceUpdate) {
        $SourceUpdateArgs = @(
            "source", "update",
            "--name", $Source,
            "--accept-source-agreements",
            "--disable-interactivity"
        )

        $SourceUpdateResult = Invoke-NativeCommand -FilePath $WinGetExe -Arguments $SourceUpdateArgs
        if ($SourceUpdateResult.ExitCode -ne 0) {
            Write-Log "Source update failed with exit code $($SourceUpdateResult.ExitCode). Continuing to install attempt."
        }
    }
    else {
        Write-Log "Source update skipped by parameter."
    }

    $InstallArgs = @(
        "install",
        "--id", $AppId,
        "--exact",
        "--source", $Source,
        "--silent",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity",
        "--log", $WinGetLog
    )

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $InstallArgs += @("--version", $Version)
    }

    if ($Scope -ne "none") {
        $InstallArgs += @("--scope", $Scope)
    }

    $MaxAttempts = [Math]::Max(1, $Retries + 1)
    $FinalExitCode = 1

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        Write-Log "Install attempt $Attempt of $MaxAttempts."
        $InstallResult = Invoke-NativeCommand -FilePath $WinGetExe -Arguments $InstallArgs
        $FinalExitCode = $InstallResult.ExitCode

        if ($FinalExitCode -eq 0) {
            Write-Log "Install completed successfully."
            exit 0
        }

        if ($Attempt -lt $MaxAttempts) {
            $Delay = $RetryDelaySeconds * $Attempt
            Write-Log "Install failed. Waiting $Delay seconds before retry."
            Start-Sleep -Seconds $Delay
        }
    }

    Write-Log "Install failed after $MaxAttempts attempt(s). Final exit code: $FinalExitCode"
    exit $FinalExitCode
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "========== WinGet install wrapper failed =========="
    exit 1
}
