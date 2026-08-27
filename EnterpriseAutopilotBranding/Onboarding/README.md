# PSADT onboarding host

This directory contains the pinned PSAppDeployToolkit 4.1.8 runtime and the thin deployment script
used by the first-login scheduled task. PSADT's client/server UI displays progress from a SYSTEM
deployment in the signed-in user's session, so this project does not require `ServiceUI.exe`.

The scheduled task launches:

```text
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

`Invoke-AppDeployToolkit.ps1` then calls the parent `Invoke-PostEnroll.ps1` worker in-process. The
worker owns all step state, retry, logging, eligibility, and completion behavior; PSADT owns only
the secure user-session presentation and user-context process launch capability.

## Branding

- `PSAppDeployToolkit/Config/config.psd1` contains the company name, purple accent color, log path,
  and UI timeout.
- `PSAppDeployToolkit/Assets/AppIcon.png` is generated from the sample `Assets/CompanyLogo.bmp`.
- Replace the source company logo and regenerate this PNG before production, or replace both files
  manually with matching organization artwork.

## Updating PSADT

Update the complete runtime as one tested unit. Do not replace only the launcher executable or one
DLL. Change the pinned version checks in `Validate-Project.ps1`, the Pester test, and this document,
then validate on x64 and ARM64 Windows 11 before deployment. Pre-release versions should remain in
a lab branch.

PSAppDeployToolkit is redistributed under the GNU Lesser General Public License v3.0. Its license
text is retained at `PSAppDeployToolkit/COPYING.Lesser`; upstream source is available from
https://github.com/PSAppDeployToolkit/PSAppDeployToolkit.
