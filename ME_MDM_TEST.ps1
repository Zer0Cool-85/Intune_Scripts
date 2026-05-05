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









function Get-MdmEnrollmentRecords {
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
                    RegistryPath            = $_.Name
                    PSPath                  = $_.PSPath
                }
            }
        }
        catch {
            # Ignore unreadable keys
        }
    }
}

function Backup-RegistryKey {
    param (
        [Parameter(Mandatory)]
        [string]$RegistryPath,

        [Parameter(Mandatory)]
        [string]$BackupDirectory
    )

    if (-not (Test-Path $BackupDirectory)) {
        New-Item -Path $BackupDirectory -ItemType Directory -Force | Out-Null
    }

    $SafeName = ($RegistryPath -replace '[\\/:*?"<>| ]', '_')
    $BackupFile = Join-Path $BackupDirectory "$SafeName.reg"

    & reg.exe export $RegistryPath $BackupFile /y | Out-Null

    return $BackupFile
}

function Test-MdmEnrollmentAssociatedArtifacts {
    param (
        [Parameter(Mandatory)]
        [string]$EnrollmentId
    )

    $Artifacts = [ordered]@{
        EnrollmentStatusKey = Test-Path "HKLM:\SOFTWARE\Microsoft\Enrollments\Status\$EnrollmentId"
        OmaDmAccountKey     = Test-Path "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\$EnrollmentId"
        EnterpriseMgmtTasks = $false
    }

    try {
        $Tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $_.TaskPath -like "\Microsoft\Windows\EnterpriseMgmt\$EnrollmentId\*"
        }

        if ($Tasks) {
            $Artifacts.EnterpriseMgmtTasks = $true
        }
    }
    catch {
        $Artifacts.EnterpriseMgmtTasks = $false
    }

    [PSCustomObject]$Artifacts
}

function Remove-StaleManageEngineMdmEnrollment {
    param (
        [string]$BackupDirectory = "C:\ProgramData\Migration\MDMEnrollmentBackup",

        [switch]$RemoveAssociatedArtifacts
    )

    $Enrollments = Get-MdmEnrollmentRecords

    $ManageEngineEnrollments = $Enrollments | Where-Object {
        $_.ProviderID -match "MEMDM|ManageEngine|DesktopCentral|EndpointCentral|Zoho" -or
        $_.DiscoveryServiceFullURL -match "memdm|manageengine|desktopcentral|endpointcentral|zoho"
    }

    if (-not $ManageEngineEnrollments) {
        Write-Host "No ManageEngine/MEMDM enrollment keys found."
        return [PSCustomObject]@{
            FoundManageEngineMdm = $false
            RemovedStaleKeys     = $false
            ShouldBlockMigration = $false
        }
    }

    $RemovedAny = $false
    $Blocked = $false

    foreach ($Enrollment in $ManageEngineEnrollments) {
        Write-Warning "Found ManageEngine/MEMDM enrollment key: $($Enrollment.EnrollmentId)"
        Write-Host "ProviderID: $($Enrollment.ProviderID)"
        Write-Host "DiscoveryServiceFullURL: $($Enrollment.DiscoveryServiceFullURL)"

        $Artifacts = Test-MdmEnrollmentAssociatedArtifacts -EnrollmentId $Enrollment.EnrollmentId

        Write-Host "Associated artifacts:"
        $Artifacts | Format-List | Out-String | Write-Host

        $LooksStale = -not $Artifacts.EnterpriseMgmtTasks -and -not $Artifacts.OmaDmAccountKey

        if ($LooksStale) {
            Write-Warning "MEMDM enrollment appears stale. Backing up and removing registry key."

            $NativeEnrollmentPath = "HKLM\SOFTWARE\Microsoft\Enrollments\$($Enrollment.EnrollmentId)"
            $NativeStatusPath     = "HKLM\SOFTWARE\Microsoft\Enrollments\Status\$($Enrollment.EnrollmentId)"

            Backup-RegistryKey -RegistryPath $NativeEnrollmentPath -BackupDirectory $BackupDirectory | Out-Null

            if (Test-Path "HKLM:\SOFTWARE\Microsoft\Enrollments\Status\$($Enrollment.EnrollmentId)") {
                Backup-RegistryKey -RegistryPath $NativeStatusPath -BackupDirectory $BackupDirectory | Out-Null
            }

            Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\$($Enrollment.EnrollmentId)" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Enrollments\Status\$($Enrollment.EnrollmentId)" -Recurse -Force -ErrorAction SilentlyContinue

            $RemovedAny = $true
        }
        else {
            Write-Warning "MEMDM enrollment still has associated artifacts."

            if ($RemoveAssociatedArtifacts) {
                Write-Warning "RemoveAssociatedArtifacts was specified. Cleaning associated MEMDM artifacts."

                $PathsToRemove = @(
                    "HKLM:\SOFTWARE\Microsoft\Enrollments\$($Enrollment.EnrollmentId)",
                    "HKLM:\SOFTWARE\Microsoft\Enrollments\Status\$($Enrollment.EnrollmentId)",
                    "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\$($Enrollment.EnrollmentId)"
                )

                foreach ($Path in $PathsToRemove) {
                    if (Test-Path $Path) {
                        $NativePath = $Path -replace "^HKLM:\\", "HKLM\"
                        Backup-RegistryKey -RegistryPath $NativePath -BackupDirectory $BackupDirectory | Out-Null
                        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }

                try {
                    $Tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
                        $_.TaskPath -like "\Microsoft\Windows\EnterpriseMgmt\$($Enrollment.EnrollmentId)\*"
                    }

                    foreach ($Task in $Tasks) {
                        Write-Warning "Removing EnterpriseMgmt scheduled task: $($Task.TaskPath)$($Task.TaskName)"
                        Unregister-ScheduledTask -TaskName $Task.TaskName -TaskPath $Task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-Warning "Failed to remove EnterpriseMgmt scheduled tasks: $($_.Exception.Message)"
                }

                $RemovedAny = $true
            }
            else {
                Write-Warning "Blocking migration because MEMDM artifacts may still be active."
                $Blocked = $true
            }
        }
    }

    [PSCustomObject]@{
        FoundManageEngineMdm = $true
        RemovedStaleKeys     = $RemovedAny
        ShouldBlockMigration = $Blocked
    }
}
