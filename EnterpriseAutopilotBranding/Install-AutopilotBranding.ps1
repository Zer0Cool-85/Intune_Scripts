#requires -Version 5.1

<#
.SYNOPSIS
Installs the Enterprise Autopilot Branding package.

.DESCRIPTION
Applies deterministic, offline-capable device branding and configuration, performs an optional
config-driven debloat pass, stages the post-enrollment runtime, and writes versioned installation
state only after all critical work succeeds.

.PARAMETER Force
Runs the installer even when the installed package version and configuration hash already match.

.PARAMETER AuditOnly
Forces debloat into Audit mode for this execution without changing Config.xml.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$AuditOnly
)

# Relaunch in native 64-bit Windows PowerShell when Intune or another host starts the 32-bit engine.
if ($env:PROCESSOR_ARCHITEW6432) {
    $nativePowerShell = Join-Path $env:SystemRoot 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $nativePowerShell) {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($Force) { $arguments += '-Force' }
        if ($AuditOnly) { $arguments += '-AuditOnly' }

        $process = Start-Process -FilePath $nativePowerShell -ArgumentList $arguments -Wait -PassThru
        exit $process.ExitCode
    }
}

Set-StrictMode -Version 3.0
$originalErrorActionPreference = $ErrorActionPreference
$originalProgressPreference = $ProgressPreference
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$productName = 'EnterpriseAutopilotBranding'
$productRoot = Join-Path $env:ProgramData $productName
$runtimeRoot = Join-Path $productRoot 'Runtime'
$logDirectory = Join-Path $productRoot 'Logs'
$stateDirectory = Join-Path $productRoot 'State'
$statePath = Join-Path $stateDirectory 'InstallState.json'
$configPath = Join-Path $PSScriptRoot 'Config.xml'
$modulePath = Join-Path $PSScriptRoot 'Modules\EnterpriseAutopilotBranding.psm1'

$script:StepResults = New-Object System.Collections.Generic.List[object]
$script:NonCriticalFailureCount = 0
$script:DebloatSummary = $null
$script:Config = $null
$script:ConfigHash = $null
$script:OsContext = $null
$script:PackageVersion = '0.0.0'
$script:RuntimeManifest = @()
$exitCode = 1

function Add-InstallStepResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][bool]$Critical,
        [Parameter(Mandatory)][long]$DurationMilliseconds,
        [Parameter()][AllowNull()][string]$ErrorMessage
    )

    $script:StepResults.Add([pscustomobject]@{
        Name                 = $Name
        Status               = $Status
        Critical             = $Critical
        DurationMilliseconds = $DurationMilliseconds
        Error                = $ErrorMessage
    })
}

function Invoke-InstallStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter()][bool]$Critical = $true
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    Write-EabLog -Component 'Install' -Message "START: $Name"
    try {
        & $Action
        $stopwatch.Stop()
        Add-InstallStepResult -Name $Name -Status 'Success' -Critical $Critical -DurationMilliseconds $stopwatch.ElapsedMilliseconds
        Write-EabLog -Component 'Install' -Message "SUCCESS: $Name ($($stopwatch.Elapsed.TotalSeconds.ToString('0.0')) seconds)"
    }
    catch {
        $stopwatch.Stop()
        $message = $_.Exception.Message
        Add-InstallStepResult -Name $Name -Status 'Failed' -Critical $Critical -DurationMilliseconds $stopwatch.ElapsedMilliseconds -ErrorMessage $message
        Write-EabLog -Level ERROR -Component 'Install' -Message "FAILED: $Name - $message"

        if ($Critical) {
            throw
        }

        $script:NonCriticalFailureCount++
    }
}

function New-InstallState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Result,
        [Parameter()][AllowNull()][string]$ErrorMessage
    )

    return [ordered]@{
        Product            = $productName
        PackageVersion     = $script:PackageVersion
        ConfigSchema       = if ($null -ne $script:Config) { [string]$script:Config.SchemaVersion } else { $null }
        ConfigHash         = $script:ConfigHash
        Result             = $Result
        CompletedUtc       = [DateTime]::UtcNow.ToString('o')
        ComputerName       = $env:COMPUTERNAME
        RunAs              = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        AuditOnly          = [bool]$AuditOnly
        NonCriticalFailure = $script:NonCriticalFailureCount
        Error              = $ErrorMessage
        Os                 = $script:OsContext
        RuntimeManifest    = @($script:RuntimeManifest)
        Steps              = @($script:StepResults)
        Debloat            = $script:DebloatSummary
    }
}

try {
    if (-not (Test-Path -LiteralPath $productRoot)) {
        New-Item -Path $productRoot -ItemType Directory -Force | Out-Null
    }

    Import-Module -Name $modulePath -Force -ErrorAction Stop
    Initialize-EabLogging -LogDirectory $logDirectory -Component 'Install'
    Write-EabLog -Component 'Install' -Message "Starting $productName from '$PSScriptRoot'."

    Invoke-InstallStep -Name 'Load and validate configuration' -Critical $true -Action {
        $script:Config = Import-EabConfiguration -Path $configPath
        $script:PackageVersion = [string]$script:Config.PackageVersion
        $script:ConfigHash = Get-EabFileHashValue -Path $configPath
        Write-EabLog -Component 'Config' -Message "Loaded schema $($script:Config.SchemaVersion), package version $script:PackageVersion, configuration hash $script:ConfigHash."
    }

    $existingState = Read-EabStateFile -Path $statePath
    if (-not $Force -and -not $AuditOnly -and $null -ne $existingState) {
        $existingResult = [string]$existingState.Result
        if ($existingResult -in @('Success', 'SuccessWithWarnings') -and
            [string]$existingState.PackageVersion -eq $script:PackageVersion -and
            [string]$existingState.ConfigHash -eq $script:ConfigHash) {
            $manifestProperty = $existingState.PSObject.Properties['RuntimeManifest']
            $runtimeMatches = $null -ne $manifestProperty -and (Test-EabRuntimeManifest -RuntimeRoot $runtimeRoot -Manifest @($manifestProperty.Value))
            if ($runtimeMatches) {
                Write-EabLog -Component 'Install' -Message 'The installed version, configuration hash, and runtime manifest already match. No work is required.'
                exit 0
            }

            Write-EabLog -Level WARN -Component 'Install' -Message 'Version and configuration match, but the staged runtime is missing or altered. The package will repair it.'
        }
    }

    Invoke-InstallStep -Name 'Preflight validation' -Critical $true -Action {
        if (-not (Test-EabIsAdministrator)) {
            throw 'Installation must run from an elevated administrator or SYSTEM context.'
        }

        $script:OsContext = Get-EabOsContext
        $minimumBuild = [int]$script:Config.Execution.MinimumSupportedBuild
        if ($script:OsContext.BuildNumber -lt $minimumBuild) {
            throw "Windows build $($script:OsContext.BuildNumber) is below the configured minimum build $minimumBuild."
        }

        if (-not $script:OsContext.Is64BitProcess) {
            throw 'The installer must run in a native 64-bit PowerShell process.'
        }

        Test-EabConfiguredAssets -Config $script:Config -SourceRoot $PSScriptRoot
        Write-EabLog -Component 'Preflight' -Message "OS: $($script:OsContext.Caption) $($script:OsContext.Version); architecture: $($script:OsContext.OsArchitecture); manufacturer/model: $($script:OsContext.Manufacturer) $($script:OsContext.Model); SYSTEM: $($script:OsContext.IsSystem)."
    }

    Invoke-InstallStep -Name 'Stage post-enrollment runtime' -Critical $true -Action {
        Copy-EabRuntimeFiles -SourceRoot $PSScriptRoot -RuntimeRoot $runtimeRoot
    }

    Invoke-InstallStep -Name 'Install branding assets' -Critical $true -Action {
        Install-EabBrandingAssets -Config $script:Config -SourceRoot $PSScriptRoot
        Install-EabTaskbarLayout -Config $script:Config -SourceRoot $PSScriptRoot
        Install-EabLegacyStartLayout -Config $script:Config -SourceRoot $PSScriptRoot -OsBuild $script:OsContext.BuildNumber
    }

    Invoke-InstallStep -Name 'Configure default user profile' -Critical $true -Action {
        $mount = $null
        try {
            $mount = Mount-EabDefaultUserHive
            Set-EabDefaultUserConfiguration -Config $script:Config -HiveRoot $mount.RegistryPath
        }
        finally {
            if ($null -ne $mount) {
                Dismount-EabDefaultUserHive -Mount $mount
            }
        }
    }

    Invoke-InstallStep -Name 'Configure machine branding and preferences' -Critical $true -Action {
        Set-EabMachineConfiguration -Config $script:Config
        Set-EabOemInformation -Config $script:Config
    }

    Invoke-InstallStep -Name 'Configure time zone' -Critical $false -Action {
        Set-EabTimeZoneConfiguration -Config $script:Config
    }

    Invoke-InstallStep -Name 'Import default app associations' -Critical $false -Action {
        Import-EabDefaultAppAssociations -Config $script:Config -SourceRoot $PSScriptRoot
    }

    Invoke-InstallStep -Name 'Configure Windows features and capabilities' -Critical $false -Action {
        Set-EabWindowsFeatures -Config $script:Config
    }

    $debloatIsCritical = Get-EabBoolean -Value $script:Config.Debloat.FailOnError -Default $false
    Invoke-InstallStep -Name 'Run device-phase debloat' -Critical $debloatIsCritical -Action {
        $script:DebloatSummary = Invoke-EabDebloat -Config $script:Config -Phase Device -AuditOnly:$AuditOnly
        $reportPath = Join-Path $stateDirectory 'Debloat-Device.json'
        Write-EabStateFile -Path $reportPath -State $script:DebloatSummary
        if ([int]$script:DebloatSummary.FailureCount -gt 0) {
            throw "The device-phase debloat report contains $($script:DebloatSummary.FailureCount) failed or unsupported action(s)."
        }
    }

    Invoke-InstallStep -Name 'Verify staged runtime integrity' -Critical $true -Action {
        $script:RuntimeManifest = @(Get-EabRuntimeManifest -RuntimeRoot $runtimeRoot)
    }

    Invoke-InstallStep -Name 'Register first-logon post-enrollment task' -Critical $true -Action {
        Register-EabPostEnrollTask -Config $script:Config -RuntimeRoot $runtimeRoot
    }

    $result = if ($script:NonCriticalFailureCount -gt 0) { 'SuccessWithWarnings' } else { 'Success' }
    $successState = New-InstallState -Result $result
    Write-EabStateFile -Path $statePath -State $successState

    Write-EabLog -Component 'Install' -Message "Installation completed with result '$result'. Versioned detection state was written only after critical steps succeeded."
    $exitCode = 0
}
catch {
    $failureMessage = $_.Exception.Message
    try {
        if (Get-Command -Name Write-EabLog -ErrorAction SilentlyContinue) {
            Write-EabLog -Level ERROR -Component 'Install' -Message "Installation failed: $failureMessage"
        }

        if (Get-Command -Name Write-EabStateFile -ErrorAction SilentlyContinue) {
            $failureState = New-InstallState -Result 'Failed' -ErrorMessage $failureMessage
            Write-EabStateFile -Path $statePath -State $failureState
        }
    }
    catch {
        Write-Warning "Unable to write failure state: $($_.Exception.Message)"
    }
    $exitCode = 1
}
finally {
    $ErrorActionPreference = $originalErrorActionPreference
    $ProgressPreference = $originalProgressPreference
}

exit $exitCode
