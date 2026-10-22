#Requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Config/Enterprise-Example.json'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Core/Setup.Common.ps1')
$cfg = Read-SetupConfiguration -Path $ConfigPath -PackageRoot $root
$problems = [Collections.Generic.List[string]]::new()
foreach ($step in $cfg.Steps | Where-Object Enabled) {
    $file = Resolve-SetupContentPath $root $step.Script
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { $problems.Add("$($step.Id): PowerShell parse errors.") }
    $names = @()
    if ($null -ne $ast.ParamBlock) { $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
    foreach ($p in $step.Parameters.PSObject.Properties) {
        if ($p.Name -notin $names) { $problems.Add("$($step.Id): Unknown parameter $($p.Name).") }
        if ($p.Name -in @('MsiRelativePath','PackageRelativePath','LicenseRelativePath','OdtRelativePath','DependencyRelativePaths')) {
            foreach ($relative in @($p.Value)) {
                if ($relative) {
                    try {
                        $path = Resolve-SetupContentPath $root $relative
                        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $problems.Add("$($step.Id): Missing payload $relative") }
                    }
                    catch { $problems.Add("$($step.Id): $($_.Exception.Message)") }
                }
            }
        }
    }
    $parameters = $step.Parameters
    if ($step.Script -like '*/Step-InstallMsi.ps1') {
        if ($null -eq $parameters.PSObject.Properties['ProductCode'] -or $parameters.ProductCode -eq '{00000000-0000-0000-0000-000000000000}') { $problems.Add("$($step.Id): Set the real MSI ProductCode.") }
    }
    if ($step.Script -match '/Step-Install(CompanyPortal|Notepad)\.ps1$') {
        $mode = 'OfflinePackage'
        if ($null -ne $parameters.PSObject.Properties['Mode']) { $mode = $parameters.Mode }
        if ($mode -eq 'OfflinePackage' -and ($null -eq $parameters.PSObject.Properties['PackageRelativePath'] -or -not $parameters.PackageRelativePath)) { $problems.Add("$($step.Id): OfflinePackage requires PackageRelativePath.") }
    }
}
if ($problems.Count) { throw ("Enterprise preflight failed:`r`n" + ($problems -join "`r`n")) }
Write-Host 'PASS: configuration, parameter names and explicitly listed payload paths. This does not validate Windows install behavior, licensing, dependencies, hashes or policy conflicts.'
