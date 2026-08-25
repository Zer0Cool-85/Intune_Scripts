#requires -Version 5.1

<#
.SYNOPSIS
Runs the delayed SYSTEM-context post-enrollment phase after an interactive sign-in.

.DESCRIPTION
Re-runs the idempotent debloat engine after Windows has created a user profile, then invokes the
optional organization-specific hook under Custom\PostEnroll.Custom.ps1. The scheduled task removes
itself after success when RunOnce is enabled.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$AuditOnly
)

if ($env:PROCESSOR_ARCHITEW6432) {
    $nativePowerShell = Join-Path $env:SystemRoot 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $nativePowerShell) {
        $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        if ($Force) { $arguments += '-Force' }
        if ($AuditOnly) { $arguments += '-AuditOnly' }
        $process = Start-Process -FilePath $nativePowerShell -ArgumentList $arguments -Wait -PassThru
        exit $process.ExitCode
    }
}

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$productName = 'EnterpriseAutopilotBranding'
$productRoot = Join-Path $env:ProgramData $productName
$runtimeRoot = Join-Path $productRoot 'Runtime'
$logDirectory = Join-Path $productRoot 'Logs'
$stateDirectory = Join-Path $productRoot 'State'
$statePath = Join-Path $stateDirectory 'PostEnrollState.json'
$configPath = Join-Path $runtimeRoot 'Config.xml'
$modulePath = Join-Path $runtimeRoot 'Modules\EnterpriseAutopilotBranding.psm1'
$exitCode = 1
$config = $null
$packageVersion = '0.0.0'
$configHash = $null
$interactiveUser = $null
$attempt = 1
$debloatSummary = $null
$steps = New-Object System.Collections.Generic.List[object]
$script:nonCriticalFailureCount = 0

function Invoke-PostEnrollStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter()][bool]$ContinueOnError = $false
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    Write-EabLog -Component 'PostEnroll' -Message "START: $Name"
    try {
        & $Action
        $timer.Stop()
        $steps.Add([pscustomobject]@{ Name = $Name; Status = 'Success'; DurationMilliseconds = $timer.ElapsedMilliseconds; Error = $null })
        Write-EabLog -Component 'PostEnroll' -Message "SUCCESS: $Name ($($timer.Elapsed.TotalSeconds.ToString('0.0')) seconds)"
    }
    catch {
        $timer.Stop()
        $message = $_.Exception.Message
        $steps.Add([pscustomobject]@{ Name = $Name; Status = 'Failed'; DurationMilliseconds = $timer.ElapsedMilliseconds; Error = $message })
        Write-EabLog -Level ERROR -Component 'PostEnroll' -Message "FAILED: $Name - $message"
        if (-not $ContinueOnError) {
            throw
        }
        $script:nonCriticalFailureCount++
    }
}

function Write-PostEnrollState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Result,
        [Parameter()][AllowNull()][string]$ErrorMessage
    )

    $state = [ordered]@{
        Product         = $productName
        PackageVersion  = $packageVersion
        ConfigHash      = $configHash
        Result          = $Result
        Attempt         = $attempt
        CompletedUtc    = [DateTime]::UtcNow.ToString('o')
        ComputerName    = $env:COMPUTERNAME
        InteractiveUser = $interactiveUser
        AuditOnly       = [bool]$AuditOnly
        Error           = $ErrorMessage
        Steps           = @($steps)
        Debloat         = $debloatSummary
    }

    Write-EabStateFile -Path $statePath -State $state
}

try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    Initialize-EabLogging -LogDirectory $logDirectory -Component 'PostEnroll'
    Write-EabLog -Component 'PostEnroll' -Message 'Starting delayed post-enrollment processing.'

    $config = Import-EabConfiguration -Path $configPath
    $packageVersion = [string]$config.PackageVersion
    $configHash = Get-EabFileHashValue -Path $configPath

    $existingState = Read-EabStateFile -Path $statePath
    if ($null -ne $existingState -and [string]$existingState.PackageVersion -eq $packageVersion -and [string]$existingState.ConfigHash -eq $configHash) {
        $attempt = [int]$existingState.Attempt + 1
        if (-not $Force -and [string]$existingState.Result -in @('Success', 'SuccessWithWarnings')) {
            $runOnce = Get-EabBoolean -Value $config.PostEnroll.RunOnce -Default $true
            if ($runOnce) {
                Write-EabLog -Component 'PostEnroll' -Message 'This package version and configuration already completed post-enrollment processing; removing the one-time task.'
                Unregister-EabPostEnrollTask -Config $config -IgnoreMissing
                exit 0
            }

            Write-EabLog -Component 'PostEnroll' -Message 'RunOnce is disabled; the successful post-enrollment workflow will run again for this sign-in.'
        }
    }

    if (-not (Test-EabIsAdministrator)) {
        throw 'Post-enrollment processing must run elevated, normally as SYSTEM.'
    }

    $waitSeconds = [int]$config.PostEnroll.WaitForInteractiveUserSeconds
    $waitedSeconds = 0
    while ($null -eq $interactiveUser) {
        $interactiveUser = Get-EabInteractiveUser
        if ($null -ne $interactiveUser -or $waitedSeconds -ge $waitSeconds) {
            break
        }

        $sleepSeconds = [Math]::Min(5, $waitSeconds - $waitedSeconds)
        Start-Sleep -Seconds $sleepSeconds
        $waitedSeconds += $sleepSeconds
    }

    if ($null -eq $interactiveUser) {
        Write-EabLog -Level WARN -Component 'PostEnroll' -Message "No interactive user was detected after $waitSeconds seconds. System-only post-enrollment steps will continue."
    }
    else {
        Write-EabLog -Component 'PostEnroll' -Message "Interactive user: $($interactiveUser.UserName); SID: $($interactiveUser.Sid)."
    }

    Invoke-PostEnrollStep -Name 'First-logon debloat pass' -ContinueOnError:(-not (Get-EabBoolean -Value $config.Debloat.FailOnError -Default $false)) -Action {
        $script:debloatSummary = Invoke-EabDebloat -Config $config -Phase PostEnroll -AuditOnly:$AuditOnly
        Write-EabStateFile -Path (Join-Path $stateDirectory 'Debloat-PostEnroll.json') -State $script:debloatSummary
        if ([int]$script:debloatSummary.FailureCount -gt 0) {
            throw "The first-logon debloat report contains $($script:debloatSummary.FailureCount) failed or unsupported action(s)."
        }
    }

    $customSettings = $config.PostEnroll.CustomScript
    if ($null -ne $customSettings -and (Get-EabBoolean -Value $customSettings.Enabled -Default $false)) {
        $continueOnCustomError = Get-EabBoolean -Value $customSettings.ContinueOnError -Default $false
        Invoke-PostEnrollStep -Name 'Organization custom post-enrollment hook' -ContinueOnError:$continueOnCustomError -Action {
            $customScriptPath = Resolve-EabChildPath -Path ([string]$customSettings.Path) -BasePath $runtimeRoot
            if (-not (Test-Path -LiteralPath $customScriptPath -PathType Leaf)) {
                throw "Configured custom post-enrollment script '$customScriptPath' does not exist."
            }

            $customParameters = @{
                ConfigurationPath = $configPath
                LogDirectory      = $logDirectory
                InteractiveUser   = if ($null -ne $interactiveUser) { $interactiveUser.UserName } else { $null }
                InteractiveUserSid = if ($null -ne $interactiveUser) { $interactiveUser.Sid } else { $null }
            }
            & $customScriptPath @customParameters
        }
    }

    $postEnrollResult = if ($script:nonCriticalFailureCount -gt 0) { 'SuccessWithWarnings' } else { 'Success' }
    Write-PostEnrollState -Result $postEnrollResult
    Write-EabLog -Component 'PostEnroll' -Message "Post-enrollment processing completed with result '$postEnrollResult'."

    if (Get-EabBoolean -Value $config.PostEnroll.RunOnce -Default $true) {
        Unregister-EabPostEnrollTask -Config $config -IgnoreMissing
    }
    $exitCode = 0
}
catch {
    $message = $_.Exception.Message
    try {
        if (Get-Command -Name Write-EabLog -ErrorAction SilentlyContinue) {
            Write-EabLog -Level ERROR -Component 'PostEnroll' -Message "Post-enrollment processing failed on attempt $attempt: $message"
        }
        if (Get-Command -Name Write-EabStateFile -ErrorAction SilentlyContinue) {
            Write-PostEnrollState -Result 'Failed' -ErrorMessage $message
        }

        if ($null -ne $config) {
            $maximumAttempts = [int]$config.PostEnroll.MaximumAttempts
            if ($attempt -ge $maximumAttempts -and (Get-EabBoolean -Value $config.PostEnroll.UnregisterAfterMaximumAttempts -Default $true)) {
                Write-EabLog -Level WARN -Component 'PostEnroll' -Message "Maximum attempt count $maximumAttempts reached; unregistering the post-enrollment task."
                Unregister-EabPostEnrollTask -Config $config -IgnoreMissing
            }
        }
    }
    catch {
        Write-Warning "Unable to finish post-enrollment failure handling: $($_.Exception.Message)"
    }
    $exitCode = 1
}

exit $exitCode
