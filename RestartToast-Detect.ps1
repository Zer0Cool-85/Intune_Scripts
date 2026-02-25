<#
.SYNOPSIS
    Checks current device uptime for proactive remediation reboot toast.

.DESCRIPTION
    If uptime is greater than 4 days, script will exit with code 1 and trigger remediation script.

#>
Function Get-DeviceUpTime
	{
	    $Last_reboot = Get-ciminstance Win32_OperatingSystem | Select-Object -Exp LastBootUpTime
		$Check_FastBoot = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ea silentlycontinue).HiberbootEnabled 
		If(($null -eq $Check_FastBoot) -or ($Check_FastBoot -eq 0))
			{
				$Boot_Event = Get-WinEvent -ProviderName 'Microsoft-Windows-Kernel-Boot'| Where-Object {$_.ID -eq 27 -and $_.message -like "*0x0*"}
				If($null -ne $Boot_Event)
					{
						$Last_boot = $Boot_Event[0].TimeCreated
					}
			}
		ElseIf($Check_FastBoot -eq 1)
			{
				$Boot_Event = Get-WinEvent -ProviderName 'Microsoft-Windows-Kernel-Boot'| Where-Object {$_.ID -eq 27 -and $_.message -like "*0x1*"}
				If($null -ne $Boot_Event)
					{
						$Last_boot = $Boot_Event[0].TimeCreated
					}
			}		
			
		If($null -eq $Last_boot)
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

if ($Uptime -ge 5){
    Write-Output "Current uptime: $($Uptime) days, notify user to restart"
    Exit 1
}else {
    Write-Output "Current uptime: $($Uptime) days, all good"
    Exit 0
}