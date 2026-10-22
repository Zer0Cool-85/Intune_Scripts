#Requires -Version 5.1
<# Isolated helper checks. No app installs, HKLM writes, or scheduled tasks.
   Run in a fresh 64-bit powershell.exe process on Windows. #>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('EnterpriseHelperTest-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$env:SETUP_PACKAGE_ROOT = $root
$env:SETUP_RUN_DIRECTORY = $temp
$env:SETUP_STEP_ID = 'test'
. (Join-Path $root 'Core/Setup.Common.ps1')
. (Join-Path $root 'EnterpriseSteps/Enterprise.Common.ps1')
function Assert-Test { param([bool]$Pass, [string]$Message); if (-not $Pass) { throw "FAIL: $Message" }; Write-Host "PASS: $Message" }
$jobs = @()
try {
    # Two writers exercise the same append/retry helper used by UI and workers.
    $log = Join-Path $temp 'Concurrent.log'
    foreach ($writer in 1..2) {
        $jobs += Start-Job -ArgumentList $root,$log,$writer -ScriptBlock {
            param($root,$log,$writer)
            . (Join-Path $root 'Core/Setup.Common.ps1')
            1..50 | ForEach-Object { Add-SetupLogLine -Path $log -Line "$writer/$_" }
        }
    }
    $jobs | Wait-Job | Receive-Job -ErrorAction Stop
    $lines = @(Get-Content -LiteralPath $log)
    Assert-Test ($lines.Count -eq 100 -and @($lines | Sort-Object -Unique).Count -eq 100) 'Concurrent log writes preserve every complete line'

    $fixture = @{Present=$false; Status='Ok'; Partial=$false; Publisher='CN=Microsoft Corporation, O=Microsoft Corporation, C=US'; Calls=0; Provisions=0; UserInstalls=0}
    function Get-AppxPackage {
        param($User,$Name,$ErrorAction)
        if ($User -ne 'S-1-5-21-100-100-100-1001') { throw 'Wrong detection SID.' }
        $fixture.Calls++
        if ($fixture.Present) { [pscustomobject]@{Name=$Name;Status=$fixture.Status;IsPartiallyStaged=$fixture.Partial;Publisher=$fixture.Publisher} }
    }
    function Set-EnterpriseProgress { param($Message) }
    function Resolve-EnterpriseFile { param($RelativePath); return (Join-Path $temp $RelativePath) }
    function Add-AppxProvisionedPackage { param([switch]$Online,$PackagePath,$LicensePath,$DependencyPackagePath,[switch]$SkipLicense,$LogPath,$ErrorAction); $fixture.Provisions++ }
    function Invoke-EnterpriseUserAction { param($UserSid,$Request); $fixture.UserInstalls++; $fixture.Present=$true }
    $sid = 'S-1-5-21-100-100-100-1001'
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Absent current-user app is missing'
    Install-EnterpriseStoreApp -Name 'Microsoft.CompanyPortal' -UserSid $sid -PackageRelativePath 'Main.appxbundle' -LicenseRelativePath 'License.xml'
    Assert-Test ($fixture.Provisions -eq 1 -and $fixture.UserInstalls -eq 1) 'Provisioning alone does not count as current-user registration'
    Install-EnterpriseStoreApp -Name 'Microsoft.CompanyPortal' -UserSid $sid -PackageRelativePath 'Main.appxbundle' -LicenseRelativePath 'License.xml'
    Assert-Test ($fixture.Provisions -eq 1 -and $fixture.UserInstalls -eq 1) 'Healthy registered app skips reinstall'
    $fixture.Partial=$true
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Partially staged app is not ready'
    $fixture.Partial=$false; $fixture.Status='Modified'
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Unhealthy app is not ready'
    $fixture.Status='Ok'; $fixture.Publisher='CN=Other Publisher'
    Assert-Test (-not (Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid)) 'Wrong publisher is rejected'
    $fixture.Present=$false
    $rejected=$false
    try { Install-EnterpriseStoreApp -Name 'Microsoft.CompanyPortal' -UserSid $sid -PackageRelativePath 'Main.appxbundle' } catch { $rejected=$true }
    Assert-Test ($rejected -and $fixture.Provisions -eq 1) 'Missing license is rejected before provisioning'
    Write-Host 'Helper tests passed. Live Windows install/removal tests remain separate.'
}
finally {
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}
