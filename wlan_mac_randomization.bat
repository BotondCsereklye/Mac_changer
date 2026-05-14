@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem WLAN MAC Randomization nur mit Windows-Bordmitteln.
rem Diese erste Version bringt das Grundgeruest, den Admin-Check und ein Menue mit.

set "SCRIPT_NAME=%~nx0"
set "SCRIPT_PATH=%~f0"
set "SCRIPT_DIR=%~dp0"
set "STATE_FILE=%SCRIPT_DIR%last_ssid.txt"
set "DEFAULT_IFACE=WLAN"
set "DETECTED_IFACE=%DEFAULT_IFACE%"

call :EnsureAdmin
if errorlevel 1 goto :CleanupAndExit

:MainMenu
cls
echo ================================================
echo WLAN MAC Randomization mit Windows-Bordmitteln
echo ================================================
echo Voreingestellter WLAN-Adapter : %DETECTED_IFACE%
echo.
echo [1] Randomization jetzt fuer alle Profile aktivieren
echo [2] Aktuelle WLAN-MAC anzeigen
echo [3] WLAN trennen und wieder verbinden
echo [4] Autostart / Scheduled Task installieren
echo [5] Beenden
echo.
choice /C 12345 /N /M "Bitte waehlen: "

if errorlevel 5 goto :CleanupAndExit
if errorlevel 4 goto :MenuInstallTasks
if errorlevel 3 goto :MenuReconnect
if errorlevel 2 goto :MenuShowMac
if errorlevel 1 goto :MenuApplyAll
goto :MainMenu

:MenuApplyAll
echo [INFO] Die Aktivierung fuer alle Profile folgt im naechsten Schritt.
echo.
pause
goto :MainMenu

:MenuShowMac
echo [INFO] Aktuelle Adapterdaten fuer "%DETECTED_IFACE%":
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter -Name '%DETECTED_IFACE%' -ErrorAction SilentlyContinue | Format-Table Name, InterfaceDescription, MacAddress, Status -AutoSize"
echo.
pause
goto :MainMenu

:MenuReconnect
echo [INFO] Die Trennen/Wiederverbinden-Funktion folgt im naechsten Schritt.
echo.
pause
goto :MainMenu

:MenuInstallTasks
echo [INFO] Die Scheduled-Task-Installation folgt im naechsten Schritt.
echo.
pause
goto :MainMenu

:EnsureAdmin
powershell -NoProfile -ExecutionPolicy Bypass -Command "$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }" >nul 2>&1
if "%errorlevel%"=="0" exit /b 0

echo [INFO] Administratorrechte fehlen. Starte %SCRIPT_NAME% mit UAC neu...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%SCRIPT_PATH%' -Verb RunAs" >nul 2>&1
if errorlevel 1 (
    echo [FEHLER] Der Neustart mit Administratorrechten wurde abgebrochen oder ist fehlgeschlagen.
    exit /b 1
)
exit /b 1

:CleanupAndExit
endlocal
exit /b 0
