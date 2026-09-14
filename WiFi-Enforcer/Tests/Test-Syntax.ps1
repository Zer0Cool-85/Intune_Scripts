#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$count = 0
foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') -and $_.FullName -notmatch '[\\/]Output[\\/]' })) {
    $tokens=$null; $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "$($file.FullName): $($parseErrors.Message -join '; ')" }
    $count++
}
Add-Type -Path (Join-Path $root 'Source/NativeWifi.cs')
$clientType=[OfficeWiFi.WlanClient]
foreach ($entry in @(@('InterfaceInfo',532), @('ProfileInfo',516), @('AvailableNetwork',628))) {
    $type=$clientType.GetNestedType($entry[0],[Reflection.BindingFlags]::NonPublic)
    $size=[Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($type))
    if ($size -ne $entry[1]) { throw "Unexpected $($entry[0]) native layout: $size; expected $($entry[1])." }
}
Write-Output "Parsed $count PowerShell files; compiled NativeWifi.cs; verified native structure layouts."
