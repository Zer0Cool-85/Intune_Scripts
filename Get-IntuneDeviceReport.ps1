#==========================================================================
#region MS Graph Connetion Functions
function Get-AuthResponse {

  $clientId = ''
  $tenantId = ''
  
  # Replace this with your secret from the PowerShell Graph app registration in AzureAD
  $clientSecret = ''
  
  $body = @{
    grant_type    = "client_credentials";
    client_id     = $clientId;
    client_secret = $clientSecret;
    scope         = "https://graph.microsoft.com/.default";
  }
  
  try {
    $response = Invoke-RestMethod -Method Post -Uri https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token -Body $body
    return $response
  }
  catch {
    $response = $null
    return $null
  }
     
}
function Get-GraphAPIToken {
  # This method will check to see if the current access token is expired based on the global variable expiresDateTime,
  # which gets set when a new token is acquired.
   
  # the -5 minutes in this if statement is to build in a 5 minute buffer
  if ($global:expiresDateTime -lt (Get-Date).AddMinutes(-5)) {
    # token needs renewed
    Write-Host "Getting access token…" -ForegroundColor Yellow -BackgroundColor Black
    $rsp = Get-AuthResponse
    $expiresIn = [double]($rsp).expires_in
      
    $token = $rsp.access_token

    # Create global variables for headers
    $authHeader = @{
      'Content-Type'  = 'application/json'
      'Authorization' = 'Bearer ' + $token
    }  
    if ($null -eq $rsp.access_token) {
      Write-Host "Failed to connect...review error and try again" -ForegroundColor Red -BackgroundColor Black
    }
    else {
      Write-Host "Successfully connected to Microsoft Graph!`n" -ForegroundColor Green -BackgroundColor Black
      $global:expiresDateTime = (Get-Date).AddSeconds($expiresIn)
      Write-Host ("Token Expiration Date/Time: " + $global:expiresDateTime + "`n")  -ForegroundColor Magenta -BackgroundColor Black
    }
  }
  else {
    $expireCounter = ( ($global:expiresDateTime).TimeOfDay - (get-date).TimeOfDay ).Minutes
    Write-Host "You are still connected to MS Graph..." -ForegroundColor Green -BackgroundColor Black
    if ($expireCounter -ile 10) {
      Write-Host "Your current token will expire in $expirecounter minutes." -ForegroundColor DarkRed -BackgroundColor Black
    }
    else {
      Write-Host "Your current token will expire in $expirecounter minutes." -ForegroundColor Yellow -BackgroundColor Black
    }
  }
  $global:authHeader = $authHeader
}
#endregion

Get-GraphAPIToken
$Devices = @()
$uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"
do {
  $result = Invoke-WebRequest -Method Get -Uri $uri -Headers $authHeader -Verbose:$VerbosePreference
  $uri = ($result.Content | ConvertFrom-Json).'@odata.nextLink'

  #If we are getting multiple pages, best add some delay to avoid throttling
  Start-Sleep -Seconds 1
  $Devices += ($result.Content | ConvertFrom-Json).Value
} while ($uri)

$output = [System.Collections.Generic.List[Object]]::new()
$Devices = $Devices | Where-Object {$_.operatingSystem -like "*Windows*"}
$deviceGroups = $devices | Where-Object { -not [String]::IsNullOrWhiteSpace($_.serialNumber) -and ($_.serialNumber -ne "Defaultstring") } | Group-Object -Property serialNumber
$duplicateDevices = $deviceGroups | Where-Object {$_.Count -gt 1 }

foreach($duplicatedDevice in $duplicateDevices){
  # Find device which is the newest
  $newestDevice = $duplicatedDevice.Group | Sort-Object -Property lastSyncDateTime -Descending | Select-Object -First 1
  Write-Output "Serial $($duplicatedDevice.Name)"
  Write-Output "# Keep $($newestDevice.deviceName) $($newestDevice.lastSyncDateTime)"
  foreach($oldDevice in ($duplicatedDevice.Group | Sort-Object -Property lastSyncDateTime -Descending | Select-Object -Skip 1)){
      Write-Output "# Remove $($oldDevice.deviceName) $($oldDevice.lastSyncDateTime)"
  }
}

foreach ($device in $Devices) {
  $deviceInfo = [PSCustomObject][ordered]@{
    "Email"          = $device.emailAddress
    "User Name"      = $device.userDisplayName 
    "Device Name"    = $device.deviceName
    "Serial"         = $device.serialNumber
    "Last Sync"      = $device.lastSyncDateTime
    "Last Log On"    = $device.usersLoggedOn.lastLogOnDate
    "Owner"          = $device.ownerType
    "Enrolled Date"  = $device.enrolledDateTime
    "Device ID"      = $device.id
    "User ID"        = $device.userId
    "Compliance"     = $device.complianceState
    "OS Version"     = $device.osVersion
    "Enroll Type"    = $device.deviceEnrollmentType
    "Azure DeviceID" = $device.azureActiveDirectoryDeviceId
    "Manufacturer"   = $device.manufacturer
    "Autopilot"      = $device.autopilotEnrolled
    "JoinType"       = $device.joinType    
  }
  $output.Add($deviceInfo)
}

$output | Select-Object * | Export-CSV -nti -Path "$((Get-Date).ToString('yyyy-MM-dd'))_IntuneDeviceInfo.csv"

