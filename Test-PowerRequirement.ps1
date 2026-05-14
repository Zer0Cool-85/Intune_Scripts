function Test-PowerRequirement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MinimumBatteryPercent = 50
    )

    Add-Type -AssemblyName System.Windows.Forms

    # If there is no battery object, treat it like a desktop and allow the script to continue
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $battery) {
        return [pscustomobject]@{
            HasBattery      = $false
            OnACPower       = $true
            BatteryPercent  = $null
            ShouldBlock     = $false
            Reason          = 'No battery detected.'
        }
    }

    $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
    $powerLineStatus = $powerStatus.PowerLineStatus.ToString()
    $batteryPercent = [math]::Round(($powerStatus.BatteryLifePercent * 100), 0)

    $onBattery = ($powerLineStatus -eq 'Offline')
    $shouldBlock = $onBattery -and ($batteryPercent -lt $MinimumBatteryPercent)

    return [pscustomobject]@{
        HasBattery      = $true
        OnACPower       = -not $onBattery
        BatteryPercent  = [int]$batteryPercent
        ShouldBlock     = $shouldBlock
        Reason          = if ($shouldBlock) {
            "On battery at $batteryPercent% charge."
        }
        else {
            "Power state is $powerLineStatus with battery at $batteryPercent%."
        }
    }
}
