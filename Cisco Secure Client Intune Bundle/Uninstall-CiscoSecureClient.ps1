#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptRoot 'Config.json'
$StateRoot = Join-Path $env:ProgramData 'CiscoSecureClientBundle'
$StatePath = Join-Path $StateRoot 'InstallState.json'
$LogRoot = Join-Path $StateRoot 'Logs'
$script:FailureExitCode = $null

New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
$LogPath = Join-Path $LogRoot ('Uninstall-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $Line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    $Line | Out-File -FilePath $LogPath -Append -Encoding utf8
    Write-Host $Line
}

function Get-ConfigValue {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $Property = $Config.PSObject.Properties[$Name]
    if ($null -eq $Property) {
        throw "Config.json is missing required setting '$Name'."
    }
    return $Property.Value
}

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
                    ProductCode    = $ProductCode
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

function Get-InstalledCiscoSecureClientProducts {
    $Products = @()
    $UninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $Views = @(
        [Microsoft.Win32.RegistryView]::Registry64,
        [Microsoft.Win32.RegistryView]::Registry32
    )

    foreach ($View in $Views) {
        $BaseKey = $null
        $UninstallKey = $null
        try {
            $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                $View
            )
            $UninstallKey = $BaseKey.OpenSubKey($UninstallPath)
            if ($null -eq $UninstallKey) { continue }

            foreach ($SubKeyName in $UninstallKey.GetSubKeyNames()) {
                $ProductKey = $null
                try {
                    $ProductKey = $UninstallKey.OpenSubKey($SubKeyName)
                    if ($null -eq $ProductKey) { continue }
                    $DisplayName = [string]$ProductKey.GetValue('DisplayName')
                    if ($DisplayName -match '(?i)^Cisco (Secure Client|AnyConnect)') {
                        $Products += [pscustomobject]@{
                            ProductCode = $SubKeyName
                            DisplayName = $DisplayName
                        }
                    }
                }
                finally {
                    if ($null -ne $ProductKey) { $ProductKey.Dispose() }
                }
            }
        }
        finally {
            if ($null -ne $UninstallKey) { $UninstallKey.Dispose() }
            if ($null -ne $BaseKey) { $BaseKey.Dispose() }
        }
    }

    return @($Products | Sort-Object ProductCode, DisplayName -Unique)
}

function Invoke-MsiUninstall {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleName,
        [Parameter(Mandatory = $true)][string]$ProductCode
    )

    if ($ProductCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
        throw "Refusing to uninstall $ModuleName because '$ProductCode' is not a valid MSI product code."
    }

    if ($null -eq (Get-RegisteredMsiProduct -ProductCode $ProductCode)) {
        Write-Log "$ModuleName product $ProductCode is already absent; skipping."
        return 0
    }

    $SafeModuleName = $ModuleName -replace '[^A-Za-z0-9_-]', '-'
    $MsiLogPath = Join-Path $LogRoot ('MSI-Uninstall-{0}-{1}.log' -f $SafeModuleName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $MsiExecPath = Join-Path $env:SystemRoot 'System32\msiexec.exe'
    if (Test-Path (Join-Path $env:SystemRoot 'Sysnative\msiexec.exe')) {
        $MsiExecPath = Join-Path $env:SystemRoot 'Sysnative\msiexec.exe'
    }
    $Arguments = @(
        '/x',
        $ProductCode,
        '/qn',
        '/norestart',
        ('/L*v "{0}"' -f $MsiLogPath)
    )

    for ($Attempt = 1; $Attempt -le ($MsiBusyRetryCount + 1); $Attempt++) {
        Write-Log "Uninstalling $ModuleName (attempt $Attempt)."
        $Process = Start-Process -FilePath $MsiExecPath -ArgumentList $Arguments -Wait -PassThru
        $ExitCode = [int]$Process.ExitCode

        if ($ExitCode -eq 1618 -and $Attempt -le $MsiBusyRetryCount) {
            Write-Log "Windows Installer is busy. Retrying in $MsiBusyRetryDelaySeconds seconds." 'WARN'
            Start-Sleep -Seconds $MsiBusyRetryDelaySeconds
            continue
        }

        if ($ExitCode -in @(0, 1605, 1614, 1641, 3010)) {
            Write-Log "$ModuleName uninstall completed with MSI exit code $ExitCode."
            return $ExitCode
        }

        $Exception = [System.Exception]::new(
            "$ModuleName uninstall failed with MSI exit code $ExitCode. Review '$MsiLogPath'."
        )
        $script:FailureExitCode = $ExitCode
        $Exception.Data['ExitCode'] = $ExitCode
        throw $Exception
    }
}

try {
    Write-Log 'Starting Cisco Secure Client bundle uninstall.'

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This uninstaller must run elevated. Configure the Intune app to install in System context.'
    }

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Configuration file not found: '$ConfigPath'."
    }
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        throw "Bundle state file is missing: '$StatePath'. Refusing a name-based uninstall to avoid removing unrelated Cisco modules."
    }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $PackageRevision = [string](Get-ConfigValue -Config $Config -Name 'PackageRevision')
    $RemoveOrgInfo = Get-ConfigValue -Config $Config -Name 'RemoveOrgInfoOnUninstall'
    $BlockAdditionalModules = Get-ConfigValue -Config $Config -Name 'BlockUninstallIfAdditionalModulesDetected'
    $MsiBusyRetryCount = [int](Get-ConfigValue -Config $Config -Name 'MsiBusyRetryCount')
    $MsiBusyRetryDelaySeconds = [int](Get-ConfigValue -Config $Config -Name 'MsiBusyRetryDelaySeconds')
    $State = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json

    if ($RemoveOrgInfo -isnot [bool] -or $BlockAdditionalModules -isnot [bool]) {
        throw 'RemoveOrgInfoOnUninstall and BlockUninstallIfAdditionalModulesDetected must be JSON booleans.'
    }
    if ($MsiBusyRetryCount -lt 0 -or $MsiBusyRetryCount -gt 20) {
        throw 'MsiBusyRetryCount must be between 0 and 20.'
    }
    if ($MsiBusyRetryDelaySeconds -lt 1 -or $MsiBusyRetryDelaySeconds -gt 300) {
        throw 'MsiBusyRetryDelaySeconds must be between 1 and 300.'
    }
    if ([string]$State.PackageRevision -ne $PackageRevision) {
        throw "Installed bundle revision '$($State.PackageRevision)' does not match this uninstall package '$PackageRevision'. Refusing to remove a newer or different deployment."
    }

    $Modules = @($State.Modules)
    if ($Modules.Count -lt 1) {
        throw 'InstallState.json does not contain any module product codes.'
    }

    if ($BlockAdditionalModules) {
        $RiskPattern = '(?i)(Network Access Manager|Network Visibility|Posture|Compliance|Start Before Login|Zero Trust Access|ThousandEyes|Data Loss Prevention|Cloud Management|\bNAM\b|\bNVM\b|\bSBL\b|\bZTA\b)'
        $AdditionalModules = @(
            Get-InstalledCiscoSecureClientProducts |
                Where-Object { $_.DisplayName -match $RiskPattern }
        )
        if ($AdditionalModules.Count -gt 0) {
            $Names = ($AdditionalModules | Select-Object -ExpandProperty DisplayName -Unique) -join '; '
            throw "Additional Cisco Secure Client modules were detected: $Names. Core removal can remove other modules, so the uninstall was blocked before making changes."
        }
    }

    $RebootCode = 0
    $RemovalOrder = @('Umbrella', 'Core', 'DART')
    foreach ($ModuleName in $RemovalOrder) {
        $Module = @($Modules | Where-Object { [string]$_.Name -eq $ModuleName } | Select-Object -First 1)
        if ($Module.Count -eq 0) { continue }

        $Result = Invoke-MsiUninstall -ModuleName $ModuleName -ProductCode ([string]$Module[0].ProductCode)
        if ($Result -eq 1641) { $RebootCode = 1641 }
        elseif ($Result -eq 3010 -and $RebootCode -eq 0) { $RebootCode = 3010 }
    }

    foreach ($Module in $Modules) {
        if ($null -ne (Get-RegisteredMsiProduct -ProductCode ([string]$Module.ProductCode))) {
            throw "$($Module.Name) product $($Module.ProductCode) is still registered after uninstall."
        }
    }

    if ($RemoveOrgInfo) {
        $TargetOrgInfoPath = Join-Path $env:ProgramData 'Cisco\Cisco Secure Client\Umbrella\OrgInfo.json'
        if (Test-Path -LiteralPath $TargetOrgInfoPath -PathType Leaf) {
            Remove-Item -LiteralPath $TargetOrgInfoPath -Force
            Write-Log 'Removed OrgInfo.json as configured.'
        }
    }

    Remove-Item -LiteralPath $StatePath -Force
    Write-Log "Cisco Secure Client bundle revision $PackageRevision uninstalled successfully."
    exit $RebootCode
}
catch {
    $FailureCode = 1
    if ($null -ne $script:FailureExitCode) {
        $FailureCode = [int]$script:FailureExitCode
    }
    elseif ($_.Exception.Data.Contains('ExitCode')) {
        $FailureCode = [int]$_.Exception.Data['ExitCode']
    }
    Write-Log $_.Exception.Message 'ERROR'
    exit $FailureCode
}
