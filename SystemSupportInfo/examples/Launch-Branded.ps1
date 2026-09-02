#requires -Version 5.1

<#
    Runtime-override example.

    Change the example URL before using this file in production. For durable
    organization-wide customization, edit config/SystemSupportInfo.config.psd1.
#>

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$launcher = Join-Path $projectRoot 'SystemSupportInfo.ps1'

& $launcher `
    -WindowTitle 'Contoso IT Support' `
    -ServiceDeskUrl 'https://support.example.com' `
    -ServiceDeskButtonText 'Open IT Service Desk'

