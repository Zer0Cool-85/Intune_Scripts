# Intune Win32 Detection Script
# Detects an app installed under the actively logged-on user's AppData\Local\Programs path

$RelativeAppPath = "Programs\AppName\AppName.exe"
# Example full expected path:
# C:\Users\jsmith\AppData\Local\Programs\AppName\AppName.exe

try {
    # Get the user currently running explorer.exe
    $explorer = Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" | Select-Object -First 1

    if (-not $explorer) {
        exit 1
    }

    $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner

    if (-not $owner.User) {
        exit 1
    }

    $ntAccount = "$($owner.Domain)\$($owner.User)"
    $sid = (New-Object System.Security.Principal.NTAccount($ntAccount)).Translate(
        [System.Security.Principal.SecurityIdentifier]
    ).Value

    $profile = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.SID -eq $sid -and $_.LocalPath
    }

    if (-not $profile) {
        exit 1
    }

    $AppPath = Join-Path -Path $profile.LocalPath -ChildPath "AppData\Local\$RelativeAppPath"

    if (Test-Path -Path $AppPath -PathType Leaf) {
        Write-Output "Installed: $AppPath"
        exit 0
    }

    exit 1
}
catch {
    exit 1
}



# Intune Win32 Detection Script
# Detects an app installed under any user's AppData\Local\Programs path

$RelativeAppPath = "AppData\Local\Programs\AppName\AppName.exe"

try {
    $UserProfiles = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.Special -eq $false -and
        $_.LocalPath -like "C:\Users\*" -and
        (Test-Path $_.LocalPath)
    }

    foreach ($Profile in $UserProfiles) {
        $AppPath = Join-Path -Path $Profile.LocalPath -ChildPath $RelativeAppPath

        if (Test-Path -Path $AppPath -PathType Leaf) {
            Write-Output "Installed: $AppPath"
            exit 0
        }
    }

    exit 1
}
catch {
    exit 1
}



$RelativeAppPath = "AppData\Local\Programs\AppName\AppName.exe"
$MinimumVersion = [version]"1.2.3.4"

try {
    $UserProfiles = Get-CimInstance Win32_UserProfile | Where-Object {
        $_.Special -eq $false -and
        $_.LocalPath -like "C:\Users\*" -and
        (Test-Path $_.LocalPath)
    }

    foreach ($Profile in $UserProfiles) {
        $AppPath = Join-Path -Path $Profile.LocalPath -ChildPath $RelativeAppPath

        if (Test-Path -Path $AppPath -PathType Leaf) {
            $DetectedVersion = [version](Get-Item $AppPath).VersionInfo.FileVersion

            if ($DetectedVersion -ge $MinimumVersion) {
                Write-Output "Installed: $AppPath version $DetectedVersion"
                exit 0
            }
        }
    }

    exit 1
}
catch {
    exit 1
}
