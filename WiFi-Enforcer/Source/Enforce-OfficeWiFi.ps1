#requires -Version 5.1
[CmdletBinding()]
param([switch]$AuditOnly, [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))
$ErrorActionPreference = 'Stop'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $launch = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-ConfigPath',$ConfigPath)
    if ($AuditOnly) { $launch += '-AuditOnly' }
    & "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" @launch
    exit $LASTEXITCODE
}
$client = $null
$lock = $null
$state = $null
$statePath = $null
$exitCode = 0
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as SYSTEM or in elevated Windows PowerShell.' }
    Import-Module (Join-Path $PSScriptRoot 'OfficeWiFi.psm1') -Force
    $paths = Get-OfficePaths
    $config = Read-OfficeConfig -Path $ConfigPath
    if ($AuditOnly) { $VerbosePreference = 'Continue' }
    else {
        if (-not (Test-Path -LiteralPath $paths.DataRoot)) { throw 'Install the package before running enforcement. Use -AuditOnly for a source-folder preview.' }
        $lockPath = Join-Path $paths.DataRoot 'run.lock'
        try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch [IO.IOException] { exit 0 }
        Initialize-OfficeLog -Path (Join-Path $paths.DataRoot 'enforcement.jsonl')
    }
    $service = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    if ($null -eq $service -or $service.Status -ne 'Running') {
        Write-OfficeLog 'WLAN AutoConfig is unavailable or stopped; waiting for the next run.' 'WARN'
        if (-not $AuditOnly) {
            Write-OfficeJson -Path (Join-Path $paths.DataRoot 'last-status.json') -Value @{Utc=[DateTime]::UtcNow.ToString('o'); Status='WaitingForWlanSvc'}
        }
        exit 0
    }
    Add-Type -Path (Join-Path $PSScriptRoot 'NativeWifi.cs')
    $client = New-Object OfficeWiFi.WlanClient
    $statePath = Join-Path $paths.DataRoot 'state.json'
    $state = Read-OfficeState -Path $statePath -ConfigHash $config.ConfigHash
    $result = Invoke-OfficePolicy -Client $client -Config $config -State $state -AuditOnly:$AuditOnly
    if ($AuditOnly) { $result | ConvertTo-Json -Depth 8 | Write-Output }
    else { Write-OfficeJson -Path (Join-Path $paths.DataRoot 'last-status.json') -Value $result }
    if ($result.Errors -gt 0) { $exitCode = 1 }
} catch {
    $exitCode = 1
    $failure = $_
    if (Get-Command Write-OfficeLog -ErrorAction SilentlyContinue) {
        try {
            Write-OfficeLog $failure.Exception.Message 'ERROR'
            if (-not $AuditOnly -and $null -ne $paths -and (Test-Path -LiteralPath $paths.DataRoot)) {
                Write-OfficeJson -Path (Join-Path $paths.DataRoot 'last-status.json') -Value @{
                    Utc=[DateTime]::UtcNow.ToString('o'); Status='Error'; Message=$failure.Exception.Message
                }
            }
        } catch { }
    }
    Write-Error $failure -ErrorAction Continue
} finally {
    if (-not $AuditOnly -and $null -ne $state -and $statePath) {
        try { Write-OfficeJson -Path $statePath -Value $state } catch { $exitCode = 1 }
    }
    if ($null -ne $client) { $client.Dispose() }
    if ($null -ne $lock) { $lock.Dispose() }
}
exit $exitCode
