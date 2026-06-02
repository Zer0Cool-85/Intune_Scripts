<#
.SYNOPSIS
    Intune Win32 app detection script for Termination Lockdown.

.DESCRIPTION
    Returns exit 0 when the lockdown registry marker exists and State is Locked.
    Returns exit 1 otherwise.
#>

$RegPath = 'HKLM:\SOFTWARE\Company\TerminationLockdown'

try {
    $state = Get-ItemProperty -Path $RegPath -Name State -ErrorAction Stop

    if ($state.State -eq 'Locked') {
        exit 0
    }
}
catch {
    exit 1
}

exit 1
