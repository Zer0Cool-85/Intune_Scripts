#requires -Version 5.1

<#
.SYNOPSIS
Validates the project, creates a source archive, generates the version-specific detection script,
and optionally builds the Intune Win32 package.

.PARAMETER ContentPrepToolPath
Path to Microsoft's IntuneWinAppUtil.exe. When omitted, the source ZIP and detection script are
still generated.

.PARAMETER OutputDirectory
Destination for build artifacts. Defaults to the repository's dist directory.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ContentPrepToolPath,

    [Parameter()]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$configPath = Join-Path $PSScriptRoot 'Config.xml'
$modulePath = Join-Path $PSScriptRoot 'Modules\EnterpriseAutopilotBranding.psm1'
$validationScript = Join-Path $PSScriptRoot 'Validate-Project.ps1'
$detectionSource = Join-Path $PSScriptRoot 'Detect-AutopilotBranding.ps1'
$temporaryRoot = Join-Path $env:TEMP ("EAB-Build-{0}" -f [guid]::NewGuid().ToString('N'))
$contentRoot = Join-Path $temporaryRoot 'Content'

try {
    & $validationScript
    if (-not $?) {
        throw 'Project validation did not complete successfully.'
    }

    Import-Module -Name $modulePath -Force
    $config = Import-EabConfiguration -Path $configPath
    $version = [string]$config.PackageVersion

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
    New-Item -Path $contentRoot -ItemType Directory -Force | Out-Null

    $rootFiles = @(
        'Install-AutopilotBranding.ps1',
        'Uninstall-AutopilotBranding.ps1',
        'Invoke-PostEnroll.ps1',
        'Invoke-Debloat.ps1',
        'Config.xml',
        'Config.xsd',
        'LICENSE',
        'NOTICE.md'
    )
    foreach ($file in $rootFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $contentRoot $file) -Force
    }
    foreach ($directory in @('Modules', 'Assets', 'Custom', 'Onboarding')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $directory) -Destination $contentRoot -Recurse -Force
    }

    $detectionText = Get-Content -LiteralPath $detectionSource -Raw
    $versionLine = "`$requiredVersion = [version]'$version' # EAB_BUILD_VERSION"
    $versionPattern = '(?m)^\$requiredVersion\s*=.*# EAB_BUILD_VERSION\r?$'
    $detectionText = [regex]::Replace(
        $detectionText,
        $versionPattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param($match)
            if ($match.Value.EndsWith("`r")) { return "$versionLine`r" }
            return $versionLine
        }
    )
    $generatedDetectionPath = Join-Path $OutputDirectory "Detect-AutopilotBranding-$version.ps1"
    Set-Content -LiteralPath $generatedDetectionPath -Value $detectionText -Encoding UTF8 -Force

    $sourceZipPath = Join-Path $OutputDirectory "EnterpriseAutopilotBranding-Source-$version.zip"
    if (Test-Path -LiteralPath $sourceZipPath) {
        Remove-Item -LiteralPath $sourceZipPath -Force
    }
    Compress-Archive -Path (Join-Path $contentRoot '*') -DestinationPath $sourceZipPath -CompressionLevel Optimal

    Write-Host "Created source archive: $sourceZipPath"
    Write-Host "Created Intune detection script: $generatedDetectionPath"

    if (-not [string]::IsNullOrWhiteSpace($ContentPrepToolPath)) {
        $resolvedToolPath = (Resolve-Path -LiteralPath $ContentPrepToolPath).Path
        $process = Start-Process -FilePath $resolvedToolPath -ArgumentList @(
            '-c', "`"$contentRoot`"",
            '-s', 'Install-AutopilotBranding.ps1',
            '-o', "`"$OutputDirectory`"",
            '-q'
        ) -Wait -PassThru

        if ($process.ExitCode -ne 0) {
            throw "IntuneWinAppUtil.exe returned exit code $($process.ExitCode)."
        }

        $toolOutput = Join-Path $OutputDirectory 'Install-AutopilotBranding.intunewin'
        $versionedOutput = Join-Path $OutputDirectory "EnterpriseAutopilotBranding-$version.intunewin"
        if (-not (Test-Path -LiteralPath $toolOutput -PathType Leaf)) {
            throw "The content prep tool completed but '$toolOutput' was not created."
        }
        Move-Item -LiteralPath $toolOutput -Destination $versionedOutput -Force
        Write-Host "Created Intune package: $versionedOutput"
    }
    else {
        Write-Host 'ContentPrepToolPath was not supplied; Intune .intunewin generation was skipped.'
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
