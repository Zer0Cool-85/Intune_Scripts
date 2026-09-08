#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptRoot 'Config.json'
$SourceRoot = Join-Path $ScriptRoot 'Files'
$StateRoot = Join-Path $env:ProgramData 'CiscoSecureClientBundle'
$StatePath = Join-Path $StateRoot 'InstallState.json'
$LogRoot = Join-Path $StateRoot 'Logs'
$script:FailureExitCode = $null

New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
$LogPath = Join-Path $LogRoot ('Install-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

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

function Assert-BooleanSetting {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -isnot [bool]) {
        throw "Config setting '$Name' must be true or false without quotation marks."
    }
}

function Get-MsiProperty {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $Installer = $null
    $Database = $null
    $View = $null
    $Record = $null

    try {
        $Installer = New-Object -ComObject WindowsInstaller.Installer
        $Database = $Installer.GetType().InvokeMember(
            'OpenDatabase',
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $Installer,
            @($Path, 0)
        )

        $Query = 'SELECT `Value` FROM `Property` WHERE `Property` = ''{0}''' -f $PropertyName
        $View = $Database.GetType().InvokeMember(
            'OpenView',
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $Database,
            @($Query)
        )
        $null = $View.GetType().InvokeMember(
            'Execute',
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $View,
            $null
        )
        $Record = $View.GetType().InvokeMember(
            'Fetch',
            [System.Reflection.BindingFlags]::InvokeMethod,
            $null,
            $View,
            $null
        )

        if ($null -eq $Record) {
            throw "MSI property '$PropertyName' was not found in '$Path'."
        }

        return $Record.GetType().InvokeMember(
            'StringData',
            [System.Reflection.BindingFlags]::GetProperty,
            $null,
            $Record,
            @(1)
        )
    }
    finally {
        foreach ($ComObject in @($Record, $View, $Database, $Installer)) {
            if ($null -ne $ComObject -and [System.Runtime.InteropServices.Marshal]::IsComObject($ComObject)) {
                $null = [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($ComObject)
            }
        }
    }
}

function Get-ModuleInstaller {
    param(
        [Parameter(Mandatory = $true)][string]$ModuleName,
        [Parameter(Mandatory = $true)][string]$FilePattern,
        [Parameter(Mandatory = $true)][bool]$Required
    )

    $Candidates = @(
        Get-ChildItem -LiteralPath $SourceRoot -File -Filter '*.msi' |
            Where-Object { $_.Name -match $FilePattern }
    )

    if (-not $Required) {
        return $null
    }

    if ($Candidates.Count -ne 1) {
        throw "Expected exactly one $ModuleName predeploy MSI in '$SourceRoot'; found $($Candidates.Count)."
    }

    $File = $Candidates[0]
    $Signature = Get-AuthenticodeSignature -LiteralPath $File.FullName
    if ($RequireValidCiscoSignature) {
        if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
            throw "$ModuleName MSI does not have a valid Authenticode signature. Status: $($Signature.Status)."
        }
        if ($null -eq $Signature.SignerCertificate -or $Signature.SignerCertificate.Subject -notmatch 'Cisco Systems') {
            throw "$ModuleName MSI is validly signed, but the signer is not recognized as Cisco Systems."
        }
    }

    [pscustomobject]@{
        ModuleName    = $ModuleName
        Path          = $File.FullName
        FileName      = $File.Name
        ProductCode   = [string](Get-MsiProperty -Path $File.FullName -PropertyName 'ProductCode')
        ProductName   = [string](Get-MsiProperty -Path $File.FullName -PropertyName 'ProductName')
        ProductVersion = [string](Get-MsiProperty -Path $File.FullName -PropertyName 'ProductVersion')
    }
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

function Invoke-MsiInstall {
    param(
        [Parameter(Mandatory = $true)]$Installer,
        [string[]]$Properties = @()
    )

    $SafeModuleName = $Installer.ModuleName -replace '[^A-Za-z0-9_-]', '-'
    $MsiLogPath = Join-Path $LogRoot ('MSI-{0}-{1}.log' -f $SafeModuleName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $MsiExecPath = Join-Path $env:SystemRoot 'System32\msiexec.exe'
    if (Test-Path (Join-Path $env:SystemRoot 'Sysnative\msiexec.exe')) {
        $MsiExecPath = Join-Path $env:SystemRoot 'Sysnative\msiexec.exe'
    }

    $Arguments = @(
        '/i',
        ('"{0}"' -f $Installer.Path),
        '/qn',
        '/norestart',
        ('/L*v "{0}"' -f $MsiLogPath)
    ) + $Properties

    for ($Attempt = 1; $Attempt -le ($MsiBusyRetryCount + 1); $Attempt++) {
        Write-Log "Installing $($Installer.ModuleName) $($Installer.ProductVersion) (attempt $Attempt)."
        $Process = Start-Process -FilePath $MsiExecPath -ArgumentList $Arguments -WorkingDirectory $SourceRoot -Wait -PassThru
        $ExitCode = [int]$Process.ExitCode

        if ($ExitCode -eq 1618 -and $Attempt -le $MsiBusyRetryCount) {
            Write-Log "Windows Installer is busy. Retrying in $MsiBusyRetryDelaySeconds seconds." 'WARN'
            Start-Sleep -Seconds $MsiBusyRetryDelaySeconds
            continue
        }

        if ($ExitCode -in @(0, 1641, 3010)) {
            Write-Log "$($Installer.ModuleName) completed with MSI exit code $ExitCode."
            return $ExitCode
        }

        $Exception = [System.Exception]::new(
            "$($Installer.ModuleName) installation failed with MSI exit code $ExitCode. Review '$MsiLogPath'."
        )
        $script:FailureExitCode = $ExitCode
        $Exception.Data['ExitCode'] = $ExitCode
        throw $Exception
    }
}

try {
    Write-Log 'Starting Cisco Secure Client bundle installation.'

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This installer must run elevated. Configure the Intune app to install in System context.'
    }

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Configuration file not found: '$ConfigPath'."
    }
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        throw "Source directory not found: '$SourceRoot'."
    }

    $Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $PackageRevision = [string](Get-ConfigValue -Config $Config -Name 'PackageRevision')
    $InstallUmbrella = Get-ConfigValue -Config $Config -Name 'InstallUmbrella'
    $InstallDart = Get-ConfigValue -Config $Config -Name 'InstallDart'
    $RequireOrgInfo = Get-ConfigValue -Config $Config -Name 'RequireOrgInfo'
    $RequireValidCiscoSignature = Get-ConfigValue -Config $Config -Name 'RequireValidCiscoSignature'
    $DisableVpn = Get-ConfigValue -Config $Config -Name 'DisableVpn'
    $EnableLockdown = Get-ConfigValue -Config $Config -Name 'EnableLockdown'
    $HideModules = Get-ConfigValue -Config $Config -Name 'HideModulesFromProgramsAndFeatures'
    $DisableFeedback = Get-ConfigValue -Config $Config -Name 'DisableCustomerExperienceFeedback'
    $RestrictVpnUpgrade = Get-ConfigValue -Config $Config -Name 'RestrictUpgradeWhenVpnActive'
    $FailIfOrgInfoDiffers = Get-ConfigValue -Config $Config -Name 'FailIfExistingOrgInfoDiffers'
    $MsiBusyRetryCount = [int](Get-ConfigValue -Config $Config -Name 'MsiBusyRetryCount')
    $MsiBusyRetryDelaySeconds = [int](Get-ConfigValue -Config $Config -Name 'MsiBusyRetryDelaySeconds')

    foreach ($BooleanSetting in @(
        @{ Name = 'InstallUmbrella'; Value = $InstallUmbrella },
        @{ Name = 'InstallDart'; Value = $InstallDart },
        @{ Name = 'RequireOrgInfo'; Value = $RequireOrgInfo },
        @{ Name = 'RequireValidCiscoSignature'; Value = $RequireValidCiscoSignature },
        @{ Name = 'DisableVpn'; Value = $DisableVpn },
        @{ Name = 'EnableLockdown'; Value = $EnableLockdown },
        @{ Name = 'HideModulesFromProgramsAndFeatures'; Value = $HideModules },
        @{ Name = 'DisableCustomerExperienceFeedback'; Value = $DisableFeedback },
        @{ Name = 'RestrictUpgradeWhenVpnActive'; Value = $RestrictVpnUpgrade },
        @{ Name = 'FailIfExistingOrgInfoDiffers'; Value = $FailIfOrgInfoDiffers }
    )) {
        Assert-BooleanSetting -Name $BooleanSetting.Name -Value $BooleanSetting.Value
    }

    if ([string]::IsNullOrWhiteSpace($PackageRevision) -or $PackageRevision -notmatch '^[A-Za-z0-9._-]+$') {
        throw 'PackageRevision must contain only letters, numbers, periods, underscores, or hyphens.'
    }
    if ($MsiBusyRetryCount -lt 0 -or $MsiBusyRetryCount -gt 20) {
        throw 'MsiBusyRetryCount must be between 0 and 20.'
    }
    if ($MsiBusyRetryDelaySeconds -lt 1 -or $MsiBusyRetryDelaySeconds -gt 300) {
        throw 'MsiBusyRetryDelaySeconds must be between 1 and 300.'
    }
    if ($RequireOrgInfo -and -not $InstallUmbrella) {
        throw 'RequireOrgInfo cannot be true when InstallUmbrella is false.'
    }

    $CoreInstaller = Get-ModuleInstaller `
        -ModuleName 'Core' `
        -FilePattern '(?i)^cisco-secure-client-win-.+-core(?:-vpn)?-predeploy-k9\.msi$' `
        -Required $true
    $DartInstaller = Get-ModuleInstaller `
        -ModuleName 'DART' `
        -FilePattern '(?i)^cisco-secure-client-win-.+-dart-predeploy-k9\.msi$' `
        -Required ([bool]$InstallDart)
    $UmbrellaInstaller = Get-ModuleInstaller `
        -ModuleName 'Umbrella' `
        -FilePattern '(?i)^cisco-secure-client-win-.+-umbrella-predeploy-k9\.msi$' `
        -Required ([bool]$InstallUmbrella)

    $Installers = @($CoreInstaller)
    if ($InstallDart) { $Installers += $DartInstaller }
    if ($InstallUmbrella) { $Installers += $UmbrellaInstaller }

    $Versions = @($Installers | Select-Object -ExpandProperty ProductVersion -Unique)
    if ($Versions.Count -ne 1) {
        $VersionSummary = ($Installers | ForEach-Object { '{0}={1}' -f $_.ModuleName, $_.ProductVersion }) -join ', '
        throw "Cisco module MSI versions do not match: $VersionSummary. Use every MSI from the same predeploy release."
    }

    $ProductVersion = $Versions[0]
    Write-Log "Validated Cisco Secure Client predeploy MSI set, version $ProductVersion."

    $SourceOrgInfoPath = Join-Path $SourceRoot 'Profiles\umbrella\OrgInfo.json'
    $TargetOrgInfoDirectory = Join-Path $env:ProgramData 'Cisco\Cisco Secure Client\Umbrella'
    $TargetOrgInfoPath = Join-Path $TargetOrgInfoDirectory 'OrgInfo.json'
    $UmbrellaDataDirectory = Join-Path $TargetOrgInfoDirectory 'data'
    $OrgInfoHash = $null

    if ($InstallUmbrella) {
        if (Test-Path -LiteralPath $SourceOrgInfoPath -PathType Leaf) {
            try {
                $null = Get-Content -LiteralPath $SourceOrgInfoPath -Raw | ConvertFrom-Json
            }
            catch {
                throw "OrgInfo.json is not valid JSON: $($_.Exception.Message)"
            }

            $OrgInfoHash = (Get-FileHash -LiteralPath $SourceOrgInfoPath -Algorithm SHA256).Hash
            if (Test-Path -LiteralPath $TargetOrgInfoPath -PathType Leaf) {
                $ExistingHash = (Get-FileHash -LiteralPath $TargetOrgInfoPath -Algorithm SHA256).Hash
                if ($ExistingHash -ne $OrgInfoHash -and $FailIfOrgInfoDiffers) {
                    throw 'The installed OrgInfo.json differs from this package. Cisco requires clearing the Umbrella data directory or uninstalling/reinstalling the Umbrella module when changing organizations. No changes were made.'
                }
                if ($ExistingHash -ne $OrgInfoHash) {
                    Write-Log 'Existing OrgInfo.json differs and replacement was explicitly allowed. Existing Umbrella registration data may still reference the previous profile.' 'WARN'
                }
            }
            elseif ((Test-Path -LiteralPath $UmbrellaDataDirectory -PathType Container) -and $FailIfOrgInfoDiffers) {
                throw 'Umbrella registration data already exists, but the installed top-level OrgInfo.json is missing, so this package cannot verify that the organization profiles match. No changes were made.'
            }

            New-Item -Path $TargetOrgInfoDirectory -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $SourceOrgInfoPath -Destination $TargetOrgInfoPath -Force
            Write-Log 'Staged OrgInfo.json in the Cisco-supported ProgramData location.'
        }
        elseif ($RequireOrgInfo) {
            throw "Required Umbrella profile is missing: '$SourceOrgInfoPath'."
        }
        else {
            Write-Log 'No OrgInfo.json was packaged. Umbrella will be installed without an organization profile.' 'WARN'
        }
    }

    # Clear only this bundle's state marker after all preflight validation succeeds.
    # If an installation subsequently fails, Intune detection will correctly fail and retry.
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        Remove-Item -LiteralPath $StatePath -Force
    }

    $CoreProperties = @()
    if ($DisableVpn) { $CoreProperties += 'PRE_DEPLOY_DISABLE_VPN=1' }
    if ($EnableLockdown) { $CoreProperties += 'LOCKDOWN=1' }
    if ($HideModules) { $CoreProperties += 'ARPSYSTEMCOMPONENT=1' }
    if ($DisableFeedback) { $CoreProperties += 'DISABLE_CUSTOMER_EXPERIENCE_FEEDBACK=1' }
    if ($RestrictVpnUpgrade) { $CoreProperties += 'RESTRICT_SOFTWARE_UPDATE_IF_VPN_SESSION_ACTIVE=1' }

    $RebootCode = 0
    $Result = Invoke-MsiInstall -Installer $CoreInstaller -Properties $CoreProperties
    if ($Result -eq 1641) { $RebootCode = 1641 }
    elseif ($Result -eq 3010 -and $RebootCode -eq 0) { $RebootCode = 3010 }

    if ($InstallDart) {
        $DartProperties = @()
        if ($HideModules) { $DartProperties += 'ARPSYSTEMCOMPONENT=1' }
        $Result = Invoke-MsiInstall -Installer $DartInstaller -Properties $DartProperties
        if ($Result -eq 1641) { $RebootCode = 1641 }
        elseif ($Result -eq 3010 -and $RebootCode -eq 0) { $RebootCode = 3010 }
    }

    if ($InstallUmbrella) {
        $UmbrellaProperties = @()
        if ($EnableLockdown) { $UmbrellaProperties += 'LOCKDOWN=1' }
        if ($HideModules) { $UmbrellaProperties += 'ARPSYSTEMCOMPONENT=1' }
        $Result = Invoke-MsiInstall -Installer $UmbrellaInstaller -Properties $UmbrellaProperties
        if ($Result -eq 1641) { $RebootCode = 1641 }
        elseif ($Result -eq 3010 -and $RebootCode -eq 0) { $RebootCode = 3010 }
    }

    $ModuleStates = @()
    foreach ($Installer in $Installers) {
        $RegisteredProduct = Get-RegisteredMsiProduct -ProductCode $Installer.ProductCode
        if ($null -eq $RegisteredProduct) {
            throw "$($Installer.ModuleName) MSI completed, but product $($Installer.ProductCode) was not found in the uninstall registry."
        }
        if ($RegisteredProduct.DisplayVersion -ne $Installer.ProductVersion) {
            throw "$($Installer.ModuleName) verification failed. Expected version $($Installer.ProductVersion), found $($RegisteredProduct.DisplayVersion)."
        }

        $ModuleStates += [ordered]@{
            Name           = $Installer.ModuleName
            ProductCode    = $Installer.ProductCode
            ProductName    = $Installer.ProductName
            ProductVersion = $Installer.ProductVersion
        }
    }

    if ($RequireOrgInfo) {
        if (-not (Test-Path -LiteralPath $TargetOrgInfoPath -PathType Leaf)) {
            throw "Umbrella installed, but OrgInfo.json was not found at '$TargetOrgInfoPath'."
        }
        $DeployedHash = (Get-FileHash -LiteralPath $TargetOrgInfoPath -Algorithm SHA256).Hash
        if ($DeployedHash -ne $OrgInfoHash) {
            throw 'The deployed OrgInfo.json hash does not match the packaged profile.'
        }
    }

    $State = [ordered]@{
        SchemaVersion  = 1
        PackageRevision = $PackageRevision
        ProductVersion = $ProductVersion
        InstalledUtc   = (Get-Date).ToUniversalTime().ToString('o')
        DisableVpn     = [bool]$DisableVpn
        EnableLockdown = [bool]$EnableLockdown
        RequireOrgInfo = [bool]$RequireOrgInfo
        OrgInfoSha256  = $OrgInfoHash
        Modules        = @($ModuleStates)
    }

    $TemporaryStatePath = "$StatePath.tmp"
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $TemporaryStatePath -Encoding utf8
    Move-Item -LiteralPath $TemporaryStatePath -Destination $StatePath -Force

    Write-Log "Cisco Secure Client bundle revision $PackageRevision installed and verified successfully."
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
