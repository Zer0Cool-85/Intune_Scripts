# Get local admin account status
# Add user name you are using for LAPS
$LAPSname = ""
$adminStatus = (Get-LocalUser -Name $LAPSname -ErrorAction SilentlyContinue).Enabled

if ($adminStatus){
    Write-Output "LAPS admin account already exists."
    Exit 0
}else {
    Write-Output "LAPS admin account does not exist."
    Exit 1
}
