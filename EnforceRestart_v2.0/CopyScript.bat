IF EXIST "%ProgramData%\MDM_Scripts\EnforceRestart" GOTO DELETEFILES

:DELETEFILES
RD /S /Q "%ProgramData%\MDM_Scripts\EnforceRestart"
GOTO COPYFILE

:COPYFILE
IF Not Exist "%ProgramData%\MDM_Scripts\EnforceRestart" mkdir "%ProgramData%\MDM_Scripts\EnforceRestart"
xcopy * %ProgramData%\MDM_Scripts\EnforceRestart\ /E /C /Q /Y

:EXIT
