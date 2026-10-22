[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestBase64)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
try {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { throw 'User action must run as the interactive user.' }
    $request = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($RequestBase64)) | ConvertFrom-Json
    switch ($request.Action) {
        'InstallAppx' {
            $args = @{Path=[string]$request.PackagePath; ErrorAction='Stop'}
            if (@($request.Dependencies).Count) { $args.DependencyPath = [string[]]$request.Dependencies }
            Add-AppxPackage @args
        }
        'UninstallOneDrive' {
            $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe'
            if (-not (Test-Path $key)) { exit 0 }
            $command = [string](Get-ItemProperty -LiteralPath $key -Name UninstallString).UninstallString
            if ($command -notmatch '^"(?<exe>[^"\r\n]+OneDriveSetup\.exe)"\s+/uninstall(?:\s+.*)?$') { throw 'Unrecognized per-user OneDrive uninstaller command.' }
            $exe = $Matches.exe
            $sig = Get-AuthenticodeSignature -LiteralPath $exe
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') { throw 'OneDrive uninstaller signature is not valid Microsoft.' }
            $p = Start-Process -FilePath $exe -ArgumentList '/uninstall' -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "OneDrive uninstall exit code: $($p.ExitCode)" }
        }
        default { throw 'Unknown user action.' }
    }
    exit 0
}
catch {
    Add-Content -LiteralPath (Join-Path $env:TEMP 'PostEnrollment-UserAction.log') -Value ("{0} {1}" -f [DateTime]::Now.ToString('o'), $_.Exception.Message) -Encoding UTF8
    exit 1
}
