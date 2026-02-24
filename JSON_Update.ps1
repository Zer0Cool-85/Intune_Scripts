<# 
Update JSON "name"/"displayName" fields and save copies into a new folder
named from the UPDATED display name.

Renames inside JSON:
- Replaces leading "Win - OIB -" with "[Baseline]"
- Removes trailing " - v<digits[.digits]...>" (e.g. " - v3.7", " - v3.0.1")

Output:
- Writes updated JSON to -OutPath
- Output filename = "<UpdatedName>__<id>.json" (sanitized) to avoid collisions
- Originals remain unchanged

Example:
.\Update-JsonNamesToNewFolder.ps1 -InputPath "C:\Temp\Jsons" -OutPath "C:\Temp\Jsons\Updated" -Recurse -WhatIf
Then run again without -WhatIf
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$InputPath,

    [Parameter(Mandatory)]
    [string]$OutPath,

    [switch]$Recurse
)

function Get-TargetNameProperty {
    param([pscustomobject]$Obj)

    if ($Obj.PSObject.Properties.Name -contains 'displayName') { return 'displayName' }
    if ($Obj.PSObject.Properties.Name -contains 'name')        { return 'name' }
    return $null
}

function Convert-PolicyName {
    param([Parameter(Mandatory)][string]$Value)

    $updated = $Value

    # 1) Prefix swap: "Win - OIB -" -> "[Baseline]"
    $updated = $updated -replace '^\s*Win\s*-\s*OIB\s*-\s*', '[Baseline] '

    # 2) Remove the policy-type identifier immediately after the prefix
    # Only when it matches: WUfB, ES, SC, TP
    # Example: "[Baseline] ES - Attack Surface Reduction ..." -> "[Baseline] Attack Surface Reduction ..."
    $updated = $updated -replace '^\s*\[Baseline\]\s+(WUfB|ES|SC|TP)\s*-\s*', '[Baseline] '

    # 3) Strip trailing version suffix like:
    # " - v3.7" / " - v3" / " - v3.7.1" / " - v3.7-beta" / " - v3.7 (Preview)"
    $updated = $updated -replace '\s*-\s*v\d+(?:\.\d+)*(?:[A-Za-z0-9\-\s\(\)]*)?\s*$', ''

    # 4) Tidy whitespace
    $updated = ($updated -replace '\s{2,}', ' ').Trim()

    return $updated
}


function Convert-ToSafeFileName {
    param([Parameter(Mandatory)][string]$Name)

    # Replace invalid filename chars with underscore
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $safe = ($Name.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } }) -join ''

    # Avoid trailing dots/spaces (Windows limitation)
    $safe = $safe.Trim().TrimEnd('.')

    # Prevent empty
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'unnamed' }

    # Optional: keep filenames from getting ridiculous
    if ($safe.Length -gt 140) { $safe = $safe.Substring(0,140).Trim() }

    return $safe
}

# Ensure output folder exists
New-Item -ItemType Directory -Path $OutPath -Force | Out-Null

# Collect JSON files
$gciParams = @{
    Path   = $InputPath
    Filter = '*.json'
    File   = $true
}
if ($Recurse) { $gciParams.Recurse = $true }

$files = Get-ChildItem @gciParams

if (-not $files) {
    Write-Warning "No .json files found under: $InputPath"
    return
}

foreach ($file in $files) {
    try {
        $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop

        $prop = Get-TargetNameProperty -Obj $obj
        if (-not $prop) {
            Write-Warning "Skipping (no name/displayName): $($file.FullName)"
            continue
        }

        $oldName = [string]$obj.$prop
        $newName = Convert-PolicyName -Value $oldName

        # Update JSON object
        $obj.$prop = $newName

        # Build a collision-resistant output filename:
        # Prefer id if present, else fallback to original basename
        $idPart = if ($obj.PSObject.Properties.Name -contains 'id' -and $obj.id) { [string]$obj.id } else { $file.BaseName }
        $safeName = Convert-ToSafeFileName -Name $newName

        $outFile = Join-Path $OutPath ("{0}__{1}.json" -f $safeName, $idPart)

        # Convert back to JSON (large depth for Graph exports)
        $jsonOut = $obj | ConvertTo-Json -Depth 100

        if ($PSCmdlet.ShouldProcess($outFile, "Write updated JSON from '$($file.FullName)'")) {
            Set-Content -LiteralPath $outFile -Value $jsonOut -Encoding UTF8
            Write-Host "Wrote: $outFile" -ForegroundColor Green
            Write-Host "  $prop: $oldName -> $newName"
        }
    }
    catch {
        Write-Warning "Failed: $($file.FullName)`n$($_.Exception.Message)"
    }
}

Write-Host "Done. Updated files saved to: $OutPath" -ForegroundColor Cyan
