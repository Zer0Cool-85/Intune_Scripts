#requires -Version 5.1
<#
Intune requirement: Integer / Equals / 1.
Run using logged-on credentials: No. Run as 32-bit on 64-bit clients: No.
Checks registered machine-wide installations in both HKLM registry views.
Portable and per-user installations are outside this SYSTEM updater's scope.
#>
$ErrorActionPreference = 'Stop'

function Get-MachineNotepadPlusPlus {
    # Explicit registry views work from either 32-bit or 64-bit PowerShell.
    $views = @([Microsoft.Win32.RegistryView]::Registry32)
    if ([Environment]::Is64BitOperatingSystem) {
        $views += [Microsoft.Win32.RegistryView]::Registry64
    }
    foreach ($view in $views) {
        $base = $null
        $uninstall = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if ($null -eq $uninstall) { continue }
            foreach ($keyName in $uninstall.GetSubKeyNames()) {
                $key = $null
                try {
                    $key = $uninstall.OpenSubKey($keyName)
                    if ($null -eq $key) { continue }
                    $name = [string]$key.GetValue('DisplayName')
                    if ($name -match '^Notepad\+\+(?:\s|$)') {
                        [pscustomobject]@{
                            Name = $name
                            Version = [string]$key.GetValue('DisplayVersion')
                            RegistryView = [string]$view
                            KeyName = $keyName
                        }
                    }
                }
                finally { if ($null -ne $key) { $key.Dispose() } }
            }
        }
        finally {
            if ($null -ne $uninstall) { $uninstall.Dispose() }
            if ($null -ne $base) { $base.Dispose() }
        }
    }
}

try {
    $installed = @(Get-MachineNotepadPlusPlus)
    if ($installed.Count -gt 0) { Write-Output 1 } else { Write-Output 0 }
    exit 0
}
catch {
    # Registry failure is a script error, not a successful "not installed" result.
    exit 1
}
