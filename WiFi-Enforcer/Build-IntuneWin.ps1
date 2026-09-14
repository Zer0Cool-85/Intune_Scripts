#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$IntuneWinAppUtilPath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'Output'),
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
try {
    $source = Join-Path $PSScriptRoot 'Source'
    Import-Module (Join-Path $source 'OfficeWiFi.psm1') -Force
    $config = Read-OfficeConfig -Path (Join-Path $source 'config.json')
    $sourceFull = [IO.Path]::GetFullPath($source).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $outFull = [IO.Path]::GetFullPath($OutputDirectory)
    if ($outFull.Equals($sourceFull, [StringComparison]::OrdinalIgnoreCase) -or
        $outFull.StartsWith($sourceFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OutputDirectory must be outside Source.'
    }
    if (-not $PrepareOnly) {
        if (-not $IntuneWinAppUtilPath -or -not (Test-Path -LiteralPath $IntuneWinAppUtilPath -PathType Leaf)) {
            throw 'Supply -IntuneWinAppUtilPath pointing to Microsoft IntuneWinAppUtil.exe, or use -PrepareOnly.'
        }
        $tool = (Resolve-Path -LiteralPath $IntuneWinAppUtilPath).Path
        if ($tool.StartsWith($sourceFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Keep IntuneWinAppUtil.exe outside the Source directory.'
        }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $source -File | Where-Object { $_.Extension -in @('.ps1','.psm1') })) {
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw "Syntax errors in $($file.Name): $($parseErrors.Message -join '; ')" }
    }
    [void](New-Item -ItemType Directory -Path $outFull -Force)
    $payload = @('OfficeWiFi.psm1','NativeWifi.cs','Enforce-OfficeWiFi.ps1','Uninstall-OfficeWiFi.ps1','config.json')
    $hashes = [ordered]@{}
    foreach ($name in $payload) { $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash }
    $template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Tools/Detection.template.ps1') -Raw -Encoding UTF8
    $detection = $template.Replace('__EXPECTED_HASHES_JSON__', ($hashes | ConvertTo-Json))
    $detection = $detection.Replace('__CONFIG_HASH__', $config.ConfigHash).Replace('__POLICY_VERSION__', $config.PolicyVersion)
    $detection = $detection.Replace('__PACKAGE_VERSION__', '1.1.0').Replace('__INTERVAL__', [string]$config.EnforcementIntervalMinutes)
    $detectPath = Join-Path $outFull 'Detect-OfficeWiFi.ps1'
    [IO.File]::WriteAllText($detectPath, $detection, (New-Object Text.UTF8Encoding($true)))
    Write-OfficeJson -Path (Join-Path $outFull 'build-info.json') -Value @{
        Utc=[DateTime]::UtcNow.ToString('o'); PackageVersion='1.1.0'; PolicyVersion=$config.PolicyVersion
        ConfigHash=$config.ConfigHash; Hashes=$hashes
    }
    if (-not $PrepareOnly) {
        $intunewin = Join-Path $outFull 'Install.intunewin'
        if (Test-Path -LiteralPath $intunewin) { Remove-Item -LiteralPath $intunewin -Force }
        & $tool -c $sourceFull -s 'Install.cmd' -o $outFull -q
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $intunewin -PathType Leaf)) {
            throw 'Microsoft Content Prep Tool did not produce Install.intunewin.'
        }
        Write-Output "Upload app content: $intunewin"
    }
    Write-Output "Upload custom detection: $detectPath"
    Write-Output 'Install command: Install.cmd | Uninstall command: Uninstall.cmd | Install behavior: System'
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }
