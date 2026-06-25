<#
.SYNOPSIS
    Helper example for creating an .intunewin package.

.DESCRIPTION
    Download Microsoft Win32 Content Prep Tool separately, then point IntuneWinAppUtilPath
    to IntuneWinAppUtil.exe. This script is intentionally an example and does not download tools.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IntuneWinAppUtilPath,

    [string]$SourceFolder = (Resolve-Path "$PSScriptRoot\..").Path,

    [string]$SetupFile = "src\Install-WinGetApp.ps1",

    [string]$OutputFolder = "$PSScriptRoot\..\out"
)

if (-not (Test-Path -Path $IntuneWinAppUtilPath)) {
    throw "IntuneWinAppUtil.exe was not found at: $IntuneWinAppUtilPath"
}

New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null

& $IntuneWinAppUtilPath -c $SourceFolder -s $SetupFile -o $OutputFolder -q
exit $LASTEXITCODE
