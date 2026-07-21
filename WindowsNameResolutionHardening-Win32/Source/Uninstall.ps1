#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Removes the Win32 app's enforcement mechanism.

.DESCRIPTION
    Removes the scheduled task, package marker, installed script, and logs.
    Security settings are deliberately retained so an Intune uninstall
    assignment cannot silently re-enable NBT-NS, LLMNR, mDNS, or WPAD.
#>

[CmdletBinding()]
param()

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $nativePowerShell = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $nativeArguments = @(
        '-NoProfile'
        '-NonInteractive'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $PSCommandPath)
    )

    $nativeProcess = Start-Process -FilePath $nativePowerShell -ArgumentList $nativeArguments -Wait -PassThru
    exit $nativeProcess.ExitCode
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'Windows Name Resolution Hardening'
$installRoot = Join-Path $env:ProgramData 'WindowsNameResolutionHardening'
$markerPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WindowsNameResolutionHardening'
$failures = [System.Collections.Generic.List[string]]::new()

try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        try {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Output "Removed scheduled task '$taskName'."
        }
        catch {
            $failures.Add("Unable to remove scheduled task '$taskName': $($_.Exception.Message)")
        }
    }

    if (Test-Path -LiteralPath $markerPath) {
        try {
            Remove-Item -LiteralPath $markerPath -Recurse -Force -ErrorAction Stop
            Write-Output 'Removed package marker.'
        }
        catch {
            $failures.Add("Unable to remove package marker: $($_.Exception.Message)")
        }
    }

    if (Test-Path -LiteralPath $installRoot) {
        try {
            $resolvedInstallRoot = [IO.Path]::GetFullPath($installRoot).TrimEnd('\')
            $expectedLeaf = 'WindowsNameResolutionHardening'
            if ((Split-Path -Path $resolvedInstallRoot -Leaf) -ne $expectedLeaf) {
                throw "Refusing to remove unexpected path '$resolvedInstallRoot'."
            }

            Remove-Item -LiteralPath $resolvedInstallRoot -Recurse -Force -ErrorAction Stop
            Write-Output "Removed installed package files from $resolvedInstallRoot."
        }
        catch {
            $failures.Add("Unable to remove installed package files: $($_.Exception.Message)")
        }
    }
}
catch {
    $failures.Add("Unexpected uninstall exception: $($_.Exception.Message)")
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Output "Uninstall failure: $failure"
    }
    exit 1
}

Write-Output 'Enforcement mechanism removed. Existing hardened registry settings were retained by design.'
exit 0
