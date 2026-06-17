<# 
.SYNOPSIS
    Refreshes the Microsoft Entra Primary Refresh Token for the logged-in user
    and logs dsregcmd status before and after the refresh attempt.

.NOTES
    Deploy this in the logged-on user context, not SYSTEM.
#>

$CompanyName = "Company"
$LogRootPreferred = "C:\Users\Public\$CompanyName\AADPRT\Logs"
$LogRootFallback  = Join-Path $env:LOCALAPPDATA "$CompanyName\AADPRT\Logs"

function New-LogPath {
    try {
        New-Item -Path $LogRootPreferred -ItemType Directory -Force -ErrorAction Stop | Out-Null
        return $LogRootPreferred
    }
    catch {
        New-Item -Path $LogRootFallback -ItemType Directory -Force | Out-Null
        return $LogRootFallback
    }
}

$LogRoot = New-LogPath
$LogFile = Join-Path $LogRoot ("Refresh-AADPRT-{0}-{1:yyyyMMdd-HHmmss}.log" -f $env:USERNAME, (Get-Date))

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $Line = "{0} - {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $Line | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Invoke-DsRegCmd {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $DsRegCmd = Join-Path $env:windir "System32\dsregcmd.exe"

    if (-not (Test-Path $DsRegCmd)) {
        Write-Log "ERROR: dsregcmd.exe not found at $DsRegCmd"
        return $null
    }

    Write-Log "Running: $DsRegCmd $($Arguments -join ' ')"

    try {
        $Output = & $DsRegCmd @Arguments 2>&1
        foreach ($Line in $Output) {
            Write-Log $Line
        }
        return $Output
    }
    catch {
        Write-Log "ERROR running dsregcmd: $($_.Exception.Message)"
        return $null
    }
}

function Get-DsRegValue {
    param(
        [string[]]$StatusOutput,
        [string]$Name
    )

    $Match = $StatusOutput | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*:\s*(.+)$" } | Select-Object -First 1

    if ($Match -match "^\s*$([regex]::Escape($Name))\s*:\s*(.+)$") {
        return $Matches[1].Trim()
    }

    return $null
}

Write-Log "============================================================"
Write-Log "Starting AAD PRT refresh script."
Write-Log "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User profile: $env:USERPROFILE"
Write-Log "Session username: $env:USERNAME"
Write-Log "Log file: $LogFile"

Write-Log "Collecting dsregcmd /status before refresh."
$BeforeStatus = Invoke-DsRegCmd -Arguments @("/status")

$BeforeAzureAdJoined = Get-DsRegValue -StatusOutput $BeforeStatus -Name "AzureAdJoined"
$BeforeDomainJoined  = Get-DsRegValue -StatusOutput $BeforeStatus -Name "DomainJoined"
$BeforeAzureAdPrt    = Get-DsRegValue -StatusOutput $BeforeStatus -Name "AzureAdPrt"
$BeforeWamDefaultSet = Get-DsRegValue -StatusOutput $BeforeStatus -Name "WamDefaultSet"
$BeforeServerError   = Get-DsRegValue -StatusOutput $BeforeStatus -Name "Server Error Code"
$BeforeErrorDesc     = Get-DsRegValue -StatusOutput $BeforeStatus -Name "Server Error Description"

Write-Log "Before summary:"
Write-Log "  AzureAdJoined: $BeforeAzureAdJoined"
Write-Log "  DomainJoined: $BeforeDomainJoined"
Write-Log "  AzureAdPrt: $BeforeAzureAdPrt"
Write-Log "  WamDefaultSet: $BeforeWamDefaultSet"
Write-Log "  Server Error Code: $BeforeServerError"
Write-Log "  Server Error Description: $BeforeErrorDesc"

Write-Log "Requesting PRT refresh."
$RefreshOutput = Invoke-DsRegCmd -Arguments @("/refreshprt")

Write-Log "Waiting 30 seconds before checking status again."
Start-Sleep -Seconds 30

Write-Log "Collecting dsregcmd /status after refresh."
$AfterStatus = Invoke-DsRegCmd -Arguments @("/status")

$AfterAzureAdJoined = Get-DsRegValue -StatusOutput $AfterStatus -Name "AzureAdJoined"
$AfterDomainJoined  = Get-DsRegValue -StatusOutput $AfterStatus -Name "DomainJoined"
$AfterAzureAdPrt    = Get-DsRegValue -StatusOutput $AfterStatus -Name "AzureAdPrt"
$AfterWamDefaultSet = Get-DsRegValue -StatusOutput $AfterStatus -Name "WamDefaultSet"
$AfterServerError   = Get-DsRegValue -StatusOutput $AfterStatus -Name "Server Error Code"
$AfterErrorDesc     = Get-DsRegValue -StatusOutput $AfterStatus -Name "Server Error Description"

Write-Log "After summary:"
Write-Log "  AzureAdJoined: $AfterAzureAdJoined"
Write-Log "  DomainJoined: $AfterDomainJoined"
Write-Log "  AzureAdPrt: $AfterAzureAdPrt"
Write-Log "  WamDefaultSet: $AfterWamDefaultSet"
Write-Log "  Server Error Code: $AfterServerError"
Write-Log "  Server Error Description: $AfterErrorDesc"

if ($AfterAzureAdPrt -eq "YES") {
    Write-Log "SUCCESS: AzureAdPrt is now YES."
    Write-Log "Finished."
    exit 0
}

if ($AfterServerError -eq "invalid_grant") {
    Write-Log "WARNING: AzureAdPrt is still not healthy and Entra returned invalid_grant."
    Write-Log "This usually means the refresh was attempted, but Entra/Okta rejected the credential/token flow."
    Write-Log "User may need to sign out and back in with password, not PIN/Hello, or the Okta/M365 sign-on policy needs review."
    Write-Log "Finished with warning."
    exit 2
}

Write-Log "WARNING: AzureAdPrt is still not YES after refresh attempt."
Write-Log "Finished with warning."
exit 1
