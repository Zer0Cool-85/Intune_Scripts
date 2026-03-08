<#
.SYNOPSIS
  Create local admin account

.DESCRIPTION
  Creates a local administrator account on computer.

.OUTPUTS
  none

.NOTES
  Version:        1.0

#>

# Configuration
$username = ""   # Administrator is built-in name
$password = ConvertTo-SecureString "%TemPp@s$w0Rd" -AsPlainText -Force  # TEMPORARY PASSWORD -- LAPS will take over and rotate

Function New-LocalAdmin {
    process {
        try {
            New-LocalUser "$username" -Password $password -FullName "$username" -Description "LAPS local admin" -AccountNeverExpires:$true -ErrorAction stop
            # Add new user to administrator group
            Add-LocalGroupMember -Group "Administrators" -Member "$username" -ErrorAction stop
        }
        catch {
            Write-Error $_.Exception.Message
        }
    }    
}

try {
    $adminStatus = (Get-LocalUser -Name $username -ErrorAction SilentlyContinue).Enabled
    if($adminStatus){
        Write-Output "$env:COMPUTERNAME - $username account already exists!"
        Exit 0
    }else{
        New-LocalAdmin
        $adminStatus = (Get-LocalUser -Name $username -ErrorAction SilentlyContinue).Enabled
        if($adminStatus){
            Write-Output "$env:COMPUTERNAME - Created $username account!"
            Exit 0
        }else{
            Write-Output "$env:COMPUTERNAME - $username account was not created!"
            Exit 1
        }
    }
}
catch {
    Write-Output "FAILED"
    Exit 1
}

