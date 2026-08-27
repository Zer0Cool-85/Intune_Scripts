#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$configPath = Join-Path $PSScriptRoot 'Config.xml'
$schemaPath = Join-Path $PSScriptRoot 'Config.xsd'
$modulePath = Join-Path $PSScriptRoot 'Modules\EnterpriseAutopilotBranding.psm1'
$detectionPath = Join-Path $PSScriptRoot 'Detect-AutopilotBranding.ps1'

Import-Module -Name $modulePath -Force
Test-EabConfigurationSchema -ConfigurationPath $configPath -SchemaPath $schemaPath
$config = Import-EabConfiguration -Path $configPath
Test-EabConfiguredAssets -Config $config -SourceRoot $PSScriptRoot

$requiredFiles = @(
    'Install-AutopilotBranding.ps1',
    'Uninstall-AutopilotBranding.ps1',
    'Invoke-PostEnroll.ps1',
    'Invoke-Debloat.ps1',
    'Config.xsd',
    'Detect-AutopilotBranding.ps1',
    'Modules\EnterpriseAutopilotBranding.psm1',
    'Custom\PostEnroll.Custom.ps1',
    'Custom\Steps\Install-AwsVpn.ps1',
    'Onboarding\Invoke-AppDeployToolkit.exe',
    'Onboarding\Invoke-AppDeployToolkit.ps1',
    'Onboarding\PSAppDeployToolkit\PSAppDeployToolkit.psd1',
    'Onboarding\PSAppDeployToolkit\COPYING.Lesser',
    'Assets\Company.theme',
    'README.md',
    'LICENSE',
    'NOTICE.md'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required project file '$relativePath' is missing."
    }
}

$detectionText = Get-Content -LiteralPath $detectionPath -Raw
if ($detectionText -notmatch '(?m)^\$requiredVersion\s*=\s*\[version\]''([^'']+)''\s*# EAB_BUILD_VERSION\r?$') {
    throw 'The marked detection-version line is missing from Detect-AutopilotBranding.ps1.'
}
if ([version]$Matches[1] -ne [version]$config.PackageVersion) {
    throw "Detect-AutopilotBranding.ps1 requires version '$($Matches[1])', but Config.xml declares '$($config.PackageVersion)'."
}

$delayMinutes = [int]$config.PostEnroll.DelayMinutes
$maximumAttempts = [int]$config.PostEnroll.MaximumAttempts
$waitSeconds = [int]$config.PostEnroll.WaitForInteractiveUserSeconds
$classicTimeout = [int]$config.Debloat.ClassicUninstallTimeoutSeconds
$classicOverallTimeout = [int]$config.Debloat.ClassicOverallTimeoutSeconds
if ($delayMinutes -lt 0 -or $delayMinutes -gt 120) {
    throw 'PostEnroll DelayMinutes must be between 0 and 120.'
}
if ($maximumAttempts -lt 1 -or $maximumAttempts -gt 20) {
    throw 'PostEnroll MaximumAttempts must be between 1 and 20.'
}
if ($waitSeconds -lt 0 -or $waitSeconds -gt 600) {
    throw 'PostEnroll WaitForInteractiveUserSeconds must be between 0 and 600.'
}
if ($classicTimeout -lt 30 -or $classicTimeout -gt 7200) {
    throw 'Debloat ClassicUninstallTimeoutSeconds must be between 30 and 7200.'
}
if ($classicOverallTimeout -lt 60 -or $classicOverallTimeout -gt 14400 -or $classicOverallTimeout -lt $classicTimeout) {
    throw 'Debloat ClassicOverallTimeoutSeconds must be between 60 and 14400 and at least the per-application timeout.'
}
if ([string]::IsNullOrWhiteSpace([string]$config.PostEnroll.TaskName) -or [string]$config.PostEnroll.TaskName -match '[\\/]') {
    throw 'PostEnroll TaskName must be a non-empty leaf name without slash characters.'
}
if (-not ([string]$config.PostEnroll.TaskPath).StartsWith('\')) {
    throw 'PostEnroll TaskPath must begin with a backslash.'
}

$toolkitManifestPath = Join-Path $PSScriptRoot 'Onboarding\PSAppDeployToolkit\PSAppDeployToolkit.psd1'
$toolkitManifest = Import-PowerShellDataFile -LiteralPath $toolkitManifestPath
if ([version]$toolkitManifest.ModuleVersion -ne [version]'4.1.8') {
    throw "The bundled PSAppDeployToolkit module must be version 4.1.8; found '$($toolkitManifest.ModuleVersion)'."
}

$enabledStepIds = @{}
foreach ($step in @($config.PostEnroll.Steps.Step | Where-Object { Get-EabBoolean -Value $_.Enabled -Default $true })) {
    if ($enabledStepIds.ContainsKey([string]$step.Id)) {
        throw "Enabled onboarding step Id '$($step.Id)' is duplicated."
    }
    $enabledStepIds[[string]$step.Id] = $true
}

$preservePatterns = @($config.Debloat.PreserveClassicApplications.Application | Where-Object {
    Get-EabBoolean -Value $_.Enabled -Default $true
} | ForEach-Object { [string]$_.DisplayNamePattern })

$dcuNames = @(
    'Dell Command | Update',
    'Dell Command | Update for Windows Universal',
    'Dell Command Update'
)
foreach ($name in $dcuNames) {
    $isPreserved = @($preservePatterns | Where-Object { $name -like $_ }).Count -gt 0
    if (-not $isPreserved) {
        throw "Dell Command Update safeguard does not preserve '$name'."
    }
}

$runtimeFiles = @(
    'Install-AutopilotBranding.ps1',
    'Invoke-PostEnroll.ps1',
    'Invoke-Debloat.ps1',
    'Modules\EnterpriseAutopilotBranding.psm1',
    'Onboarding\Invoke-AppDeployToolkit.ps1',
    'Custom\Steps\Install-AwsVpn.ps1'
)
$forbiddenRuntimePatterns = [ordered]@{
    'Invoke-WebRequest'             = '\bInvoke-WebRequest\b'
    'PSGallery module installation' = '\bInstall-(Module|Script)\b'
    'WinGet repair'                 = '\bRepair-WinGetPackageManager\b'
    'embedded local user creation'  = '\bNew-LocalUser\b'
    'plain-text secure-string use'  = '(?is)ConvertTo-SecureString.{0,200}-AsPlainText'
    'edition product-key change'    = '\b(changepk|slmgr)(\.exe)?\b'
    'legacy ServiceUI executable'   = '\bServiceUI\.exe\b'
}
foreach ($relativePath in $runtimeFiles) {
    $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Raw
    foreach ($description in $forbiddenRuntimePatterns.Keys) {
        if ($text -match $forbiddenRuntimePatterns[$description]) {
            throw "Runtime file '$relativePath' contains forbidden $description logic. Keep that workload in a separately detected deployment."
        }
    }
}

Write-Host "Project validation succeeded for package version $($config.PackageVersion)."
