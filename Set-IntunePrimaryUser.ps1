# Obtain AccessToken for Microsoft Graph via the managed identity
try {
    $ResourceURL = "https://graph.microsoft.com/" 
    $Response = [System.Text.Encoding]::Default.GetString((Invoke-WebRequest -UseBasicParsing -Uri "$($env:IDENTITY_ENDPOINT)?resource=$resourceURL" -Method 'GET' -Headers @{'X-IDENTITY-HEADER' = "$env:IDENTITY_HEADER"; 'Metadata' = 'True' }).RawContentStream.ToArray()) | ConvertFrom-Json 
    # Construct AuthHeader
    $authHeader = @{
    'Content-Type'  = 'application/json'
    'Authorization' = "Bearer " + $Response.access_token
    }
   }
   catch {
    throw "An error occurred while obtaining the access token: $_"
   }
   
   function Get-Win10IntuneManagedDevice {
       [cmdletbinding()]
   
       param
       (
           [parameter(Mandatory = $false)]
           [ValidateNotNullOrEmpty()]
           [string]$deviceName
       )
       
       $graphApiVersion = "beta"
   
       try {
   
           if ($deviceName) {
   
               $Resource = "deviceManagement/managedDevices?`$filter=deviceName eq '$deviceName'"
               $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)" 
   
               (Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get).value
   
           }
   
           else {
   
               $Resource = "deviceManagement/managedDevices?`$filter=(((deviceType%20eq%20%27desktop%27)%20or%20(deviceType%20eq%20%27windowsRT%27)%20or%20(deviceType%20eq%20%27winEmbedded%27)%20or%20(deviceType%20eq%20%27surfaceHub%27)))"
               $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
           
               (Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get).value
   
           }
   
       }
       catch {
           throw "Get-IntuneManagedDevices error: $_"
       }
   
   }
   function Get-EntraIDUser() {
       [cmdletbinding()]
   
       param
       (
           $userPrincipalName,
           $Property
       )
   
       # Defining Variables
       $graphApiVersion = "v1.0"
       $User_resource = "users"
       
       try {
           
           if ($userPrincipalName -eq "" -or $null -eq $userPrincipalName) {
           
               $uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)"
           (Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get).Value
           
           }
   
           else {
               
               if ($Property -eq "" -or $null -eq $Property) {
   
                   $uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)/$userPrincipalName"
                   Write-Verbose $uri
                   Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get
   
               }
   
               else {
   
                   $uri = "https://graph.microsoft.com/$graphApiVersion/$($User_resource)/$userPrincipalName/$Property"
                   Write-Verbose $uri
               (Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get).Value
   
               }
   
           }
       
       }
   
       catch {
           throw "Get-EntraIDUser error: $_"
       }
   
   }
   function Get-IntuneDevicePrimaryUser {
       [cmdletbinding()]
   
       param
       (
           [Parameter(Mandatory = $true)]
           [string] $deviceId
       )
       $graphApiVersion = "beta"
       $Resource = "deviceManagement/managedDevices"
       $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)" + "/" + $deviceId + "/users"
   
       try {
           
           $primaryUser = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get
   
           return $primaryUser.value."id"
           
       }
       catch {
           throw "Get-IntuneDevicePrimaryUser error: $_"
       }
   }
   function Set-IntuneDevicePrimaryUser {
       [cmdletbinding()]
   
       param
       (
           [parameter(Mandatory = $true)]
           [ValidateNotNullOrEmpty()]
           $IntuneDeviceId,
           [parameter(Mandatory = $true)]
           [ValidateNotNullOrEmpty()]
           $userId
       )
       $graphApiVersion = "beta"
       $Resource = "deviceManagement/managedDevices('$IntuneDeviceId')/users/`$ref"
   
       try {
           
           $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)"
   
           $userUri = "https://graph.microsoft.com/$graphApiVersion/users/" + $userId
   
           $id = "@odata.id"
           $JSON = @{ $id = "$userUri" } | ConvertTo-Json -Compress
   
           Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Post -Body $JSON -ContentType "application/json"
   
       }
       catch {
           throw "Set-IntuneDevicePrimaryUser error: $_"
       }
   
   }
   
    # Get all Intune devices where the userId field is blank and owner is company
    $Devices = @()
    $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"
    do {
        $result = Invoke-WebRequest -Method Get -Uri $uri -Headers $authHeader -Verbose:$VerbosePreference
        $uri = ($result.Content | ConvertFrom-Json).'@odata.nextLink'

        #If we are getting multiple pages, best add some delay to avoid throttling
        Start-Sleep -Seconds 1
        $Devices += ($result.Content | ConvertFrom-Json).Value
    } while ($uri)
    
    $deviceNoUser = $Devices | Where-Object { $_.userId -eq "" -or $_.userId -eq $null -and $_.ownerType -eq "company" }
    
   $output = [System.Collections.Generic.List[Object]]::new()
   $deviceInfo = @()
   Foreach ($computer in $deviceNoUser){ 
       # Set variable to tell script if a user is already assigned to a device
       $name = $computer.deviceName
       $device = Get-Win10IntuneManagedDevice -deviceName $name
   
       $IntuneDevicePrimaryUser = Get-IntuneDevicePrimaryUser -deviceId $Device.id
   
       #Check if there is a Primary user set on the device already
       if($null -eq $IntuneDevicePrimaryUser){
           $assignedUser = "No"
       }
       else {
           $PrimaryEntraIDUser = Get-EntraIDUser -userPrincipalName $IntuneDevicePrimaryUser
           $assignedUser = "Yes - $PrimaryEntraIDUser"
       }
   
       #Get the objectID of the last logged in user for the device, which is the last object in the list of usersLoggedOn
       $LastLoggedInUser = ($Device.usersLoggedOn[-1]).userId
   
       if($null -eq $LastLoggedInUser -or $LastLoggedInUser -eq ""){
           $lastUser = $false
       }
       else{
           $lastUser = $true
       }
   
       $deviceInfo = [PSCustomObject][ordered]@{
           "DeviceName"   = $computer.deviceName
           "DeviceID"     = $computer.id
           "UserAssigned" = $assignedUser
           "UserDetected" = $lastUser
           "UserID"       = $LastLoggedInUser
       }
       $output.Add($deviceInfo)
   
   }
   
   Write-Output "$($output.Count) devices have no primary user assigned in Intune."
   
   $updateUsers = $output | Where-Object {$_.UserDetected -eq "True" -and $_.UserAssigned -eq "No"}
   
   $devicesToUpdate = $updateUsers.DeviceName
   
   if($devicesToUpdate.count -ge 1){
       Write-Output "Attempting to update primary user for the following devices:`n$devicesToUpdate"
   }else{
       Write-Output "No devices to update."
   }
   
   $report = [System.Collections.Generic.List[Object]]::new()
   $userInfo = @()
   foreach($pc in $updateUsers){
       try{
       #Using the last logged on user objectID, get the user from the Microsoft Graph for logging purposes
       $User = Get-EntraIDUser -userPrincipalName $pc.UserID
       $userName = $user.displayName
       $userUPN = $user.userPrincipalName
   
       # Set the last logged in user as the new Primary User
       Write-Output "Setting primary user of $($pc.DeviceName) to: $userName ($userUPN)`n"
       
       Set-IntuneDevicePrimaryUser -IntuneDeviceId $pc.DeviceID -userId $User.id
   
       $userInfo = [PSCustomObject][ordered]@{
           "DeviceName"   = $pc.DeviceName
           "UserAssigned" = $userName
           "Email" = $userUPN
       }
       $report.Add($userInfo)
       }catch{
           if ($_.Exception.Message -match "\(404\) Not Found") {
               Write-Output "Last logged on user not found in EntraID for $($pc.DeviceName)"
           } else {
               Write-Output "Error setting primary user on $($pc.DeviceName)"
           }
       }
   }
   if($report.Count -ge 1){
       Write-Output "$($report.Count) device(s) updated."
   }