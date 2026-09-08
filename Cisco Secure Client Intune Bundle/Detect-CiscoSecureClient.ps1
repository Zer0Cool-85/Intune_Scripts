#Requires -Version 5.1

# Keep this value identical to PackageRevision in Config.json. Increment both
# whenever you publish a new Intune package, even if the Cisco version is unchanged.
$ExpectedPackageRevision = '2026.09.08.1'

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$StatePath = Join-Path $env:ProgramData 'CiscoSecureClientBundle\InstallState.json'
$TargetOrgInfoPath = Join-Path $env:ProgramData 'Cisco\Cisco Secure Client\Umbrella\OrgInfo.json'

function Get-RegisteredMsiProduct {
    param([Parameter(Mandatory = $true)][string]$ProductCode)

    $SubKeyPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{0}' -f $ProductCode
    $Views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )

    foreach ($View in $Views) {
        $BaseKey = $null
        $SubKey = $null
        try {
            $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                $View
            )
            $SubKey = $BaseKey.OpenSubKey($SubKeyPath)
            if ($null -ne $SubKey) {
                return [pscustomobject]@{
                    DisplayName    = [string]$SubKey.GetValue('DisplayName')
                    DisplayVersion = [string]$SubKey.GetValue('DisplayVersion')
                }
            }
        }
        finally {
            if ($null -ne $SubKey) { $SubKey.Dispose() }
            if ($null -ne $BaseKey) { $BaseKey.Dispose() }
        }
    }

    return $null
}

try {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        exit 1
    }

    $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if ([string]$State.PackageRevision -ne $ExpectedPackageRevision) {
        exit 1
    }

    $Modules = @($State.Modules)
    if ($Modules.Count -lt 1) {
        exit 1
    }

    foreach ($Module in $Modules) {
        if ([string]::IsNullOrWhiteSpace([string]$Module.ProductCode)) {
            exit 1
        }

        $RegisteredProduct = Get-RegisteredMsiProduct -ProductCode ([string]$Module.ProductCode)
        if ($null -eq $RegisteredProduct) {
            exit 1
        }
        if ($RegisteredProduct.DisplayVersion -ne [string]$Module.ProductVersion) {
            exit 1
        }
    }

    if ([bool]$State.RequireOrgInfo) {
        if (-not (Test-Path -LiteralPath $TargetOrgInfoPath -PathType Leaf)) {
            exit 1
        }

        $CurrentHash = (Get-FileHash -LiteralPath $TargetOrgInfoPath -Algorithm SHA256).Hash
        if ($CurrentHash -ne [string]$State.OrgInfoSha256) {
            exit 1
        }
    }

    Write-Output "Cisco Secure Client bundle $ExpectedPackageRevision detected; product version $($State.ProductVersion)."
    exit 0
}
catch {
    exit 1
}
