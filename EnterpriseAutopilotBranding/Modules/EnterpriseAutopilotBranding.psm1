#requires -Version 5.1

Set-StrictMode -Version 3.0

$script:EabLogPath = $null
$script:EabJsonLogPath = $null
$script:EabLogComponent = 'General'

function Initialize-EabLogging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Component = 'General'
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $script:EabLogPath = Join-Path $LogDirectory 'EnterpriseAutopilotBranding.log'
    $script:EabJsonLogPath = Join-Path $LogDirectory 'EnterpriseAutopilotBranding.jsonl'
    $script:EabLogComponent = $Component
}

function Write-EabLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [Parameter()]
        [string]$Component = $script:EabLogComponent
    )

    $timestampUtc = [DateTime]::UtcNow.ToString('o')
    $textLine = '{0} [{1}] [{2}] {3}' -f $timestampUtc, $Level, $Component, $Message

    switch ($Level) {
        'ERROR' { Write-Host $textLine -ForegroundColor Red }
        'WARN'  { Write-Host $textLine -ForegroundColor Yellow }
        'DEBUG' { Write-Verbose $textLine }
        default { Write-Host $textLine }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:EabLogPath)) {
        try {
            Add-Content -LiteralPath $script:EabLogPath -Value $textLine -Encoding UTF8 -ErrorAction Stop

            $jsonLine = [ordered]@{
                TimestampUtc = $timestampUtc
                Level        = $Level
                Component    = $Component
                Message      = $Message
            } | ConvertTo-Json -Compress

            Add-Content -LiteralPath $script:EabJsonLogPath -Value $jsonLine -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Warning "Unable to append to the Enterprise Autopilot Branding log: $($_.Exception.Message)"
        }
    }
}

function Get-EabBoolean {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value,

        [Parameter()]
        [bool]$Default = $false
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $Default
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    switch -Regex (([string]$Value).Trim()) {
        '^(1|true|yes|on)$'  { return $true }
        '^(0|false|no|off)$' { return $false }
        default { throw "Invalid Boolean value '$Value'. Expected true or false." }
    }
}

function Resolve-EabPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$BasePath
    )

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if ([System.IO.Path]::IsPathRooted($expandedPath)) {
        return [System.IO.Path]::GetFullPath($expandedPath)
    }

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        throw "Relative path '$Path' was supplied without a base path."
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $expandedPath))
}

function Resolve-EabChildPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $resolvedPath = Resolve-EabPath -Path $Path -BasePath $BasePath
    $resolvedBase = [System.IO.Path]::GetFullPath($BasePath)
    $separators = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $basePrefix = $resolvedBase.TrimEnd($separators) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $resolvedPath.StartsWith($basePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path '$Path' resolves outside the allowed base directory '$resolvedBase'."
    }

    return $resolvedPath
}

function Test-EabConfigurationSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$ConfigurationPath,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$SchemaPath
    )

    $schemaSet = New-Object System.Xml.Schema.XmlSchemaSet
    $schemaSet.XmlResolver = $null
    $null = $schemaSet.Add($null, $SchemaPath)
    $validationErrors = New-Object System.Collections.Generic.List[string]
    $validationHandler = [System.Xml.Schema.ValidationEventHandler]{
        param($sender, $eventArguments)
        $validationErrors.Add($eventArguments.Message)
    }

    $readerSettings = New-Object System.Xml.XmlReaderSettings
    $readerSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $readerSettings.XmlResolver = $null
    $readerSettings.Schemas = $schemaSet
    $readerSettings.ValidationType = [System.Xml.ValidationType]::Schema
    $readerSettings.add_ValidationEventHandler($validationHandler)

    $reader = [System.Xml.XmlReader]::Create($ConfigurationPath, $readerSettings)
    try {
        while ($reader.Read()) {}
    }
    finally {
        $reader.Dispose()
    }

    if ($validationErrors.Count -gt 0) {
        throw "Configuration '$ConfigurationPath' failed schema validation: $($validationErrors -join ' | ')"
    }
}

function Import-EabConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    $resolvedConfigurationPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $configurationDirectory = Split-Path -Path $resolvedConfigurationPath -Parent
    $moduleProjectRoot = Split-Path -Path $PSScriptRoot -Parent
    $schemaCandidates = @(
        (Join-Path $configurationDirectory 'Config.xsd'),
        (Join-Path $moduleProjectRoot 'Config.xsd')
    )
    $schemaPath = @($schemaCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($schemaPath.Count -eq 0) {
        throw "Config.xsd was not found beside '$resolvedConfigurationPath' or at '$moduleProjectRoot'."
    }

    Test-EabConfigurationSchema -ConfigurationPath $resolvedConfigurationPath -SchemaPath $schemaPath[0]

    try {
        $readerSettings = New-Object System.Xml.XmlReaderSettings
        $readerSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $readerSettings.XmlResolver = $null
        $reader = [System.Xml.XmlReader]::Create($resolvedConfigurationPath, $readerSettings)
        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.XmlResolver = $null
            $xml.Load($reader)
        }
        finally {
            $reader.Dispose()
        }
    }
    catch {
        throw "Unable to read configuration '$Path': $($_.Exception.Message)"
    }

    $config = $xml.EnterpriseAutopilotBranding
    if ($null -eq $config) {
        throw "The configuration root element must be <EnterpriseAutopilotBranding>."
    }

    if ([string]$config.SchemaVersion -ne '1') {
        throw "Unsupported configuration SchemaVersion '$($config.SchemaVersion)'. This release supports schema 1."
    }

    foreach ($sectionName in @('Metadata', 'Execution', 'Branding', 'OsConfiguration', 'Debloat', 'PostEnroll')) {
        if ($null -eq $config.$sectionName) {
            throw "Required configuration section <$sectionName> is missing."
        }
    }

    try {
        $minimumBuild = [int]$config.Execution.MinimumSupportedBuild
    }
    catch {
        throw "Execution MinimumSupportedBuild '$($config.Execution.MinimumSupportedBuild)' is not an integer."
    }
    if ($minimumBuild -lt 22000) {
        throw 'Execution MinimumSupportedBuild must be Windows 11 build 22000 or later.'
    }

    $timeZoneMode = [string]$config.OsConfiguration.TimeZone.Mode
    if ($timeZoneMode -notin @('Unchanged', 'Explicit', 'Automatic')) {
        throw "TimeZone Mode must be Unchanged, Explicit, or Automatic; found '$timeZoneMode'."
    }
    if ($timeZoneMode -eq 'Explicit' -and [string]::IsNullOrWhiteSpace([string]$config.OsConfiguration.TimeZone.Id)) {
        throw 'TimeZone Mode is Explicit, but no Id was specified.'
    }

    try {
        $null = [version]$config.PackageVersion
    }
    catch {
        throw "PackageVersion '$($config.PackageVersion)' is not a valid version."
    }

    if ($null -ne $config.Debloat) {
        $mode = [string]$config.Debloat.Mode
        if ($mode -notin @('Audit', 'Enforce')) {
            throw "Debloat Mode must be Audit or Enforce; found '$mode'."
        }

        $patterns = @()
        $patterns += @($config.Debloat.AppxPackages.Package | ForEach-Object { [string]$_.NamePattern })
        $patterns += @($config.Debloat.PreserveAppxPackages.Package | ForEach-Object { [string]$_.NamePattern })
        $patterns += @($config.Debloat.ClassicApplications.Application | ForEach-Object { [string]$_.DisplayNamePattern })
        $patterns += @($config.Debloat.PreserveClassicApplications.Application | ForEach-Object { [string]$_.DisplayNamePattern })
        $patterns += @($config.Debloat.PublicDesktopShortcuts.Shortcut | ForEach-Object { [string]$_.NamePattern })
        $patterns += @($config.Debloat.ClassicApplications.Application | ForEach-Object {
            $publisherPattern = [string](Get-EabObjectPropertyValue -InputObject $_ -Name 'PublisherPattern')
            if (-not [string]::IsNullOrWhiteSpace($publisherPattern)) { $publisherPattern }
        })

        foreach ($pattern in $patterns) {
            if ([string]::IsNullOrWhiteSpace($pattern)) {
                throw 'Debloat patterns cannot be empty.'
            }

            $meaningfulCharacters = ($pattern -replace '[\*\?\[\]]', '').Length
            if ($meaningfulCharacters -lt 4) {
                throw "Debloat pattern '$pattern' is too broad. Use at least four non-wildcard characters."
            }
        }

        $classicTimeout = [int]$config.Debloat.ClassicUninstallTimeoutSeconds
        if ($classicTimeout -lt 30 -or $classicTimeout -gt 7200) {
            throw 'Debloat ClassicUninstallTimeoutSeconds must be between 30 and 7200.'
        }
        $classicOverallTimeout = [int]$config.Debloat.ClassicOverallTimeoutSeconds
        if ($classicOverallTimeout -lt 60 -or $classicOverallTimeout -gt 14400) {
            throw 'Debloat ClassicOverallTimeoutSeconds must be between 60 and 14400.'
        }
        if ($classicOverallTimeout -lt $classicTimeout) {
            throw 'Debloat ClassicOverallTimeoutSeconds cannot be lower than ClassicUninstallTimeoutSeconds.'
        }
    }

    $delayMinutes = [int]$config.PostEnroll.DelayMinutes
    $maximumAttempts = [int]$config.PostEnroll.MaximumAttempts
    $waitSeconds = [int]$config.PostEnroll.WaitForInteractiveUserSeconds
    if ($delayMinutes -lt 0 -or $delayMinutes -gt 120) {
        throw 'PostEnroll DelayMinutes must be between 0 and 120.'
    }
    if ($maximumAttempts -lt 1 -or $maximumAttempts -gt 20) {
        throw 'PostEnroll MaximumAttempts must be between 1 and 20.'
    }
    if ($waitSeconds -lt 0 -or $waitSeconds -gt 600) {
        throw 'PostEnroll WaitForInteractiveUserSeconds must be between 0 and 600.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.PostEnroll.TaskName) -or [string]$config.PostEnroll.TaskName -match '[\\/]') {
        throw 'PostEnroll TaskName must be a non-empty leaf name without slash characters.'
    }
    if (-not ([string]$config.PostEnroll.TaskPath).StartsWith('\')) {
        throw 'PostEnroll TaskPath must begin with a backslash.'
    }

    return $config
}

function Test-EabIsAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-EabIsSystem {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
}

function Get-EabOsContext {
    [CmdletBinding()]
    param()

    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

    [pscustomobject]@{
        ComputerName        = $env:COMPUTERNAME
        Caption             = $operatingSystem.Caption
        Version             = $operatingSystem.Version
        BuildNumber         = [int]$operatingSystem.BuildNumber
        OsArchitecture      = $operatingSystem.OSArchitecture
        ProcessArchitecture = $env:PROCESSOR_ARCHITECTURE
        Manufacturer        = $computerSystem.Manufacturer
        Model               = $computerSystem.Model
        IsSystem            = Test-EabIsSystem
        Is64BitProcess      = [Environment]::Is64BitProcess
    }
}

function Invoke-EabNativeProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [AllowEmptyString()]
        [string]$ArgumentString = '',

        [Parameter()]
        [int[]]$AcceptedExitCodes = @(0),

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds = 600,

        [Parameter()]
        [string]$WorkingDirectory
    )

    $startParameters = @{
        FilePath     = $FilePath
        ArgumentList = $ArgumentString
        PassThru     = $true
        WindowStyle  = 'Hidden'
        ErrorAction  = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startParameters.WorkingDirectory = $WorkingDirectory
    }

    Write-EabLog -Level DEBUG -Component 'Process' -Message "Starting '$FilePath' $ArgumentString"
    $process = Start-Process @startParameters

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        catch {}

        throw "Process '$FilePath' exceeded the $TimeoutSeconds second timeout."
    }

    $exitCode = $process.ExitCode
    if ($AcceptedExitCodes -notcontains $exitCode) {
        throw "Process '$FilePath' returned exit code $exitCode. Accepted exit codes: $($AcceptedExitCodes -join ', ')."
    }

    Write-EabLog -Level DEBUG -Component 'Process' -Message "Process '$FilePath' returned exit code $exitCode."
    return $exitCode
}

function Write-EabStateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$State
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -Path $parent -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $temporaryPath = "$Path.$PID.tmp"
    try {
        $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8 -Force -ErrorAction Stop
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-EabStateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-EabLog -Level WARN -Component 'State' -Message "Unable to read state file '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Get-EabFileHashValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Get-EabRuntimeManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RuntimeRoot
    )

    if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
        throw "Runtime directory '$RuntimeRoot' does not exist."
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $RuntimeRoot -ErrorAction Stop).Path.TrimEnd('\')
    $rootPrefix = "$resolvedRoot\"
    $manifest = New-Object System.Collections.Generic.List[object]

    foreach ($file in @(Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse -Force -ErrorAction Stop | Sort-Object FullName)) {
        if (-not $file.FullName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Runtime file '$($file.FullName)' resolves outside '$resolvedRoot'."
        }

        $relativePath = $file.FullName.Substring($rootPrefix.Length)
        $isPayload = $relativePath.StartsWith('Custom\Payloads\', [StringComparison]::OrdinalIgnoreCase)
        $manifest.Add([pscustomobject]@{
            RelativePath = $relativePath
            Length       = $file.Length
            Sha256       = if ($isPayload) { $null } else { Get-EabFileHashValue -Path $file.FullName }
        })
    }

    if ($manifest.Count -eq 0) {
        throw "Runtime directory '$resolvedRoot' contains no files."
    }

    return @($manifest)
}

function Test-EabRuntimeManifest {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$RuntimeRoot,

        [Parameter()]
        [AllowNull()]
        [object[]]$Manifest
    )

    if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container) -or $null -eq $Manifest -or $Manifest.Count -eq 0) {
        return $false
    }

    try {
        $currentManifest = @(Get-EabRuntimeManifest -RuntimeRoot $RuntimeRoot)
        if ($currentManifest.Count -ne $Manifest.Count) {
            return $false
        }

        $expected = @{}
        foreach ($entry in $Manifest) {
            $relativePath = [string]$entry.RelativePath
            if ([string]::IsNullOrWhiteSpace($relativePath) -or $expected.ContainsKey($relativePath)) {
                return $false
            }
            $expected[$relativePath] = $entry
        }

        foreach ($entry in $currentManifest) {
            if (-not $expected.ContainsKey($entry.RelativePath)) {
                return $false
            }
            $expectedEntry = $expected[$entry.RelativePath]
            if ([long]$expectedEntry.Length -ne [long]$entry.Length -or [string]$expectedEntry.Sha256 -ne [string]$entry.Sha256) {
                return $false
            }
        }

        return $true
    }
    catch {
        return $false
    }
}

function Copy-EabFileIfChanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Required source file '$Source' does not exist."
    }

    $destinationDirectory = Split-Path -Path $Destination -Parent
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -Path $destinationDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $copyRequired = $true
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $sourceHash = Get-EabFileHashValue -Path $Source
        $destinationHash = Get-EabFileHashValue -Path $Destination
        $copyRequired = $sourceHash -ne $destinationHash
    }

    if ($copyRequired) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        Write-EabLog -Component 'Files' -Message "Copied '$Source' to '$Destination'."
    }
    else {
        Write-EabLog -Level DEBUG -Component 'Files' -Message "Destination '$Destination' already matches the source."
    }
}

function Set-EabRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('String', 'ExpandString', 'DWord', 'QWord', 'MultiString', 'Binary')]
        [string]$Type,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [object]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    $convertedValue = $Value
    switch ($Type) {
        'DWord' { $convertedValue = [int]$Value }
        'QWord' { $convertedValue = [long]$Value }
        'MultiString' { $convertedValue = @([string]$Value -split '\|') }
        'Binary' {
            $hex = ([string]$Value -replace '[^0-9A-Fa-f]', '')
            if (($hex.Length % 2) -ne 0) {
                throw "Binary registry data for '$Path\$Name' must contain an even number of hexadecimal characters."
            }
            $convertedValue = [byte[]]@(for ($index = 0; $index -lt $hex.Length; $index += 2) {
                [Convert]::ToByte($hex.Substring($index, 2), 16)
            })
        }
    }

    New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $convertedValue -Force -ErrorAction Stop | Out-Null
    Write-EabLog -Level DEBUG -Component 'Registry' -Message "Set '$Path\$Name' ($Type)."
}

function Set-EabConfiguredRegistryValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Container,

        [Parameter(Mandatory)]
        [string]$RootPath
    )

    foreach ($entry in @($Container.Value)) {
        if (-not (Get-EabBoolean -Value $entry.Enabled -Default $true)) {
            continue
        }

        $relativeKey = ([string]$entry.Key).TrimStart('\')
        $path = "$($RootPath.TrimEnd('\'))\$relativeKey"
        Set-EabRegistryValue -Path $path -Name ([string]$entry.Name) -Type ([string]$entry.Type) -Value ([string]$entry.Data)
    }
}

function Mount-EabDefaultUserHive {
    [CmdletBinding()]
    param()

    $hivePath = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $hivePath -PathType Leaf)) {
        throw "Default user registry hive '$hivePath' was not found."
    }

    $keyName = "EAB_DefaultUser_$PID"
    $registryPath = "Registry::HKEY_LOCAL_MACHINE\$keyName"
    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'

    Invoke-EabNativeProcess -FilePath $regExe -ArgumentString "load `"HKLM\$keyName`" `"$hivePath`"" -TimeoutSeconds 30 | Out-Null

    if (-not (Test-Path -LiteralPath $registryPath)) {
        throw "Default user hive was reported as loaded but '$registryPath' is unavailable."
    }

    Write-EabLog -Component 'DefaultUser' -Message "Mounted the default user hive as HKLM\$keyName."
    return [pscustomobject]@{
        KeyName      = $keyName
        RegistryPath = $registryPath
        HivePath     = $hivePath
    }
}

function Dismount-EabDefaultUserHive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Mount
    )

    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    $lastError = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-EabNativeProcess -FilePath $regExe -ArgumentString "unload `"HKLM\$($Mount.KeyName)`"" -TimeoutSeconds 30 | Out-Null
            Write-EabLog -Component 'DefaultUser' -Message "Unmounted HKLM\$($Mount.KeyName)."
            return
        }
        catch {
            $lastError = $_
            if ($attempt -lt 3) {
                Start-Sleep -Seconds 1
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
    }

    throw "Unable to unload HKLM\$($Mount.KeyName): $($lastError.Exception.Message)"
}

function Test-EabConfiguredAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    if (-not (Get-EabBoolean -Value $Config.Branding.Enabled -Default $true)) {
        return
    }

    foreach ($assetName in @('Wallpaper', 'LockScreen', 'Theme', 'OemLogo', 'TaskbarLayout')) {
        $asset = $Config.Branding.$assetName
        if ($null -eq $asset -or -not (Get-EabBoolean -Value $asset.Enabled -Default $false)) {
            continue
        }

        $source = Resolve-EabChildPath -Path ([string]$asset.Source) -BasePath $SourceRoot
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "$assetName is enabled, but its source file '$source' does not exist."
        }
    }

    $legacyStart = $Config.Branding.LegacyStartLayout
    if ($null -ne $legacyStart -and (Get-EabBoolean -Value $legacyStart.Enabled -Default $false)) {
        foreach ($property in @('Start2Source', 'SettingsSource')) {
            $source = Resolve-EabChildPath -Path ([string]$legacyStart.$property) -BasePath $SourceRoot
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "LegacyStartLayout is enabled, but '$source' does not exist."
            }
        }
    }

    $defaultApps = $Config.OsConfiguration.DefaultAppAssociations
    if ($null -ne $defaultApps -and (Get-EabBoolean -Value $defaultApps.Enabled -Default $false)) {
        $source = Resolve-EabChildPath -Path ([string]$defaultApps.Source) -BasePath $SourceRoot
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "DefaultAppAssociations is enabled, but '$source' does not exist."
        }
    }
}

function Install-EabBrandingAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    if (-not (Get-EabBoolean -Value $Config.Branding.Enabled -Default $true)) {
        Write-EabLog -Component 'Branding' -Message 'Branding assets are disabled in Config.xml.'
        return
    }

    foreach ($assetName in @('Wallpaper', 'LockScreen', 'Theme', 'OemLogo')) {
        $asset = $Config.Branding.$assetName
        if ($null -eq $asset -or -not (Get-EabBoolean -Value $asset.Enabled -Default $false)) {
            continue
        }

        $source = Resolve-EabChildPath -Path ([string]$asset.Source) -BasePath $SourceRoot
        $destination = Resolve-EabPath -Path ([string]$asset.Destination)
        Copy-EabFileIfChanged -Source $source -Destination $destination
    }
}

function Set-EabDefaultUserConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$HiveRoot
    )

    if (-not (Get-EabBoolean -Value $Config.Branding.Enabled -Default $true)) {
        return
    }

    $theme = $Config.Branding.Theme
    if ($null -ne $theme -and (Get-EabBoolean -Value $theme.Enabled -Default $false)) {
        $themeDestination = Resolve-EabPath -Path ([string]$theme.Destination)
        $themeRegistryPath = "$HiveRoot\Software\Microsoft\Windows\CurrentVersion\Themes"
        Set-EabRegistryValue -Path $themeRegistryPath -Name 'InstallTheme' -Type ExpandString -Value $themeDestination
        Set-EabRegistryValue -Path $themeRegistryPath -Name 'CurrentTheme' -Type ExpandString -Value $themeDestination
    }

    if ($null -ne $Config.Branding.DefaultUserRegistry) {
        Set-EabConfiguredRegistryValues -Container $Config.Branding.DefaultUserRegistry -RootPath $HiveRoot
    }
}

function Set-EabMachineConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    if (-not (Get-EabBoolean -Value $Config.Branding.Enabled -Default $true)) {
        return
    }

    if ($null -ne $Config.Branding.MachineRegistry) {
        Set-EabConfiguredRegistryValues -Container $Config.Branding.MachineRegistry -RootPath 'Registry::HKEY_LOCAL_MACHINE'
    }

    $lockScreen = $Config.Branding.LockScreen
    if ($null -ne $lockScreen -and (Get-EabBoolean -Value $lockScreen.Enabled -Default $false)) {
        $lockScreenPath = Resolve-EabPath -Path ([string]$lockScreen.Destination)
        $personalizationPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
        Set-EabRegistryValue -Path $personalizationPath -Name 'LockScreenImagePath' -Type String -Value $lockScreenPath
        Set-EabRegistryValue -Path $personalizationPath -Name 'LockScreenImageUrl' -Type String -Value $lockScreenPath
        Set-EabRegistryValue -Path $personalizationPath -Name 'LockScreenImageStatus' -Type DWord -Value 1
    }
}

function Set-EabOemInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    if (-not (Get-EabBoolean -Value $Config.Branding.Enabled -Default $true)) {
        return
    }

    $oem = $Config.Branding.OemInformation
    if ($null -eq $oem -or -not (Get-EabBoolean -Value $oem.Enabled -Default $false)) {
        return
    }

    $registryPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'
    $values = @{
        Manufacturer = [string]$oem.Manufacturer
        Model        = [string]$oem.Model
        SupportPhone = [string]$oem.SupportPhone
        SupportHours = [string]$oem.SupportHours
        SupportURL   = [string]$oem.SupportURL
    }

    foreach ($name in $values.Keys) {
        if (-not [string]::IsNullOrWhiteSpace($values[$name])) {
            Set-EabRegistryValue -Path $registryPath -Name $name -Type String -Value $values[$name]
        }
        elseif (Test-Path -LiteralPath $registryPath) {
            Remove-ItemProperty -LiteralPath $registryPath -Name $name -Force -ErrorAction SilentlyContinue
        }
    }

    $logo = $Config.Branding.OemLogo
    if ($null -ne $logo -and (Get-EabBoolean -Value $logo.Enabled -Default $false)) {
        $logoPath = Resolve-EabPath -Path ([string]$logo.Destination)
        Set-EabRegistryValue -Path $registryPath -Name 'Logo' -Type String -Value $logoPath
    }
}

function Install-EabTaskbarLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    if (-not (Get-EabBoolean -Value $Config.Branding.Enabled -Default $true)) {
        return
    }

    $taskbar = $Config.Branding.TaskbarLayout
    if ($null -eq $taskbar -or -not (Get-EabBoolean -Value $taskbar.Enabled -Default $false)) {
        return
    }

    $source = Resolve-EabChildPath -Path ([string]$taskbar.Source) -BasePath $SourceRoot
    $destination = Resolve-EabPath -Path ([string]$taskbar.Destination)
    Copy-EabFileIfChanged -Source $source -Destination $destination

    $explorerPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'
    Set-EabRegistryValue -Path $explorerPath -Name 'LayoutXMLPath' -Type ExpandString -Value $destination
}

function Install-EabLegacyStartLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [int]$OsBuild
    )

    if (-not (Get-EabBoolean -Value $Config.Branding.Enabled -Default $true)) {
        return
    }

    $layout = $Config.Branding.LegacyStartLayout
    if ($null -eq $layout -or -not (Get-EabBoolean -Value $layout.Enabled -Default $false)) {
        return
    }

    $minimumBuild = [int]$layout.MinimumBuild
    $maximumBuild = [int]$layout.MaximumBuild
    if ($OsBuild -lt $minimumBuild -or $OsBuild -gt $maximumBuild) {
        throw "Legacy Start layout is enabled for builds $minimumBuild-$maximumBuild, but this device is build $OsBuild. Disable the feature or provide build-tested assets."
    }

    $start2Source = Resolve-EabChildPath -Path ([string]$layout.Start2Source) -BasePath $SourceRoot
    $settingsSource = Resolve-EabChildPath -Path ([string]$layout.SettingsSource) -BasePath $SourceRoot
    $start2Destination = Resolve-EabPath -Path ([string]$layout.Start2Destination)
    $settingsDestination = Resolve-EabPath -Path ([string]$layout.SettingsDestination)

    Copy-EabFileIfChanged -Source $start2Source -Destination $start2Destination
    Copy-EabFileIfChanged -Source $settingsSource -Destination $settingsDestination
}

function Set-EabTimeZoneConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $timeZone = $Config.OsConfiguration.TimeZone
    if ($null -eq $timeZone) {
        return
    }

    $mode = [string]$timeZone.Mode
    switch ($mode) {
        'Unchanged' {
            Write-EabLog -Component 'TimeZone' -Message 'Time-zone configuration is set to Unchanged.'
        }
        'Explicit' {
            $id = [string]$timeZone.Id
            if ([string]::IsNullOrWhiteSpace($id)) {
                throw 'TimeZone Mode is Explicit, but no Id was specified.'
            }

            Set-TimeZone -Id $id -ErrorAction Stop
            $actual = (Get-TimeZone -ErrorAction Stop).Id
            if ($actual -ne $id) {
                throw "Requested time zone '$id', but Windows reports '$actual'."
            }
            Write-EabLog -Component 'TimeZone' -Message "Configured time zone '$id'."
        }
        'Automatic' {
            Set-EabRegistryValue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name 'Value' -Type String -Value 'Allow'
            Set-EabRegistryValue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' -Name 'SensorPermissionState' -Type DWord -Value 1
            Set-Service -Name 'tzautoupdate' -StartupType Automatic -ErrorAction Stop
            Start-Service -Name 'tzautoupdate' -ErrorAction SilentlyContinue
            Start-Service -Name 'lfsvc' -ErrorAction SilentlyContinue
            Write-EabLog -Component 'TimeZone' -Message 'Enabled Windows automatic time-zone support.'
        }
        default {
            throw "Unknown TimeZone Mode '$mode'. Use Unchanged, Explicit, or Automatic."
        }
    }
}

function Import-EabDefaultAppAssociations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $associations = $Config.OsConfiguration.DefaultAppAssociations
    if ($null -eq $associations -or -not (Get-EabBoolean -Value $associations.Enabled -Default $false)) {
        return
    }

    $source = Resolve-EabChildPath -Path ([string]$associations.Source) -BasePath $SourceRoot
    $dism = Join-Path $env:SystemRoot 'System32\Dism.exe'
    Invoke-EabNativeProcess -FilePath $dism -ArgumentString "/Online /Import-DefaultAppAssociations:`"$source`"" -AcceptedExitCodes @(0, 3010) -TimeoutSeconds 600 | Out-Null
    Write-EabLog -Component 'DefaultApps' -Message "Imported default app associations from '$source'."
}

function Set-EabWindowsFeatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $settings = $Config.OsConfiguration.WindowsFeatures
    if ($null -eq $settings -or -not (Get-EabBoolean -Value $settings.Enabled -Default $false)) {
        return
    }

    $windowsUpdatePath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $originalUseWuServer = $null
    $changedUseWuServer = $false

    try {
        if (Get-EabBoolean -Value $settings.TemporarilyBypassWsus -Default $false) {
            $windowsUpdateProperties = Get-ItemProperty -LiteralPath $windowsUpdatePath -Name 'UseWuServer' -ErrorAction SilentlyContinue
            if ($null -ne $windowsUpdateProperties) {
                $originalUseWuServer = Get-EabObjectPropertyValue -InputObject $windowsUpdateProperties -Name 'UseWuServer'
            }
            if ($originalUseWuServer -eq 1) {
                Set-EabRegistryValue -Path $windowsUpdatePath -Name 'UseWuServer' -Type DWord -Value 0
                $changedUseWuServer = $true
                Restart-Service -Name wuauserv -Force -ErrorAction Stop
                Write-EabLog -Component 'WindowsFeatures' -Message 'Temporarily bypassed WSUS for capability servicing.'
            }
        }

        $enabledFeatures = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object State -eq 'Enabled')
        foreach ($feature in @($settings.DisableOptionalFeatures.Feature)) {
            if (-not (Get-EabBoolean -Value $feature.Enabled -Default $true)) {
                continue
            }

            $name = [string]$feature.Name
            if ($enabledFeatures.FeatureName -contains $name) {
                Write-EabLog -Component 'WindowsFeatures' -Message "Disabling optional feature '$name'."
                Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop | Out-Null
            }
        }

        $installedCapabilities = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object State -eq 'Installed')
        foreach ($capability in @($settings.RemoveCapabilities.Capability)) {
            if (-not (Get-EabBoolean -Value $capability.Enabled -Default $true)) {
                continue
            }

            $name = [string]$capability.Name
            foreach ($installed in @($installedCapabilities | Where-Object { $_.Name.Split('~')[0] -eq $name })) {
                Write-EabLog -Component 'WindowsFeatures' -Message "Removing capability '$($installed.Name)'."
                Remove-WindowsCapability -Online -Name $installed.Name -ErrorAction Stop | Out-Null
            }
        }

        foreach ($capability in @($settings.AddCapabilities.Capability)) {
            if (-not (Get-EabBoolean -Value $capability.Enabled -Default $true)) {
                continue
            }

            $name = [string]$capability.Name
            if ($installedCapabilities.Name -notcontains $name) {
                Write-EabLog -Component 'WindowsFeatures' -Message "Adding capability '$name'."
                Add-WindowsCapability -Online -Name $name -ErrorAction Stop | Out-Null
            }
        }
    }
    finally {
        if ($changedUseWuServer) {
            Set-EabRegistryValue -Path $windowsUpdatePath -Name 'UseWuServer' -Type DWord -Value $originalUseWuServer
            Restart-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Write-EabLog -Component 'WindowsFeatures' -Message 'Restored the original WSUS configuration.'
        }
    }
}

function Get-EabObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-EabWildcardMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules,

        [Parameter(Mandatory)]
        [ValidateSet('NamePattern', 'DisplayNamePattern')]
        [string]$PatternProperty
    )

    foreach ($rule in $Rules) {
        if ($null -eq $rule) {
            continue
        }

        $enabled = Get-EabObjectPropertyValue -InputObject $rule -Name 'Enabled'
        if (-not (Get-EabBoolean -Value $enabled -Default $true)) {
            continue
        }

        $pattern = [string](Get-EabObjectPropertyValue -InputObject $rule -Name $PatternProperty)
        if ($Value -like $pattern) {
            return $true
        }
    }

    return $false
}

function Get-EabMatchingClassicRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Application,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )

    foreach ($rule in $Rules) {
        if ($null -eq $rule) {
            continue
        }
        $enabled = Get-EabObjectPropertyValue -InputObject $rule -Name 'Enabled'
        if (-not (Get-EabBoolean -Value $enabled -Default $true)) {
            continue
        }

        $displayNamePattern = [string](Get-EabObjectPropertyValue -InputObject $rule -Name 'DisplayNamePattern')
        if ([string]$Application.DisplayName -notlike $displayNamePattern) {
            continue
        }

        $publisherPattern = [string](Get-EabObjectPropertyValue -InputObject $rule -Name 'PublisherPattern')
        if (-not [string]::IsNullOrWhiteSpace($publisherPattern) -and [string]$Application.Publisher -notlike $publisherPattern) {
            continue
        }

        return $rule
    }

    return $null
}

function Get-EabClassicApplicationInventory {
    [CmdletBinding()]
    param()

    $registryPaths = @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $applications = New-Object System.Collections.Generic.List[object]
    foreach ($registryPath in $registryPaths) {
        foreach ($entry in @(Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue)) {
            $displayName = [string](Get-EabObjectPropertyValue -InputObject $entry -Name 'DisplayName')
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                continue
            }

            $uninstallString = [string](Get-EabObjectPropertyValue -InputObject $entry -Name 'UninstallString')
            $quietUninstallString = [string](Get-EabObjectPropertyValue -InputObject $entry -Name 'QuietUninstallString')
            $childName = [string](Get-EabObjectPropertyValue -InputObject $entry -Name 'PSChildName')
            $productCode = $null
            $windowsInstaller = [int](Get-EabObjectPropertyValue -InputObject $entry -Name 'WindowsInstaller')

            # A GUID-shaped registry key is not sufficient proof that an entry is MSI-backed.
            # Use the key only when WindowsInstaller=1, or extract a product code from an
            # uninstall command that explicitly calls msiexec.
            if ($windowsInstaller -eq 1 -and $childName -match '^\{[0-9A-Fa-f-]{36}\}$') {
                $productCode = $childName
            }
            elseif ($uninstallString -match '(?i)\bmsiexec(?:\.exe)?\b.*?(\{[0-9A-F-]{36}\})') {
                $productCode = $Matches[1]
            }

            $applications.Add([pscustomobject]@{
                DisplayName          = $displayName
                DisplayVersion       = [string](Get-EabObjectPropertyValue -InputObject $entry -Name 'DisplayVersion')
                Publisher            = [string](Get-EabObjectPropertyValue -InputObject $entry -Name 'Publisher')
                WindowsInstaller     = $windowsInstaller
                ProductCode          = $productCode
                UninstallString      = $uninstallString
                QuietUninstallString = $quietUninstallString
                RegistryPath         = [string](Get-EabObjectPropertyValue -InputObject $entry -Name 'PSPath')
            })
        }
    }

    return @($applications)
}

function Get-EabDebloatInventory {
    [CmdletBinding()]
    param()

    $errors = New-Object System.Collections.Generic.List[object]
    $provisioned = @()
    $installed = @()
    $classic = @()

    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Sort-Object DisplayName, PackageName | ForEach-Object {
            [pscustomobject]@{
                DisplayName = $_.DisplayName
                PackageName = $_.PackageName
                Version     = $_.Version
            }
        })
    }
    catch {
        $errors.Add([pscustomobject]@{ Category = 'ProvisionedAppx'; Error = $_.Exception.Message })
    }

    try {
        $installed = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Sort-Object Name, PackageFullName -Unique | ForEach-Object {
            [pscustomobject]@{
                Name            = $_.Name
                PackageFullName = $_.PackageFullName
                Version         = $_.Version
                Publisher       = $_.Publisher
            }
        })
    }
    catch {
        $errors.Add([pscustomobject]@{ Category = 'InstalledAppx'; Error = $_.Exception.Message })
    }

    try {
        $classic = @(Get-EabClassicApplicationInventory | Sort-Object DisplayName, DisplayVersion | ForEach-Object {
            $silentMethod = if (-not [string]::IsNullOrWhiteSpace([string]$_.ProductCode)) {
                'MSI'
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$_.QuietUninstallString)) {
                'QuietUninstallString'
            }
            else {
                'None'
            }

            [pscustomobject]@{
                DisplayName    = $_.DisplayName
                DisplayVersion = $_.DisplayVersion
                Publisher      = $_.Publisher
                SilentMethod   = $silentMethod
                RegistryPath   = $_.RegistryPath
            }
        })
    }
    catch {
        $errors.Add([pscustomobject]@{ Category = 'ClassicApplication'; Error = $_.Exception.Message })
    }

    return [pscustomobject]@{
        CollectedUtc        = [DateTime]::UtcNow.ToString('o')
        ProvisionedAppx     = $provisioned
        InstalledAppx       = $installed
        ClassicApplications = $classic
        Errors              = @($errors)
    }
}

function Split-EabCommandLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandLine
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine).Trim()
    if ($expanded -match '^"([^"]+)"\s*(.*)$') {
        return [pscustomobject]@{
            FilePath  = $Matches[1]
            Arguments = $Matches[2]
        }
    }

    if ($expanded -match '^(.*?\.(?:exe|com|cmd|bat))(?=\s|$)\s*(.*)$') {
        return [pscustomobject]@{
            FilePath  = $Matches[1]
            Arguments = $Matches[2]
        }
    }

    if ($expanded -match '^(\S+)\s*(.*)$') {
        return [pscustomobject]@{
            FilePath  = $Matches[1]
            Arguments = $Matches[2]
        }
    }

    throw "Unable to parse command line '$CommandLine'."
}

function Invoke-EabClassicApplicationUninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Application,

        [Parameter()]
        [ValidateRange(30, 7200)]
        [int]$TimeoutSeconds = 900
    )

    $acceptedExitCodes = @(0, 1605, 1614, 1641, 3010)
    if (-not [string]::IsNullOrWhiteSpace([string]$Application.ProductCode)) {
        $msiExec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
        $arguments = "/x $($Application.ProductCode) /qn /norestart /L*v `"$env:TEMP\EAB-MSI-$($Application.ProductCode.Trim('{}')).log`""
        return Invoke-EabNativeProcess -FilePath $msiExec -ArgumentString $arguments -AcceptedExitCodes $acceptedExitCodes -TimeoutSeconds $TimeoutSeconds
    }

    if ([string]::IsNullOrWhiteSpace([string]$Application.QuietUninstallString)) {
        throw "No MSI product code or QuietUninstallString is available for '$($Application.DisplayName)'."
    }

    $command = Split-EabCommandLine -CommandLine ([string]$Application.QuietUninstallString)
    $resolvedExecutable = $command.FilePath
    if (-not [System.IO.Path]::IsPathRooted($resolvedExecutable)) {
        $commandInfo = Get-Command -Name $resolvedExecutable -ErrorAction SilentlyContinue
        if ($null -eq $commandInfo) {
            throw "Quiet uninstall executable '$resolvedExecutable' could not be resolved."
        }
        $resolvedExecutable = $commandInfo.Source
    }

    if (-not (Test-Path -LiteralPath $resolvedExecutable -PathType Leaf)) {
        throw "Quiet uninstall executable '$resolvedExecutable' does not exist."
    }

    return Invoke-EabNativeProcess -FilePath $resolvedExecutable -ArgumentString $command.Arguments -AcceptedExitCodes $acceptedExitCodes -TimeoutSeconds $TimeoutSeconds
}

function Invoke-EabProvisionedAppxDebloat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateSet('Audit', 'Enforce')]
        [string]$Mode
    )

    $results = New-Object System.Collections.Generic.List[object]
    if (-not (Get-EabBoolean -Value $Config.Debloat.RemoveProvisionedPackages -Default $true)) {
        return @($results)
    }

    $removeRules = @($Config.Debloat.AppxPackages.Package)
    $preserveRules = @($Config.Debloat.PreserveAppxPackages.Package)
    $packages = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)

    foreach ($package in $packages) {
        $candidateValues = @([string]$package.DisplayName, [string]$package.PackageName)
        $remove = $false
        foreach ($candidate in $candidateValues) {
            if (Test-EabWildcardMatch -Value $candidate -Rules $removeRules -PatternProperty NamePattern) {
                $remove = $true
                break
            }
        }

        if (-not $remove) {
            continue
        }

        $preserve = $false
        foreach ($candidate in $candidateValues) {
            if (Test-EabWildcardMatch -Value $candidate -Rules $preserveRules -PatternProperty NamePattern) {
                $preserve = $true
                break
            }
        }

        if ($preserve) {
            Write-EabLog -Component 'Debloat' -Message "Preserving provisioned package '$($package.DisplayName)'."
            $results.Add([pscustomobject]@{ Type = 'ProvisionedAppx'; Name = $package.DisplayName; Action = 'Preserved'; Success = $true; Error = $null })
            continue
        }

        if ($Mode -eq 'Audit') {
            Write-EabLog -Component 'Debloat' -Message "[AUDIT] Would remove provisioned package '$($package.DisplayName)'."
            $results.Add([pscustomobject]@{ Type = 'ProvisionedAppx'; Name = $package.DisplayName; Action = 'WouldRemove'; Success = $true; Error = $null })
            continue
        }

        try {
            Write-EabLog -Component 'Debloat' -Message "Removing provisioned package '$($package.DisplayName)'."
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -AllUsers -ErrorAction Stop | Out-Null
            $results.Add([pscustomobject]@{ Type = 'ProvisionedAppx'; Name = $package.DisplayName; Action = 'Removed'; Success = $true; Error = $null })
        }
        catch {
            Write-EabLog -Level WARN -Component 'Debloat' -Message "Unable to remove provisioned package '$($package.DisplayName)': $($_.Exception.Message)"
            $results.Add([pscustomobject]@{ Type = 'ProvisionedAppx'; Name = $package.DisplayName; Action = 'RemoveFailed'; Success = $false; Error = $_.Exception.Message })
        }
    }

    return @($results)
}

function Invoke-EabInstalledAppxDebloat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateSet('Audit', 'Enforce')]
        [string]$Mode
    )

    $results = New-Object System.Collections.Generic.List[object]
    if (-not (Get-EabBoolean -Value $Config.Debloat.RemoveInstalledPackages -Default $true)) {
        return @($results)
    }

    $removeRules = @($Config.Debloat.AppxPackages.Package)
    $preserveRules = @($Config.Debloat.PreserveAppxPackages.Package)
    $seenPackages = @{}
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
        -not (Get-EabBoolean -Value (Get-EabObjectPropertyValue -InputObject $_ -Name 'IsFramework') -Default $false) -and
        -not (Get-EabBoolean -Value (Get-EabObjectPropertyValue -InputObject $_ -Name 'IsResourcePackage') -Default $false)
    })

    foreach ($package in $packages) {
        if ($seenPackages.ContainsKey([string]$package.PackageFullName)) {
            continue
        }
        $seenPackages[[string]$package.PackageFullName] = $true

        $candidateValues = @([string]$package.Name, [string]$package.PackageFullName)
        $remove = $false
        foreach ($candidate in $candidateValues) {
            if (Test-EabWildcardMatch -Value $candidate -Rules $removeRules -PatternProperty NamePattern) {
                $remove = $true
                break
            }
        }

        if (-not $remove) {
            continue
        }

        $preserve = $false
        foreach ($candidate in $candidateValues) {
            if (Test-EabWildcardMatch -Value $candidate -Rules $preserveRules -PatternProperty NamePattern) {
                $preserve = $true
                break
            }
        }

        if ($preserve) {
            Write-EabLog -Component 'Debloat' -Message "Preserving installed package '$($package.Name)'."
            $results.Add([pscustomobject]@{ Type = 'InstalledAppx'; Name = $package.Name; Action = 'Preserved'; Success = $true; Error = $null })
            continue
        }

        if ($Mode -eq 'Audit') {
            Write-EabLog -Component 'Debloat' -Message "[AUDIT] Would remove installed package '$($package.Name)'."
            $results.Add([pscustomobject]@{ Type = 'InstalledAppx'; Name = $package.Name; Action = 'WouldRemove'; Success = $true; Error = $null })
            continue
        }

        try {
            Write-EabLog -Component 'Debloat' -Message "Removing installed package '$($package.Name)' for all users."
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            $results.Add([pscustomobject]@{ Type = 'InstalledAppx'; Name = $package.Name; Action = 'Removed'; Success = $true; Error = $null })
        }
        catch {
            Write-EabLog -Level WARN -Component 'Debloat' -Message "Unable to remove installed package '$($package.Name)': $($_.Exception.Message)"
            $results.Add([pscustomobject]@{ Type = 'InstalledAppx'; Name = $package.Name; Action = 'RemoveFailed'; Success = $false; Error = $_.Exception.Message })
        }
    }

    return @($results)
}

function Invoke-EabClassicApplicationDebloat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateSet('Audit', 'Enforce')]
        [string]$Mode
    )

    $results = New-Object System.Collections.Generic.List[object]
    if (-not (Get-EabBoolean -Value $Config.Debloat.RemoveClassicApplications -Default $true)) {
        return @($results)
    }

    $removeRules = @($Config.Debloat.ClassicApplications.Application)
    $preserveRules = @($Config.Debloat.PreserveClassicApplications.Application)
    $inventory = @(Get-EabClassicApplicationInventory)
    $seen = @{}
    $perApplicationTimeout = [int]$Config.Debloat.ClassicUninstallTimeoutSeconds
    $overallTimeout = [int]$Config.Debloat.ClassicOverallTimeoutSeconds
    $overallTimer = [Diagnostics.Stopwatch]::StartNew()

    foreach ($application in $inventory) {
        $removeRule = Get-EabMatchingClassicRule -Application $application -Rules $removeRules
        if ($null -eq $removeRule) {
            continue
        }

        if ($seen.ContainsKey($application.RegistryPath)) {
            continue
        }
        $seen[$application.RegistryPath] = $true

        if (-not (Test-Path -LiteralPath $application.RegistryPath)) {
            Write-EabLog -Component 'Debloat' -Message "Classic application '$($application.DisplayName)' was removed by an earlier package action."
            $results.Add([pscustomobject]@{ Type = 'ClassicApplication'; Name = $application.DisplayName; Version = $application.DisplayVersion; Action = 'AlreadyRemoved'; Success = $true; Error = $null })
            continue
        }

        $preserveRule = Get-EabMatchingClassicRule -Application $application -Rules $preserveRules
        if ($null -ne $preserveRule) {
            Write-EabLog -Component 'Debloat' -Message "Preserving classic application '$($application.DisplayName)'."
            $results.Add([pscustomobject]@{ Type = 'ClassicApplication'; Name = $application.DisplayName; Version = $application.DisplayVersion; Action = 'Preserved'; Success = $true; Error = $null })
            continue
        }

        if ($Mode -eq 'Audit') {
            $hasSilentCommand = (
                -not [string]::IsNullOrWhiteSpace([string]$application.ProductCode) -or
                -not [string]::IsNullOrWhiteSpace([string]$application.QuietUninstallString)
            )
            if ($hasSilentCommand) {
                Write-EabLog -Component 'Debloat' -Message "[AUDIT] Would silently uninstall classic application '$($application.DisplayName)' version '$($application.DisplayVersion)'."
                $results.Add([pscustomobject]@{ Type = 'ClassicApplication'; Name = $application.DisplayName; Version = $application.DisplayVersion; Action = 'WouldRemove'; Success = $true; Error = $null })
            }
            else {
                $message = 'No MSI product code or QuietUninstallString is registered.'
                Write-EabLog -Level WARN -Component 'Debloat' -Message "[AUDIT] Would skip classic application '$($application.DisplayName)': $message"
                $results.Add([pscustomobject]@{ Type = 'ClassicApplication'; Name = $application.DisplayName; Version = $application.DisplayVersion; Action = 'WouldSkipNoSilentCommand'; Success = $false; Error = $message })
            }
            continue
        }

        try {
            $remainingSeconds = $overallTimeout - [int][Math]::Floor($overallTimer.Elapsed.TotalSeconds)
            if ($remainingSeconds -lt 30) {
                $message = "The $overallTimeout second classic-application time budget was exhausted."
                Write-EabLog -Level WARN -Component 'Debloat' -Message $message
                $results.Add([pscustomobject]@{ Type = 'ClassicApplication'; Name = '*'; Version = $null; Action = 'TimeBudgetExceeded'; Success = $false; ExitCode = $null; Error = $message })
                break
            }

            $processTimeout = [Math]::Min($perApplicationTimeout, $remainingSeconds)
            Write-EabLog -Component 'Debloat' -Message "Uninstalling classic application '$($application.DisplayName)' version '$($application.DisplayVersion)'."
            $exitCode = Invoke-EabClassicApplicationUninstall -Application $application -TimeoutSeconds $processTimeout
            $results.Add([pscustomobject]@{
                Type            = 'ClassicApplication'
                Name            = $application.DisplayName
                Version         = $application.DisplayVersion
                Action          = 'Removed'
                Success         = $true
                ExitCode        = $exitCode
                RestartRequired = $exitCode -in @(1641, 3010)
                Error           = $null
            })
        }
        catch {
            $action = 'RemoveFailed'
            if ($_.Exception.Message -like 'No MSI product code or QuietUninstallString*') {
                $action = 'SkippedNoSilentCommand'
            }
            Write-EabLog -Level WARN -Component 'Debloat' -Message "Unable to silently uninstall '$($application.DisplayName)': $($_.Exception.Message)"
            $results.Add([pscustomobject]@{ Type = 'ClassicApplication'; Name = $application.DisplayName; Version = $application.DisplayVersion; Action = $action; Success = $false; ExitCode = $null; Error = $_.Exception.Message })
        }
    }

    return @($results)
}

function Remove-EabPublicDesktopShortcuts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateSet('Audit', 'Enforce')]
        [string]$Mode
    )

    $results = New-Object System.Collections.Generic.List[object]
    if (-not (Get-EabBoolean -Value $Config.Debloat.RemovePublicDesktopShortcuts -Default $true)) {
        return @($results)
    }

    $desktopPath = Join-Path $env:PUBLIC 'Desktop'
    if (-not (Test-Path -LiteralPath $desktopPath)) {
        return @($results)
    }

    $rules = @($Config.Debloat.PublicDesktopShortcuts.Shortcut)
    foreach ($file in @(Get-ChildItem -LiteralPath $desktopPath -File -ErrorAction SilentlyContinue)) {
        if (-not (Test-EabWildcardMatch -Value $file.Name -Rules $rules -PatternProperty NamePattern)) {
            continue
        }

        if ($Mode -eq 'Audit') {
            Write-EabLog -Component 'Debloat' -Message "[AUDIT] Would remove public desktop shortcut '$($file.FullName)'."
            $results.Add([pscustomobject]@{ Type = 'PublicDesktopShortcut'; Name = $file.Name; Action = 'WouldRemove'; Success = $true; Error = $null })
            continue
        }

        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            Write-EabLog -Component 'Debloat' -Message "Removed public desktop shortcut '$($file.FullName)'."
            $results.Add([pscustomobject]@{ Type = 'PublicDesktopShortcut'; Name = $file.Name; Action = 'Removed'; Success = $true; Error = $null })
        }
        catch {
            Write-EabLog -Level WARN -Component 'Debloat' -Message "Unable to remove public desktop shortcut '$($file.FullName)': $($_.Exception.Message)"
            $results.Add([pscustomobject]@{ Type = 'PublicDesktopShortcut'; Name = $file.Name; Action = 'RemoveFailed'; Success = $false; Error = $_.Exception.Message })
        }
    }

    return @($results)
}

function Invoke-EabDebloat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateSet('Device', 'PostEnroll', 'Manual')]
        [string]$Phase,

        [Parameter()]
        [switch]$AuditOnly
    )

    if ($null -eq $Config.Debloat -or -not (Get-EabBoolean -Value $Config.Debloat.Enabled -Default $false)) {
        Write-EabLog -Component 'Debloat' -Message 'Debloat is disabled.'
        return [pscustomobject]@{
            Phase = $Phase; Mode = 'Disabled'; CompletedUtc = [DateTime]::UtcNow.ToString('o')
            Results = @(); RemovedCount = 0; AuditCount = 0; FailureCount = 0; RestartRequiredCount = 0
        }
    }

    if ($Phase -eq 'Device' -and -not (Get-EabBoolean -Value $Config.Debloat.RunDuringDevicePhase -Default $true)) {
        Write-EabLog -Component 'Debloat' -Message 'The device-phase debloat pass is disabled.'
        return [pscustomobject]@{
            Phase = $Phase; Mode = 'DisabledForPhase'; CompletedUtc = [DateTime]::UtcNow.ToString('o')
            Results = @(); RemovedCount = 0; AuditCount = 0; FailureCount = 0; RestartRequiredCount = 0
        }
    }

    if ($Phase -eq 'PostEnroll' -and -not (Get-EabBoolean -Value $Config.Debloat.RunAtFirstLogon -Default $true)) {
        Write-EabLog -Component 'Debloat' -Message 'The first-logon debloat pass is disabled.'
        return [pscustomobject]@{
            Phase = $Phase; Mode = 'DisabledForPhase'; CompletedUtc = [DateTime]::UtcNow.ToString('o')
            Results = @(); RemovedCount = 0; AuditCount = 0; FailureCount = 0; RestartRequiredCount = 0
        }
    }

    $mode = [string]$Config.Debloat.Mode
    if ($AuditOnly) {
        $mode = 'Audit'
    }

    Write-EabLog -Component 'Debloat' -Message "Starting $Phase debloat pass in $mode mode."
    $allResults = New-Object System.Collections.Generic.List[object]

    $categories = @(
        [pscustomobject]@{ Name = 'ProvisionedAppx'; Action = { Invoke-EabProvisionedAppxDebloat -Config $Config -Mode $mode } },
        [pscustomobject]@{ Name = 'InstalledAppx'; Action = { Invoke-EabInstalledAppxDebloat -Config $Config -Mode $mode } },
        [pscustomobject]@{ Name = 'ClassicApplication'; Action = { Invoke-EabClassicApplicationDebloat -Config $Config -Mode $mode } },
        [pscustomobject]@{ Name = 'PublicDesktopShortcut'; Action = { Remove-EabPublicDesktopShortcuts -Config $Config -Mode $mode } }
    )

    foreach ($category in $categories) {
        try {
            foreach ($result in @(& $category.Action)) {
                $allResults.Add($result)
            }
        }
        catch {
            $message = $_.Exception.Message
            Write-EabLog -Level ERROR -Component 'Debloat' -Message "Debloat category '$($category.Name)' failed: $message"
            $allResults.Add([pscustomobject]@{
                Type    = $category.Name
                Name    = '*'
                Action  = 'CategoryFailed'
                Success = $false
                Error   = $message
            })
        }
    }

    $failureCount = @($allResults | Where-Object { -not $_.Success }).Count
    $removedCount = @($allResults | Where-Object Action -eq 'Removed').Count
    $auditCount = @($allResults | Where-Object Action -eq 'WouldRemove').Count
    $restartRequiredCount = @($allResults | Where-Object {
        Get-EabBoolean -Value (Get-EabObjectPropertyValue -InputObject $_ -Name 'RestartRequired') -Default $false
    }).Count
    Write-EabLog -Component 'Debloat' -Message "Completed $Phase debloat pass. Removed: $removedCount; audit matches: $auditCount; failures/skips: $failureCount; restart-required results: $restartRequiredCount."

    return [pscustomobject]@{
        Phase        = $Phase
        Mode         = $mode
        CompletedUtc = [DateTime]::UtcNow.ToString('o')
        Results      = @($allResults)
        RemovedCount = $removedCount
        AuditCount   = $auditCount
        FailureCount = $failureCount
        RestartRequiredCount = $restartRequiredCount
    }
}

function Copy-EabRuntimeFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$RuntimeRoot
    )

    $runtimeParent = Split-Path -Path $RuntimeRoot -Parent
    if (-not (Test-Path -LiteralPath $runtimeParent -PathType Container)) {
        New-Item -Path $runtimeParent -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $stagingRoot = "$RuntimeRoot.staging.$PID"
    $backupRoot = "$RuntimeRoot.backup"
    foreach ($temporaryPath in @($stagingRoot, $backupRoot)) {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Recurse -Force -ErrorAction Stop
        }
    }
    New-Item -Path $stagingRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null

    $files = @(
        'Config.xml',
        'Config.xsd',
        'Invoke-PostEnroll.ps1',
        'Invoke-Debloat.ps1'
    )

    try {
        foreach ($relativePath in $files) {
            $source = Join-Path $SourceRoot $relativePath
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Required runtime source file '$source' does not exist."
            }
            Copy-Item -LiteralPath $source -Destination (Join-Path $stagingRoot $relativePath) -Force -ErrorAction Stop
        }

        foreach ($directoryName in @('Modules', 'Custom')) {
            $sourceDirectory = Join-Path $SourceRoot $directoryName
            if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
                throw "Required runtime source directory '$sourceDirectory' does not exist."
            }
            Copy-Item -LiteralPath $sourceDirectory -Destination $stagingRoot -Recurse -Force -ErrorAction Stop
        }

        # Hashing the complete staging tree verifies that every copied file is readable before the
        # active runtime is replaced.
        $null = @(Get-EabRuntimeManifest -RuntimeRoot $stagingRoot)

        if (Test-Path -LiteralPath $RuntimeRoot) {
            Move-Item -LiteralPath $RuntimeRoot -Destination $backupRoot -Force -ErrorAction Stop
        }

        try {
            Move-Item -LiteralPath $stagingRoot -Destination $RuntimeRoot -Force -ErrorAction Stop
        }
        catch {
            if ((Test-Path -LiteralPath $backupRoot) -and -not (Test-Path -LiteralPath $RuntimeRoot)) {
                Move-Item -LiteralPath $backupRoot -Destination $RuntimeRoot -Force -ErrorAction SilentlyContinue
            }
            throw
        }

        if (Test-Path -LiteralPath $backupRoot) {
            try {
                Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-EabLog -Level WARN -Component 'Runtime' -Message "The previous runtime backup '$backupRoot' could not be removed: $($_.Exception.Message)"
            }
        }

        Write-EabLog -Component 'Runtime' -Message "Staged and activated the complete runtime at '$RuntimeRoot'."
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-EabScheduledTaskFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Service,

        [Parameter(Mandatory)]
        [string]$TaskPath,

        [Parameter()]
        [switch]$Create
    )

    $normalizedPath = '\' + $TaskPath.Trim('\')
    if ($normalizedPath -eq '\') {
        return $Service.GetFolder('\')
    }

    try {
        return $Service.GetFolder($normalizedPath)
    }
    catch {
        if (-not $Create) {
            throw
        }
    }

    $currentFolder = $Service.GetFolder('\')
    $currentPath = ''
    foreach ($segment in @($normalizedPath.Trim('\').Split('\'))) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }

        $currentPath = "$currentPath\$segment"
        try {
            $currentFolder = $Service.GetFolder($currentPath)
        }
        catch {
            $currentFolder = $currentFolder.CreateFolder($segment)
        }
    }

    return $currentFolder
}

function Register-EabPostEnrollTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter(Mandatory)]
        [string]$RuntimeRoot
    )

    $settings = $Config.PostEnroll
    if ($null -eq $settings -or -not (Get-EabBoolean -Value $settings.Enabled -Default $false)) {
        Write-EabLog -Component 'PostEnroll' -Message 'Post-enrollment task registration is disabled.'
        return
    }

    $scriptPath = Join-Path $RuntimeRoot 'Invoke-PostEnroll.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Post-enrollment script '$scriptPath' was not staged."
    }

    $taskPath = [string]$settings.TaskPath
    $taskName = [string]$settings.TaskName
    $delayMinutes = [int]$settings.DelayMinutes
    if ($delayMinutes -lt 0 -or $delayMinutes -gt 120) {
        throw 'PostEnroll DelayMinutes must be between 0 and 120.'
    }

    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $folder = Get-EabScheduledTaskFolder -Service $service -TaskPath $taskPath -Create
    $definition = $service.NewTask(0)

    $definition.RegistrationInfo.Description = 'Runs Enterprise Autopilot Branding post-enrollment work after the first interactive sign-in.'
    $definition.RegistrationInfo.Author = [string]$Config.Metadata.OrganizationName

    $definition.Principal.UserId = 'SYSTEM'
    $definition.Principal.LogonType = 5
    $definition.Principal.RunLevel = 1

    $definition.Settings.Enabled = $true
    $definition.Settings.Hidden = $false
    $definition.Settings.StartWhenAvailable = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.AllowHardTerminate = $true
    $definition.Settings.ExecutionTimeLimit = 'PT1H'
    $definition.Settings.MultipleInstances = 2

    $trigger = $definition.Triggers.Create(9)
    $trigger.Enabled = $true
    if ($delayMinutes -gt 0) {
        $trigger.Delay = "PT$($delayMinutes)M"
    }

    $action = $definition.Actions.Create(0)
    $action.Path = $powerShellPath
    $action.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""
    $action.WorkingDirectory = $RuntimeRoot

    $taskCreateOrUpdate = 6
    $taskLogonServiceAccount = 5
    $null = $folder.RegisterTaskDefinition($taskName, $definition, $taskCreateOrUpdate, 'SYSTEM', $null, $taskLogonServiceAccount, $null)
    Write-EabLog -Component 'PostEnroll' -Message "Registered scheduled task '$taskPath\$taskName' with a $delayMinutes minute logon delay."
}

function Unregister-EabPostEnrollTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter()]
        [switch]$IgnoreMissing
    )

    $settings = $Config.PostEnroll
    if ($null -eq $settings) {
        return
    }

    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    try {
        $folder = Get-EabScheduledTaskFolder -Service $service -TaskPath ([string]$settings.TaskPath)
        $folder.DeleteTask([string]$settings.TaskName, 0)
        Write-EabLog -Component 'PostEnroll' -Message "Unregistered scheduled task '$($settings.TaskPath)\$($settings.TaskName)'."
    }
    catch {
        if (-not $IgnoreMissing) {
            throw
        }
        Write-EabLog -Level DEBUG -Component 'PostEnroll' -Message 'Post-enrollment task was not present.'
    }
}

function Get-EabInteractiveUser {
    [CmdletBinding()]
    param()

    $userName = [string](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
    if ([string]::IsNullOrWhiteSpace($userName)) {
        return $null
    }

    try {
        $account = New-Object Security.Principal.NTAccount($userName)
        $sid = $account.Translate([Security.Principal.SecurityIdentifier]).Value
    }
    catch {
        $sid = $null
    }

    return [pscustomobject]@{
        UserName = $userName
        Sid      = $sid
    }
}

function Remove-EabInstalledArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter()]
        [switch]$RemoveBrandingAssets
    )

    Unregister-EabPostEnrollTask -Config $Config -IgnoreMissing

    if (-not $RemoveBrandingAssets) {
        return
    }

    foreach ($assetName in @('Wallpaper', 'LockScreen', 'Theme', 'OemLogo', 'TaskbarLayout')) {
        $asset = $Config.Branding.$assetName
        if ($null -eq $asset -or [string]::IsNullOrWhiteSpace([string]$asset.Destination)) {
            continue
        }

        $destination = Resolve-EabPath -Path ([string]$asset.Destination)
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            Remove-Item -LiteralPath $destination -Force -ErrorAction Stop
            Write-EabLog -Component 'Uninstall' -Message "Removed branding asset '$destination'."
        }
    }
}

Export-ModuleMember -Function @(
    'Copy-EabRuntimeFiles',
    'Dismount-EabDefaultUserHive',
    'Get-EabBoolean',
    'Get-EabClassicApplicationInventory',
    'Get-EabDebloatInventory',
    'Get-EabFileHashValue',
    'Get-EabInteractiveUser',
    'Get-EabOsContext',
    'Get-EabRuntimeManifest',
    'Import-EabConfiguration',
    'Import-EabDefaultAppAssociations',
    'Initialize-EabLogging',
    'Install-EabBrandingAssets',
    'Install-EabLegacyStartLayout',
    'Install-EabTaskbarLayout',
    'Invoke-EabDebloat',
    'Invoke-EabNativeProcess',
    'Mount-EabDefaultUserHive',
    'Read-EabStateFile',
    'Register-EabPostEnrollTask',
    'Remove-EabInstalledArtifacts',
    'Resolve-EabChildPath',
    'Resolve-EabPath',
    'Set-EabConfiguredRegistryValues',
    'Set-EabDefaultUserConfiguration',
    'Set-EabMachineConfiguration',
    'Set-EabOemInformation',
    'Set-EabRegistryValue',
    'Set-EabTimeZoneConfiguration',
    'Set-EabWindowsFeatures',
    'Test-EabConfigurationSchema',
    'Test-EabConfiguredAssets',
    'Test-EabIsAdministrator',
    'Test-EabIsSystem',
    'Test-EabRuntimeManifest',
    'Unregister-EabPostEnrollTask',
    'Write-EabLog',
    'Write-EabStateFile'
)
