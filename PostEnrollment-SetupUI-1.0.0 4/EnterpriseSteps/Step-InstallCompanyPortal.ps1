[CmdletBinding()]
param(
    [ValidateSet('OfflinePackage','IntuneWait')][string]$Mode = 'OfflinePackage',
    [string]$RegistryPath = 'HKLM:\SOFTWARE\Company\PostEnrollmentSetup',
    [string]$TargetUserSid = '',
    [string]$PackageRelativePath = '',
    [string[]]$DependencyRelativePaths = @(),
    [string]$LicenseRelativePath = '',
    [bool]$AllowUnlicensedPackage = $false,
    [ValidateRange(0,3600)][int]$WaitSeconds = 300
)
. (Join-Path $PSScriptRoot 'Enterprise.Common.ps1')
try {
    $sid = Get-EnterpriseUserSid $TargetUserSid
    # Recheck regardless of an old registry flag: Intune may have installed it meanwhile.
    $present = Test-EnterpriseUserApp -Name 'Microsoft.CompanyPortal' -UserSid $sid
    Set-CompanyPortalState -RegistryPath $RegistryPath -UserSid $sid -Present $present
    if ($present) { Set-EnterpriseProgress 'Company Portal is already available.'; return }
    if ($Mode -eq 'IntuneWait') {
        Wait-EnterpriseStoreApp -Name 'Microsoft.CompanyPortal' -UserSid $sid -WaitSeconds $WaitSeconds
    }
    else {
        Install-EnterpriseStoreApp -Name 'Microsoft.CompanyPortal' -UserSid $sid -PackageRelativePath $PackageRelativePath -DependencyRelativePaths $DependencyRelativePaths -LicenseRelativePath $LicenseRelativePath -AllowUnlicensedPackage $AllowUnlicensedPackage
    }
    Set-CompanyPortalState -RegistryPath $RegistryPath -UserSid $sid -Present $true
}
catch { Write-EnterpriseLog -Level ERROR -Message $_.Exception.Message; throw }
