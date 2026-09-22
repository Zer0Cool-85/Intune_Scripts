# CVE Triage Toolkit

Turn a ticket full of CVE links into one searchable report. Version 1.0.0.

## Quick start

1. Extract this ZIP into a folder on your workstation.
2. Copy the Zendesk ticket text, including the CVE IDs or full CVE URLs.
3. Open PowerShell in the extracted folder and run:

```powershell
.\Get-CveReport.ps1 -Clipboard -OpenReport
```

The HTML report opens in your browser. Search for a product such as `Acrobat`,
`ColdFusion`, or `Windows 11`, or use **Browse products**. Expand a CVE to see
the description, published version statements, scores and advisory links.
The report works offline after collection; following an advisory link requires
internet access.

Alternatively, paste the ticket text into a UTF-8 text file:

```powershell
.\Get-CveReport.ps1 -InputPath .\ticket.txt -OpenReport
```

You can also supply IDs directly:

```powershell
.\Get-CveReport.ps1 -Text 'CVE-2023-36884 CVE-2023-26360'
```

The included `ticket-example.txt` contains three historical CVEs for trying
the tool. You can also open `example-output/report.html` to see a completed
example immediately. They are demonstrations, not a current patch recommendation.

```powershell
.\Get-CveReport.ps1 -InputPath .\ticket-example.txt -OpenReport
```

If your organization requires signed scripts, follow its normal script review
and signing process. The tool does not change execution policy.

## Outputs

Each run creates a separate folder under `CveReports` in your current directory.
Existing reports are retained.

| File | Contents |
| --- | --- |
| `report.html` | Searchable report, product navigation, KEV filter and data-review filter |
| `cve-summary.csv` | One row per CVE, including failed and rejected records |
| `cve-products.csv` | One row per product statement per source/CVE, with platforms and version statements; omitted if no product data is returned |
| `report.json` | Combined structured results, source URLs, retrieval times and errors |
| `raw/` | Retrieved CVE records, KEV snapshot and EPSS responses for traceability |

CSV files open in Excel. Use `cve-products.csv` to sort/filter by product and
version. Product rows from different publishing sources may overlap; this is
intentional, and `VersionSource` identifies the publisher. Summary rows include
all requested CVEs even when no product rows are available.

Use a different destination or omit EPSS with:

```powershell
.\Get-CveReport.ps1 -Clipboard -OutputDirectory C:\Reports\CVE -SkipEpss
```

## Data sources and behavior

- **CVE Program:** Fetches each official JSON record from CVEProject/cvelistV5;
  falls back to the public CVE Services record endpoint if retrieval fails.
  Includes CNA and additional provider (ADP) product data, references, CVSS
  entries, solutions and workarounds where published.
- **CISA KEV:** Downloads the catalog once per run, with CISA's own GitHub
  mirror as fallback. Reports `Listed`, `Not listed`, or `Unknown - feed
  unavailable`. A fallback's earlier failure appears as a source notice even
  if the fallback succeeds.
- **FIRST EPSS:** Queries IDs in batches, preserving the score's date.
  Distinguishes unavailable scores, failed lookups and intentionally skipped
  lookups. A zero score remains zero; missing scores are not converted to zero.

Only extracted CVE IDs are used in outbound requests. The original ticket text
is neither uploaded nor copied into the report. Requests go to fixed public
data endpoints; the tool does not open arbitrary URLs pasted in a ticket.
No credentials, API keys, admin rights or additional PowerShell modules are
needed. There is no Zendesk connection or endpoint scan in this version.

Required network destinations:

```text
raw.githubusercontent.com  (official CVE records and CISA fallback)
cveawg.mitre.org           (CVE record fallback)
www.cisa.gov              (primary KEV feed)
api.first.org             (EPSS, unless -SkipEpss)
```

Calls use the runtime's normal proxy/TLS behavior. A corporate proxy requiring
special authentication may need local configuration. Requests have timeouts,
limited retries and a small delay between CVE lookups. A run with 50-100 CVEs
may take several minutes depending on network latency and retries.

## What the report can and cannot establish

**Aggregation is not an applicability assessment.** Every row starts as
`Unverified - inventory comparison required`. Match exact product, installed
version, platform, architecture, release track, component/configuration and
inventory freshness before deciding a device is affected or safe.

- A CVE ID does not prove the relevant product is present in your environment.
- An absent inventory entry does not prove absence if collection is incomplete
  or stale; portable software, bundled components and unmanaged assets can be
  missed.
- An entry outside CISA KEV is not necessarily unexploited or low priority.
- CVSS measures severity. EPSS estimates exploitation in the wild over the
  next 30 days; it is not your organization's compromise probability.
- The report retains every published CVSS entry and scenario. The compact
  headline uses the highest score within the newest CVSS version available.
  Scores from different CVSS versions/sources are not interchangeable.
- Source version statements can use nonnumeric formats such as `CF2021U5`,
  wildcard values or ambiguous placeholders. The tool preserves them and
  their status changes; it does not try to compare them as `[version]` values.
- A version range's upper bound is not automatically a confirmed fix.
  Structured solutions are included when published, but **the tool does not
  automatically resolve every Microsoft KB or Adobe fixed version**. Vendor
  bulletin links remain the authority for remediation and prerequisites.
- On Windows, identify the correct OS release/build and cumulative update
  supersedence. Absence of an old KB alone does not prove vulnerability.
- Rejected CVEs and lookup failures are retained visibly for review. No
  record is silently treated as safe because a request failed.
- **Data review only** flags non-published/unavailable CVEs, missing product
  details and failed KEV feeds. It is not a comprehensive data-quality score.
- IDs must appear in the text or URL. A generic bulletin URL without CVE IDs
  is not expanded. For linked text that hides the URL, use the ticket's full
  text/HTML export or copy the actual link addresses.

Public record text is HTML-encoded. Potential spreadsheet formulas are
neutralized in CSV string cells; original values remain in JSON.

## A better ticket workflow

Use this tool immediately to make existing tickets readable. For the bot,
add inventory matching and remediation grouping before creating endpoint
work items:

1. Extract and deduplicate CVE IDs; record changes to existing advisories.
2. Enrich with exact products/version statements, vendor fix guidance, KEV
   status and EPSS. Keep source timestamps and links.
3. Compare with current endpoint/server inventory or a vulnerability scanner.
   Normalize vendor/product aliases, but keep uncertain matches in review.
4. Assign a result: confirmed affected, potentially affected, verified not
   applicable, or unknown. Store the evidence behind the decision.
5. Group confirmed work by product, supported release/track, remediation and
   owner. One update may fix many CVEs; one CVE may need different updates for
   different OS releases.
6. Create/update one work item per remediation group. Include devices, observed
   versions/builds, target update/version, CVEs covered, exploitation signals,
   owner and your internal due date. Keep the full CVE list as supporting data.
7. Verify patch installation, required restart and a fresh assessment before
   closing. Reopen or update the existing item when evidence changes.

Avoid both one giant vendor ticket and one ticket per CVE per device. Keep a
separate triage queue for unknown inventory/matches instead of silently dropping
them. Base duplicate prevention on stable product/track/remediation/owner keys.

For this environment, useful inventory inputs include Intune Windows app/OS
inventory, Jamf macOS inventory, server inventory and any existing vulnerability
management platform. An existing CrowdStrike Spotlight/Exposure Management
entitlement may already provide host-level findings and remediation status;
verify entitlement and coverage with the security team. Installing the endpoint
sensor alone does not establish that this capability is available.

## References

- CVE Program downloads: https://www.cve.org/downloads
- Official CVE records: https://github.com/CVEProject/cvelistV5
- CVE schema and version statements: https://cveproject.github.io/cve-schema/schema/docs/
- CISA KEV: https://www.cisa.gov/known-exploited-vulnerabilities-catalog
- Official KEV mirror: https://github.com/cisagov/kev-data
- FIRST EPSS API: https://api.first.org/epss/
- EPSS interpretation: https://www.first.org/epss/
- Microsoft Security Updates API: https://github.com/microsoft/MSRC-Microsoft-Security-Updates-API
- Adobe bulletins: https://helpx.adobe.com/security/security-bulletin.html
- Intune Windows app inventory: https://learn.microsoft.com/en-us/intune/app-management/deployment/enhanced-app-inventory
- CrowdStrike vulnerability APIs: https://developer.crowdstrike.com/accomplish/hunt-vulnerabilities/

## Compatibility and validation

Written for Windows PowerShell 5.1 and PowerShell 7 using built-in commands.
Validated with PowerShell 7 on Linux against live Microsoft/Adobe CVE records,
KEV and EPSS, plus controlled missing-data/error cases. Windows PowerShell 5.1
and Windows clipboard/browser launching were not available for execution testing.
Generated HTML structure and embedded JavaScript syntax were checked. Browser
rendering and interaction testing were not available in this environment.
