#requires -version 5.1
<#
.SYNOPSIS
    Recurring local remediation runner.

.DESCRIPTION
    This is the script the scheduled task runs. Customize Test-Compliance and Invoke-Remediation.
    Keep secrets and personal data out of this script and out of logs.

.NOTES
    Runs as SYSTEM when installed by Install-ScheduledRemediation.ps1.
#>

[CmdletBinding()]
param(
    [string]$CompanyName = 'Contoso',
    [string]$AppName = 'ScheduledRemediation',
    [string]$Version = '1.0.0'
)

#region Relaunch 64-bit PowerShell if needed
if ($env:PROCESSOR_ARCHITEW6432 -and $PSHOME -like '*SysWOW64*') {
    $sysNativePowerShell = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    $argList = @(
        '-ExecutionPolicy', 'Bypass',
        '-NoProfile',
        '-File', "`"$PSCommandPath`""
    )

    foreach ($key in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$key]
        $argList += "-$key"
        $argList += "`"$value`""
    }

    Start-Process -FilePath $sysNativePowerShell -ArgumentList $argList -Wait
    exit $LASTEXITCODE
}
#endregion

$InstallRoot = Join-Path -Path $env:ProgramData -ChildPath "$CompanyName\$AppName"
$LogRoot = Join-Path -Path $InstallRoot -ChildPath 'Logs'
$LogFile = Join-Path -Path $LogRoot -ChildPath 'RemediationRunner.log'
$RegistryPath = "HKLM:\SOFTWARE\$CompanyName\$AppName"
$MutexName = "Global\$CompanyName-$AppName-Runner"

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    if (-not (Test-Path -LiteralPath $LogRoot)) {
        New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
    }

    # Basic log rotation at ~2 MB.
    if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 2MB)) {
        $archive = Join-Path -Path $LogRoot -ChildPath "RemediationRunner-$((Get-Date).ToString('yyyyMMdd-HHmmss')).log"
        Move-Item -LiteralPath $LogFile -Destination $archive -Force
    }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $LogFile -Value "[$timestamp][$Level] $Message"
}

function Set-RunnerStatus {
    param(
        [string]$LastResult,
        [int]$LastExitCode,
        [string]$LastMessage
    )

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }

    New-ItemProperty -Path $RegistryPath -Name 'Version' -Value $Version -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'LastRunUtc' -Value ((Get-Date).ToUniversalTime().ToString('o')) -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'LastResult' -Value $LastResult -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'LastExitCode' -Value $LastExitCode -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name 'LastMessage' -Value $LastMessage -PropertyType String -Force | Out-Null
}

function Test-Compliance {
    <#
        Replace this with your detection logic.

        Return:
          $true  = device is already compliant; no remediation needed.
          $false = issue detected; Invoke-Remediation will run.

        Example ideas:
          - Check a registry value.
          - Check if a local admin group contains/doesn't contain an account.
          - Check if a service is running.
          - Check if a config file exists and has the expected content.
    #>

    # Demo placeholder: checks for a local marker file.
    # Replace this entire block with your own detection logic.
    $markerFile = Join-Path -Path $InstallRoot -ChildPath 'ExampleHealthy.marker'
    return (Test-Path -LiteralPath $markerFile)
}

function Invoke-Remediation {
    <#
        Replace this with your repair logic.

        Throw an error if remediation fails. The script will log the failure and exit 1.
    #>

    # Demo placeholder: creates a local marker file so the next run is compliant.
    # Replace this entire block with your own remediation logic.
    $markerFile = Join-Path -Path $InstallRoot -ChildPath 'ExampleHealthy.marker'
    Set-Content -LiteralPath $markerFile -Value "Created by $AppName at $((Get-Date).ToString('s'))" -Force
}

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($false, $MutexName, [ref]$createdNew)

try {
    if (-not $mutex.WaitOne(0)) {
        Write-Log 'Another remediation runner instance is already active. Exiting.'
        Set-RunnerStatus -LastResult 'Skipped' -LastExitCode 0 -LastMessage 'Another instance was already active.'
        exit 0
    }

    Write-Log "Starting remediation runner. Version=$Version User=$([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

    $isCompliant = Test-Compliance
    if ($isCompliant) {
        Write-Log 'Detection result: compliant. No remediation needed.'
        Set-RunnerStatus -LastResult 'Compliant' -LastExitCode 0 -LastMessage 'No remediation needed.'
        exit 0
    }

    Write-Log 'Detection result: not compliant. Running remediation.' -Level WARN
    Invoke-Remediation

    $isCompliantAfterRemediation = Test-Compliance
    if ($isCompliantAfterRemediation) {
        Write-Log 'Remediation completed and post-check passed.'
        Set-RunnerStatus -LastResult 'Remediated' -LastExitCode 0 -LastMessage 'Remediation completed successfully.'
        exit 0
    }

    throw 'Remediation completed, but post-check still reports non-compliance.'
}
catch {
    $message = $_.Exception.Message
    Write-Log -Message "Runner failed: $message" -Level ERROR
    Set-RunnerStatus -LastResult 'Failed' -LastExitCode 1 -LastMessage $message
    exit 1
}
finally {
    if ($mutex) {
        try { [void]$mutex.ReleaseMutex() } catch {}
        $mutex.Dispose()
    }
}
