# Übergabe an einen neuen Chat (Stand 26.10.2026)

Text unter der Linie in einen neuen Claude-Code-Chat (Repo GodzilaShow/raumsteuerung) einfügen.

---

Wir machen am Projekt Raumsteuerung (Sitzungszimmer 5, Landkreis Emsland) weiter. Antworte mir auf Russisch, kurz.
Code, Kommentare, Commits auf Deutsch (Commit-Betreff ohne Umlaute). Branch: `claude/modest-mayer-tbnbre` – dort
entwickeln und pushen, vorher immer `git pull`.

**Zuerst lesen:** `UEBERGABE.md` (Gesamtstand), `ANLEITUNG.txt` (Bedienung/Companion-Buttons), `docs/NETZPLAN.md`
(geplantes Netz), `SICHERHEIT.md`. Dann kurz bestätigen, was du verstanden hast, und auf meine Aufgabe warten.

## Was es gibt
- `Raumsteuerung/raumsteuerung.html` – Tablet-Seite (Vanilla JS) → Bitfocus Companion HTTP-API :8000 → OBS + Yamaha RM-CR.
- `Raumsteuerung/teams-steuerung.ps1` – Teams per UI Automation (Beitreten, Mikro, Kamera, Bildschirm teilen,
  Teams-Fenster auf den Teams-Bildschirm legen). Einstellungen in `mikro-automatik.json` (Name historisch).
- `Raumsteuerung/Raumsteuerung.exe` (Version 1.7) – Tray-Programm (C#, .NET 4.8, nur **C# 5**, Quelle
  `tools/RaumsteuerungTray/`, Bau: `build.sh` (Mono) bzw. `build.ps1` (Windows csc)). Startet Webserver + Teams-Steuerung,
  Status, Einstellungen (RM-CR-IP, Teams-Link, Bildschirme „Präsentation zeigen“ / „Teams-Fenster“, „Nummern zeigen“),
  **Pausenbild**: Companion `r5_blank = 1` (Tablet „Pausenbild zeigen“, Buttons 1/2/4 an, 1/2/5 aus) → `pause.png`
  im Vollbild auf dem Präsentations-Bildschirm. Werkzeuge: Prüfen, Dienste neu starten, Protokolle, Tablet-Kiosk.
- `android-kiosk/` – Kiosk-App fürs Tablet (vom PC-Claude gebaut), URL derzeit 192.168.137.1:8080.
- Tests: `bash test/alle-tests.sh` (Companion-Konfig 48, Tablet-Seite 88, Chaos 19 – alle grün). Mock: `test/mock-companion.js`.
- `.ps1`-Dateien: UTF-8 mit BOM + CRLF beibehalten.

## Am PC (Windows)
- Repo in `C:\Raum5`, installiert nach `C:\Raumsteuerung`. Git nicht im PATH. Aktualisieren (Admin-PowerShell):
  ```powershell
  cd C:\Raum5
  & "C:\Program Files\Git\cmd\git.exe" pull origin claude/modest-mayer-tbnbre
  powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Raum5\Raumsteuerung\installieren.ps1" -OhneWarten
  ```
- Lokaler Claude Code auf dem PC: `& "$env:USERPROFILE\.local\bin\claude.exe" --dangerously-skip-permissions`,
  Auftrag: `docs/PROMPT-LOKAL-TEST.md` („teste, Raum ist frei“ = alles ohne Rückfrage).

## Stand / zuletzt erledigt
- Exe 1.5–1.7: Bildschirm-Auswahl, Nummern-Overlay (4 s), Auswahlliste klappt zu, Dienste je einzeln erkannt,
  unlesbare JSON wird nicht überschrieben, Pausenbild; Symbol = Emsland-Logo auf Weiß.
- Teams-Steuerung: Teilen-Menü wird geschlossen, „kein Meeting“ erst nach 8 s (kein Hin-und-Her beim Teilen),
  Companion-Fehlerantworten geschlossen, fehlender Präsentations-Bildschirm → Teams nicht verschieben.
- Raumplan-Artefakt: https://claude.ai/artifact/9YnAMbALNAxYghGx7v6xu3 (Geräte ziehen, Kabel/Längen, Symbole,
  PTZ-Blickkegel drehbar, Sprechertisch 220 × 80, Reihen 30 cm nach hinten, PTZ-Kabel über die Decke).

## Offen
1. Netz nach `docs/NETZPLAN.md` umsetzen (ICS → 192.168.55.0/24, Zusatz-Switch, Tablet per Kabel, Kiosk-URL).
2. Hardware entscheiden: PTZ-Modell (PoE+, NDI/RTSP, VISCA), kabellos zeigen (ClickShare / RoomCast / EZCast),
   Publikum-Kamera (Yealink UVC30 Room empfohlen), Sprechertisch (Steh-Sitz 220 × 80, Dreifach-Monitorarm 27″).
3. ViewSonic-Befehle (LFD, TCP 5000; ANLEITUNG Abschnitt 8) am echten Display testen.
4. Fehler in `teams-steuerung.log` beobachten (Beitritt nach Standby, GetCurrentPattern).
