# Mac_changer

Windows-11-Batchskript fuer WLAN-MAC-Randomization mit Windows-Bordmitteln.

## Ziel

Das Projekt aktiviert die zufaellige Hardwareadresse fuer den WLAN-Adapter ueber `netsh` und setzt gespeicherte WLAN-Profile auf eine regelmaessige Randomization, ohne Registry-Hacks oder Drittanbieter-Tools.

## Enthalten

- `wlan_mac_randomization.bat`: interaktives Batchskript fuer Admin-Start, Adapter-Erkennung, Profil-Updates, Statusanzeige und optionale Scheduled Tasks

## Menue

- `[1]` Randomization jetzt fuer alle Profile aktivieren
- `[2]` Aktuelle WLAN-MAC anzeigen
- `[3]` WLAN trennen und wieder verbinden
- `[4]` Autostart / Scheduled Task installieren
- `[5]` Beenden

## Verwendete Windows-Befehle

- `netsh wlan show profiles`
- `netsh wlan show interfaces`
- `netsh wlan set randomization enabled=yes interface="..."`
- `netsh wlan set profileparameter name="..." interface="..." randomization=daily`
- `Get-NetAdapter`

## Hinweise

- Das Skript ist fuer Windows 11 gedacht.
- Es nutzt nur Windows-eigene Befehle und PowerShell.
- WLAN-Profile werden nicht geloescht.
- Die geplante Hintergrundpruefung nutzt `last_ssid.txt` im gleichen Ordner.
