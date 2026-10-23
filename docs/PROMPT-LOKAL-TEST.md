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
1. Aktualisieren und installieren. Vorher `git status`: lokale Änderungen erst committen, nie verwerfen
   (kein `reset --hard`, kein `checkout --`, kein `clean`).
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
   - Pausenbild: `Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/location/1/2/4/press` (nur wenn r5_room = 1 und der Raum frei ist – siehe „Grenzen“ unten; sonst Test
     überspringen und in der Tabelle als „übersprungen“ melden),
     2 s warten, Screenshot aller Bildschirme nach `C:\Raum5\backup\screens\` (PowerShell + System.Drawing,
     `CopyFromScreen`; `backup/` steht in `.gitignore`), prüfen, ob
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
- `installieren.ps1` installiert die FERTIGE `Raumsteuerung\Raumsteuerung.exe` aus dem Repo (baut nicht selbst).
  Nach einer Änderung an `tools\RaumsteuerungTray\*.cs`: `Version` in Program.cs erhöhen, bauen mit
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\RaumsteuerungTray\build.ps1`, die neue exe mit committen,
  dann installieren. Der Windows-Compiler kann nur C# 5 (kein `$"..."`, kein `?.`, kein `out var`, keine `=>`-Methoden).
- Schlägt `push` wegen Anmeldung fehl: nicht erneut versuchen, mir melden (Commit bleibt lokal).

## Freie Hand
Du darfst alles selbst machen, ohne zu fragen: installieren, testen, Companion-Buttons drücken, Raum an/aus,
Teams-Test-Meeting (Link in `C:\Raumsteuerung\teams-link.txt`) beitreten/verlassen, Mikro/Kamera/Teilen schalten,
Pausenbild, Displays, Companion-Konfiguration und OBS anpassen, Fehler im Code beheben, bauen, committen, pushen.
Arbeite selbstständig weiter, bis alles grün ist; frag nur, wenn du wirklich nicht weiterkommst.

Nur diese Grenzen:
- Läuft gerade ein echtes Meeting mit Menschen im Raum (`r5_t_in = 1` und ich habe nicht gesagt, dass es ein Test ist):
  keine Teams-Befehle und nicht Raum aus – warten oder mich fragen.
- Ist `r5_room = 1` und ich habe nicht gesagt, dass der Raum frei ist (auch ohne Teams kann eine Sitzung laufen):
  vorher fragen, bevor du Raum aus, Pausenbild oder Displays schaltest.
- Vor dem Ändern der Companion-Konfiguration einen Export als Sicherung in `C:\Raum5\backup\` ablegen.
- Kein `git push --force`, keine History umschreiben. Am Ende den Raum so hinterlassen, wie du ihn vorgefunden hast,
  und mir kurz berichten, was du getestet, geändert und gepusht hast.
