# Prompt für Claude Code auf dem PC (lokal testen und installieren)

Claude Code in einer **PowerShell als Administrator** in `C:\Raum5` starten (`claude`) und den Text unten einfügen.

---

Du arbeitest lokal auf einem Windows-PC im Projekt Raumsteuerung (Sitzungszimmer 5, Landkreis Emsland).
Antworte mir auf Russisch, kurz. Code, Kommentare und Commits sind auf Deutsch.

## Projekt
- Repo: `C:\Raum5`, Branch `claude/modest-mayer-tbnbre`. Git ist NICHT im PATH: immer `& "C:\Program Files\Git\cmd\git.exe" ...`.
- Lies zuerst `UEBERGABE.md` und `ANLEITUNG.txt` (Überblick, Variablen, Buttons).
- Installiert wird nach `C:\Raumsteuerung` mit `installieren.ps1` (braucht Admin). Dort laufen:
  `Raumsteuerung.exe` (Tray, startet `server.ps1` + `teams-steuerung.ps1`), Logs `raumsteuerung.log`, `teams-steuerung.log`.
- Bitfocus Companion: HTTP-API `http://127.0.0.1:8000` (Variablen `r5_*`, Buttons `/api/location/<seite>/<zeile>/<spalte>/press`).
- Tablet-Seite: `http://127.0.0.1:8080/` (Webserver `server.ps1`).

## Ablauf (jedes Mal, wenn ich "teste" oder "update" sage)
1. Aktualisieren und installieren:
   ```powershell
   cd C:\Raum5
   & "C:\Program Files\Git\cmd\git.exe" pull origin claude/modest-mayer-tbnbre
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Raum5\Raumsteuerung\installieren.ps1" -OhneWarten
   ```
   (`-OhneWarten`: wartet am Ende nicht auf Enter. Gibt es den Schalter noch nicht, erst `pull`.)
2. Version prüfen: letzte Zeile "Start Raumsteuerung" in `C:\Raumsteuerung\raumsteuerung.log`; muss zu
   `public const string Version` in `tools\RaumsteuerungTray\Program.cs` passen.
3. `C:\Raumsteuerung\pruefen.ps1` ausführen und jede Zeile FEHLER/WARN erklären.
4. Funktionstests über die Companion-API (Zustand vorher merken und danach wiederherstellen):
   - Variablen lesen: `Invoke-RestMethod http://127.0.0.1:8000/api/custom-variable/<name>/value`
     für r5_room, r5_blank, r5_disp, r5_t_in, r5_t_mute, r5_t_video, r5_t_share, r5_t_mode, r5_t_status.
   - Pausenbild: `Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/location/1/2/4/press` (nur wenn r5_room = 1),
     2 s warten, Screenshot aller Bildschirme machen (PowerShell + System.Drawing, `CopyFromScreen`), prüfen, ob
     pause.png auf dem Präsentations-Bildschirm liegt und "Pausenbild an" im raumsteuerung.log steht;
     dann `1/2/5/press` und prüfen, dass es weg ist.
   - Tablet-Seite: `Invoke-WebRequest http://127.0.0.1:8080/` muss 200 liefern.
   - Teams-Steuerung: Ende von `C:\Raumsteuerung\teams-steuerung.log` lesen, Fehler melden.
5. Ergebnis als kurze Tabelle: was geprüft, OK / Fehler, Beleg (Logzeile, Wert, Screenshot-Pfad).

## Fehler beheben
- Ursache zuerst im Code finden (Repo `C:\Raum5`), nicht raten. Kleine, klare Fixes darfst du selbst machen,
  testen, committen und pushen:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" add -A
  & "C:\Program Files\Git\cmd\git.exe" commit -m "<deutsche Beschreibung>"
  & "C:\Program Files\Git\cmd\git.exe" push origin claude/modest-mayer-tbnbre
  ```
  Vorher immer erst `pull`. `.ps1`-Dateien bleiben UTF-8 mit BOM und CRLF.
- `Raumsteuerung.exe` wird aus `tools\RaumsteuerungTray\*.cs` gebaut. Lokal mit dem .NET-Framework-Compiler:
  `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (Parameter wie in `tools\RaumsteuerungTray\build.sh`);
  bei jeder Änderung `Version` in Program.cs erhöhen.

## Nicht ohne Rückfrage
- Companion-Konfiguration ändern/importieren, OBS-Szenen ändern, Teams-Meetings beitreten/verlassen, Mikro/Kamera
  in einem laufenden Meeting schalten (`r5_t_in = 1` -> keine Teams-Befehle!), Raum aus (1/0/2) drücken,
  Firewall/Netzwerk/Autostart ändern, Dateien außerhalb von `C:\Raum5` und `C:\Raumsteuerung` anfassen,
  `git push --force` oder History umschreiben.
- Den Zustand, den du für einen Test änderst (z. B. Pausenbild), stellst du danach wieder her.
