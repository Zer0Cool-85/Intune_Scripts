#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Writes an embedded PowerShell script and registers a SYSTEM scheduled task.
.NOTES
Upload this file to Intune > Devices > Scripts and remediations > Platform scripts.
  Run this script using the logged on credentials: No
  Enforce script signature check: No for this unsigned example
  Run script in 64-bit PowerShell host: Yes

For local testing, use elevated Windows PowerShell 5.1.
The example worker only writes a transcript. Replace its marked section.
Default schedule: every startup, plus one immediate start when deployed.
Intune reports the deployment script's result, not subsequent task results.
Removing the Intune assignment does not uninstall this local task or script.
#>

$ErrorActionPreference = 'Stop'

# Customize these values. Use a dedicated folder for this task.
$TaskName       = 'Company-DeviceMaintenance'
$InstallFolder  = Join-Path $env:ProgramData 'Company-DeviceMaintenance'
$ScriptPath     = Join-Path $InstallFolder 'Invoke-DeviceMaintenance.ps1'
$RunImmediately = $true

# Single quotes preserve variables until the generated script actually runs.
$ScriptContent = @'
$ErrorActionPreference = 'Stop'
$TranscriptStarted = $false

try {
    # Overwrite the previous transcript to keep only the latest run.
    Start-Transcript -Path (Join-Path $PSScriptRoot 'LastRun.log') -Force | Out-Null
    $TranscriptStarted = $true

    # ----- Put the code you want to run as SYSTEM here -----
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Output ('Started: {0:u} | Running as: {1}' -f (Get-Date), $Identity)

    # Your commands go here.
    # Check exit codes explicitly if you call installers or other executables.

    Write-Output 'Completed successfully.'
    # ----- End of your code -----
}
catch {
    Write-Error -Message $_.ToString() -ErrorAction Continue
    exit 1
}
finally {
    if ($TranscriptStarted) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
}
exit 0
'@

# Prepare a folder writable only by SYSTEM and local Administrators.
# SDDL uses built-in identities, so this also works on non-English Windows.
# O:BA sets the owner to Administrators; D:P disables inherited permissions.
New-Item -Path $InstallFolder -ItemType Directory -Force | Out-Null
if ((Get-Item -LiteralPath $InstallFolder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'The install folder must be a regular directory, not a link or junction.'
}
$FolderAcl = New-Object System.Security.AccessControl.DirectorySecurity
$FolderAcl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
Set-Acl -LiteralPath $InstallFolder -AclObject $FolderAcl

if (Test-Path -LiteralPath $ScriptPath) {
    $ExistingFile = Get-Item -LiteralPath $ScriptPath -Force
    if ($ExistingFile.PSIsContainer -or ($ExistingFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The script path must be a regular file, not a directory or link.'
    }
}

# Write the script, then explicitly protect the file when updating an old copy.
Set-Content -LiteralPath $ScriptPath -Value $ScriptContent -Encoding UTF8 -Force
$FileAcl = New-Object System.Security.AccessControl.FileSecurity
$FileAcl.SetSecurityDescriptorSddlForm('O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)')
Set-Acl -LiteralPath $ScriptPath -AclObject $FileAcl

# Task Scheduler resolves System32 itself; use Windows PowerShell 5.1.
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Action = New-ScheduledTaskAction -Execute $PowerShellExe `
    -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath) `
    -WorkingDirectory $InstallFolder

# Default: run at every computer startup.
$Trigger = New-ScheduledTaskTrigger -AtStartup

# Alternative examples: replace the preceding $Trigger line with one of these.
# $Trigger = New-ScheduledTaskTrigger -AtLogOn
# $Trigger = New-ScheduledTaskTrigger -Daily -At '09:00'
# $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(20)
# For the Once example, set $RunImmediately = $false if you want only the delayed run.

# S-1-5-18 is Local SYSTEM. No password is needed.
$Principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' `
    -LogonType ServiceAccount -RunLevel Highest

$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

# Re-running this installer overwrites the script and updates this same task.
Register-ScheduledTask -TaskName $TaskName -TaskPath '\' `
    -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings `
    -Description 'Runs the locally deployed maintenance script as SYSTEM.' `
    -Force | Out-Null

if ($RunImmediately) {
    # Asynchronous: this requests a start; it does not wait for worker completion.
    Start-ScheduledTask -TaskName $TaskName -TaskPath '\'
}

Write-Output "Deployed $ScriptPath and registered scheduled task $TaskName."
exit 0
