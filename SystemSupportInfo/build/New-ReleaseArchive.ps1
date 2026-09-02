#requires -Version 5.1

<#
.SYNOPSIS
    Creates a clean repository ZIP for sharing or release upload.

.PARAMETER OutputPath
    Destination ZIP. Defaults to dist/SystemSupportInfo-Source.zip.

.PARAMETER IncludeBuiltExe
    Includes EXE files already present in dist.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$IncludeBuiltExe
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'dist\SystemSupportInfo-Source.zip'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location).Path $OutputPath
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Path $OutputPath -Parent
$null = New-Item -Path $outputDirectory -ItemType Directory -Force

$stagingParent = Join-Path `
    -Path ([System.IO.Path]::GetTempPath()) `
    -ChildPath ('SystemSupportInfo-Archive-{0}' -f [guid]::NewGuid().ToString('N'))
$stagingRoot = Join-Path $stagingParent 'SystemSupportInfo'

try {
    $null = New-Item -Path $stagingRoot -ItemType Directory -Force

    foreach ($item in (Get-ChildItem -LiteralPath $projectRoot -Force)) {
        if ($item.Name -eq '.git') {
            continue
        }

        if ($item.Name -eq 'dist') {
            $stagedDist = Join-Path $stagingRoot 'dist'
            $null = New-Item -Path $stagedDist -ItemType Directory -Force

            if ($IncludeBuiltExe) {
                Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.exe' -ErrorAction SilentlyContinue |
                    Copy-Item -Destination $stagedDist -Force
            }

            continue
        }

        Copy-Item -LiteralPath $item.FullName -Destination $stagingRoot -Recurse -Force
    }

    if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    Compress-Archive -LiteralPath $stagingRoot -DestinationPath $OutputPath -CompressionLevel Optimal
}
finally {
    if (Test-Path -LiteralPath $stagingParent -PathType Container) {
        Remove-Item -LiteralPath $stagingParent -Recurse -Force
    }
}

$archive = Get-Item -LiteralPath $OutputPath
Write-Host 'Archive created' -ForegroundColor Green
Write-Host ('  File: {0}' -f $archive.FullName)
Write-Host ('  Size: {0:N2} MB' -f ($archive.Length / 1MB))
