# Validation record

Release: 1.1.0. Prepared September 14, 2026.

Completed in a Linux test environment using PowerShell 7.4.6:

- Parsed all eight PowerShell source, build, template, and test files without syntax errors.
- Compiled the native WLAN C# helper and checked the marshaled interface/profile/available-network structure sizes.
- Passed 37 offline behavior tests using a fake WLAN client, including both legacy actions, preservation of unlisted profile XML and relative order, forced-switch scope, active-connection rechecks, default settings-only behavior without connection queries, preservation of credentials, invalid configuration rejection, and the original migration/removal safeguards.
- Ran the build helper in prepare-only mode against an isolated configured copy; generated standalone detection and matching payload/configuration hashes.
- Checked the generated detection script for syntax and unresolved placeholders.

The runtime targets Windows PowerShell 5.1 and uses its supported syntax and .NET APIs. The tests above were not run in Windows PowerShell 5.1; no live Windows Wi-Fi adapter, Task Scheduler COM service, Windows ACL/registry operation, or Intune tenant was available in this environment. Those integrations require a Windows pilot.

The Microsoft Content Prep Tool was not executed here. The archive contains source plus the build helper; after entering your SSIDs, run that helper with IntuneWinAppUtil.exe on Windows to generate the uploadable `.intunewin` and its matching detection script.

Use the Windows verification cases and troubleshooting notes in README.md before assigning the app broadly. In particular, verify actual certificate authentication and network access, Task Scheduler creation under SYSTEM, profile visibility at device scope, and Windows Wi-Fi information permissions on your managed build.
