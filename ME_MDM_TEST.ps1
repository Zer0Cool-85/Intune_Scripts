function Get-WindowsMdmEnrollment {
    $EnrollmentRoot = "HKLM:\SOFTWARE\Microsoft\Enrollments"

    if (-not (Test-Path $EnrollmentRoot)) {
        return @()
    }

    Get-ChildItem -Path $EnrollmentRoot -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $Props = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop

            if (
                $Props.ProviderID -or
                $Props.DiscoveryServiceFullURL -or
                $Props.EnrollmentType -or
                $Props.UPN
            ) {
                [PSCustomObject]@{
                    EnrollmentId            = $_.PSChildName
                    ProviderID              = $Props.ProviderID
                    UPN                     = $Props.UPN
                    EnrollmentType          = $Props.EnrollmentType
                    EnrollmentState         = $Props.EnrollmentState
                    DiscoveryServiceFullURL = $Props.DiscoveryServiceFullURL
                    KeyPath                 = $_.Name
                }
            }
        }
        catch {
            # Skip unreadable enrollment keys
        }
    }
}

$MdmEnrollments = Get-WindowsMdmEnrollment

if ($MdmEnrollments) {
    Write-Host "Existing MDM enrollment entries found:"
    $MdmEnrollments | Format-List
}
else {
    Write-Host "No MDM enrollment entries found."
}




Write-Host "Checking for existing ManageEngine MDM enrollment..."

$MdmEnrollments = Get-WindowsMdmEnrollment

$ManageEngineMdm = $MdmEnrollments | Where-Object {
    $_.ProviderID -match "ManageEngine|DesktopCentral|EndpointCentral|Zoho|ME MDM|MEMDM" -or
    $_.DiscoveryServiceFullURL -match "manageengine|desktopcentral|endpointcentral|zoho|memdm"
}

if ($ManageEngineMdm) {
    Write-Warning "ManageEngine MDM profile is still present."
    Write-Warning "Device should be deprovisioned from ManageEngine MDM before Intune enrollment is attempted."
    exit 7001
}

Write-Host "ManageEngine MDM profile does not appear to be present. Starting Intune enrollment..."

# Continue with provisioning package / Entra join / Intune enrollment here
