# Kontext für die Einrichtung am Raum-PC (Stand 22.10.2026)

Repo `github.com/godzilashow/raumsteuerung`, Branch `claude/modest-mayer-tbnbre`. Antworte dem Nutzer auf Russisch.
Ausführliche Doku: `ANLEITUNG.txt` (Abschnitt 9 j–p, 10), `UEBERGABE.md` („Nächster Schritt“, Punkt 6), `TECHNIK.md`.

## Aktuelles Schema: „Präsentation zeigen“ (nicht mehr nur Virtuelle Kamera)

Teams bekommt das Bild in **zwei Kanälen** (wie Teams Rooms):

1. **Personen** = Teams-Kamera = OBS Virtuelle Kamera (OBS-Programm). Szenen: „Nur Redner“ (Standard), „Diskussion“
   (Redner + Publikum), „Pausenbild“.
2. **Präsentation** = Teams „Teilen“ eines **echten** Bildschirms – den, auf dem die Präsentation läuft
   („Nur Inhalt“, „Sound einschließen“). Folien kommen scharf, die Kamera flüssig.
   Seit 22.10.2026 **ohne** OBS-Projektor und ohne virtuellen Bildschirm (Virtual Display Driver, Maus-Sperre,
   Fenster-Schieben entfernt – zu fehleranfällig).

## So sieht das Tablet im Modus „teilen“ aus

| Raum an, kein Meeting | Im Meeting | Präsentation wird gezeigt |
|---|---|---|
| ![](ui-1-raum-an-ohne-meeting.png) | ![](ui-2-im-meeting.png) | ![](ui-3-praesentation-wird-gezeigt.png) |

- „Raum starten“ → Kamera-Szene „Nur Redner“.
- Großer Knopf **„Teams-Meeting starten“** → `teams-steuerung.ps1` tritt dem Raum-Meeting bei (`teams-link.txt`),
  **nur mit Kamera**, ohne Teilen.
- Im Meeting drei große Knöpfe: **Mikro / Kamera / „Präsentation zeigen“** (`r5_tcmd` = `share_on`/`share_off`,
  Zustand `r5_t_share`). „Verlassen“ klein oben neben „Raum ausschalten“ (beendet vorher das Teilen).
- Im Modus „teilen“ (`r5_t_mode`, gemeldet von `teams-steuerung.ps1`) blendet das Tablet **„Alles im Blick“ und
  „Folien groß“ aus** – die Folien kommen über das Teilen. Steht `r5_t_mode` auf „kamera“ oder ist leer, sieht man
  alle 5 Ansichten und **keinen** Knopf „Präsentation zeigen“ (alter Weg).

## Wenn „Alles im Blick“/„Folien groß“ sichtbar sind und „Präsentation zeigen“ fehlt

Dann meldet `teams-steuerung.ps1` kein `r5_t_mode = teilen`. Prüfen:

1. `http://127.0.0.1:8000/api/custom-variable/r5_t_mode/value` muss `teilen` liefern. „Not found“ = Companion-Konfig zu
   alt → `Raum5_Companion.companionconfig` aus diesem Branch neu importieren („Import Preserving Unselected“), danach
   OBS-Verbindung (WebSocket-Passwort) in Companion prüfen.
2. Läuft `teams-steuerung.ps1`?
   `Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? CommandLine -match 'teams-steuerung'`.
   Sonst Aufgabe „Raumsteuerung Teams-Steuerung“ starten bzw. ab- und wieder anmelden. **Nicht** innerhalb eines
   Hintergrund-Jobs starten (stirbt beim Beenden des Jobs mit). Log `C:\Raumsteuerung\teams-steuerung.log`,
   `teams-steuerung.ps1 -Status` muss „Modus: teilen“ zeigen.
3. `C:\Raumsteuerung\mikro-automatik.json` darf kein `"teamsBild": "kamera"` enthalten.
4. `C:\Raumsteuerung\raumsteuerung.html` = aktuelle Version aus dem Branch; danach Seite auf dem Tablet neu laden.
5. `pruefen.cmd` → Zeile „Praesentation teilen“ grün (zeigt, welcher Bildschirm geteilt wird).

## Was der PC für „teilen“ braucht

- **Welcher Bildschirm geteilt wird:** `mikro-automatik.json` → `teilenBildschirm` = Nummer wie in Windows
  (Einstellungen → Anzeige, z. B. `"2"`) oder Teil des Monitornamens. **Ohne Eintrag: Hauptbildschirm.**
  `pruefen.cmd` listet alle Bildschirme mit Nummer. Stand 22.10.: am Laptop nur **ein** Monitor → Hauptbildschirm;
  der Nutzer schließt später einen zweiten an und sagt, welcher geteilt werden soll.
- Companion-Button 1/3/9 („OBS Projektor“) und Variable `r5_proj_mon` werden nicht mehr benutzt (stören nicht).
- **`teams-steuerung.ps1`** (läuft als Benutzer): teilt den richtigen Bildschirm (merkt den Teams-Listeneintrag in
  `teilen-eintrag.txt`, prüft an der Lage der Teams-Teilen-Leiste), legt Teams auf
  den Sprecherplatz-Monitor (`teamsBildschirm`), klickt bei OBS „Absturz erkannt“ „Im normalen Modus starten“.
- Ist der eingetragene Bildschirm nicht da (Monitor aus): Tablet zeigt „Präsentation nicht geteilt – am Rednerplatz in Teams Teilen tippen“;
  Kamera und Mikro laufen weiter.

## Nicht im Repo (von Hand)

- `C:\Raumsteuerung\teams-link.txt` – Link des **echten** Raum-Meetings.
- OBS-WebSocket-Passwort in Companion (Verbindung „obs“).
- `teilenBildschirm` in `mikro-automatik.json`, sobald der zweite Monitor dran ist.

## Noch offen (mit der echten Hardware entscheiden)

- Laptop (HDMI) / Kabellos in Teams zeigen: geht nur, wenn deren Bild auf einem Raum-PC-Bildschirm landet
  (Capture-Karte + Vollbild, oder Matrix) – mit der echten Hardware entscheiden.
- Vorschlag, nicht angewendet: Pausenbild-Kachel dunkelblau wie die echte OBS-Pause, Status-Kachel ohne Kartenrahmen.

## Erfahrungen vom Test-Laptop

- Companion und Teams brauchen Autostart („Run at login“ / „Teams automatisch starten“).
- Tests mit `API_PORT=8100 PAGE_PORT=8180`, wenn der echte Companion läuft (8000/8080 belegt).
- Auf einem ausgelasteten PC (Teams im Meeting + OBS) schlagen zeitabhängige Tests gelegentlich fehl – Wiederholung
  allein genügt dann.
