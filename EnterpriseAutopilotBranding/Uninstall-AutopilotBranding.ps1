#requires -Version 5.1

<#
.SYNOPSIS
Removes Enterprise Autopilot Branding detection state and scheduled runtime.

.PARAMETER RemoveBrandingAssets
Also removes the exact wallpaper, lock-screen, theme, logo, and taskbar files listed in the
installed Config.xml. Existing user profiles and policy-backed settings are intentionally not
rewritten.

.PARAMETER RemoveLogs
Also removes the Logs directory. Logs are preserved by default for troubleshooting.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$RemoveBrandingAssets,

    [Parameter()]
    [switch]$RemoveLogs
)

if ($env:PROCESSOR_ARCHITEW6432) {
    $nativePowerShell = Join-Path $env:SystemRoot 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $nativePowerShell) {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($RemoveBrandingAssets) { $arguments += '-RemoveBrandingAssets' }
        if ($RemoveLogs) { $arguments += '-RemoveLogs' }
        $process = Start-Process -FilePath $nativePowerShell -ArgumentList $arguments -Wait -PassThru
        exit $process.ExitCode
    }
}

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$productRoot = Join-Path $env:ProgramData 'EnterpriseAutopilotBranding'
$runtimeRoot = Join-Path $productRoot 'Runtime'
$runtimeBackupRoot = Join-Path $productRoot 'Runtime.backup'
$logDirectory = Join-Path $productRoot 'Logs'
$stateDirectory = Join-Path $productRoot 'State'
$modulePath = Join-Path $runtimeRoot 'Modules\EnterpriseAutopilotBranding.psm1'
$configPath = Join-Path $runtimeRoot 'Config.xml'

if (-not (Test-Path -LiteralPath $productRoot)) {
    exit 0
}

try {
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf) -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw 'The installed runtime or configuration is missing. Manual state cleanup will be attempted.'
    }

    Import-Module -Name $modulePath -Force -ErrorAction Stop
    Initialize-EabLogging -LogDirectory $logDirectory -Component 'Uninstall'
    $config = Import-EabConfiguration -Path $configPath
    Write-EabLog -Component 'Uninstall' -Message 'Starting Enterprise Autopilot Branding removal.'

    Remove-EabInstalledArtifacts -Config $config -RemoveBrandingAssets:$RemoveBrandingAssets

    if (Test-Path -LiteralPath $runtimeRoot) {
        Remove-Item -LiteralPath $runtimeRoot -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $runtimeBackupRoot) {
        Remove-Item -LiteralPath $runtimeBackupRoot -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $stateDirectory) {
        Remove-Item -LiteralPath $stateDirectory -Recurse -Force -ErrorAction Stop
    }

    Write-EabLog -Component 'Uninstall' -Message 'Removal completed successfully.'
    if ($RemoveLogs -and (Test-Path -LiteralPath $logDirectory)) {
        Remove-Item -LiteralPath $logDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 0
}
catch {
    $message = $_.Exception.Message
    try {
        if (-not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }
        Add-Content -LiteralPath (Join-Path $logDirectory 'EnterpriseAutopilotBranding-UninstallFailure.log') -Value "$([DateTime]::UtcNow.ToString('o')) $message" -Encoding UTF8

        # Best-effort cleanup still runs when the installed module or configuration is damaged.
        $taskName = '\EnterpriseAutopilotBranding\PostEnroll'
        $taskUtility = Join-Path $env:SystemRoot 'System32\schtasks.exe'
        if (Test-Path -LiteralPath $taskUtility -PathType Leaf) {
            $taskProcess = Start-Process -FilePath $taskUtility -ArgumentList @('/Delete', '/TN', $taskName, '/F') -Wait -PassThru -WindowStyle Hidden
            if ($taskProcess.ExitCode -notin @(0, 1)) {
                Add-Content -LiteralPath (Join-Path $logDirectory 'EnterpriseAutopilotBranding-UninstallFailure.log') -Value "$([DateTime]::UtcNow.ToString('o')) Scheduled task cleanup returned exit code $($taskProcess.ExitCode)." -Encoding UTF8
            }
        }

        if (Test-Path -LiteralPath $stateDirectory) {
            Remove-Item -LiteralPath $stateDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $runtimeRoot) {
            Remove-Item -LiteralPath $runtimeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $runtimeBackupRoot) {
            Remove-Item -LiteralPath $runtimeBackupRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($RemoveLogs -and (Test-Path -LiteralPath $logDirectory)) {
            Remove-Item -LiteralPath $logDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}
    exit 1
}
