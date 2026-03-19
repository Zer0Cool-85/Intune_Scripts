# TempAdmin App

Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop

$logName = "Temp Admin"
$logSource = "localpriv"
$appName = "Admin Privileges"

# CHANGED: Use Entra-formatted admin identities instead of old SIDs
$itAdmins = @(
    "AzureAD\admin1@contoso.com",
    "AzureAD\admin2@contoso.com",
    "AzureAD\admin3@contoso.com",
    "AzureAD\admin4@contoso.com",
    "AzureAD\admin5@contoso.com"
)

$localadmins = "admin", "corpAdmin", "Administrator"

# CHANGED: Helper to get current signed-in Entra user in local group format
function Get-EntraPrincipal {
    $upn = (whoami /upn 2>$null).Trim()
    if (-not $upn -or $upn -notmatch '@') {
        throw "Unable to determine current user's UPN."
    }
    return "AzureAD\$upn"
}

Function Get-LocalGroupMembers  {

    [Cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$GroupName
    )
    [adsi]$adsiGroup = "WinNT://$($env:COMPUTERNAME)/$GroupName,group"
    $adsiGroup.Invoke('Members') | %{
        $username = $_.GetType().InvokeMember('Name','GetProperty',$null,$_,$null)
        $path = $_.GetType().InvokeMember('AdsPath','GetProperty',$null,$_,$null).Replace('WinNT://','')
        $class = $_.GetType().InvokeMember('Class','GetProperty',$null,$_,$null)
        $userObj = New-Object System.Security.Principal.NTAccount($username)
        $ErrorActionPreference = "Stop"
        Try {
            $sid = $userObj.Translate([System.Security.Principal.SecurityIdentifier] )
            $sid = $sid.Value
        }
        Catch {
            $sid = $username
        }
        [pscustomobject]@{
            Username = $username
            Type = $class
            SID = $sid
            Path = $path
        }

    }

}


#get current local Administrators and add them to TempAdmin group
#remove them from Administrators group
function revoke {
    $gAdmin = Get-LocalGroupMember -Group Administrators

    foreach ($member in $gAdmin) {
        $name = $member.Name
        $shortName = ($name -split '\\')[-1]

        if ($itAdmins.Contains($name) -or $localadmins.Contains($shortName)) {
            # Keep permanent/admin allowlisted accounts
        } else {
            Write-Host "other admin $name"

            # Preserve non-local admins in TempAdmin before removal
            if ($member.PrincipalSource -ne "Local") {
                Add-LocalGroupMember -Group TempAdmin -Member $name -ErrorAction SilentlyContinue
            }

            Write-Host "revoke $name"
            Remove-LocalGroupMember -Group Administrators -Member $name -ErrorAction SilentlyContinue
        }
    }

    Write-EventLog -LogName $logName -Source $logSource -EventID 3002 -Message "admin privileges have been revoked"
}


function grant {
   $Ev = Get-EventLog -LogName $logName -Newest 1

   if ($Ev.EventID -eq 3004 ){
       $entraUser = $Ev.Message.Trim()
       $admin = Get-LocalGroupMember -Group TempAdmin -Member $entraUser -ErrorAction SilentlyContinue
       $adminName = $admin.Name

       if ($admin.Name) {
          Add-LocalGroupMember -Group Administrators -Member $entraUser -ErrorAction SilentlyContinue
          Write-EventLog -LogName $logName -Source $logSource -EventID 3005 -Message "admin granted, $adminName"
       }
   }
}


#get current local Administrators and add them to TempAdmin group
#remove them from Administrators group
function revoke_old {

    $admins = Get-LocalGroupMember -Group Administrators
    foreach ($member in $admins) {
        write-host $member.sid
        if (($member.PrincipalSource -eq "ActiveDirectory") -and ($member.ObjectClass -eq "User")){
            Write-Host $member.Name
            Add-LocalGroupMember -Group TempAdmin -Member $member
            Remove-LocalGroupMember -Group Administrators -Member $member
        }
    }
    Write-EventLog  -LogName $logName -Source $logSource -EventID 3002 -Message "admin privileges have been revoked"
}


function request {
    $entraUser = Get-EntraPrincipal
    $adminUser = Get-LocalGroupMember -Group TempAdmin -Member $entraUser -ErrorAction SilentlyContinue

    Add-Type -AssemblyName Microsoft.VisualBasic

    if ($adminUser) {
        $adminName = $adminUser.Name
        do {
            $reason = [Microsoft.VisualBasic.Interaction]::InputBox(
                'Please enter the reason you need admin rights in the text field below (at least 10 characters)',
                'Why do you need admin rights?',
                ""
            )
            if (-not ($reason)) {$reason = "-1"}
            write-host "reason $reason"
            $l = $reason.Length
            Write-Host("length $l")
        } while (($reason -ne "-1") -and ($reason.Length -lt 10))

        if ($reason.Length -ge 10){
            $msg = "You are now a member of the Administrators group. Membership will be revoked after 30 minutes."
            [Microsoft.VisualBasic.Interaction]::MsgBox($msg, 'okonly,information', $appName)
            Write-EventLog -LogName $logName -Source $logSource -EventID 3003 -Message "$adminName, $reason"

            # CHANGED: write Entra identity instead of SID
            Write-EventLog -LogName $logName -Source $logSource -EventID 3004 -Message $entraUser
        } else {
            $msg = "Cancelled. You didn't enter the reason you need admin rights"
            [Microsoft.VisualBasic.Interaction]::MsgBox($msg, 'okonly,exclamation', $appName)
        }
    } else {
        $msg = "Access denied. Please contact CorpIT if you need admin rights"
        [Microsoft.VisualBasic.Interaction]::MsgBox($msg, 'okonly,critical', $appName)
    }
}




$param1=$args[0]

write-host $param1
#$param1 = "revoke"


switch($param1) {
   "grant" {grant}
   "revoke" {revoke}
   "request" {request}
   default {request}
}
