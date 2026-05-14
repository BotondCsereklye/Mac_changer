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
set "UPDATED_FILE=%RUNTIME_DIR%\updated.txt"
set "FALLBACK_FILE=%RUNTIME_DIR%\fallback.txt"
set "FAILED_FILE=%RUNTIME_DIR%\failed.txt"
set "ERROR_FILE=%RUNTIME_DIR%\errors.txt"
set "DETECTED_IFACE="
set "CURRENT_SSID="
set "CURRENT_PROFILE="
set "CURRENT_MAC="
set "TARGET_PROFILE="

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
call :ResetRunState
call :EnableGlobalRandomization
call :RefreshStatus
if defined CURRENT_PROFILE (
    call :ProcessCurrentProfile
) else (
    echo [HINWEIS] Es ist aktuell kein WLAN-Profil aktiv.
    call :AddError "Kein aktives WLAN-Profil erkannt."
)
echo.
echo [INFO] Aktuelle Verbindung:
netsh wlan show interfaces
echo.
call :ShowCurrentMac
call :DisplaySummary
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
set "TARGET_PROFILE="
set /a PROFILE_TOTAL=0
set /a UPDATED_COUNT=0
set /a FALLBACK_COUNT=0
set /a FAILED_COUNT=0
type nul > "%UPDATED_FILE%"
type nul > "%FALLBACK_FILE%"
type nul > "%FAILED_FILE%"
type nul > "%ERROR_FILE%"
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

:EnableGlobalRandomization
echo [INFO] Aktiviere globale MAC-Randomization fuer "%DETECTED_IFACE%"...
netsh wlan set randomization enabled=yes interface="%DETECTED_IFACE%" >nul 2>&1
if errorlevel 1 (
    echo [FEHLER] Globale Randomization konnte fuer "%DETECTED_IFACE%" nicht aktiviert werden.
    call :AddError "Globale MAC-Randomization konnte nicht aktiviert werden."
    exit /b 1
)
echo [OK] Globale MAC-Randomization ist fuer "%DETECTED_IFACE%" aktiv.
exit /b 0

:SetCurrentProfileRandomization
set "PROFILE_RESULT=FAILED"
if not defined CURRENT_PROFILE (
    echo [FEHLER] Es wurde kein WLAN-Profil zum Aktualisieren erkannt.
    call :AddError "Kein WLAN-Profil zum Aktualisieren erkannt."
    exit /b 1
)

echo [INFO] Setze Profil "%CURRENT_PROFILE%" auf Randomization=daily...
netsh wlan set profileparameter name="%CURRENT_PROFILE%" interface="%DETECTED_IFACE%" randomization=daily >nul 2>&1
if not errorlevel 1 (
    set "PROFILE_RESULT=DAILY"
    echo [OK] Profil "%CURRENT_PROFILE%" wurde auf daily gesetzt.
    exit /b 0
)

echo [HINWEIS] "daily" wurde fuer "%CURRENT_PROFILE%" nicht akzeptiert. Versuche Fallback auf "yes"...
netsh wlan set profileparameter name="%CURRENT_PROFILE%" interface="%DETECTED_IFACE%" randomization=yes >nul 2>&1
if not errorlevel 1 (
    set "PROFILE_RESULT=YES"
    echo [OK] Profil "%CURRENT_PROFILE%" wurde ersatzweise auf yes gesetzt.
    exit /b 0
)

echo [FEHLER] Profil "%CURRENT_PROFILE%" konnte nicht aktualisiert werden.
set "PROFILE_RESULT=FAILED"
exit /b 1

:ProcessCurrentProfile
set /a PROFILE_TOTAL+=1
call :SetCurrentProfileRandomization

if /i "%PROFILE_RESULT%"=="DAILY" (
    set /a UPDATED_COUNT+=1
    >> "%UPDATED_FILE%" echo(%CURRENT_PROFILE% [daily]
    exit /b 0
)

if /i "%PROFILE_RESULT%"=="YES" (
    set /a FALLBACK_COUNT+=1
    >> "%FALLBACK_FILE%" echo(%CURRENT_PROFILE% [yes-Fallback]
    exit /b 0
)

set /a FAILED_COUNT+=1
>> "%FAILED_FILE%" echo(%CURRENT_PROFILE%
call :AddError "Mindestens ein WLAN-Profil konnte nicht aktualisiert werden."
exit /b 1

:AddError
>> "%ERROR_FILE%" echo(%~1
exit /b 0

:DisplaySummary
call :RefreshStatus
echo ================================================
echo Zusammenfassung
echo ================================================
echo Adaptername          : %DETECTED_IFACE%
if defined CURRENT_SSID (
    echo Aktuelle SSID     : %CURRENT_SSID%
) else (
    echo Aktuelle SSID     : Nicht verbunden
)
if defined CURRENT_MAC (
    echo Aktive MAC        : %CURRENT_MAC%
) else (
    echo Aktive MAC        : Unbekannt
)
echo Profile gesamt       : %PROFILE_TOTAL%
echo Erfolgreich daily    : %UPDATED_COUNT%
echo Fallback auf yes     : %FALLBACK_COUNT%
echo Fehlgeschlagen       : %FAILED_COUNT%

if %UPDATED_COUNT% GTR 0 (
    echo.
    echo Aktualisierte Profile:
    type "%UPDATED_FILE%"
)

if %FALLBACK_COUNT% GTR 0 (
    echo.
    echo Profile mit yes-Fallback:
    type "%FALLBACK_FILE%"
)

if %FAILED_COUNT% GTR 0 (
    echo.
    echo Nicht aktualisierte Profile:
    type "%FAILED_FILE%"
)

if exist "%ERROR_FILE%" (
    echo.
    echo Hinweise:
    type "%ERROR_FILE%"
)
echo ================================================
exit /b 0

:CleanupAndExit
if exist "%RUNTIME_DIR%" rd /s /q "%RUNTIME_DIR%" >nul 2>&1
endlocal
exit /b 0
