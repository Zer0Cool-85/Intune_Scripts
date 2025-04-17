<#
.SYNOPSIS
    Collects application install information from Windows PC for Intune app deployment detection

.DESCRIPTION
    Runs a custom function to scrape installed apps and return name and version
    Verifies app and version specified are present
    The variables for app name and version should be updated to match the deployment

.NOTES
    Created by: Dale Lute
    Last update: 3/13/2023
    Filename: CustomAppDetection.ps1
    Version: 1.0
#> 

# Change the Application and Version variable below to match the app you're deploying
$Application = "Software"
$Version = "7.0"

function Get-InstalledApplications {
    [CmdletBinding()]
        Param (
            [Parameter(Mandatory = $true)]
            [ValidateNotNullorEmpty()]
            [String]$Name
            )
    $uninstallKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $AllApps = @()
    foreach ($key in $uninstallKeys) {
        $app = Get-ItemProperty $key | Where-Object {$_.DisplayName -and $_.UninstallString} | Select-Object DisplayName, DisplayVersion, UninstallString
        $AllApps += $app
    }

    $AllApps | Where-Object {$_.DisplayName -like "*$($Name)*"}
}

If((Get-InstalledApplications -Name $Application).displayversion -ge $Version) {
    Write-Host "Installed"
    Exit 0
}
else {
    Write-Host "Not Installed"
    Exit 1
}