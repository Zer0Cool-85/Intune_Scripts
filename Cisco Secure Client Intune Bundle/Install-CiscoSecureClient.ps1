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
        UpgradeCode   = [string](Get-MsiProperty -Path $File.FullName -PropertyName 'UpgradeCode')
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

function Compare-VersionString {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    if ($Left -notmatch '^\d+(?:\.\d+)*$' -or $Right -notmatch '^\d+(?:\.\d+)*$') {
        throw "Unable to compare installed version '$Left' with packaged version '$Right'."
    }

    $LeftParts = @($Left.Split('.') | ForEach-Object { [uint64]$_ })
    $RightParts = @($Right.Split('.') | ForEach-Object { [uint64]$_ })
    $PartCount = [Math]::Max($LeftParts.Count, $RightParts.Count)

    for ($Index = 0; $Index -lt $PartCount; $Index++) {
        $LeftPart = if ($Index -lt $LeftParts.Count) { $LeftParts[$Index] } else { [uint64]0 }
        $RightPart = if ($Index -lt $RightParts.Count) { $RightParts[$Index] } else { [uint64]0 }

        if ($LeftPart -gt $RightPart) { return 1 }
        if ($LeftPart -lt $RightPart) { return -1 }
    }

    return 0
}

function Get-InstalledRelatedMsiProduct {
    param([Parameter(Mandatory = $true)]$Installer)

    $WindowsInstaller = $null
    $RelatedProducts = $null
    $Candidates = @()

    try {
        $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $RelatedProducts = $WindowsInstaller.GetType().InvokeMember(
            'RelatedProducts',
            [System.Reflection.BindingFlags]::GetProperty,
            $null,
            $WindowsInstaller,
            @($Installer.UpgradeCode)
        )

        if ($null -ne $RelatedProducts) {
            $Count = [int]$RelatedProducts.GetType().InvokeMember(
                'Count',
                [System.Reflection.BindingFlags]::GetProperty,
                $null,
                $RelatedProducts,
                $null
            )

            for ($Index = 0; $Index -lt $Count; $Index++) {
                $ProductCode = [string]$RelatedProducts.GetType().InvokeMember(
                    'Item',
                    [System.Reflection.BindingFlags]::GetProperty,
                    $null,
                    $RelatedProducts,
                    @($Index)
                )

                $RegisteredProduct = Get-RegisteredMsiProduct -ProductCode $ProductCode
                if ($null -ne $RegisteredProduct) {
                    $Candidates += $RegisteredProduct
                }
            }
        }
    }
    finally {
        foreach ($ComObject in @($RelatedProducts, $WindowsInstaller)) {
            if ($null -ne $ComObject -and [System.Runtime.InteropServices.Marshal]::IsComObject($ComObject)) {
                $null = [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($ComObject)
            }
        }
    }

    # Include an exact ProductCode match as a defensive fallback in case the
    # registered product cannot be enumerated by UpgradeCode.
    $ExactProduct = Get-RegisteredMsiProduct -ProductCode $Installer.ProductCode
    $CandidateProductCodes = @($Candidates | ForEach-Object { $_.ProductCode })
    if ($null -ne $ExactProduct -and $CandidateProductCodes -notcontains $ExactProduct.ProductCode) {
        $Candidates += $ExactProduct
    }

    $HighestVersionProduct = $null
    foreach ($Candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($Candidate.DisplayVersion)) {
            throw "Installed $($Installer.ModuleName) product $($Candidate.ProductCode) has no DisplayVersion. Refusing to run an MSI because downgrade safety cannot be evaluated."
        }

        if ($null -eq $HighestVersionProduct -or
            (Compare-VersionString -Left $Candidate.DisplayVersion -Right $HighestVersionProduct.DisplayVersion) -gt 0) {
            $HighestVersionProduct = $Candidate
        }
    }

    return $HighestVersionProduct
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
        'REBOOT=ReallySuppress',
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

    $ModuleAssessments = @()
    foreach ($Installer in $Installers) {
        $ExistingProduct = Get-InstalledRelatedMsiProduct -Installer $Installer
        $Comparison = $null

        if ($null -eq $ExistingProduct) {
            Write-Log "$($Installer.ModuleName) is not installed; the packaged MSI will be installed."
        }
        else {
            $Comparison = Compare-VersionString `
                -Left $ExistingProduct.DisplayVersion `
                -Right $Installer.ProductVersion
            Write-Log "Detected $($Installer.ModuleName) $($ExistingProduct.DisplayVersion) as product $($ExistingProduct.ProductCode)."
        }

        $ModuleAssessments += [pscustomobject]@{
            Installer       = $Installer
            ExistingProduct = $ExistingProduct
            Comparison      = $Comparison
            InstallRequired = ($null -eq $ExistingProduct -or $Comparison -lt 0)
        }
    }

    $NewerAssessments = @($ModuleAssessments | Where-Object { $null -ne $_.Comparison -and $_.Comparison -gt 0 })
    if ($NewerAssessments.Count -gt 0) {
        $MissingAssessments = @($ModuleAssessments | Where-Object { $null -eq $_.ExistingProduct })
        $InstalledVersions = @(
            $ModuleAssessments |
                Where-Object { $null -ne $_.ExistingProduct } |
                ForEach-Object { $_.ExistingProduct.DisplayVersion } |
                Select-Object -Unique
        )

        if ($MissingAssessments.Count -gt 0 -or $InstalledVersions.Count -ne 1) {
            $AssessmentSummary = ($ModuleAssessments | ForEach-Object {
                if ($null -eq $_.ExistingProduct) {
                    '{0}=missing' -f $_.Installer.ModuleName
                }
                else {
                    '{0}={1}' -f $_.Installer.ModuleName, $_.ExistingProduct.DisplayVersion
                }
            }) -join ', '

            throw "At least one installed Cisco module is newer than the packaged version $ProductVersion, but the required installed modules are missing or do not share one version ($AssessmentSummary). Refusing to install older MSI content or create a mixed-version client. Package a release at least as new as the endpoint."
        }

        foreach ($Assessment in $ModuleAssessments) {
            $Assessment.InstallRequired = $false
        }
        Write-Log "All required modules are already installed at newer version $($InstalledVersions[0]). No Cisco MSI will be executed; the installation will be adopted into bundle state."
    }
    else {
        foreach ($Assessment in @($ModuleAssessments | Where-Object { $null -ne $_.ExistingProduct -and $_.Comparison -eq 0 })) {
            Write-Log "$($Assessment.Installer.ModuleName) already matches packaged version $ProductVersion. The MSI will be skipped."
        }
    }

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
    $CoreAssessment = $ModuleAssessments | Where-Object { $_.Installer.ModuleName -eq 'Core' }
    if ($CoreAssessment.InstallRequired) {
        $Result = Invoke-MsiInstall -Installer $CoreInstaller -Properties $CoreProperties
        if ($Result -eq 1641) { $RebootCode = 1641 }
        elseif ($Result -eq 3010 -and $RebootCode -eq 0) { $RebootCode = 3010 }
    }
    elseif ($CoreProperties.Count -gt 0) {
        Write-Log 'Core is already at an equal or newer version, so MSI-only Core properties were not reapplied.' 'WARN'
    }

    if ($InstallDart) {
        $DartProperties = @()
        if ($HideModules) { $DartProperties += 'ARPSYSTEMCOMPONENT=1' }
        $DartAssessment = $ModuleAssessments | Where-Object { $_.Installer.ModuleName -eq 'DART' }
        if ($DartAssessment.InstallRequired) {
            $Result = Invoke-MsiInstall -Installer $DartInstaller -Properties $DartProperties
            if ($Result -eq 1641) { $RebootCode = 1641 }
            elseif ($Result -eq 3010 -and $RebootCode -eq 0) { $RebootCode = 3010 }
        }
    }

    if ($InstallUmbrella) {
        $UmbrellaProperties = @()
        if ($EnableLockdown) { $UmbrellaProperties += 'LOCKDOWN=1' }
        if ($HideModules) { $UmbrellaProperties += 'ARPSYSTEMCOMPONENT=1' }
        $UmbrellaAssessment = $ModuleAssessments | Where-Object { $_.Installer.ModuleName -eq 'Umbrella' }
        if ($UmbrellaAssessment.InstallRequired) {
            $Result = Invoke-MsiInstall -Installer $UmbrellaInstaller -Properties $UmbrellaProperties
            if ($Result -eq 1641) { $RebootCode = 1641 }
            elseif ($Result -eq 3010 -and $RebootCode -eq 0) { $RebootCode = 3010 }
        }
    }

    $ModuleStates = @()
    foreach ($Installer in $Installers) {
        $RegisteredProduct = Get-InstalledRelatedMsiProduct -Installer $Installer
        if ($null -eq $RegisteredProduct) {
            throw "$($Installer.ModuleName) verification failed because no installed product with UpgradeCode $($Installer.UpgradeCode) was found."
        }
        if ((Compare-VersionString -Left $RegisteredProduct.DisplayVersion -Right $Installer.ProductVersion) -lt 0) {
            throw "$($Installer.ModuleName) verification failed. Expected version $($Installer.ProductVersion) or newer, found $($RegisteredProduct.DisplayVersion)."
        }

        $ModuleStates += [ordered]@{
            Name           = $Installer.ModuleName
            ProductCode    = $RegisteredProduct.ProductCode
            ProductName    = $RegisteredProduct.DisplayName
            ProductVersion = $RegisteredProduct.DisplayVersion
            PackagedVersion = $Installer.ProductVersion
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
        SchemaVersion  = 2
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
