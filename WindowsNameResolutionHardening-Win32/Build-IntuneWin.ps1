#Requires -Version 5.1

<#
.SYNOPSIS
    Builds the .intunewin file with Microsoft's Win32 Content Prep Tool.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$IntuneWinAppUtilPath,

    [string]$OutputFolder = (Join-Path $PSScriptRoot 'Output')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceFolder = Join-Path $PSScriptRoot 'Source'
if (-not (Test-Path -LiteralPath $sourceFolder -PathType Container)) {
    throw "Source folder not found: $sourceFolder"
}

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

$tool = (Resolve-Path -LiteralPath $IntuneWinAppUtilPath).Path
$output = (Resolve-Path -LiteralPath $OutputFolder).Path

& $tool -c $sourceFolder -s 'Install.ps1' -o $output -q
if ($LASTEXITCODE -ne 0) {
    throw "IntuneWinAppUtil exited with code $LASTEXITCODE."
}

$package = Join-Path $output 'Install.intunewin'
if (-not (Test-Path -LiteralPath $package -PathType Leaf)) {
    throw "The tool completed, but the expected output wasn't found: $package"
}

Write-Output "Created $package"
