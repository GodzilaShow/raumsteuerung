# Raumsteuerung Sitzungszimmer 5 – Technik kurz erklärt

## Wie es zusammenhängt

```
Tablet / Handy (Browser)
   │  HTTP, Port 8080 (Seite)       HTTP-API, Port 8000
   ▼                                   ▼
server.ps1 ──liefert Seite──►  Bitfocus Companion 5  ──► OBS (WebSocket v5): Szenen, Virtuelle Kamera
                                   │                  ──► Yamaha RM-CR (TCP 49280, RCP): Mikrofone, Lautsprecher
                                   │  Variablen (r5_*)
                                   ▼
                         teams-steuerung.ps1 ──► Microsoft Teams (Windows UI Automation)
```

Companion ist die Zentrale: Die Tablet-Seite drückt nur Companion-Tasten und liest Variablen.
Alles andere hängt an Companion.

## Bausteine und Sprachen

| Datei | Sprache | Aufgabe |
|---|---|---|
| `raumsteuerung.html` | HTML, CSS, JavaScript (eine Datei, ohne Framework, ohne Internet) | Bedienoberfläche fürs Tablet: Raum an/aus, Szenen, Lautstärke, Teams, Ton aus. Fragt den Zustand alle paar Sekunden ab. Abends gibt es eine Rückfrage mit automatischem Ausschalten. |
| `server.ps1` | PowerShell (.NET TcpListener) | Kleiner Webserver, der die Seite im Netz bereitstellt. |
| `teams-steuerung.ps1` | PowerShell + Windows UI Automation | Bedient die Teams-App wie ein Mensch: Meeting über `msteams:`-Link beitreten, Mikro, Kamera, Auflegen. Meldet den Zustand an Companion (`r5_t_*`). Startet OBS neu, falls es abstürzt. |
| `installieren.ps1` / `deinstallieren.ps1` | PowerShell | Kopiert nach C:\Raumsteuerung, Autostart von Raumsteuerung.exe (startet Webserver und Teams-Steuerung), Firewall. |
| `pruefen.ps1` / `.cmd` | PowerShell | Selbsttest: Läuft alles? Sind Companion, OBS, RM-CR und Teams erreichbar? |
| `tools/companion_config.py` | Python | Erzeugt die Companion-Konfiguration (`Raum5_Companion.companionconfig`) als Code statt per Hand. So ist sie reproduzierbar und versioniert. |
| `test/*.js`, `test/*.py` | JavaScript (Node.js + Playwright), Python | Automatische Tests: Nachgebautes Companion und RM-CR (Mocks). Die Seite wird im Headless-Chromium bedient. Die Konfiguration wird geprüft. |

## Warum so gebaut

- **Keine Installation auf dem Tablet:** Es braucht nur einen Browser. Bei Fully Kiosk ist die Seite im Vollbild.
- **Keine Cloud, kein Teams-Admin-Zugriff:** Die Teams-API wäre nur mit Admin-Freigabe nutzbar. UI Automation läuft lokal und braucht keine Rechte.
- **Bordmittel:** PowerShell ist auf jedem Windows vorhanden. Nur Companion, OBS und Teams müssen installiert sein.
- **Konfiguration als Code:** Änderungen sind nachvollziehbar (Git) und mit einem Import auf einen neuen PC übertragbar.

## Umfang

Rund 2 300 Zeilen Code. Tests: Funktionstests der Seite, Konfigurationsprüfungen, Chaos-Test (Störungen + Zufallsbedienung).

## Weiterführend

- Bedienung und Einrichtung: `ANLEITUNG.txt`
- Übergabe und offene Punkte: `UEBERGABE.md`
- Passwörter, Netz, Konten: `SICHERHEIT.md`
