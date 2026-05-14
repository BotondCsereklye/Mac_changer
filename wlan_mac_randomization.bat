@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem WLAN MAC Randomization nur mit Windows-Bordmitteln.
rem Diese erste Version bringt das Grundgeruest, den Admin-Check und ein Menue mit.

set "SCRIPT_NAME=%~nx0"
set "SCRIPT_PATH=%~f0"
set "SCRIPT_DIR=%~dp0"
set "STATE_FILE=%SCRIPT_DIR%last_ssid.txt"
set "DEFAULT_IFACE=WLAN"
set "RUNTIME_ID=%RANDOM%%RANDOM%"
set "RUNTIME_DIR=%TEMP%\wlan_mac_randomization_%RUNTIME_ID%"
set "DETECTED_IFACE="
set "CURRENT_SSID="
set "CURRENT_PROFILE="
set "CURRENT_MAC="

if not exist "%RUNTIME_DIR%" md "%RUNTIME_DIR%" >nul 2>&1

call :EnsureAdmin
if errorlevel 1 goto :CleanupAndExit
call :ResetRunState
call :DetectWlanInterface

if not defined DETECTED_IFACE (
    echo [FEHLER] Kein WLAN-Adapter gefunden. Geprueft wurden aktive WLAN-Schnittstellen, "WLAN" und "Wi-Fi".
    goto :CleanupAndExit
)

:MainMenu
cls
call :RefreshStatus
echo ================================================
echo WLAN MAC Randomization mit Windows-Bordmitteln
echo ================================================
echo Erkannter WLAN-Adapter : %DETECTED_IFACE%
if defined CURRENT_SSID (
    echo Aktuelle SSID        : %CURRENT_SSID%
) else (
    echo Aktuelle SSID        : Nicht verbunden
)
if defined CURRENT_MAC (
    echo Aktive MAC-Adresse   : %CURRENT_MAC%
) else (
    echo Aktive MAC-Adresse   : Unbekannt
)
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
call :ShowCurrentMac
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

:ResetRunState
set "CURRENT_SSID="
set "CURRENT_PROFILE="
set "CURRENT_MAC="
exit /b 0

:DetectWlanInterface
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$iface = netsh wlan show interfaces 2>$null | ForEach-Object { if ($_ -match '^\s*Name\s*:\s*(.+)$') { $matches[1].Trim() } } | Select-Object -First 1; if (-not $iface) { $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Disabled' -and ($_.NdisPhysicalMedium -eq 'Native 802.11' -or $_.InterfaceDescription -match 'Wireless|Wi-?Fi|WLAN|802\.11' -or $_.Name -match 'WLAN|Wi-?Fi') } | Sort-Object @{Expression={ if ($_.Status -eq 'Up') { 0 } else { 1 } }}, Name; if ($adapters) { $iface = $adapters[0].Name } }; if (-not $iface) { $iface = 'WLAN','Wi-Fi','WiFi' | Where-Object { Get-NetAdapter -Name $_ -ErrorAction SilentlyContinue } | Select-Object -First 1 }; if ($iface) { $iface }"`) do set "DETECTED_IFACE=%%I"
exit /b 0

:RefreshStatus
set "CURRENT_SSID="
set "CURRENT_PROFILE="
set "CURRENT_MAC="
set "PS_IFACE=%DETECTED_IFACE%"

for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$iface = $env:PS_IFACE; $adapter = Get-NetAdapter -Name $iface -ErrorAction SilentlyContinue | Select-Object -First 1; if ($adapter) { $adapter.MacAddress }"`) do if not defined CURRENT_MAC set "CURRENT_MAC=%%I"

for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$iface = $env:PS_IFACE; $profile = Get-NetConnectionProfile -InterfaceAlias $iface -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name; if (-not $profile) { $current = $null; foreach ($line in (netsh wlan show interfaces 2>$null)) { if ($line -match '^\s*Name\s*:\s*(.+)$') { $current = $matches[1].Trim(); continue }; if ($current -eq $iface -and $line -match '^\s*(?:Profile|Profil)\s*:\s*(.+)$') { $profile = $matches[1].Trim(); break } } }; if ($profile) { $profile }"`) do if not defined CURRENT_PROFILE set "CURRENT_PROFILE=%%I"

for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$iface = $env:PS_IFACE; $ssid = $null; $current = $null; foreach ($line in (netsh wlan show interfaces 2>$null)) { if ($line -match '^\s*Name\s*:\s*(.+)$') { $current = $matches[1].Trim(); continue }; if ($current -eq $iface -and $line -match '^\s*SSID\s*:\s*(.+)$' -and $line -notmatch '^\s*BSSID') { $ssid = $matches[1].Trim(); break } }; if (-not $ssid) { $ssid = Get-NetConnectionProfile -InterfaceAlias $iface -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name }; if ($ssid) { $ssid }"`) do if not defined CURRENT_SSID set "CURRENT_SSID=%%I"

if not defined CURRENT_PROFILE if defined CURRENT_SSID set "CURRENT_PROFILE=%CURRENT_SSID%"
exit /b 0

:ShowCurrentMac
call :RefreshStatus
echo [INFO] Aktuelle Adapterdaten:
set "PS_IFACE=%DETECTED_IFACE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter -Name $env:PS_IFACE -ErrorAction SilentlyContinue | Format-Table Name, InterfaceDescription, MacAddress, Status -AutoSize"
exit /b 0

:CleanupAndExit
if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%" >nul 2>&1
endlocal
exit /b 0
