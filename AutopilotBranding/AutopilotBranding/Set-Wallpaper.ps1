#region set-wallpaper function
Function Set-WallPaper {
    <#
    .SYNOPSIS
    Applies a specified wallpaper to the current user's desktop
    
    .PARAMETER Image
    Provide the exact path to the image
 
    .PARAMETER Style
    Provide wallpaper style (Example: Fill, Fit, Stretch, Tile, Center, or Span)
  
    .EXAMPLE
    Set-WallPaper -Image "C:\Wallpaper\Default.jpg"
    Set-WallPaper -Image "C:\Wallpaper\Background.jpg" -Style Fit
#>
    param (
        [parameter(Mandatory = $True)]
        # Provide path to image
        [string]$Image,
        # Provide wallpaper style that you would like applied
        [parameter(Mandatory = $False)]
        [ValidateSet('Fill', 'Fit', 'Stretch', 'Tile', 'Center', 'Span')]
        [string]$Style
    )
    $WallpaperStyle = Switch ($Style) {
  
        "Fill" { "10" }
        "Fit" { "6" }
        "Stretch" { "2" }
        "Tile" { "0" }
        "Center" { "0" }
        "Span" { "22" }
  
    }
 
    If ($Style -eq "Tile") {
 
        New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -PropertyType String -Value $WallpaperStyle -Force
        New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -PropertyType String -Value 1 -Force
 
    }
    Else {
 
        New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -PropertyType String -Value $WallpaperStyle -Force
        New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -PropertyType String -Value 0 -Force
 
    }
 
    Add-Type -TypeDefinition @" 
using System; 
using System.Runtime.InteropServices;
  
public class Params
{ 
    [DllImport("User32.dll",CharSet=CharSet.Unicode)] 
    public static extern int SystemParametersInfo (Int32 uAction, 
                                                   Int32 uParam, 
                                                   String lpvParam, 
                                                   Int32 fuWinIni);
}
"@ 
  
    $SPI_SETDESKWALLPAPER = 0x0014
    $UpdateIniFile = 0x01
    $SendChangeEvent = 0x02
  
    $fWinIni = $UpdateIniFile -bor $SendChangeEvent
  
    $ret = [Params]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $Image, $fWinIni)
}
#endregion

# Registry variables, use them to create entry when task runs and sets the wallpaper
$RegistryPath = 'HKCU:\Software\Company'
$Name = 'WallpaperSchdTask'
$Value = '1'

if (-Not (Test-Path $RegistryPath)) {
    $null = New-Item -Path $RegistryPath
}

$regKey = Get-ItemProperty -Path $RegistryPath -Name $Name -ErrorAction SilentlyContinue

if (($regKey -eq "") -or ($null -eq $regKey)) {
    Write-Output "Set registry key and wallpaper."
    $null = New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType DWORD -Force
    $null = Set-WallPaper -Image "C:\Windows\web\wallpaper\Autopilot\Wallpaper.jpg" -Style Fill
    Exit 0
}
elseif ($regKey.WallpaperSchdTask -eq 1) {
    Write-Output "Do nothing and disable."
    $null = Disable-ScheduledTask -TaskName "Set-Wallpaper"
    Exit 0
}
else {
    Write-Output "Do nothing and disable."
    $null = Disable-ScheduledTask -TaskName "Set-Wallpaper"
    Exit 0
}