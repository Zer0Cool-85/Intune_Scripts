<#
.SYNOPSIS
    Checks current device uptime for proactive remediation reboot toast.

.DESCRIPTION
    If uptime is greater than 7 days, script will exit with code 1 and trigger remediation script.

#>
Function Get-DeviceUpTime
	{
	    $Last_reboot = Get-ciminstance Win32_OperatingSystem | Select -Exp LastBootUpTime
		$Check_FastBoot = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ea silentlycontinue).HiberbootEnabled 
		If(($Check_FastBoot -eq $null) -or ($Check_FastBoot -eq 0))
			{
				$Boot_Event = Get-WinEvent -ProviderName 'Microsoft-Windows-Kernel-Boot'| where {$_.ID -eq 27 -and $_.message -like "*0x0*"}
				If($Boot_Event -ne $null)
					{
						$Last_boot = $Boot_Event[0].TimeCreated
					}
			}
		ElseIf($Check_FastBoot -eq 1)
			{
				$Boot_Event = Get-WinEvent -ProviderName 'Microsoft-Windows-Kernel-Boot'| where {$_.ID -eq 27 -and $_.message -like "*0x1*"}
				If($Boot_Event -ne $null)
					{
						$Last_boot = $Boot_Event[0].TimeCreated
					}
			}		
			
		If($Last_boot -eq $null)
			{
				$Uptime = $Uptime = $Last_reboot
			}
		Else
			{
				If($Last_reboot -ge $Last_boot)
					{
						$Uptime = $Last_reboot
					}
				Else
					{
						$Uptime = $Last_boot
					}
			}
		
		$Current_Date = get-date
		$Diff_boot_time = $Current_Date - $Uptime
		$Boot_Uptime_Days = $Diff_boot_time.Days	
		$Boot_Uptime_Days
}

$Uptime = Get-DeviceUpTime

if ($Uptime -gt 7){
    Write-Output "Device has not rebooted in $($Uptime) days, force user to reboot"
    Exit 1
}else {
    Write-Output "Device rebooted $($Uptime) days ago, all good"
    Exit 0
}