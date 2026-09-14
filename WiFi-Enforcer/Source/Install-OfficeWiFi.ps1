#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    & "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

function Set-ProtectedDirectory {
    param([string]$Path, [switch]$UsersRead)
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Refusing unsafe installation path: $Path" }
        $owner = (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($owner -notin @('S-1-5-18','S-1-5-32-544')) { throw "Existing directory must be owned by SYSTEM or Administrators: $Path" }
        $children = @(Get-ChildItem -LiteralPath $Path -Force -Recurse)
        if (@($children | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
            throw "Refusing a reparse point inside $Path"
        }
    } else { [void](New-Item -ItemType Directory -Path $Path -Force) }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $sddl = 'O:BAG:BAD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
    if ($UsersRead) { $sddl += '(A;OICI;0x1200a9;;;BU)' }
    $acl.SetSecurityDescriptorSddlForm($sddl)
    Set-Acl -LiteralPath $Path -AclObject $acl
    # Reset pre-existing children to inherit only this protected parent ACL.
    foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force -Recurse)) {
        if ($child.PSIsContainer) { $childAcl = New-Object Security.AccessControl.DirectorySecurity }
        else { $childAcl = New-Object Security.AccessControl.FileSecurity }
        $childAcl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        $childAcl.SetAccessRuleProtection($false, $false)
        Set-Acl -LiteralPath $child.FullName -AclObject $childAcl
    }
}

$lock = $null
$transcribing = $false
$task = $null
$oldEnabled = $false
$committed = $false
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as SYSTEM or an elevated administrator.' }
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'This package targets 64-bit Windows.' }
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { throw 'FullLanguage PowerShell is required for the native WLAN helper.' }
    Import-Module (Join-Path $PSScriptRoot 'OfficeWiFi.psm1') -Force
    $paths = Get-OfficePaths
    $config = Read-OfficeConfig -Path (Join-Path $PSScriptRoot 'config.json')
    $payload = @('OfficeWiFi.psm1','NativeWifi.cs','Enforce-OfficeWiFi.ps1','Uninstall-OfficeWiFi.ps1','config.json')
    # Validate before touching an existing deployment.
    foreach ($name in $payload) {
        $path = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing payload: $name" }
        if ($name -match '\.ps(m1|1)$') {
            $parseErrors = $null; $tokens = $null
            [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors.Count -gt 0) { throw "PowerShell syntax errors in $name" }
        }
    }
    Add-Type -Path (Join-Path $PSScriptRoot 'NativeWifi.cs')
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    $folder = $scheduler.GetFolder('\')
    try { $task = $folder.GetTask($paths.TaskName) } catch { $task = $null }
    if ($null -ne $task) {
        $expectedScript = Join-Path $paths.InstallRoot 'Enforce-OfficeWiFi.ps1'
        if ($task.Definition.Actions.Count -ne 1 -or
            $task.Definition.Actions.Item(1).Arguments.IndexOf(('"' + $expectedScript + '"'), [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw 'A different scheduled task already uses the OfficeWiFi-Enforcer name. Resolve that name collision before installing.'
        }
        $oldEnabled = $task.Enabled
        $task.Enabled = $false
        $task.Stop(0)
    }
    Set-ProtectedDirectory -Path $paths.InstallRoot -UsersRead
    Set-ProtectedDirectory -Path $paths.DataRoot
    $lockPath = Join-Path $paths.DataRoot 'run.lock'
    for ($i = 0; $i -lt 10; $i++) {
        try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None); break }
        catch [IO.IOException] { Start-Sleep -Milliseconds 500 }
    }
    if ($null -eq $lock) { throw 'Another installer or enforcement process still holds the runtime lock.' }
    Start-Transcript -Path (Join-Path $paths.DataRoot 'install.log') -Force | Out-Null
    $transcribing = $true
    $hashes = [ordered]@{}
    foreach ($name in $payload) {
        $source = Join-Path $PSScriptRoot $name
        $destination = Join-Path $paths.InstallRoot $name
        if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($destination)) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        $hashes[$name] = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    }
    # COM API: no hand-written task XML, no maximum-date repetition duration.
    $definition = $scheduler.NewTask(0)
    $definition.RegistrationInfo.Description = "Office Wi-Fi enforcement; policy $($config.PolicyVersion)."
    $definition.RegistrationInfo.Author = 'IT'
    $definition.Principal.UserId = 'S-1-5-18'
    $definition.Principal.LogonType = 5 # ServiceAccount
    $definition.Principal.RunLevel = 1 # Highest
    $definition.Settings.Enabled = $true
    $definition.Settings.StartWhenAvailable = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.RunOnlyIfNetworkAvailable = $false
    $definition.Settings.MultipleInstances = 2 # IgnoreNew
    $definition.Settings.ExecutionTimeLimit = 'PT5M'
    $definition.Settings.WakeToRun = $false
    $boot = $definition.Triggers.Create(8)
    $boot.Delay = 'PT1M'
    $logon = $definition.Triggers.Create(9)
    $logon.Delay = 'PT1M'
    $timer = $definition.Triggers.Create(1)
    $timer.StartBoundary = (Get-Date).AddMinutes(2).ToString('yyyy-MM-ddTHH:mm:ss')
    $timer.Repetition.Interval = "PT$($config.EnforcementIntervalMinutes)M"
    # Omit Repetition.Duration and EndBoundary: repetition remains indefinite.
    $action = $definition.Actions.Create(0)
    $action.Path = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action.Arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $paths.InstallRoot 'Enforce-OfficeWiFi.ps1') + '"'
    $action.WorkingDirectory = $paths.InstallRoot
    $taskSddl = 'O:BAG:BAD:P(A;;GA;;;SY)(A;;GA;;;BA)'
    $registered = $folder.RegisterTaskDefinition($paths.TaskName, $definition, 6, 'SYSTEM', $null, 5, $taskSddl)
    Write-OfficeJson -Path (Join-Path $paths.InstallRoot 'install-manifest.json') -Value @{
        PackageVersion=$paths.PackageVersion; PolicyVersion=$config.PolicyVersion; ConfigHash=$config.ConfigHash
        InstalledUtc=[DateTime]::UtcNow.ToString('o'); Hashes=$hashes
    }
    [void](New-Item -Path $paths.RegistryPath -Force)
    foreach ($pair in @{
        PackageVersion=$paths.PackageVersion; PolicyVersion=$config.PolicyVersion; ConfigHash=$config.ConfigHash
        InstallRoot=$paths.InstallRoot; TaskName=$paths.TaskName
    }.GetEnumerator()) {
        [void](New-ItemProperty -Path $paths.RegistryPath -Name $pair.Key -Value $pair.Value -PropertyType String -Force)
    }
    $committed = $true
    $lock.Dispose(); $lock = $null
    [void]$registered.Run($null)
    Write-Output 'Office Wi-Fi enforcement installed. Network readiness is evaluated by the scheduled task.'
} catch {
    if (-not $committed -and $null -ne $task) {
        try { $task.Enabled = $oldEnabled } catch { }
    }
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
    if ($transcribing) { Stop-Transcript | Out-Null }
}
exit 0
