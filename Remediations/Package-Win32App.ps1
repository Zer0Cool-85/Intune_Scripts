#requires -version 5.1
<#
.SYNOPSIS
    Helper to package this folder into an .intunewin file.

.EXAMPLE
    .\Package-Win32App.ps1 -IntuneWinAppUtilPath 'C:\Tools\IntuneWinAppUtil.exe' -OutputFolder 'C:\IntuneOutput'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$IntuneWinAppUtilPath,

    [Parameter(Mandatory)]
    [string]$OutputFolder
)

if (-not (Test-Path -LiteralPath $IntuneWinAppUtilPath)) {
    throw "IntuneWinAppUtil.exe not found at $IntuneWinAppUtilPath"
}

$sourceFolder = $PSScriptRoot
$setupFile = 'Install-ScheduledRemediation.ps1'

if (-not (Test-Path -LiteralPath (Join-Path $sourceFolder $setupFile))) {
    throw "Setup file not found: $setupFile"
}

New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null

& $IntuneWinAppUtilPath -c $sourceFolder -s $setupFile -o $OutputFolder -q
exit $LASTEXITCODE
