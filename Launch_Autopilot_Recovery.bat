@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0src\Invoke-AutopilotSafeRecovery.ps1' -ErrorAction SilentlyContinue"

:menu
cls
echo ============================================================
echo   AUTOPILOT AND INTUNE SAFE RECOVERY TOOLKIT
echo ============================================================
echo   1. Diagnose only
echo   2. Run safe recovery set
echo   3. Restart Intune Management Extension
echo   4. Restart Windows MDM client services
echo   5. Trigger existing EnterpriseMgmt sync tasks
echo   6. Refresh current user Primary Refresh Token
echo   7. Flush DNS cache
echo   8. Archive Intune Management Extension logs
echo   0. Exit
echo ============================================================
set /p CHOICE=Select an option: 

if "%CHOICE%"=="1" goto diagnose
if "%CHOICE%"=="2" goto safe
if "%CHOICE%"=="3" goto ime
if "%CHOICE%"=="4" goto mdm
if "%CHOICE%"=="5" goto sync
if "%CHOICE%"=="6" goto prt
if "%CHOICE%"=="7" goto dns
if "%CHOICE%"=="8" goto archive
if "%CHOICE%"=="0" goto end
goto menu

:diagnose
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Invoke-AutopilotSafeRecovery.ps1"
goto complete

:safe
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Invoke-AutopilotSafeRecovery.ps1" -RepairAllSafe
goto complete

:ime
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Invoke-AutopilotSafeRecovery.ps1" -RestartIntuneManagementExtension
goto complete

:mdm
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Invoke-AutopilotSafeRecovery.ps1" -RestartMdmServices
goto complete

:sync
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Invoke-AutopilotSafeRecovery.ps1" -TriggerMdmSync
goto complete

:prt
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Invoke-AutopilotSafeRecovery.ps1" -RefreshPrimaryRefreshToken
goto complete

:dns
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Invoke-AutopilotSafeRecovery.ps1" -FlushDns
goto complete

:archive
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Invoke-AutopilotSafeRecovery.ps1" -ArchiveIntuneLogs
goto complete

:complete
echo.
pause
goto menu

:end
endlocal
