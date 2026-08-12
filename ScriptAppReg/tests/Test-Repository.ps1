#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$configurationPath = Join-Path $repositoryRoot 'config\AppRegistration.json'
$buildScript = Join-Path $repositoryRoot 'tools\Build-Package.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("IntuneAppRegistrationTests-{0}" -f [guid]::NewGuid())

function Assert-PowerShellSyntax {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $tokens = $null
    $parseErrors = $null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if ($parseErrors.Count -gt 0) {
        $messages = $parseErrors |
            ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }

        throw "PowerShell syntax errors in '$Path':`n$($messages -join "`n")"
    }
}

try {
    if (-not (Test-Path -LiteralPath $configurationPath -PathType Leaf)) {
        throw "Configuration not found: $configurationPath"
    }

    if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
        throw "Build script not found: $buildScript"
    }

    [void](Get-Content -LiteralPath $configurationPath -Raw | ConvertFrom-Json)

    $repositoryScripts = Get-ChildItem `
        -LiteralPath $repositoryRoot `
        -Filter '*.ps1' `
        -File `
        -Recurse |
        Where-Object { $_.FullName -notlike "*$([System.IO.Path]::DirectorySeparatorChar)build$([System.IO.Path]::DirectorySeparatorChar)*" }

    foreach ($script in $repositoryScripts) {
        Assert-PowerShellSyntax -Path $script.FullName
    }

    & $buildScript `
        -ConfigurationPath $configurationPath `
        -OutputDirectory $temporaryRoot `
        -SkipIntuneWin | Out-Null

    $expectedFiles = @(
        'Source\Install.ps1'
        'Source\Uninstall.ps1'
        'Rules\Requirement.ps1'
        'Rules\Detection.ps1'
    )

    foreach ($relativePath in $expectedFiles) {
        $generatedPath = Join-Path $temporaryRoot $relativePath

        if (-not (Test-Path -LiteralPath $generatedPath -PathType Leaf)) {
            throw "Expected generated file was not created: $generatedPath"
        }

        $generatedContent = Get-Content -LiteralPath $generatedPath -Raw

        if ($generatedContent.Contains('@@CONFIG_BASE64@@')) {
            throw "Unresolved configuration token found in: $generatedPath"
        }

        Assert-PowerShellSyntax -Path $generatedPath
    }

    Write-Host 'All repository validation tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
