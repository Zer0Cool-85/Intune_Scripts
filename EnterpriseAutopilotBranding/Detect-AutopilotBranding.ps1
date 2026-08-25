#requires -Version 5.1

[CmdletBinding()]
param()

# Build-IntuneWin.ps1 updates the value on the following marked line from Config.xml.
$requiredVersion = [version]'4.0.0' # EAB_BUILD_VERSION
$productRoot = Join-Path $env:ProgramData 'EnterpriseAutopilotBranding'
$statePath = Join-Path $productRoot 'State\InstallState.json'
$runtimeRoot = Join-Path $productRoot 'Runtime'
$installedConfigPath = Join-Path $productRoot 'Runtime\Config.xml'

try {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        exit 1
    }

    if (-not (Test-Path -LiteralPath $installedConfigPath -PathType Leaf)) {
        exit 1
    }

    $state = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$state.Result -notin @('Success', 'SuccessWithWarnings')) {
        exit 1
    }

    $installedVersion = [version]$state.PackageVersion
    if ($installedVersion -lt $requiredVersion) {
        exit 1
    }

    $currentConfigHash = (Get-FileHash -LiteralPath $installedConfigPath -Algorithm SHA256 -ErrorAction Stop).Hash
    if ([string]$state.ConfigHash -ne $currentConfigHash) {
        exit 1
    }

    $expectedManifest = @($state.RuntimeManifest)
    if ($expectedManifest.Count -eq 0 -or -not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) {
        exit 1
    }

    $resolvedRuntime = (Resolve-Path -LiteralPath $runtimeRoot -ErrorAction Stop).Path.TrimEnd('\')
    $runtimePrefix = "$resolvedRuntime\"
    $runtimeFiles = @(Get-ChildItem -LiteralPath $resolvedRuntime -File -Recurse -Force -ErrorAction Stop)
    if ($runtimeFiles.Count -ne $expectedManifest.Count) {
        exit 1
    }

    $expectedEntries = @{}
    foreach ($entry in $expectedManifest) {
        $relativePath = [string]$entry.RelativePath
        if ([string]::IsNullOrWhiteSpace($relativePath) -or $expectedEntries.ContainsKey($relativePath)) {
            exit 1
        }
        $expectedEntries[$relativePath] = $entry
    }

    foreach ($file in $runtimeFiles) {
        if (-not $file.FullName.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            exit 1
        }
        $relativePath = $file.FullName.Substring($runtimePrefix.Length)
        if (-not $expectedEntries.ContainsKey($relativePath)) {
            exit 1
        }
        $expectedEntry = $expectedEntries[$relativePath]
        if ([long]$expectedEntry.Length -ne [long]$file.Length) {
            exit 1
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$expectedEntry.Sha256)) {
            $actualHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            if ([string]$expectedEntry.Sha256 -ne $actualHash) {
                exit 1
            }
        }
    }

    Write-Output "Enterprise Autopilot Branding $installedVersion is installed successfully."
    exit 0
}
catch {
    exit 1
}
