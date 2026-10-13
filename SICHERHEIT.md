# Raumsteuerung Sitzungszimmer 5 – Sicherheit und Netzwerk

Stand 13.10.2026. Für IT und Projektleitung: wer mit wem spricht, über welche Ports, mit welchen Rechten,
welche Risiken bestehen und was vor dem Echtbetrieb zu tun ist.

## Kurzfassung

- Die Raumsteuerung selbst meldet sich **bei keinem Konto** an. Ein Microsoft-Konto hat nur Teams (Raumkonto).
- **Keine Komponente hat eine Anmeldung** (Tablet-Seite, Companion-API, RM-CR-RCP). Schutz entsteht
  ausschließlich über das Netzwerk → Raum-PC, Tablet und AV-Geräte gehören in ein **eigenes AV-Netz**.
- Im Repository liegen **keine Passwörter oder Tokens** (Test „kein Passwort im Paket“).
- Wichtigste Maßnahmen: Companion-Admin-Passwort setzen, AV-Netz trennen, Firewall auf das AV-Netz einschränken,
  Windows-Internetfreigabe (ICS) im Raum nicht verwenden.

## Komponenten und Verbindungen

```
Tablet ──HTTP 8080──► Webserver (server.ps1)            liefert nur die Seite aus
Tablet ──HTTP 8000──► Companion (HTTP-API)              Buttons drücken, Variablen lesen/setzen
                         │
                         ├─WebSocket 4455 (localhost, Passwort)──► OBS ──Virtual Camera──► Teams
                         ├─TCP 49280 (RCP, ohne Anmeldung)───────► Yamaha RM-CR (Lautstärke, Mute)
                         │
mikro-automatik.ps1 ──TCP 49280──► RM-CR (Pegel lesen)   ──HTTP 8000──► Companion (Kamera-Zone)
teams-steuerung.ps1 ──UI Automation (lokal, kein Netz)──► Teams-Fenster ──HTTP 8000──► Companion (Zustand)
Teams ──Internet──► Microsoft 365 (Raumkonto)
```

| Verbindung | Port | Schutz | Was ein Angreifer im selben Netz damit kann |
|---|---|---|---|
| Tablet → Webserver | TCP 8080 | keiner | nur die Seite abrufen (statische Dateien, kein Schreiben) |
| Tablet → Companion-API | TCP 8000 | keiner | jeden Companion-Button drücken, Custom Variables setzen |
| Browser → Companion-Weboberfläche | TCP 8000 | optional Admin-Passwort | **gesamte Konfiguration ändern**, Verbindungen, Import/Export |
| Companion → OBS | TCP 4455, nur 127.0.0.1 | WebSocket-Passwort | – (nicht von außen erreichbar) |
| Companion / Automatik → RM-CR | TCP 49280 | keiner (RCP hat kein Login) | alle Parameter des Prozessors (Pegel, Mute, …) |
| teams-steuerung → Teams | kein Netz | Windows-Benutzerrechte | – |
| Teams → Microsoft 365 | HTTPS | Raumkonto | normales Teams |

## Konten und Rechte

| Teil | Läuft als | Konto / Anmeldung |
|---|---|---|
| Teams | angemeldeter Windows-Benutzer | **Microsoft-Raumkonto** (einziges Cloud-Konto) |
| teams-steuerung.ps1 | angemeldeter Benutzer (Aufgabe „bei Anmeldung“, Gruppe Benutzer, eingeschränkt) | keins – drückt nur Buttons im offenen Teams-Fenster, kennt keine Passwörter/Tokens |
| server.ps1, mikro-automatik.ps1 | **SYSTEM** (Aufgaben „beim Start“) | keins |
| Companion | angemeldeter Benutzer | keins; Weboberfläche ohne Passwort, bis eins gesetzt ist |
| OBS | angemeldeter Benutzer | keins; WebSocket-Passwort lokal in OBS |
| RM-CR | – | RCP ohne Login; Weboberfläche des Geräts mit eigenem Login |

Was teams-steuerung **kann**: Mikro und Kamera des Raums in Teams umschalten, Meeting verlassen.
Was es **nicht kann**: Meetings beitreten, zuhören/zusehen, Chats lesen, andere Teilnehmer steuern.

## Risiken und Maßnahmen

| # | Risiko | Maßnahme | Status |
|---|---|---|---|
| 1 | Companion-Weboberfläche ohne Passwort über Netz erreichbar → Konfiguration manipulierbar | Companion → Settings → **Admin-Passwort** setzen (HTTP-API für Tablet/Automatik bleibt nutzbar – am 13.10. getestet: Weboberfläche „locked“, API, Mikro-Automatik und Teams-Steuerung laufen weiter) | Test-PC: gesetzt (Testpasswort). Raum-PC: eigenes, starkes Passwort |
| 2 | Tablet-Seite und Companion-API ohne Anmeldung → jeder im Netz kann den Raum bedienen | **Eigenes AV-Netz/-WLAN** (TP-Link EAP225 im Ausstattungsplan) nur für Raum-PC, Tablet, AV-Geräte | offen (Hardware) |
| 3 | Firewall-Regeln 8080/8000 gelten für alle Adressen der Profile Privat/Domäne | Regeln auf das AV-Subnetz beschränken: `Set-NetFirewallRule -DisplayName 'Raumsteuerung Port *' -RemoteAddress <AV-Netz>/24` | offen |
| 4 | RM-CR per RCP ohne Login steuerbar | RM-CR nur im AV-Netz (3. Netzwerkkarte im Ausstattungsplan), nie im Verwaltungsnetz | offen (Hardware) |
| 5 | Webserver und Mikro-Automatik laufen als SYSTEM (mehr Rechte als nötig) | Optional: eigener lokaler Dienstbenutzer ohne Adminrechte für beide Aufgaben | optional |
| 6 | teams-steuerung braucht einen angemeldeten Benutzer → automatische Anmeldung des Raumkontos | Raumkonto mit minimalen Rechten, keine Laufwerke/Freigaben, Bildschirmsperre aus Sicht des Raums abwägen | offen |
| 7 | **Windows-Internetfreigabe (ICS)** auf dem Test-Laptop (Ethernet 192.168.137.1 = ICS-Standard): Laptop verteilt im RM-CR-Netz IP-Adressen (DHCP) und routet ins Internet. Bei Verbindung mit dem Verwaltungsnetz → fremder DHCP-Server | Im Raum **kein ICS**. RM-CR, RM-TT und Raum-PC mit festen Adressen bzw. DHCP-Reservierung im AV-Netz | prüfen |
| 8 | Dante/RM-Netz (RM-CR ↔ RM-TT) erzeugt Multicast- und PTP-Verkehr | Eigenes VLAN/Switch; bei Managed Switch IGMP-Snooping an, Energy Efficient Ethernet (EEE) aus | offen (Hardware) |
| 9 | Teams-Updates können Button-Kennungen ändern → Tablet-Leiste wirkungslos (kein Sicherheitsrisiko) | Nach Teams-Updates kurz testen; Kennungen in `teams-steuerung.ps1` (`$IDS`) | Betrieb |

## Daten und Protokolle

- Keine personenbezogenen Daten. Protokolle unter `C:\Raumsteuerung\*.log` enthalten nur Zeitstempel,
  Befehle (z. B. „Befehl mute“) und Mikrofonnummern, keine Namen, keine Audiodaten.
- Die Mikrofon-Automatik liest nur **Pegel** (Lautstärkewerte), keinen Ton.
- Die Tablet-Seite speichert im Browser nur Bedienzustand (Szene, Lautstärke) und die Companion-Adresse.

## Checkliste vor dem Echtbetrieb

- [ ] AV-Netz/-VLAN eingerichtet; Raum-PC, Tablet, RM-CR, RM-TT, Matrix, Displays darin; kein Übergang ins Verwaltungsnetz außer Raum-PC → Internet (Teams)
- [ ] Feste IPs / DHCP-Reservierungen für Raum-PC und AV-Geräte; **kein ICS**
- [ ] Companion Admin-Passwort gesetzt, Companion „Run at login“
- [ ] Firewall-Regeln 8080/8000 auf das AV-Subnetz eingeschränkt
- [ ] OBS-WebSocket-Passwort gesetzt (nur localhost)
- [ ] Raumkonto: minimale Rechte, automatische Anmeldung, Teams-Autostart
- [ ] `pruefen.cmd`: alles grün
- [ ] Test-Checkliste ANLEITUNG Abschnitt 6 und 9
