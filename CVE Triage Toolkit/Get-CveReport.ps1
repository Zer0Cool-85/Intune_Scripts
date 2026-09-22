#requires -Version 5.1
<#
.SYNOPSIS
Turn CVE IDs or pasted ticket text into a searchable HTML report and CSV exports.
.DESCRIPTION
Reads official public CVE JSON, CISA KEV, and FIRST EPSS data. No API key,
admin rights, third-party PowerShell module, or Zendesk access is required.
Only extracted CVE IDs are used in requests; the ticket text stays local.
This is an advisory aggregation tool, not an endpoint vulnerability scanner.
.EXAMPLE
.\Get-CveReport.ps1 -Clipboard -OpenReport
.EXAMPLE
.\Get-CveReport.ps1 -InputPath .\ticket.txt -OpenReport
.EXAMPLE
.\Get-CveReport.ps1 -Text 'CVE-2023-36884 CVE-2023-26360'
#>
[CmdletBinding(DefaultParameterSetName = 'File')]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'File')]
    [string]$InputPath,
    [Parameter(Mandatory = $true, ParameterSetName = 'Text')]
    [string[]]$Text,
    [Parameter(Mandatory = $true, ParameterSetName = 'Clipboard')]
    [switch]$Clipboard,
    [string]$OutputDirectory = (Join-Path (Get-Location).Path 'CveReports'),
    [switch]$SkipEpss,
    [switch]$OpenReport
)

$ErrorActionPreference = 'Stop'
$toolVersion = '1.0.0'
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Get-Json {
    param([string]$Uri)
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 30 -Headers @{
                Accept = 'application/json'
                'User-Agent' = "CVE-Triage-Toolkit/$toolVersion"
            } -ErrorAction Stop
        } catch {
            $status = 0
            try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            if (($status -ge 400 -and $status -lt 500 -and $status -ne 429) -or $attempt -eq 2) { throw }
            $delay = [int][Math]::Pow(2, $attempt + 1)
            # Respect a longer Retry-After by stopping, rather than retrying too soon.
            $retryAfter = $null
            try { $retryAfter = $_.Exception.Response.Headers['Retry-After'] } catch { }
            $seconds = 0
            if ($retryAfter -and [int]::TryParse([string]$retryAfter, [ref]$seconds)) {
                if ($seconds -gt 30) { throw }
                $delay = [Math]::Max($delay, $seconds)
            }
            Start-Sleep -Seconds $delay
        }
    }
}

function Write-Json {
    param($Value, [string]$Path)
    ConvertTo-Json -InputObject $Value -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-EnglishText {
    param($Items)
    $itemsArray = @($Items | Where-Object { $null -ne $_ })
    $english = @($itemsArray | Where-Object { $_.lang -match '^en($|-)' })
    if ($english.Count -gt 0) { return (($english | ForEach-Object { $_.value }) -join "`n") }
    if ($itemsArray.Count -gt 0) { return [string]$itemsArray[0].value }
    return ''
}

function Get-VersionStatement {
    param($Version)
    $status = [string]$Version.status
    if (-not $status) { $status = 'unknown status' }
    $start = [string]$Version.version
    if (-not $start) { $start = '[start not provided]' }
    $range = $start
    if ($null -ne $Version.lessThan) { $range += " to < $($Version.lessThan)" }
    if ($null -ne $Version.lessThanOrEqual) { $range += " to <= $($Version.lessThanOrEqual)" }
    $statement = "${status}: $range"
    if ($Version.versionType) { $statement += " (version type: $($Version.versionType))" }
    foreach ($change in @($Version.changes | Where-Object { $null -ne $_ })) {
        $statement += "; status changes at $($change.at) to $($change.status)"
    }
    return $statement
}

function ConvertTo-SafeCsvRows {
    param([object[]]$Rows)
    foreach ($row in $Rows) {
        $safe = [ordered]@{}
        foreach ($property in $row.PSObject.Properties) {
            $value = $property.Value
            if ($value -is [string] -and $value -match '^\s*[=+@-]') { $value = "'$value" }
            $safe[$property.Name] = $value
        }
        [pscustomobject]$safe
    }
}

function ConvertTo-HtmlText { param($Value) return [System.Net.WebUtility]::HtmlEncode([string]$Value) }
function New-HtmlTable {
    param([object[]]$Rows, [string[]]$Columns)
    if (-not $Rows -or $Rows.Count -eq 0) { return '<p class="muted">Not provided in the source record.</p>' }
    $html = New-Object System.Text.StringBuilder
    [void]$html.Append('<div class="table-scroll"><table><thead><tr>')
    foreach ($column in $Columns) { [void]$html.Append('<th>' + (ConvertTo-HtmlText $column) + '</th>') }
    [void]$html.Append('</tr></thead><tbody>')
    foreach ($row in $Rows) {
        [void]$html.Append('<tr>')
        foreach ($column in $Columns) { [void]$html.Append('<td>' + (ConvertTo-HtmlText $row.$column) + '</td>') }
        [void]$html.Append('</tr>')
    }
    [void]$html.Append('</tbody></table></div>')
    return $html.ToString()
}

switch ($PSCmdlet.ParameterSetName) {
    'File' { $ticketText = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8 }
    'Text' { $ticketText = $Text -join "`n" }
    'Clipboard' { $ticketText = Get-Clipboard -Raw }
}
# Also recognize URL-encoded IDs and common Unicode hyphens from copied text.
$ticketText = [System.Net.WebUtility]::HtmlDecode([string]$ticketText)
$ticketText = [Uri]::UnescapeDataString($ticketText) -replace '[\u2010-\u2015\u2212]', '-'
$ids = @([regex]::Matches($ticketText, '(?i)\bCVE-[0-9]{4}-[0-9]{4,}\b') |
    ForEach-Object { $_.Value.ToUpperInvariant() } | Sort-Object -Unique)
if ($ids.Count -eq 0) {
    throw 'No CVE IDs were found. Copy the ticket text including the CVE IDs or full CVE URLs. Generic advisory URLs without IDs are not expanded.'
}

$runName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$runPath = Join-Path $OutputDirectory $runName
$rawPath = Join-Path $runPath 'raw'
[void](New-Item -ItemType Directory -Path $rawPath -Force)
$runPath = (Resolve-Path -LiteralPath $runPath).Path
$rawPath = Join-Path $runPath 'raw'
$startedUtc = [DateTime]::UtcNow.ToString('o')
$warnings = New-Object 'System.Collections.Generic.List[string]'
Write-Host "Found $($ids.Count) unique CVEs. Loading public data..."

$kev = $null
$kevUri = ''
$kevMap = @{}
foreach ($uri in @(
    'https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json',
    'https://raw.githubusercontent.com/cisagov/kev-data/develop/known_exploited_vulnerabilities.json'
)) {
    try {
        $candidate = Get-Json $uri
        if (-not $candidate.catalogVersion -or -not $candidate.vulnerabilities -or
            @($candidate.vulnerabilities).Count -ne [int]$candidate.count) { throw 'Unexpected or incomplete KEV feed.' }
        foreach ($entry in $candidate.vulnerabilities) {
            if ($entry.cveID -notmatch '^CVE-\d{4}-\d{4,}$') { throw 'Unexpected KEV record.' }
        }
        $kev = $candidate
        $kevUri = $uri
        break
    } catch { [void]$warnings.Add("KEV source unavailable: $uri | $($_.Exception.Message)") }
}
if ($kev) {
    foreach ($entry in $kev.vulnerabilities) { $kevMap[[string]$entry.cveID] = $entry }
    Write-Json $kev (Join-Path $rawPath 'cisa-kev.json')
} else {
    Write-Warning 'KEV feed unavailable. KEV status will be Unknown, never Not listed.'
}

$epssMap = @{}
$epssStatus = @{}
foreach ($id in $ids) { $epssStatus[$id] = if ($SkipEpss) { 'Skipped' } else { 'Unknown - lookup failed' } }
if (-not $SkipEpss) {
    # Keep each request below FIRST's 2,000-character CVE parameter limit and 100-row default page size.
    $offset = 0
    $batchNumber = 0
    while ($offset -lt $ids.Count) {
        $batch = New-Object 'System.Collections.Generic.List[string]'
        $length = 0
        while ($offset -lt $ids.Count -and $batch.Count -lt 50 -and ($length + $ids[$offset].Length + 1) -le 1800) {
            [void]$batch.Add($ids[$offset])
            $length += $ids[$offset].Length + 1
            $offset++
        }
        if ($batch.Count -eq 0) { $offset++; continue }
        $batchNumber++
        try {
            $uri = 'https://api.first.org/data/v1/epss?cve=' + ($batch -join ',') + '&limit=100'
            $response = Get-Json $uri
            if ($response.status -ne 'OK' -or $null -eq $response.data -or
                [int]$response.total -ne @($response.data).Count) { throw 'Unexpected or incomplete EPSS response.' }
            foreach ($id in $batch) { $epssStatus[$id] = 'No score returned' }
            foreach ($entry in $response.data) {
                $score = [double]::Parse([string]$entry.epss, [Globalization.CultureInfo]::InvariantCulture)
                if ($entry.cve -in $batch -and $score -ge 0 -and $score -le 1) {
                    $epssMap[[string]$entry.cve] = $entry
                    $epssStatus[[string]$entry.cve] = 'Available'
                }
            }
            Write-Json $response (Join-Path $rawPath "epss-$batchNumber.json")
        } catch { [void]$warnings.Add("EPSS batch $batchNumber unavailable: $($_.Exception.Message)") }
    }
}

$reports = New-Object 'System.Collections.Generic.List[object]'
$productRows = New-Object 'System.Collections.Generic.List[object]'
$index = 0
foreach ($id in $ids) {
    $index++
    Write-Progress -Activity 'Collecting CVE records' -Status "$index / $($ids.Count): $id" -PercentComplete ($index * 100 / $ids.Count)
    $parts = $id.Split('-')
    $bucket = $parts[2].Substring(0, $parts[2].Length - 3) + 'xxx'
    $sourceUri = ''
    $record = $null
    $errors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($uri in @(
        "https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/$($parts[1])/$bucket/$id.json",
        "https://cveawg.mitre.org/api/cve/$id"
    )) {
        try {
            $candidate = Get-Json $uri
            if ($candidate.cveMetadata.cveId -ne $id -or -not $candidate.cveMetadata.state) { throw 'CVE identity or state is missing from response.' }
            $record = $candidate
            $sourceUri = $uri
            break
        } catch { [void]$errors.Add("$uri | $($_.Exception.Message)") }
    }
    $state = 'LOOKUP_FAILED'
    $title = 'Record unavailable - review required'
    $description = ''
    $products = @()
    $metrics = @()
    $references = @()
    $solutions = @()
    $workarounds = @()
    $published = ''
    $updated = ''
    if ($record) {
        Write-Json $record (Join-Path $rawPath "$id.json")
        $state = [string]$record.cveMetadata.state
        $published = [string]$record.cveMetadata.datePublished
        $updated = [string]$record.cveMetadata.dateUpdated
        $cna = $record.containers.cna
        $description = Get-EnglishText $cna.descriptions
        if ($state -eq 'REJECTED') { $description = Get-EnglishText $cna.rejectedReasons }
        $title = [string]$cna.title
        if (-not $title) {
            $title = $description
            if ($title.Length -gt 160) { $title = $title.Substring(0, 157) + '...' }
            if (-not $title) { $title = "No title provided ($state)" }
        }
        $containers = @($cna) + @($record.containers.adp)
        foreach ($container in @($containers | Where-Object { $null -ne $_ })) {
            $provider = [string]$container.providerMetadata.shortName
            if (-not $provider) { $provider = [string]$container.providerMetadata.orgId }
            foreach ($affected in @($container.affected | Where-Object { $null -ne $_ })) {
                $vendor = [string]$affected.vendor
                $product = [string]$affected.product
                if (-not $vendor) { $vendor = '[vendor not provided]' }
                if (-not $product) { $product = '[product not provided]' }
                $statements = @($affected.versions | Where-Object { $null -ne $_ } | ForEach-Object { Get-VersionStatement $_ })
                if ($statements.Count -eq 0) { $statements = @('Version details not provided; consult vendor advisory.') }
                $defaultStatus = [string]$affected.defaultStatus
                if (-not $defaultStatus) { $defaultStatus = 'not provided' }
                $products += [pscustomobject][ordered]@{
                    Vendor = $vendor; Product = $product
                    Platforms = (@($affected.platforms) -join '; ')
                    Modules = (@($affected.modules) -join '; ')
                    'Version statements' = $statements -join "`n"
                    'Default status' = $defaultStatus; Source = $provider
                    VersionsJson = ConvertTo-Json -InputObject @($affected.versions) -Depth 30 -Compress
                }
            }
            foreach ($metric in @($container.metrics | Where-Object { $null -ne $_ })) {
                foreach ($field in @('cvssV4_0', 'cvssV3_1', 'cvssV3_0', 'cvssV2_0')) {
                    $value = $metric.$field
                    if ($null -ne $value -and $null -ne $value.baseScore) {
                        $metrics += [pscustomobject][ordered]@{
                            Version = [string]$value.version; Score = [double]$value.baseScore
                            Severity = [string]$value.baseSeverity; Vector = [string]$value.vectorString
                            Scenarios = (Get-EnglishText $metric.scenarios); Source = $provider
                        }
                    }
                }
            }
            foreach ($reference in @($container.references | Where-Object { $null -ne $_ })) {
                if ($reference.url -match '^https?://') { $references += [string]$reference.url }
            }
            $solution = Get-EnglishText $container.solutions
            if ($solution) { $solutions += "${provider}: $solution" }
            $workaround = Get-EnglishText $container.workarounds
            if ($workaround) { $workarounds += "${provider}: $workaround" }
        }
    } else {
        [void]$warnings.Add("$id could not be retrieved. Details in report.json.")
    }
    $references = @($references | Sort-Object -Unique)
    $kevEntry = $kevMap[$id]
    $kevStatus = if (-not $kev) { 'Unknown - feed unavailable' } elseif ($kevEntry) { 'Listed' } else { 'Not listed' }
    $epssEntry = $epssMap[$id]
    $epssProbability = $null
    $epssPercent = ''
    if ($epssEntry) {
        $epssProbability = [double]::Parse([string]$epssEntry.epss, [Globalization.CultureInfo]::InvariantCulture)
        $epssPercent = ($epssProbability * 100).ToString('0.000', [Globalization.CultureInfo]::InvariantCulture) + '%'
    }
    # Show every CVSS score. The compact headline uses highest score within newest available CVSS version.
    $headline = @($metrics | Sort-Object @{Expression = { [version]$_.Version }; Descending = $true},
        @{Expression = { $_.Score }; Descending = $true} | Select-Object -First 1)
    $cvssDisplay = 'Not provided'
    if ($headline.Count -gt 0) { $cvssDisplay = "$($headline[0].Score) (v$($headline[0].Version))" }
    $report = [pscustomobject][ordered]@{
        CVE = $id; State = $state; Title = $title; Description = $description
        Published = $published; Updated = $updated
        Vendors = (@($products.Vendor | Sort-Object -Unique) -join '; ')
        Products = (@($products.Product | Sort-Object -Unique) -join '; ')
        Affected = @($products); CVSS = $cvssDisplay; Metrics = @($metrics)
        KEV = $kevStatus; KEVDateAdded = [string]$kevEntry.dateAdded
        KEVRequiredAction = [string]$kevEntry.requiredAction; KEVNotes = [string]$kevEntry.notes
        EPSS = $epssProbability; EPSSPercent = $epssPercent; EPSSStatus = $epssStatus[$id]
        EPSSDate = [string]$epssEntry.date; EPSSPercentile = [string]$epssEntry.percentile
        Solutions = ($solutions -join "`n`n"); Workarounds = ($workarounds -join "`n`n")
        References = @($references); Applicability = 'Unverified - inventory comparison required'
        Source = $sourceUri; RetrievedUtc = [DateTime]::UtcNow.ToString('o'); LookupErrors = @($errors.ToArray())
    }
    [void]$reports.Add($report)
    foreach ($product in $products) {
        [void]$productRows.Add([pscustomobject][ordered]@{
            CVE = $id; State = $state; Vendor = $product.Vendor; Product = $product.Product
            Platforms = $product.Platforms; Modules = $product.Modules
            VersionStatements = $product.'Version statements'; DefaultStatus = $product.'Default status'
            VersionSource = $product.Source; VersionsJson = $product.VersionsJson
            CISA_KEV = $kevStatus; CVSS = $cvssDisplay; EPSSPercent = $epssPercent
            Applicability = $report.Applicability; AdvisoryURLs = ($references -join "`n")
        })
    }
    Start-Sleep -Milliseconds 250
}
Write-Progress -Activity 'Collecting CVE records' -Completed

$ordered = @($reports.ToArray() | Sort-Object @{Expression = { if ($_.KEV -eq 'Listed') { 0 } else { 1 } }},
    @{Expression = { if ($null -eq $_.EPSS) { -1 } else { $_.EPSS } }; Descending = $true}, CVE)
$manifest = [pscustomobject][ordered]@{
    ToolVersion = $toolVersion; StartedUtc = $startedUtc; CompletedUtc = [DateTime]::UtcNow.ToString('o')
    RequestedCVEs = $ids; KEVSource = $kevUri; KEVCatalogVersion = [string]$kev.catalogVersion
    KEVDateReleased = [string]$kev.dateReleased; Warnings = @($warnings.ToArray()); CVEs = $ordered
}
Write-Json $manifest (Join-Path $runPath 'report.json')
$summaryRows = @($ordered | Select-Object CVE, State, Title, Description, Vendors, Products, CVSS, KEV,
    KEVDateAdded, KEVRequiredAction, EPSSPercent, EPSSStatus, EPSSDate, Solutions, Workarounds,
    Applicability, Published, Updated, Source, @{Name = 'AdvisoryURLs'; Expression = { $_.References -join "`n" }})
ConvertTo-SafeCsvRows $summaryRows | Export-Csv -LiteralPath (Join-Path $runPath 'cve-summary.csv') -NoTypeInformation -Encoding UTF8
if ($productRows.Count -gt 0) {
    ConvertTo-SafeCsvRows $productRows.ToArray() | Export-Csv -LiteralPath (Join-Path $runPath 'cve-products.csv') -NoTypeInformation -Encoding UTF8
}

$cards = New-Object System.Text.StringBuilder
foreach ($row in $ordered) {
    $search = (@($row.CVE, $row.Title, $row.Description, $row.Products, $row.Vendors,
        ($row.Affected.'Version statements' -join ' ')) -join ' ').ToLowerInvariant()
    $listed = if ($row.KEV -eq 'Listed') { 'yes' } else { 'no' }
    $unresolved = if ($row.State -ne 'PUBLISHED' -or $row.Affected.Count -eq 0 -or $row.KEV -like 'Unknown*') { 'yes' } else { 'no' }
    [void]$cards.Append('<details class="cve" data-search="' + (ConvertTo-HtmlText $search) + '" data-kev="' + $listed + '" data-unresolved="' + $unresolved + '">')
    [void]$cards.Append('<summary><div><strong>' + (ConvertTo-HtmlText $row.CVE) + '</strong><span class="title">' + (ConvertTo-HtmlText $row.Title) + '</span></div><div class="badges">')
    if ($listed -eq 'yes') { [void]$cards.Append('<span class="badge exploited">CISA KEV</span>') }
    if ($row.State -ne 'PUBLISHED') { [void]$cards.Append('<span class="badge caution">' + (ConvertTo-HtmlText $row.State) + '</span>') }
    [void]$cards.Append('<span class="badge">CVSS ' + (ConvertTo-HtmlText $row.CVSS) + '</span></div></summary><div class="detail">')
    [void]$cards.Append('<p class="preserve">' + (ConvertTo-HtmlText $row.Description) + '</p>')
    [void]$cards.Append('<div class="facts"><p><b>CISA KEV</b><br>' + (ConvertTo-HtmlText $row.KEV) + '</p><p><b>EPSS probability</b><br>')
    if ($row.EPSSPercent) { [void]$cards.Append((ConvertTo-HtmlText $row.EPSSPercent) + ' &middot; ' + (ConvertTo-HtmlText $row.EPSSDate)) }
    else { [void]$cards.Append((ConvertTo-HtmlText $row.EPSSStatus)) }
    [void]$cards.Append('</p><p><b>Applicability</b><br>Inventory comparison required</p></div><h3>Products and published version statements</h3>')
    [void]$cards.Append((New-HtmlTable -Rows $row.Affected -Columns @('Vendor', 'Product', 'Platforms', 'Modules', 'Version statements', 'Default status', 'Source')))
    [void]$cards.Append('<p class="muted">Version labels and status changes are preserved from the publisher. An upper bound is not automatically a verified fix. Check the release track, platform, configuration and vendor advisory.</p>')
    [void]$cards.Append('<h3>Remediation guidance</h3>')
    if ($row.KEVRequiredAction) { [void]$cards.Append('<p class="preserve"><b>CISA required action:</b> ' + (ConvertTo-HtmlText $row.KEVRequiredAction) + '</p>') }
    if ($row.Solutions) { [void]$cards.Append('<p class="preserve"><b>Published solutions:</b> ' + (ConvertTo-HtmlText $row.Solutions) + '</p>') }
    else { [void]$cards.Append('<p>No structured solution is provided in the CVE record. Check the vendor bulletin below for the correct fixed version or KB.</p>') }
    if ($row.Workarounds) { [void]$cards.Append('<p class="preserve"><b>Published workarounds:</b> ' + (ConvertTo-HtmlText $row.Workarounds) + '</p>') }
    [void]$cards.Append('<h3>References</h3><ul class="references">')
    foreach ($uri in $row.References) { [void]$cards.Append('<li><a rel="noreferrer noopener" href="' + (ConvertTo-HtmlText $uri) + '">' + (ConvertTo-HtmlText $uri) + '</a></li>') }
    [void]$cards.Append('<li><a href="https://www.cve.org/CVERecord?id=' + (ConvertTo-HtmlText $row.CVE) + '">CVE Program record</a></li></ul>')
    [void]$cards.Append('<details class="scores"><summary>All published CVSS scores and source details</summary>')
    [void]$cards.Append((New-HtmlTable -Rows $row.Metrics -Columns @('Version', 'Score', 'Severity', 'Scenarios', 'Vector', 'Source')))
    [void]$cards.Append('<p>Published: ' + (ConvertTo-HtmlText $row.Published) + '<br>Updated: ' + (ConvertTo-HtmlText $row.Updated) + '<br>Retrieved: ' + (ConvertTo-HtmlText $row.RetrievedUtc) + '<br>Source: ' + (ConvertTo-HtmlText $row.Source) + '</p>')
    if ($row.LookupErrors.Count -gt 0) { [void]$cards.Append('<p class="preserve">' + (ConvertTo-HtmlText ($row.LookupErrors -join "`n")) + '</p>') }
    [void]$cards.Append('</details></div></details>')
}

$productIndex = New-Object System.Text.StringBuilder
$productGroups = @($productRows.ToArray() | Group-Object Vendor, Product | Sort-Object Name)
foreach ($group in $productGroups) {
    $first = $group.Group[0]
    $count = @($group.Group.CVE | Sort-Object -Unique).Count
    [void]$productIndex.Append('<button class="product" data-product="' + (ConvertTo-HtmlText $first.Product) + '">' +
        (ConvertTo-HtmlText ($first.Vendor + ' / ' + $first.Product)) + ' <b>' + $count + '</b></button>')
}
$warningHtml = ''
if ($warnings.Count -gt 0) {
    $warningHtml = '<details class="warning"><summary>Source notices (' + $warnings.Count + ')</summary><ul>' +
        (($warnings.ToArray() | ForEach-Object { '<li>' + (ConvertTo-HtmlText $_) + '</li>' }) -join '') + '</ul></details>'
}
$template = @'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>CVE triage report</title>
<style>
:root{color-scheme:light;--ink:#15283e;--muted:#53667a;--line:#d7e0e9;--blue:#0756b4}*{box-sizing:border-box}
body{margin:0;background:#f1f5f9;color:var(--ink);font:15px/1.55 system-ui,-apple-system,Segoe UI,sans-serif}
main{max-width:1360px;margin:auto;padding:36px 28px 70px}h1{font-size:36px;margin:4px 0 12px;line-height:1.15}h2{font-size:21px}h3{font-size:16px;margin-top:25px}
.eyebrow{color:var(--blue);font-size:12px;font-weight:800;letter-spacing:.16em;text-transform:uppercase}.muted{color:var(--muted);font-size:13px}
.intro{max-width:920px}.stats{display:flex;gap:12px;margin:24px 0}.stat{background:white;border:1px solid var(--line);border-radius:10px;padding:16px 24px;flex:1}.stat b{display:block;font-size:29px;line-height:1.15}
.toolbar{display:flex;gap:18px;align-items:center;flex-wrap:wrap;background:#fff;border:1px solid var(--line);border-radius:10px;padding:16px;margin:20px 0}
input[type=search]{min-width:240px;flex:1;font:inherit;padding:11px;border:1px solid #9bb0c5;border-radius:6px}.toolbar button,.product{font:inherit;cursor:pointer;border:1px solid var(--line);border-radius:6px;background:white;color:var(--blue);padding:7px 11px}
button:hover{background:#e9f2fc}button:focus-visible,input:focus-visible,summary:focus-visible{outline:3px solid #3275cc;outline-offset:2px}
.products{margin:20px 0}.product{font-size:12px;margin:4px 4px 4px 0;text-align:left}.product b{margin-left:7px}
details.cve{background:white;border:1px solid var(--line);border-radius:10px;margin:12px 0;overflow:hidden}summary{cursor:pointer}
.cve>summary{display:flex;align-items:center;justify-content:space-between;gap:20px;padding:19px 20px;list-style:none}.cve>summary::before{content:'+';font-size:20px;color:var(--blue)}.cve[open]>summary::before{content:'\2212'}.cve>summary>div:first-of-type{flex:1}.title{display:block;font-size:14px;color:var(--muted);margin-top:5px}
.badges{display:flex;flex-wrap:wrap;gap:7px;justify-content:flex-end}.badge{font-size:12px;padding:4px 9px;border-radius:5px;background:#eaf0f7;white-space:nowrap}.exploited{background:#fde2df;color:#932e27}.caution,.warning{background:#fff1cd;color:#745314}.warning{padding:12px;border-radius:8px;margin-top:18px}
.detail{border-top:1px solid var(--line);padding:5px 22px 24px}.facts{display:flex;flex-wrap:wrap;gap:35px}.facts p{font-size:13px}.preserve,td{white-space:pre-wrap}.table-scroll{overflow:auto}table{width:100%;border-collapse:collapse;font-size:12px}th,td{text-align:left;vertical-align:top;padding:10px 12px;border-bottom:1px solid var(--line);min-width:90px}th{background:#edf3f9}td:nth-child(5){min-width:240px}
a{color:var(--blue);overflow-wrap:anywhere}.references{font-size:13px;padding-left:20px}.scores{font-size:12px;margin-top:22px}.scores summary{font-weight:700;margin-bottom:10px}footer{font-size:12px;color:var(--muted);margin-top:30px}
[hidden]{display:none!important}@media(max-width:700px){main{padding:24px 14px}.stats{flex-wrap:wrap}.stat{padding:12px}.cve>summary{align-items:flex-start;padding:14px;gap:10px}.badges{max-width:115px}.detail{padding:8px 14px 18px}h1{font-size:30px}}
@media print{body{background:white}.toolbar,.products{display:none}.cve{break-inside:avoid}.stats{margin:10px 0}main{padding:0}.detail{display:block}}
</style></head><body><main>
<div class="eyebrow">Vulnerability review / public advisory data</div><h1>CVE triage report</h1>
<p class="intro">Search the products, versions and vulnerability details from the ticket in one place. Expand a CVE for the original description, version statements and advisory links.</p>
<p class="muted">Generated {{GENERATED}} &middot; CISA KEV catalog {{CATALOG}} &middot; No endpoint inventory was evaluated.</p>
<div class="stats"><div class="stat"><b>{{TOTAL}}</b>unique CVEs</div><div class="stat"><b>{{KEV}}</b>listed in CISA KEV</div><div class="stat"><b>{{PRODUCTS}}</b>vendor/product combinations</div><div class="stat"><b>{{UNRESOLVED}}</b>need data review</div></div>
<p class="intro muted">KEV listing means known exploitation in the wild; absence does not establish safety. EPSS is the modeled probability of exploitation in the next 30 days, not the probability that your organization will be compromised. Records are ordered by KEV listing, then EPSS. Missing data stays unknown.</p>
{{WARNINGS}}
<details class="products"><summary><b>Browse products</b> &mdash; select a product to search</summary>{{PRODUCTINDEX}}</details>
<div class="toolbar"><input id="q" type="search" aria-label="Search CVEs" placeholder="Search: Acrobat, ColdFusion, Windows 11, CVE..."><label><input type="checkbox" id="kev"> CISA KEV only</label><label><input type="checkbox" id="unresolved"> Data review only</label><button id="clear">Clear</button><button id="expand">Expand visible</button><button id="collapse">Collapse all</button></div>
<p id="count" class="muted" aria-live="polite"></p><noscript><p>Enable JavaScript to filter the report. All records remain readable below.</p></noscript>
<section id="records">{{CARDS}}</section>
<footer>All applicability decisions remain unverified until matched to current inventory. "Data review" flags an unavailable/non-published CVE, missing product details or an unavailable KEV feed; it is not an applicability decision. Published version ranges may be incomplete or inconsistent. Use vendor guidance to validate fixed versions, KBs, cumulative update supersedence and required configurations. All CVSS entries are retained; the headline shows the highest score within the newest CVSS version present. Source snapshots are in raw/ and report.json.</footer>
</main><script>
const q=document.getElementById('q'),kev=document.getElementById('kev'),unresolved=document.getElementById('unresolved');
const cards=Array.from(document.querySelectorAll('details.cve'));
function filter(){const term=q.value.toLowerCase().trim();let shown=0;cards.forEach(c=>{c.hidden=!!((term&&!c.dataset.search.includes(term))||(kev.checked&&c.dataset.kev!=='yes')||(unresolved.checked&&c.dataset.unresolved!=='yes'));if(!c.hidden)shown++;});document.getElementById('count').textContent=shown+' of '+cards.length+' CVEs shown';}
q.addEventListener('input',filter);kev.addEventListener('change',filter);unresolved.addEventListener('change',filter);
document.getElementById('clear').addEventListener('click',()=>{q.value='';kev.checked=false;unresolved.checked=false;filter();});
document.getElementById('expand').addEventListener('click',()=>cards.forEach(c=>{if(!c.hidden)c.open=true;}));
document.getElementById('collapse').addEventListener('click',()=>cards.forEach(c=>c.open=false));
document.querySelectorAll('[data-product]').forEach(b=>b.addEventListener('click',()=>{q.value=b.dataset.product;filter();q.focus();}));filter();
</script></body></html>
'@
$tokens = @{
    GENERATED = ConvertTo-HtmlText ([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm') + ' UTC')
    CATALOG = ConvertTo-HtmlText $(if ($kev) { $kev.catalogVersion } else { 'unavailable' })
    TOTAL = [string]$ordered.Count; KEV = [string]@($ordered | Where-Object { $_.KEV -eq 'Listed' }).Count
    PRODUCTS = [string]$productGroups.Count
    UNRESOLVED = [string]@($ordered | Where-Object { $_.State -ne 'PUBLISHED' -or $_.Affected.Count -eq 0 -or $_.KEV -like 'Unknown*' }).Count
    WARNINGS = $warningHtml; PRODUCTINDEX = $productIndex.ToString(); CARDS = $cards.ToString()
}
# Single-pass replacement prevents source text containing template tokens from being reinterpreted.
$html = [regex]::Replace($template, '\{\{([A-Z]+)\}\}', [System.Text.RegularExpressions.MatchEvaluator]{
    param($match) return [string]$tokens[$match.Groups[1].Value]
})
$htmlPath = Join-Path $runPath 'report.html'
$html | Set-Content -LiteralPath $htmlPath -Encoding UTF8
Write-Host "Report ready: $htmlPath"
Write-Host 'CSV exports and source JSON are in the same folder. Applicability still requires inventory comparison.'
if ($warnings.Count -gt 0) { Write-Warning "$($warnings.Count) source notices; review the HTML notices and report.json." }
if ($OpenReport) {
    try { Invoke-Item -LiteralPath $htmlPath } catch { Write-Warning "Could not launch a browser. Open $htmlPath manually." }
}
[pscustomobject]@{ ReportPath = $htmlPath; OutputDirectory = $runPath; CVECount = $ids.Count; SourceNotices = $warnings.Count }
