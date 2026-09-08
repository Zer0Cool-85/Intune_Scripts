Place exactly one CrowdStrike Falcon Windows Sensor installer EXE in this folder.

Examples of filenames used by CrowdStrike releases include:
  FalconSensor_Windows.exe
  WindowsSensor.exe
  WindowsSensor.<release-name>.exe

The wrapper does not depend on the filename. It reads the version metadata from
the EXE and, by default, requires a valid Authenticode signature whose signer
contains "CrowdStrike".

Do not commit the licensed installer to a public repository. The parent
.gitignore excludes Files/*.exe.
