@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem WLAN MAC Randomization nur mit Windows-Bordmitteln.
rem Diese erste Version bringt das Grundgeruest, den Admin-Check und ein Menue mit.

set "SCRIPT_NAME=%~nx0"
set "SCRIPT_PATH=%~f0"
set "SCRIPT_DIR=%~dp0"
set "STATE_FILE=%SCRIPT_DIR%last_ssid.txt"
set "DEFAULT_IFACE=WLAN"
set "TASK_LOGON_NAME=WLAN-MAC-Randomization-Login"
set "TASK_MONITOR_NAME=WLAN-MAC-Randomization-10Min"
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
set "SCHEDULED_MODE=0"

if /i "%~1"=="--scheduled" set "SCHEDULED_MODE=1"

if not exist "%RUNTIME_DIR%" md "%RUNTIME_DIR%" >nul 2>&1

call :EnsureAdmin
if errorlevel 1 goto :CleanupAndExit
call :ResetRunState
call :DetectWlanInterface

if not defined DETECTED_IFACE (
    echo [FEHLER] Kein WLAN-Adapter gefunden. Geprueft wurden aktive WLAN-Schnittstellen, "WLAN" und "Wi-Fi".
    goto :CleanupAndExit
)

if "%SCHEDULED_MODE%"=="1" (
    call :ScheduledCheck
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
call :ApplyRandomizationAllProfiles
echo.
pause
goto :MainMenu

:MenuShowMac
call :ShowCurrentMac
echo.
pause
goto :MainMenu

:MenuReconnect
call :ResetRunState
call :ReconnectWlan
echo.
pause
goto :MainMenu

:MenuInstallTasks
call :ResetRunState
call :InstallScheduledTasks
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
set /a ERROR_COUNT=0
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

:ApplyRandomizationAllProfiles
call :EnableGlobalRandomization
echo.
echo [INFO] Lese gespeicherte WLAN-Profile mit "netsh wlan show profiles"...
set "PS_IFACE=%DETECTED_IFACE%"
set "PROFILE_FOUND="

for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$iface = $env:PS_IFACE; netsh wlan show profiles interface=""$iface"" 2>$null | ForEach-Object { if ($_ -match '^\s{2,}.*(?:Profile|Profil)[^:]*:\s*(.+)$') { $name = $matches[1].Trim(); if ($name -and $name -notmatch '^(<None>|<Keine>)$') { $name } } } | Select-Object -Unique"`) do (
    set "PROFILE_FOUND=1"
    set "CURRENT_PROFILE=%%P"
    call :ProcessCurrentProfile
)

if not defined PROFILE_FOUND (
    echo [HINWEIS] Es wurden keine gespeicherten WLAN-Profile gefunden.
    call :AddError "Keine gespeicherten WLAN-Profile gefunden."
)

echo.
echo [INFO] Aktuelle Verbindung:
netsh wlan show interfaces
echo.
call :ShowCurrentMac
call :RefreshStatus
call :WriteCurrentSSIDState
call :DisplaySummary
exit /b 0

:ReconnectWlan
call :RefreshStatus
if not defined CURRENT_PROFILE (
    echo [FEHLER] Keine aktive WLAN-Verbindung erkannt. Reconnect ist deshalb nicht moeglich.
    call :AddError "Reconnect nicht moeglich, weil kein aktives WLAN-Profil erkannt wurde."
    call :DisplaySummary
    exit /b 1
)

set "TARGET_PROFILE=%CURRENT_PROFILE%"
echo [INFO] Trenne WLAN-Adapter "%DETECTED_IFACE%"...
netsh wlan disconnect interface="%DETECTED_IFACE%" >nul 2>&1
timeout /t 3 >nul

echo [INFO] Verbinde erneut mit Profil "%TARGET_PROFILE%"...
netsh wlan connect name="%TARGET_PROFILE%" interface="%DETECTED_IFACE%" >nul 2>&1
if errorlevel 1 (
    echo [FEHLER] Die Wiederverbindung mit "%TARGET_PROFILE%" ist fehlgeschlagen.
    call :AddError "Wiederverbindung mit dem aktuellen WLAN-Profil ist fehlgeschlagen."
    call :DisplaySummary
    exit /b 1
)

timeout /t 5 >nul
call :RefreshStatus
call :WriteCurrentSSIDState
echo [OK] WLAN wurde getrennt und erneut verbunden.
echo.
echo [INFO] Aktuelle Verbindung:
netsh wlan show interfaces
echo.
call :ShowCurrentMac
call :DisplaySummary
exit /b 0

:WriteCurrentSSIDState
if defined CURRENT_SSID (
    > "%STATE_FILE%" echo(%CURRENT_SSID%
)
exit /b 0

:InstallScheduledTasks
echo [INFO] Erstelle geplante Aufgaben fuer Login und 10-Minuten-Pruefung...
set "PS_SCRIPT_PATH=%SCRIPT_PATH%"
set "PS_TASK_LOGON=%TASK_LOGON_NAME%"
set "PS_TASK_MONITOR=%TASK_MONITOR_NAME%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$script = $env:PS_SCRIPT_PATH; $taskLogon = $env:PS_TASK_LOGON; $taskMonitor = $env:PS_TASK_MONITOR; $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name; $action = New-ScheduledTaskAction -Execute $env:ComSpec -Argument ('/c ""{0}"" --scheduled' -f $script); $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest; $triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $user; $triggerMonitor = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 3650); Register-ScheduledTask -TaskName $taskLogon -Action $action -Trigger $triggerLogon -Principal $principal -Description 'Aktiviert WLAN MAC Randomization beim Login.' -Force | Out-Null; Register-ScheduledTask -TaskName $taskMonitor -Action $action -Trigger $triggerMonitor -Principal $principal -Description 'Prueft alle 10 Minuten auf WLAN-Wechsel und aktualisiert WLAN MAC Randomization.' -Force | Out-Null" >nul 2>&1

if errorlevel 1 (
    echo [FEHLER] Scheduled Tasks konnten nicht erstellt werden.
    call :AddError "Geplante Aufgaben konnten nicht erstellt werden."
    call :DisplaySummary
    exit /b 1
)

echo [OK] Geplante Aufgaben wurden erstellt:
echo      - %TASK_LOGON_NAME%
echo      - %TASK_MONITOR_NAME%
echo [HINWEIS] Die SSID-Zwischenablage liegt in:
echo      %STATE_FILE%
exit /b 0

:ScheduledCheck
echo [INFO] Geplanter Hintergrundlauf startet...
call :RefreshStatus

if not defined CURRENT_SSID (
    echo [INFO] Keine aktive WLAN-SSID erkannt. Es wird nichts geaendert.
    exit /b 0
)

set "LAST_SSID="
if exist "%STATE_FILE%" set /p LAST_SSID=<"%STATE_FILE%"

if /i "%LAST_SSID%"=="%CURRENT_SSID%" (
    echo [INFO] SSID unveraendert: "%CURRENT_SSID%". Kein erneutes Setzen notwendig.
    if defined CURRENT_MAC echo [INFO] Aktive MAC-Adresse: %CURRENT_MAC%
    exit /b 0
)

echo [INFO] WLAN-Wechsel erkannt.
if defined LAST_SSID (
    echo        Alt: %LAST_SSID%
) else (
    echo        Alt: ^<leer^>
)
echo        Neu: %CURRENT_SSID%

call :EnableGlobalRandomization
set /a PROFILE_TOTAL=1
call :SetCurrentProfileRandomization

if /i "%PROFILE_RESULT%"=="DAILY" (
    set /a UPDATED_COUNT+=1
    >> "%UPDATED_FILE%" echo(%CURRENT_PROFILE% [daily]
) else (
    if /i "%PROFILE_RESULT%"=="YES" (
        set /a FALLBACK_COUNT+=1
        >> "%FALLBACK_FILE%" echo(%CURRENT_PROFILE% [yes-Fallback]
    ) else (
        set /a FAILED_COUNT+=1
        >> "%FAILED_FILE%" echo(%CURRENT_PROFILE%
        call :AddError "Aktuelles WLAN-Profil konnte im geplanten Lauf nicht aktualisiert werden."
    )
)

call :WriteCurrentSSIDState
call :RefreshStatus
if defined CURRENT_MAC echo [INFO] Aktive MAC-Adresse: %CURRENT_MAC%
call :DisplaySummary
exit /b 0

:AddError
set /a ERROR_COUNT+=1
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
echo Fehleranzahl         : %ERROR_COUNT%

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
