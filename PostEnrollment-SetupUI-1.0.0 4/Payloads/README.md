# Stage your approved installers here

No Microsoft or third-party installer binaries, offline licenses, or credentials are bundled.

Suggested folders: `MSI/`, `ODT/`, `CompanyPortal/`, `Notepad/`.

Use exact package-relative filenames in each step's Parameters. For Store packages,
keep the main APPX/MSIX bundle, required architecture-specific dependencies and
offline license XML together. See [the enterprise guide](../Docs/ENTERPRISE-STEPS.md).

Deploy the whole package to a local directory where SYSTEM and Administrators
have write access and Users have read/execute only. User registration must be able
to read its script, package and dependencies. Do not give users write access to
scripts or payloads that run as SYSTEM. Keep runtime logs in the existing protected
ProgramData state directory.
