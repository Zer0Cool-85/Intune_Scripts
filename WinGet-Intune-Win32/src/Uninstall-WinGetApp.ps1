<#
.SYNOPSIS
    Uninstalls a WinGet package from Microsoft Intune Win32 app deployments.

.DESCRIPTION
    This wrapper is designed for Intune Management Extension / SYSTEM-context uninstalls.
    It resolves winget.exe from WindowsApps, runs exact package uninstall commands, disables
    interactivity, writes logs to ProgramData, retries failures, and exits with the native
    WinGet exit code so Intune receives accurate results.

.PARAMETER AppId
    The exact WinGet package ID, for example Git.Git or 7zip.7zip.

.PARAMETER Source
    WinGet source to restrict the uninstall query. Keeping this set helps avoid source prompts.

.PARAMETER Scope
    Installed package scope filter. Use machine, user, or none.

.PARAMETER Version
    Optional exact version to uninstall.

.PARAMETER AllVersions
    Uninstall all installed versions when supported by the package.

.PARAMETER ProductCode
    Optional product code filter. Useful for MSI-backed apps where WinGet ID matching is unreliable.

.PARAMETER Retries
    Number of retry attempts after the first failed uninstall attempt.

.PARAMETER RetryDelaySeconds
    Base retry delay. The delay is multiplied by the attempt number.

.PARAMETER LogRoot
    Folder for wrapper and WinGet logs.

.PARAMETER TreatNotInstalledAsSuccess
    Return success when WinGet indicates the package was not found.

.EXAMPLE
    .\Uninstall-WinGetApp.ps1 -AppId "Git.Git" -Source winget -Scope machine

.EXAMPLE
    .\Uninstall-WinGetApp.ps1 -AppId "SomeVendor.SomeApp" -Scope none -TreatNotInstalledAsSuccess
#>

[CmdletBinding(DefaultParameterSetName = "ByAppId")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "ByAppId")]
    [ValidateNotNullOrEmpty()]
    [string]$AppId,

    [Parameter(Mandatory = $true, ParameterSetName = "ByProductCode")]
    [ValidateNotNullOrEmpty()]
    [string]$ProductCode,

    [ValidateSet("winget", "msstore")]
    [string]$Source = "winget",

    [ValidateSet("machine", "user", "none")]
    [string]$Scope = "machine",

    [string]$Version,

    [switch]$AllVersions,

    [int]$Retries = 1,

    [int]$RetryDelaySeconds = 30,

    [string]$LogRoot = "$env:ProgramData\Company\Logs\WinGet",

    [switch]$TreatNotInstalledAsSuccess
)

$ErrorActionPreference = "Stop"

function New-SafeFileName {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value -replace '[\\/:*?"<>|]', '_')
}

$LogNameSeed = if ($PSCmdlet.ParameterSetName -eq "ByProductCode") { $ProductCode } else { $AppId }
$SafeLogName = New-SafeFileName -Value $LogNameSeed
New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null

$ScriptLog = Join-Path $LogRoot "$SafeLogName-uninstall-wrapper.log"
$WinGetLog = Join-Path $LogRoot "$SafeLogName-winget-uninstall.log"

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

function Test-NotInstalledOutput {
    param([object[]]$Output)

    $Text = ($Output | ForEach-Object { [string]$_ }) -join "`n"

    $NotInstalledPatterns = @(
        "No installed package found",
        "No package found",
        "No installed package found matching input criteria",
        "not found"
    )

    foreach ($Pattern in $NotInstalledPatterns) {
        if ($Text -match [regex]::Escape($Pattern)) {
            return $true
        }
    }

    return $false
}

try {
    Write-Log "========== WinGet uninstall wrapper started =========="
    Write-Log "User context: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Log "ParameterSet: $($PSCmdlet.ParameterSetName)"
    Write-Log "AppId: $AppId"
    Write-Log "ProductCode: $ProductCode"
    Write-Log "Source: $Source"
    Write-Log "Scope: $Scope"
    Write-Log "Version: $Version"
    Write-Log "AllVersions: $AllVersions"
    Write-Log "TreatNotInstalledAsSuccess: $TreatNotInstalledAsSuccess"

    $WinGetExe = Get-WinGetPath
    Write-Log "Resolved winget.exe: $WinGetExe"

    $null = Invoke-NativeCommand -FilePath $WinGetExe -Arguments @("--version")

    $UninstallArgs = @(
        "uninstall",
        "--silent",
        "--disable-interactivity",
        "--log", $WinGetLog
    )

    if ($PSCmdlet.ParameterSetName -eq "ByProductCode") {
        $UninstallArgs += @("--product-code", $ProductCode)
    }
    else {
        $UninstallArgs += @("--id", $AppId, "--exact", "--source", $Source)
    }

    if ($Scope -ne "none") {
        $UninstallArgs += @("--scope", $Scope)
    }

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $UninstallArgs += @("--version", $Version)
    }

    if ($AllVersions) {
        $UninstallArgs += "--all-versions"
    }

    $MaxAttempts = [Math]::Max(1, $Retries + 1)
    $FinalExitCode = 1
    $FinalOutput = @()

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        Write-Log "Uninstall attempt $Attempt of $MaxAttempts."
        $UninstallResult = Invoke-NativeCommand -FilePath $WinGetExe -Arguments $UninstallArgs
        $FinalExitCode = $UninstallResult.ExitCode
        $FinalOutput = $UninstallResult.Output

        if ($FinalExitCode -eq 0) {
            Write-Log "Uninstall completed successfully."
            exit 0
        }

        if ($TreatNotInstalledAsSuccess -and (Test-NotInstalledOutput -Output $FinalOutput)) {
            Write-Log "Package appears to be not installed. Treating as success."
            exit 0
        }

        if ($Attempt -lt $MaxAttempts) {
            $Delay = $RetryDelaySeconds * $Attempt
            Write-Log "Uninstall failed. Waiting $Delay seconds before retry."
            Start-Sleep -Seconds $Delay
        }
    }

    Write-Log "Uninstall failed after $MaxAttempts attempt(s). Final exit code: $FinalExitCode"
    exit $FinalExitCode
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "========== WinGet uninstall wrapper failed =========="
    exit 1
}
