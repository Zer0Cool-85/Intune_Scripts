[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ProfileName = 'Company AWS VPN'
$ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'company.ovpn'

$InstallFolder = Join-Path -Path $env:ProgramFiles -ChildPath 'Amazon\AWS VPN Client'
$AwsVpnCli = Join-Path -Path $InstallFolder -ChildPath 'aws-vpn-client.exe'
$VersionFile = Join-Path -Path $InstallFolder -ChildPath 'app_version'

function Invoke-AwsVpnCli {
    param(
        [Parameter(Mandatory)]
        [string[]]$CliArguments
    )

    Write-Host "Executing: aws-vpn-client $($CliArguments -join ' ')"

    $CommandOutput = & $AwsVpnCli @CliArguments 2>&1
    $ExitCode = $LASTEXITCODE

    if ($CommandOutput) {
        $CommandOutput | ForEach-Object {
            Write-Host $_
        }
    }

    if ($ExitCode -ne 0) {
        throw "aws-vpn-client exited with code $ExitCode."
    }
}

# Validate installation
if (-not (Test-Path -LiteralPath $AwsVpnCli)) {
    throw "AWS VPN Client CLI was not found at: $AwsVpnCli"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "VPN configuration was not found at: $ConfigPath"
}

# Confirm that this is the new 6.x client
if (Test-Path -LiteralPath $VersionFile) {
    $InstalledVersion = (Get-Content -LiteralPath $VersionFile -Raw).Trim()

    Write-Host "Installed AWS VPN Client version: $InstalledVersion"

    if ([version]$InstalledVersion -lt [version]'6.0.0') {
        throw "AWS VPN Client 6.0.0 or later is required."
    }
}

# Make sure the new privileged service is running
$ServiceName = 'AWS VPN Client Service'
$Service = Get-Service -Name $ServiceName -ErrorAction Stop

if ($Service.Status -ne 'Running') {
    Write-Host "Starting $ServiceName..."
    Start-Service -Name $ServiceName
    $Service.WaitForStatus('Running', [timespan]::FromSeconds(30))
}

# Check whether this global profile already exists.
# Output is discarded because get-config returns the complete OVPN configuration.
$null = & $AwsVpnCli get-config $ProfileName 2>$null
$ProfileExists = $LASTEXITCODE -eq 0

if ($ProfileExists) {
    Write-Host "Profile '$ProfileName' already exists. Leaving it unchanged."
}
else {
    Invoke-AwsVpnCli -CliArguments @(
        'import-profile'
        '--profile-name', $ProfileName
        '--config-path', $ConfigPath
        '--global'
    )

    Write-Host "Global VPN profile imported successfully."
}

# Apply deterministic administrative settings
Invoke-AwsVpnCli -CliArguments @(
    'put-preference'
    'enable-user-profile-management'
    'false'
)

Invoke-AwsVpnCli -CliArguments @(
    'put-preference'
    'max-connections'
    '1'
)

Invoke-AwsVpnCli -CliArguments @(
    'put-preference'
    'enable-telemetry'
    'false'
)

Write-Host "AWS VPN Client profile deployment completed successfully."
exit 0
