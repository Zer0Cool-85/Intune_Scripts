#requires -Version 5.1

<#
.SYNOPSIS
Runs the stateful first-login onboarding workflow.

.DESCRIPTION
Executes manifest-defined device and user steps under SYSTEM after an eligible interactive user
signs in. When hosted by PSAppDeployToolkit 4.1.8, progress is rendered securely in the user's
session without ServiceUI. Each step is versioned and persisted immediately, allowing a failed or
interrupted workflow to resume at the first incomplete critical step.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$AuditOnly,

    [Parameter()]
    [ValidateSet('Auto', 'Psadt', 'None')]
    [string]$UiMode = 'Auto',

    [Parameter()]
    [switch]$ReturnExitCode
)

if ($env:PROCESSOR_ARCHITEW6432) {
    if ($UiMode -eq 'Psadt') {
        throw 'The PSADT-hosted post-enrollment worker must run in a native 64-bit process.'
    }

    $nativePowerShell = Join-Path $env:SystemRoot 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $nativePowerShell) {
        $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-UiMode', $UiMode)
        if ($Force) { $arguments += '-Force' }
        if ($AuditOnly) { $arguments += '-AuditOnly' }
        $process = Start-Process -FilePath $nativePowerShell -ArgumentList $arguments -Wait -PassThru
        if ($ReturnExitCode) { return [int]$process.ExitCode }
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
$postEnrollStateDirectory = Join-Path $stateDirectory 'PostEnroll'
$summaryStatePath = Join-Path $stateDirectory 'PostEnrollState.json'
$deviceStatePath = Join-Path $postEnrollStateDirectory 'Device.json'
$configPath = Join-Path $runtimeRoot 'Config.xml'
$modulePath = Join-Path $runtimeRoot 'Modules\EnterpriseAutopilotBranding.psm1'

$script:Config = $null
$script:PackageVersion = '0.0.0'
$script:ConfigHash = $null
$script:InteractiveUser = $null
$script:UserStatePath = $null
$script:DeviceState = $null
$script:UserState = $null
$script:ConfiguredSteps = @()
$script:RunResults = New-Object System.Collections.Generic.List[object]
$script:UiStatuses = @{}
$script:UiAvailable = $false
$script:Attempt = 1
$script:WarningCount = 0
$script:RestartRequired = $false
$script:Mutex = $null
$script:MutexOwned = $false
$exitCode = 1

function Complete-PostEnrollInvocation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Code)

    if ($ReturnExitCode) {
        return $Code
    }
    exit $Code
}

function Get-PostEnrollStepProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Step,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowNull()][object]$Default
    )

    $property = $Step.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return $Default
    }
    return $property.Value
}

function Test-PostEnrollUserEligibility {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object]$User)

    if ($null -eq $User -or [string]::IsNullOrWhiteSpace([string]$User.UserName)) {
        return $false
    }

    $fullName = [string]$User.UserName
    $leafName = if ($fullName -like '*\*') { $fullName.Split('\')[-1] } else { $fullName }
    if ($leafName.EndsWith('$')) {
        return $false
    }

    foreach ($rule in @($script:Config.PostEnroll.ExcludedUsers.User)) {
        if (-not (Get-EabBoolean -Value $rule.Enabled -Default $true)) {
            continue
        }

        $pattern = [string]$rule.Pattern
        if ($fullName -like $pattern -or $leafName -like $pattern) {
            Write-EabLog -Component 'PostEnroll' -Message "Interactive account '$fullName' matched exclusion '$pattern'."
            return $false
        }
    }

    return $true
}

function Get-ScopedPostEnrollState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Device', 'User')][string]$Scope)

    if ($Scope -eq 'Device') { return $script:DeviceState }
    return $script:UserState
}

function Get-SavedPostEnrollStepResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Step)

    $scope = [string]$Step.Scope
    $state = Get-ScopedPostEnrollState -Scope $scope
    if ($null -eq $state -or $null -eq $state.PSObject.Properties['Steps']) {
        return $null
    }

    $stepId = [string]$Step.Id
    $stepVersion = [string]$Step.Version
    $matches = @($state.Steps | Where-Object {
        [string]$_.Id -eq $stepId -and [string]$_.Version -eq $stepVersion
    } | Select-Object -Last 1)
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Test-PostEnrollStepSatisfied {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Step)

    if ($Force) { return $false }
    $saved = Get-SavedPostEnrollStepResult -Step $Step
    if ($null -eq $saved) { return $false }
    return [string]$saved.Status -in @('Success', 'Warning')
}

function Set-ScopedPostEnrollStepResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Step,
        [Parameter(Mandatory)][object]$Result
    )

    $scope = [string]$Step.Scope
    $path = if ($scope -eq 'Device') { $deviceStatePath } else { $script:UserStatePath }
    if ([string]::IsNullOrWhiteSpace([string]$path)) {
        throw "No state path is available for $scope step '$($Step.Id)'."
    }

    $currentState = Get-ScopedPostEnrollState -Scope $scope
    $existingResults = @()
    if ($null -ne $currentState -and $null -ne $currentState.PSObject.Properties['Steps']) {
        $existingResults = @($currentState.Steps | Where-Object { [string]$_.Id -ne [string]$Step.Id })
    }

    $state = [ordered]@{
        Product        = $productName
        Scope          = $scope
        PackageVersion = $script:PackageVersion
        ConfigHash     = $script:ConfigHash
        UpdatedUtc     = [DateTime]::UtcNow.ToString('o')
        ComputerName   = $env:COMPUTERNAME
        UserName       = if ($scope -eq 'User') { [string]$script:InteractiveUser.UserName } else { $null }
        UserSid        = if ($scope -eq 'User') { [string]$script:InteractiveUser.Sid } else { $null }
        Steps          = @($existingResults) + @($Result)
    }

    Write-EabStateFile -Path $path -State $state
    if ($scope -eq 'Device') { $script:DeviceState = [pscustomobject]$state }
    else { $script:UserState = [pscustomobject]$state }
}

function Write-PostEnrollSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Result,
        [Parameter()][AllowNull()][string]$ErrorMessage
    )

    $summary = [ordered]@{
        Product          = $productName
        PackageVersion   = $script:PackageVersion
        ConfigHash       = $script:ConfigHash
        Result           = $Result
        Attempt          = $script:Attempt
        UpdatedUtc       = [DateTime]::UtcNow.ToString('o')
        ComputerName     = $env:COMPUTERNAME
        InteractiveUser  = if ($null -ne $script:InteractiveUser) { [string]$script:InteractiveUser.UserName } else { $null }
        InteractiveSid   = if ($null -ne $script:InteractiveUser) { [string]$script:InteractiveUser.Sid } else { $null }
        AuditOnly        = [bool]$AuditOnly
        WarningCount     = $script:WarningCount
        RestartRequired  = $script:RestartRequired
        Error            = $ErrorMessage
        Steps            = @($script:RunResults)
    }
    Write-EabStateFile -Path $summaryStatePath -State $summary
}

function Update-PostEnrollUi {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][string]$CurrentStepId)

    if (-not $script:UiAvailable) { return }

    $completedCount = 0
    $lines = foreach ($step in $script:ConfiguredSteps) {
        $id = [string]$step.Id
        $displayName = [string]$step.DisplayName
        $status = if ($script:UiStatuses.ContainsKey($id)) { [string]$script:UiStatuses[$id] } else { 'Pending' }
        switch ($status) {
            'Success' { $completedCount++; "[x] $displayName" }
            'Warning' { $completedCount++; "[!] $displayName" }
            'Running' { "[>] $displayName" }
            'Failed'  { "[!] $displayName" }
            default   { "[ ] $displayName" }
        }
    }

    $total = [Math]::Max(1, $script:ConfiguredSteps.Count)
    $currentIndex = if ([string]::IsNullOrWhiteSpace($CurrentStepId)) {
        [Math]::Min($total, $completedCount + 1)
    }
    else {
        $foundIndex = [Array]::IndexOf(@($script:ConfiguredSteps | ForEach-Object { [string]$_.Id }), $CurrentStepId)
        if ($foundIndex -lt 0) { [Math]::Min($total, $completedCount + 1) } else { $foundIndex + 1 }
    }

    $currentStep = @($script:ConfiguredSteps | Where-Object { [string]$_.Id -eq $CurrentStepId } | Select-Object -First 1)
    $headline = if ($currentStep.Count -gt 0) {
        "Step $currentIndex of $total - $([string]$currentStep[0].DisplayName)"
    }
    else {
        'Finalizing your device setup'
    }

    $progressParameters = @{
        StatusMessage       = $headline
        StatusMessageDetail = ($lines -join "`n")
        StatusBarPercentage = [double][Math]::Round(($completedCount / $total) * 100, 0)
    }
    if (Get-EabBoolean -Value $script:Config.PostEnroll.UiAllowMove -Default $true) {
        $progressParameters.AllowMove = $true
    }
    if (-not (Get-EabBoolean -Value $script:Config.PostEnroll.UiTopMost -Default $true)) {
        $progressParameters.NotTopMost = $true
    }

    Show-ADTInstallationProgress @progressParameters
}

function Close-PostEnrollUi {
    [CmdletBinding()]
    param()

    if ($script:UiAvailable) {
        try { Close-ADTInstallationProgress } catch {}
    }
}

function Show-PostEnrollResultPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Success', 'Failed')][string]$Result,
        [Parameter()][AllowNull()][string]$ErrorMessage
    )

    if (-not $script:UiAvailable) { return }
    Close-PostEnrollUi

    if ($Result -eq 'Failed') {
        Show-ADTInstallationPrompt -Message 'Device setup could not finish. It will automatically retry at a later sign-in. If the problem continues, contact IT support.' -ButtonRightText 'OK' -Icon Error -Timeout 180 -NoExitOnTimeout | Out-Null
        return
    }

    if (-not (Get-EabBoolean -Value $script:Config.PostEnroll.ShowCompletionPrompt -Default $true)) {
        return
    }

    if ($script:RestartRequired -and (Get-EabBoolean -Value $script:Config.PostEnroll.ShowRestartPrompt -Default $true)) {
        $response = Show-ADTInstallationPrompt -Message 'Your device setup is complete. A restart is recommended to finish applying all changes.' -ButtonLeftText 'Restart later' -ButtonRightText 'Restart now' -Icon Information -Timeout 300 -NoExitOnTimeout
        if ([string]$response -eq 'Restart now') {
            $shutdown = Join-Path $env:SystemRoot 'System32\shutdown.exe'
            Invoke-EabNativeProcess -FilePath $shutdown -ArgumentString '/r /t 15 /c "Your organization finished setting up this device."' -TimeoutSeconds 30 | Out-Null
        }
        return
    }

    Show-ADTInstallationPrompt -Message 'Your device setup is complete and the computer is ready to use.' -ButtonRightText 'OK' -Icon Information -Timeout 180 -NoExitOnTimeout | Out-Null
}

function Wait-PostEnrollFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $resolvedPath = Resolve-EabPath -Path $Path
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $resolvedPath) {
            return [pscustomobject]@{ ExitCode = 0; RestartRequired = $false; DetectedPath = $resolvedPath }
        }
        Start-Sleep -Seconds 5
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Detection path '$resolvedPath' was not present after $TimeoutSeconds seconds."
}

function Wait-PostEnrollApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DisplayNamePattern,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $match = @(Get-EabClassicApplicationInventory | Where-Object { [string]$_.DisplayName -like $DisplayNamePattern } | Select-Object -First 1)
        if ($match.Count -gt 0) {
            return [pscustomobject]@{ ExitCode = 0; RestartRequired = $false; DetectedApplication = [string]$match[0].DisplayName }
        }
        Start-Sleep -Seconds 5
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Application '$DisplayNamePattern' was not detected after $TimeoutSeconds seconds."
}

function Invoke-PostEnrollPowerShellStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Step)

    $scriptPath = Resolve-EabChildPath -Path ([string]$Step.Path) -BasePath $runtimeRoot
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Configured onboarding script '$scriptPath' does not exist."
    }

    foreach ($value in @($scriptPath, $configPath, $logDirectory, $stateDirectory, [string]$script:InteractiveUser.UserName, [string]$script:InteractiveUser.Sid)) {
        if ([string]$value -match '"') {
            throw 'Onboarding script arguments cannot contain a double-quote character.'
        }
    }

    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argumentString = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`" -ConfigurationPath `"$configPath`" -LogDirectory `"$logDirectory`" -StateDirectory `"$stateDirectory`" -InteractiveUser `"$([string]$script:InteractiveUser.UserName)`" -InteractiveUserSid `"$([string]$script:InteractiveUser.Sid)`""
    $extraArguments = [string](Get-PostEnrollStepProperty -Step $Step -Name 'Arguments' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($extraArguments)) {
        $argumentString = "$argumentString $extraArguments"
    }

    $timeoutSeconds = [int]$Step.TimeoutSeconds
    $scope = [string]$Step.Scope
    if ($scope -eq 'User') {
        if (-not (Get-Command -Name Start-ADTProcessAsUser -ErrorAction SilentlyContinue)) {
            throw "User-scoped step '$($Step.Id)' requires the PSADT host."
        }

        $result = Start-ADTProcessAsUser -Username ([string]$script:InteractiveUser.UserName) -FilePath $powerShellPath -ArgumentList $argumentString -WindowStyle Hidden -Timeout (New-TimeSpan -Seconds $timeoutSeconds) -SuccessExitCodes @(0) -RebootExitCodes @(1641, 3010) -PassThru
        $exitCode = [int]$result.ExitCode
    }
    else {
        $exitCode = Invoke-EabNativeProcess -FilePath $powerShellPath -ArgumentString $argumentString -AcceptedExitCodes @(0, 1641, 3010) -TimeoutSeconds $timeoutSeconds
    }

    return [pscustomobject]@{
        ExitCode        = $exitCode
        RestartRequired = $exitCode -in @(1641, 3010)
    }
}

function Invoke-ConfiguredPostEnrollAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Step)

    $handler = [string]$Step.Handler
    switch ($handler) {
        'Debloat' {
            $summary = Invoke-EabDebloat -Config $script:Config -Phase PostEnroll -AuditOnly:$AuditOnly
            Write-EabStateFile -Path (Join-Path $stateDirectory 'Debloat-PostEnroll.json') -State $summary
            if ([int]$summary.FailureCount -gt 0) {
                throw "The first-login debloat report contains $($summary.FailureCount) failed or unsupported action(s)."
            }
            return [pscustomobject]@{ ExitCode = 0; RestartRequired = ([int]$summary.RestartRequiredCount -gt 0) }
        }
        'PowerShell' {
            return Invoke-PostEnrollPowerShellStep -Step $Step
        }
        'WaitForFile' {
            return Wait-PostEnrollFile -Path ([string]$Step.DetectionPath) -TimeoutSeconds ([int]$Step.TimeoutSeconds)
        }
        'WaitForApplication' {
            return Wait-PostEnrollApplication -DisplayNamePattern ([string]$Step.DetectionNamePattern) -TimeoutSeconds ([int]$Step.TimeoutSeconds)
        }
        default {
            throw "Unsupported onboarding handler '$handler' for step '$($Step.Id)'."
        }
    }
}

function Test-AllPostEnrollStepsSatisfied {
    [CmdletBinding()]
    param()

    foreach ($step in $script:ConfiguredSteps) {
        if (-not (Test-PostEnrollStepSatisfied -Step $step)) { return $false }
    }
    return $true
}

try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    Initialize-EabLogging -LogDirectory $logDirectory -Component 'PostEnroll'

    $createdNew = $false
    $script:Mutex = [System.Threading.Mutex]::new($true, 'Global\EnterpriseAutopilotBranding-PostEnroll', [ref]$createdNew)
    $script:MutexOwned = $createdNew
    if (-not $createdNew) {
        Write-EabLog -Level WARN -Component 'PostEnroll' -Message 'Another post-enrollment instance is already running; this invocation will exit.'
        $exitCode = 0
    }
    else {
        Write-EabLog -Component 'PostEnroll' -Message 'Starting manifest-driven post-enrollment processing.'
        $script:Config = Import-EabConfiguration -Path $configPath
        $script:PackageVersion = [string]$script:Config.PackageVersion
        $script:ConfigHash = Get-EabFileHashValue -Path $configPath
        $script:ConfiguredSteps = @($script:Config.PostEnroll.Steps.Step | Where-Object {
            Get-EabBoolean -Value $_.Enabled -Default $true
        })

        $existingSummary = Read-EabStateFile -Path $summaryStatePath
        if ($null -ne $existingSummary -and $null -ne $existingSummary.PSObject.Properties['Attempt']) {
            $script:Attempt = [int]$existingSummary.Attempt + 1
        }

        $waitSeconds = [int]$script:Config.PostEnroll.WaitForInteractiveUserSeconds
        $waitedSeconds = 0
        while ($null -eq $script:InteractiveUser) {
            $script:InteractiveUser = Get-EabInteractiveUser
            if ($null -ne $script:InteractiveUser -or $waitedSeconds -ge $waitSeconds) { break }
            $sleepSeconds = [Math]::Min(5, $waitSeconds - $waitedSeconds)
            Start-Sleep -Seconds $sleepSeconds
            $waitedSeconds += $sleepSeconds
        }

        if (-not (Test-PostEnrollUserEligibility -User $script:InteractiveUser)) {
            Write-EabLog -Component 'PostEnroll' -Message 'No eligible interactive user is signed in. The task will remain registered for a later logon.'
            Write-PostEnrollSummary -Result 'DeferredNoEligibleUser'
            $exitCode = 0
        }
        else {
            Write-EabLog -Component 'PostEnroll' -Message "Eligible interactive user: $($script:InteractiveUser.UserName); SID: $($script:InteractiveUser.Sid)."
            $safeSid = if ([string]::IsNullOrWhiteSpace([string]$script:InteractiveUser.Sid)) {
                ([string]$script:InteractiveUser.UserName -replace '[^A-Za-z0-9_.-]', '_')
            }
            else { [string]$script:InteractiveUser.Sid }
            $script:UserStatePath = Join-Path (Join-Path $postEnrollStateDirectory 'Users') "$safeSid.json"
            $script:DeviceState = Read-EabStateFile -Path $deviceStatePath
            $script:UserState = Read-EabStateFile -Path $script:UserStatePath

            $script:UiAvailable = $UiMode -ne 'None' -and
                $null -ne (Get-Command -Name Show-ADTInstallationProgress -ErrorAction SilentlyContinue) -and
                (Get-EabBoolean -Value $script:Config.PostEnroll.UiEnabled -Default $true)

            foreach ($step in $script:ConfiguredSteps) {
                $script:UiStatuses[[string]$step.Id] = if (Test-PostEnrollStepSatisfied -Step $step) { 'Success' } else { 'Pending' }
            }

            if (Test-AllPostEnrollStepsSatisfied) {
                Write-EabLog -Component 'PostEnroll' -Message 'Every configured onboarding step version already completed successfully.'
                if (Get-EabBoolean -Value $script:Config.PostEnroll.RunOnce -Default $true) {
                    Unregister-EabPostEnrollTask -Config $script:Config -IgnoreMissing
                }
                $exitCode = 0
            }
            else {
                foreach ($step in $script:ConfiguredSteps) {
                    $stepId = [string]$step.Id
                    $stepVersion = [string]$step.Version
                    $displayName = [string]$step.DisplayName
                    $critical = Get-EabBoolean -Value $step.Critical -Default $true
                    if (Test-PostEnrollStepSatisfied -Step $step) {
                        Write-EabLog -Component 'PostEnroll' -Message "SKIP: $displayName ($stepId v$stepVersion) already completed."
                        $script:RunResults.Add([pscustomobject]@{ Id = $stepId; Version = $stepVersion; DisplayName = $displayName; Scope = [string]$step.Scope; Status = 'SkippedAlreadyComplete'; Critical = $critical; Error = $null })
                        continue
                    }

                    $script:UiStatuses[$stepId] = 'Running'
                    Update-PostEnrollUi -CurrentStepId $stepId
                    $timer = [Diagnostics.Stopwatch]::StartNew()
                    $startedUtc = [DateTime]::UtcNow.ToString('o')
                    Write-EabLog -Component 'PostEnroll' -Message "START: $displayName ($stepId v$stepVersion; scope $($step.Scope); handler $($step.Handler))."

                    try {
                        $handlerOutput = @(Invoke-ConfiguredPostEnrollAction -Step $step)
                        $handlerResult = if ($handlerOutput.Count -gt 0) { $handlerOutput[-1] } else { $null }
                        $timer.Stop()
                        $restartRequired = $false
                        $stepExitCode = 0
                        if ($null -ne $handlerResult) {
                            if ($null -ne $handlerResult.PSObject.Properties['RestartRequired']) {
                                $restartRequired = Get-EabBoolean -Value $handlerResult.RestartRequired -Default $false
                            }
                            if ($null -ne $handlerResult.PSObject.Properties['ExitCode']) {
                                $stepExitCode = [int]$handlerResult.ExitCode
                            }
                        }

                        $stepResult = [pscustomobject]@{
                            Id = $stepId; Version = $stepVersion; DisplayName = $displayName; Scope = [string]$step.Scope
                            Status = 'Success'; Critical = $critical; Attempt = $script:Attempt; StartedUtc = $startedUtc
                            CompletedUtc = [DateTime]::UtcNow.ToString('o'); DurationMilliseconds = $timer.ElapsedMilliseconds
                            ExitCode = $stepExitCode; RestartRequired = $restartRequired; Error = $null
                        }
                        Set-ScopedPostEnrollStepResult -Step $step -Result $stepResult
                        $script:RunResults.Add($stepResult)
                        $script:UiStatuses[$stepId] = 'Success'
                        if ($restartRequired) { $script:RestartRequired = $true }
                        Write-EabLog -Component 'PostEnroll' -Message "SUCCESS: $displayName ($($timer.Elapsed.TotalSeconds.ToString('0.0')) seconds)."
                    }
                    catch {
                        $timer.Stop()
                        $message = $_.Exception.Message
                        $status = if ($critical) { 'Failed' } else { 'Warning' }
                        $stepResult = [pscustomobject]@{
                            Id = $stepId; Version = $stepVersion; DisplayName = $displayName; Scope = [string]$step.Scope
                            Status = $status; Critical = $critical; Attempt = $script:Attempt; StartedUtc = $startedUtc
                            CompletedUtc = [DateTime]::UtcNow.ToString('o'); DurationMilliseconds = $timer.ElapsedMilliseconds
                            ExitCode = $null; RestartRequired = $false; Error = $message
                        }
                        Set-ScopedPostEnrollStepResult -Step $step -Result $stepResult
                        $script:RunResults.Add($stepResult)
                        $script:UiStatuses[$stepId] = $status
                        Write-EabLog -Level $(if ($critical) { 'ERROR' } else { 'WARN' }) -Component 'PostEnroll' -Message "$status`: $displayName - $message"
                        if ($critical) { throw }
                        $script:WarningCount++
                    }

                    Update-PostEnrollUi -CurrentStepId $stepId
                }

                Update-PostEnrollUi
                $result = if ($script:WarningCount -gt 0) { 'SuccessWithWarnings' } else { 'Success' }
                Write-PostEnrollSummary -Result $result
                Write-EabLog -Component 'PostEnroll' -Message "Post-enrollment processing completed with result '$result'."
                if (Get-EabBoolean -Value $script:Config.PostEnroll.RunOnce -Default $true) {
                    Unregister-EabPostEnrollTask -Config $script:Config -IgnoreMissing
                }
                Show-PostEnrollResultPrompt -Result Success
                $exitCode = 0
            }
        }
    }
}
catch {
    $message = $_.Exception.Message
    try {
        if (Get-Command -Name Write-EabLog -ErrorAction SilentlyContinue) {
            Write-EabLog -Level ERROR -Component 'PostEnroll' -Message "Post-enrollment processing failed on attempt $($script:Attempt): $message"
        }
        if (Get-Command -Name Write-EabStateFile -ErrorAction SilentlyContinue) {
            Write-PostEnrollSummary -Result 'Failed' -ErrorMessage $message
        }
        Show-PostEnrollResultPrompt -Result Failed -ErrorMessage $message

        if ($null -ne $script:Config) {
            $maximumAttempts = [int]$script:Config.PostEnroll.MaximumAttempts
            if ($script:Attempt -ge $maximumAttempts -and (Get-EabBoolean -Value $script:Config.PostEnroll.UnregisterAfterMaximumAttempts -Default $false)) {
                Write-EabLog -Level WARN -Component 'PostEnroll' -Message "Maximum attempt count $maximumAttempts reached; unregistering the post-enrollment task as configured."
                Unregister-EabPostEnrollTask -Config $script:Config -IgnoreMissing
            }
        }
    }
    catch {
        Write-Warning "Unable to finish post-enrollment failure handling: $($_.Exception.Message)"
    }
    $exitCode = 1
}
finally {
    Close-PostEnrollUi
    if ($script:MutexOwned -and $null -ne $script:Mutex) {
        try { $script:Mutex.ReleaseMutex() } catch {}
    }
    if ($null -ne $script:Mutex) {
        try { $script:Mutex.Dispose() } catch {}
    }
}

Complete-PostEnrollInvocation -Code $exitCode
