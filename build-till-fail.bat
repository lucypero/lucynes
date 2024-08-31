@echo off
set count=0

:loop
odin build . --debug
if %ERRORLEVEL% neq 0 (
    echo The command failed with error code %ERRORLEVEL%.
    echo The command ran successfully %count% times before failing.
    goto :end
)
set /a count+=1
goto :loop

:end
echo Exiting the loop due to an error.
