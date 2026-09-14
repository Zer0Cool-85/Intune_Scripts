#requires -Version 5.1
[CmdletBinding()]
param([switch]$PurgeLogs)
$ErrorActionPreference = 'Stop'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $launch = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$PSCommandPath)
    if ($PurgeLogs) { $launch += '-PurgeLogs' }
    & "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" @launch
    exit $LASTEXITCODE
}
$lock = $null
try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as SYSTEM or an elevated administrator.' }
    # Fixed paths let Intune uninstall even if the runtime module is damaged.
    $installRoot = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'OfficeWiFiEnforcer'
    $dataRoot = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'OfficeWiFiEnforcer'
    foreach ($path in @($installRoot,$dataRoot)) {
        if (Test-Path -LiteralPath $path) {
            if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing reparse point: $path" }
            if (@(Get-ChildItem -LiteralPath $path -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
                throw "Refusing reparse point inside $path"
            }
        }
    }
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    $folder = $scheduler.GetFolder('\')
    $task = $null
    try { $task = $folder.GetTask('OfficeWiFi-Enforcer') } catch { }
    if ($null -ne $task) {
        $expectedScript = Join-Path $installRoot 'Enforce-OfficeWiFi.ps1'
        if ($task.Definition.Actions.Count -ne 1 -or
            $task.Definition.Actions.Item(1).Arguments.IndexOf(('"' + $expectedScript + '"'), [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw 'The task name belongs to a different action; refusing to uninstall an unrelated task.'
        }
        $task.Enabled = $false
        $task.Stop(0)
        $folder.DeleteTask('OfficeWiFi-Enforcer', 0)
    }
    if (Test-Path -LiteralPath $dataRoot) {
        for ($i = 0; $i -lt 10; $i++) {
            try { $lock = [IO.File]::Open((Join-Path $dataRoot 'run.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None); break }
            catch [IO.IOException] { Start-Sleep -Milliseconds 500 }
        }
        if ($null -eq $lock) { throw 'An enforcement process still holds the runtime lock.' }
    }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\OfficeWiFiEnforcer') { Remove-Item -LiteralPath 'HKLM:\SOFTWARE\OfficeWiFiEnforcer' -Recurse -Force }
    if (Test-Path -LiteralPath $installRoot) { Remove-Item -LiteralPath $installRoot -Recurse -Force }
    if ($null -ne $lock) { $lock.Dispose(); $lock = $null }
    if (Test-Path -LiteralPath $dataRoot) {
        if ($PurgeLogs) { Remove-Item -LiteralPath $dataRoot -Recurse -Force }
        else {
            foreach ($name in @('state.json','last-status.json','run.lock')) {
                $path = Join-Path $dataRoot $name
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
            }
        }
    }
    Write-Output 'Enforcement uninstalled. Automatic connection settings and deleted profiles are not restored.'
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }
finally { if ($null -ne $lock) { $lock.Dispose() } }
exit 0
