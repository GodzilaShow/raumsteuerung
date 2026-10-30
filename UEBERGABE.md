# Übergabe: Raumsteuerung Sitzungszimmer 5 (KH II) – Stand 23.10.2026

Neuer Chat: Repo https://github.com/godzilashow/raumsteuerung, Branch `claude/modest-mayer-tbnbre`.
Schreiben: „Wir machen hier weiter. Lies UEBERGABE.md und setz bei ‚Nächster Schritt‘ an. Antworte auf Russisch."

**Aktualisieren am PC (bestätigt funktionierend, PowerShell als Admin; Repo liegt in `C:\Raum5`, Git nicht im PATH):**
```powershell
cd C:\Raum5
& "C:\Program Files\Git\cmd\git.exe" pull origin claude/modest-mayer-tbnbre
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Raum5\Raumsteuerung\installieren.ps1"
```

## Projekt
- Hybrider Teams-Raum „Sitzungszimmer 5", Landkreis Emsland. Tablet-Steuerung (eine HTML-Datei, Vanilla JS) → Bitfocus Companion 5.0.6 (HTTP-API) → OBS (WebSocket 4455) + Yamaha RM-CR (RCP, TCP 49280).
- Test-PC = privater PC von Arsenij (nicht der Raum-PC). Companion: http://127.0.0.1:8000.
- Design: Emsland-Farben (Blau #0071BC, Grün #3B6D11/#8DC63F, Ink #0E2A3F), 1280×800 Bühne, skaliert.

## Tablet-Seite (raumsteuerung.html)
- Screens: Start (mit „So starten Sie ein Teams-Meeting“ in 4 Schritten), Steuerung, Kamera, Hilfe. Navigation nur über Tabs unten.
- Steuerung: 5 Szenen (Alles im Blick, Folien Groß, Diskussion, Nur Redner, Pausenbild) + Live-Kachel, Lautstärke 0–100 % (Schritte → r5_vol_db), Quelle (Raum-PC/Laptop/Kabellos), Pausenbild (ab 23.10.: `pause.png` im Vollbild von Raumsteuerung.exe auf dem Präsentations-Bildschirm, gesteuert über `r5_blank`), Displays.
- Kamera:
  - Redner-Kamera: Am Sprecherplatz (r_pult 3/0/1), Bei den Displays (r_displays 3/0/2), Ganze Front (r_front 3/0/3); Pfeile/Zoom halten (3/2/x), „Zurück auf Standard“ (r_home 3/2/7, p_home 3/3/7); Schalter „Kamera folgt der sprechenden Person“.
  - Publikum-Kamera: **seit 22.10.2026 fest** (ohne Zoom, ganzer Raum) – keine Steuerung, keine Mikrofon-Automatik mehr; auf der Kamera-Seite nur ein Hinweis. (Früher: Saalplan mit Zonen, Schalter „Automatisch“, mikro-automatik.ps1.)
- Steuerung (seit 21.10.): unter dem Kopf drei große Teams-Knöpfe Mikro, Kamera, Präsentation zeigen (nur im Meeting; ohne Meeting ein großer Knopf „Teams-Meeting starten“), „Verlassen“ klein im Kopf neben „Raum ausschalten“ (zweimal tippen). Ansichten in einer Reihe, Lautstärke als eine Zeile „− 70 % +“ mit „Ton aus“ (keine Balken mehr), darunter Quelle/Displays.
- Synchronisiert alle 3 s: obs:scene_active, custom r5_vol_db, r5_live, r5_room, r5_spk_mute, r5_t_in/_mute/_video/_status/_mode/_share.
- Animationen per CSS; Regel `prefers-reduced-motion` schaltet sie ab (evtl. entfernen).
- Schrift: Source Sans 3 (variabel, SIL OFL) als base64 eingebettet, ersetzt Asap (12.10.).

## Companion (Ist-Stand)
- Verbindungen: `obs` (OBS Studio, 127.0.0.1:4455, Passwort gesetzt), `rmcr` (Generic TCP 192.168.137.185:49280, Save Response → $(rmcr:tcp_response)).
- Custom Variables: r5_cmd (RCP-Befehl für Button 1/0/3 „send“), r5_vol_db, r5_live, r5_room, r5_last_use, r5_vol.
- Buttons Seite 1: 1/0/1 Raum an, 1/0/2 Raum aus, 1/0/3 RCP-Befehl aus r5_cmd senden, 1/1/1–5 Szenen, 1/3/1 Lautstärke anwenden, 1/3/6 Ton reset (On=1, Level −10 dB, r5_vol_db=−1000).
- Teams-Bild in zwei Kanälen: Präsentation = Teams teilt einen echten Bildschirm (Knopf „Präsentation zeigen“, Bildschirm per `teilenBildschirm`, ohne Angabe der Hauptbildschirm), Personen über die OBS Virtuelle Kamera. Seit 22.10.2026 ohne OBS-Projektor und ohne virtuellen Bildschirm (Virtual Display Driver, Maus-Sperre entfernt – zu fehleranfällig).
- Trigger: „Raum 5: Auto-Aus nachts“ (Tablet fragt ab 20 Uhr stündlich, nicht im Teams-Meeting; Sicherheitsnetz 23–5 Uhr ohne Meeting und 2 h ohne Bedienung; tagsüber nie), „Raum 5: Live-Status an/aus“ (alle 2–3 s, Bedingung obs Output Active Virtual Camera → r5_live 1/0).
- Seit 12.10. ist `Raum5_Companion.companionconfig` importiert (alle Tablet-Buttons, 3/1/6–7, r5_pauto, r5_pmic),
  am 13.10. neu importiert mit Teams-Buttons 1/0/4–6 (r5_tcmd, r5_t_*) und Präsentation aus/an 1/2/4–5
  (OBS „Set Source Visibility“ der Szene „Präsentation pausiert“ in „Alles im Blick“ und „Folien Groß“).
  Geräte-Aktionen für Quelle/Displays/Kameras fehlen noch (Hardware fehlt), diese Buttons setzen nur Variablen.
- Admin-Passwort der Weboberfläche gesetzt (Test-PC, Testpasswort). HTTP-API bleibt offen – getestet.

## OBS
- Szenen mit Platzhaltern (Hintergrund #0B3A5B, Präsentation/Redner/Publikum als Farbflächen), gesperrt.
- Pausenbild: Text + Emsland-Logo (`C:/Raumsteuerung/emsland-logo.png`, kommt mit `installieren.ps1`).
- Szenen-Hintergrund: dunkelblau mit Logo „Landkreis Emsland“ und grüner Emsland-Linie (`C:/Raumsteuerung/szenen-hintergrund.png`, Vorlage `tools/szenen-hintergrund.html`), in allen Szenen über der Farbfläche „Hintergrund“.
- Szene „Präsentation pausiert“ (Ink-Fläche, Logo, Text) liegt ausgeblendet über dem Präsentations-Rahmen.
- Backup im Repo: `Raum5_OBS_Szenen_Backup.json` (Stand 13.10., Sammlung „Raum5“, ohne Test-Quellen und ohne
  Audiogeräte des Laptops). OBS immer über Datei → Beenden schließen.
- Auf dem Test-PC liegen zusätzlich Bildschirm + Laptop-Kamera exakt in den Rahmen (Platzhalter ausgeblendet).

## Yamaha RM-CR (Prozessor) – Erkenntnisse
- IP 192.168.137.185 (statisch), Firmware V3.0.1. Web-UI: http://192.168.137.185 (Arsenij loggt sich selbst ein).
- RM-TT Mikrofone: 192.168.137.92 (MAC …8D:E3) und 192.168.137.205 (…8D:E5). **Am 12.10. im RM-CR unter Settings → Peripheral registriert (beide „connected“, SUBMIT).** Vorher: „No devices have been added“ → kein Ton an den Eingängen.
- RCP: `prmnum` = 166 Parameter, `prminfo N` listet sie. Kein Parameter „Taste gedrückt“. Relevante:
  - RM:NeOut_Fader/Ch/Level|On (X5) = Lautsprecher (Kanal 0+1 gekoppelt)
  - RM:AllMic_Mute/Ch/On (X5), RM:MicMute/All, RM:MicMute/Group (X9)
- Meter: `mtrnum` = 26, `mtrstart <ID> <ms>` (alle ≤10 s erneuern), Antwort `NOTIFY mtr <ID> level <hex…>` (7E = 0 dBFS). Wichtig: RM:NeInPostFader (16 Kanäle), RM:InputPort (26), RM:NeInAutomixGain (16).
- Nach der Registrierung kam Signal: InputPort #11/#12 und NeInPostFader #1/#2 (Grundpegel ~0x61, Spitzen ~0x78). Zuordnung Kanal ↔ Mikrofon noch nicht sicher (ein RM-TT kann 2 Kanäle liefern).

## Stand Test-PC (Arsenijs Laptop, 12.10.2026)
- Repo geklont nach `C:\Raum5`, mit `installieren.ps1` nach `C:\Raumsteuerung` installiert (Aufgaben „Raumsteuerung Webserver“
  und „Raumsteuerung Mikrofon-Automatik“ als SYSTEM). Alte Companion-DB gesichert in `C:\Raum5_Sicherung\`.
- Companion: Konfiguration importiert („Import Preserving Unselected“, Settings blieben), OBS-Verbindung blieb grün
  (Passwort musste nicht neu eingetragen werden), GUI-Interface auf 0.0.0.0 (für Telefon/Tablet).
- Live geprüft mit echtem Companion/OBS/RM-CR: Raum an (Virtual Cam, „Live in Teams“), 5 Szenen, Rück-Sync aus OBS,
  Lautstärke ±, Kamera-Seite mit „Mikrofon 1 spricht“, Raum aus (Pausenbild, Startbildschirm). Telefon im WLAN: läuft.
- Mikrofone: RM-TT liefern auf NeInPostFader Kanal 1 und 2, Kanäle 3–16 still. Am Testtisch stehen beide Mikros
  nebeneinander und hören dieselbe Stimme (Spitzen 7A/77) -> Zuordnung erst im Raum sicher. Beide muten gemeinsam
  (vermutlich MicMute-Kopplung im RM-CR).
- Laptop: WLAN „Besprechung 6“ und Ethernet sind „Öffentlich“ -> Firewall-Regeln (Domain/Private) greifen nicht.

Am 12.10. geändert (alles gepusht):
- `server.ps1`: wartet, wenn Port 8080 belegt ist (lief vorher ohne Listener weiter).
- `installieren.ps1`: Aufgaben laufen auch im Akkubetrieb (Windows beendete sie beim Ziehen des Netzsteckers).
- Mikrofon-Automatik: bei zwei aktiven Mikros gewinnt ein deutlich lauteres (`vorsprungStufen`, Standard 8); Glättung zeitbasiert (150 ms).
- Schrift Source Sans 3 eingebettet (statt Asap), Seite 155 -> 110 KB.
- Kamera-Seite: Umschalter Redner/Publikum war abgeschnitten (Panel zu hoch) -> behoben.
- Teams-Leiste auf dem Tablet (Mikro/Bild/Verlassen, nur im Meeting sichtbar): `teams-steuerung.ps1` drückt die
  Teams-Buttons per UI Automation (feste AutomationIds, sprachunabhängig), Companion 1/0/4–6 setzen `r5_tcmd`,
  Zustand in `r5_t_in/_mute/_video`. Live getestet 13.10. (Tablet -> Companion -> Skript -> Teams stumm/an).
  Teams-Drittanbieter-API war auf beiden Testkonten nicht verfügbar (kein „API verwalten“) -> nicht genutzt.
  27.10.2026: auch mit Arsenijs normalem Landkreis-Konto fehlt „API verwalten“ ganz (Einstellungen → Datenschutz).
  Offen: M365-Admin fragen (Richtlinie für Drittanbieter-Geräte), mit dem späteren Raumkonto erneut prüfen.
  Laut Microsoft kann die API Mikro, Kamera, Hand, Verlassen – Beitritt per Link und Bildschirm teilen nicht.
- OBS-Pausenbild mit Emsland-Logo (`Raumsteuerung/emsland-logo.png`); OBS-Test mit Bildschirm + Laptop-Kamera
  in den Rahmen (Platzhalter nur ausgeblendet, Sicherung `C:\Raum5_Sicherung\obs_scenes_2026-10-13_0955`).
- Tests: Ports per `API_PORT`/`PAGE_PORT` änderbar (wenn echter Companion/Webserver laufen), Chromium-Pfad mit Fallback.
  Ergebnis 13.10. auf dem Laptop: Config 67/67, Tablet-Seite 48/48, Mikro-Automatik 21/21.

Am 13.10. außerdem:
- `pruefen.cmd`: Schnellprüfung (Companion, OBS, RM-CR, Webserver, Automatik, Teams-Steuerung, Netz, Firewall, Audio).
- `teams-steuerung.ps1` holt das Teams-Fenster nicht mehr nach vorn (Kompaktleiste bevorzugt, Vordergrund zurück).
- Präsentation ausblenden über OBS (siehe oben), live getestet.
- `SICHERHEIT.md`: Verbindungen, Ports, Konten, Risiken, Checkliste für den Echtbetrieb.
- Test-Laptop: Ethernet 192.168.137.1 ist die Windows-Internetfreigabe-Adresse (ICS) -> im Raum kein ICS verwenden.
- 15.10.: Nach Kabel-/Neustarts hatten RM-TT und Dante-Lautsprecher (Yamaha **VXL1-16P**) nur 169.254.x.x
  (kein DHCP von ICS) -> kein Ton. In Dante Controller feste Adressen gesetzt: RM-TT 8D042B = 192.168.137.17,
  VXL1-16P 565FF0 = 192.168.137.171 (/24), RM-CR Dante = .253, RM-CR Steuerung = .185. Nur ein RM-TT aktiv (Port 11).
- Teams: Knopf „Teams-Meeting starten“ (Teams-Symbol) tritt dem Raum-Meeting bei (teams-link.txt), „Raum starten“ nur Raum, Abschlussfenster nach dem
  Meeting wird automatisch geschlossen.
- Offen auf dem Test-PC (Aufräumen): Teams-Flag `enable_third_party_devices_service` in app_settings.json
  zurücksetzen (Sicherung in `C:\Raum5_Sicherung\`), Testlink „Raum5 Test“ in Teams löschen.
  Aufruf: `API_PORT=8100 PAGE_PORT=8180 bash test/alle-tests.sh` (Playwright global installiert).

## Stand PC DESKTOP-9GQP24U (22.10.2026)
- Eingerichtet mit `tools/Raum5_einrichten.ps1` (als Admin: Git, Klon nach `C:\Raum5`, OBS 32.2.2, Companion 5.1.0
  per winget, dann `installieren.ps1`). Erneut ausführen = `git pull` + Neuinstallation von `C:\Raumsteuerung`.
- OBS: Sammlung „Raum5“ importiert, WebSocket 4455 mit Testpasswort (auch in Companion „obs“ eingetragen, grün).
- Companion: Konfig importiert („Import Preserving Unselected“), GUI auf 0.0.0.0, „Run at login“. Admin-Passwort
  noch nicht gesetzt. `rmcr` rot (RM-CR noch nicht im Netz). Live geprüft: Raum an/aus, 5 Szenen, Präsentation
  aus/an, Lautstärke, Ton aus/an, Publikum-Automatik, Trigger Live-Status, CORS (`*`).
- Virtual Display Driver installiert (`pruefen.cmd`: Teilen-Bildschirm MTT grün). **Seit 22.10. (später) nicht mehr nötig** – „Präsentation zeigen“
  teilt einen echten Bildschirm. VDD dort abschalten (VDD Control → Disable bzw. Geräte-Manager), sonst verschwindet die
  Maus auf einen unsichtbaren Bildschirm; danach `pruefen.cmd` → Zeile „Praesentation teilen“. `teams-link.txt` = Test-Meeting
  (teams.live.com, privat) – Teams auf dem PC nicht angemeldet -> Gast -> Wartebereich.
- Durchlauf: Teams-Meeting starten -> Wartebereich -> eingelassen -> im Meeting erkannt; „Präsentation zeigen“ teilt
  nach ca. 6 s.
- Am 22.10. geändert: „Raum ausschalten“ im Kopf ruhig (Kontur, rotes Symbol); Teams-Steuerung verwirft beim Start
  liegengebliebene `r5_tcmd`; läuft unsichtbar (conhost --headless); erkennt den Wartebereich
  (`r5_t_status` = `warten: Wartebereich`, Tablet „Wartet auf Einlass“, nach 15 min `fehler: nicht eingelassen`).
- 22.10. 08:40: `teams-steuerung.ps1`, `pruefen.ps1`, `raumsteuerung.html` (Stand b7814c1) nach `C:\Raumsteuerung`
  kopiert. Die laufende Teams-Steuerung (Start 07:08) hat noch den alten Code - erst `Raum5_einrichten.ps1` als
  Admin (registriert die Aufgabe headless neu und startet sie neu) bzw. ab-/anmelden. Aufgabenplanung läuft erhöht,
  dort war Neustart per Fernbedienung nicht möglich. Teams: angemeldet (privates Konto), „Teams automatisch starten“
  und „im Hintergrund öffnen“ an. Durchlauf mit dem neuen Code steht noch aus.
- Offen hier: Netzwerkprofil „Privat“, RM-CR (Netz + USB-Audio), Raumkonto (M365-Benutzer mit Teams-Lizenz,
  automatische Anmeldung, eigenes Dauer-Meeting mit Wartebereich umgehen = Alle), Teams-Autostart, Companion-Admin-
  Passwort, echte Passwörter statt Testpasswörter.

## Programm Raumsteuerung.exe (seit 22.10.2026)
- Ersetzt die drei Aufgaben der Aufgabenplanung: `Raumsteuerung/Raumsteuerung.exe` (C#, .NET Framework 4.8, Quelltext
  `tools/RaumsteuerungTray/`, Bau mit `build.sh`/Mono) läuft im Infobereich, startet `server.ps1` und
  `teams-steuerung.ps1` unsichtbar (Job-Objekt: enden mit dem Programm), startet sie bei Abbruch neu (Backoff bis 60 s).
- Fenster: Status (Companion, OBS, Raum, RM-CR, Webserver, Teams-Steuerung, Teams, Netzprofil), Tablet-
  Adresse; Einstellungen (RM-CR-IP, Bildschirme: `teilenBildschirm` und `teamsBildschirm` als Auswahlliste + „Nummern zeigen“ (Overlay je Bildschirm, ab 1.5), Teams-Link, Autostart) –
  schreibt `mikro-automatik.json` (+ `.bak`) im bisherigen Format; Werkzeuge (Prüfen = pruefen.ps1,
  Protokolle, Dienste neu starten). „Aktualisieren“ und „Deinstallieren“ gibt es im Programm bewusst nicht (22.10.,
  Wunsch Nutzer) – neue Version = `installieren.ps1` erneut, entfernen = `deinstallieren.ps1` (beide als Admin).
- `installieren.ps1`: beendet Programm/alte Aufgaben, kopiert, Firewall, Autostart `HKLM\...\Run` „--tray“, startet
  die exe als normaler Benutzer (über explorer.exe). Findet die exe noch alte Aufgaben, startet sie nichts doppelt
  (Status „über Aufgabenplanung“).
- Oberfläche wie Systemeinstellungen (Seitenleiste, gruppierte Listen, eigene Knöpfe/Schalter/Felder in `Ui.cs`,
  Segoe UI Variable + Segoe Fluent Icons unter Windows 11, Titelleiste in Grundfarbe).
- Unter Windows getestet (23.10., DESKTOP-9GQP24U, Version 1.7): Start, Statusfenster, Pausenbild. Bau unter Windows
  mit `tools/RaumsteuerungTray/build.ps1` (csc aus .NET Framework, nur C# 5), unter Linux weiter `build.sh`/Mono.

## Stand 23.10.2026 (lokaler Test auf DESKTOP-9GQP24U, Claude Code am PC)
- Ablauf für lokale Tests: `docs/PROMPT-LOKAL-TEST.md` (Prompt für Claude Code am PC; „teste, Raum ist frei“ =
  ohne Rückfrage testen, danach Raum wie vorgefunden). `installieren.ps1 -OhneWarten` wartet am Ende nicht auf Enter.
  Screenshots/Sicherungen nach `C:\Raum5\backup\` (in `.gitignore`).
- Raumsteuerung.exe 1.7: Pausenbild (`pause.png` im Vollbild auf dem Präsentations-Bildschirm, über `r5_blank`,
  Companion 1/2/4 an, 1/2/5 aus) – live geprüft: Log „Pausenbild an (Bildschirm 1)“ / „Pausenbild aus“, Screenshot ok.
- `pruefen.ps1` auf dem Test-PC: 1 Fehler, 3 Hinweise – alle erwartet (fehlende Hardware): RM-CR nicht im Netz,
  nur ein Monitor (kein Sprecherplatz-Monitor für Teams), WLAN „Öffentlich“, kein RM-CR-USB-Audio
  (Windows hat dann **gar kein Mikrofon** -> Teams sperrt „Mikro an“).
- `teams-steuerung.ps1` (Commit 2dfd768), Ursachen aus dem Log vom 23.10. früh:
  - 05:46 „GetCurrentPattern … Nicht unterstütztes Muster“: Ließ sich ein Teams-Button nicht drücken (gesperrt, z. B.
    Mikro ohne Mikrofon), versuchte der Code immer „Aufklappen“ (nur für „Verlassen“ sinnvoll). Jetzt: Aufklappen nur
    bei „Verlassen“, sonst bis 4 Versuche und klare Logzeile („… lässt sich nicht drücken (Grund) – Mikrofon in
    Windows/Teams vorhanden?“). Live nachgestellt (mic_on ohne Mikrofon).
  - 05:05/05:22 „Beitritt fehlgeschlagen (kein Meetingfenster)“: nach Standby verschluckt Teams den Klick auf
    „Jetzt teilnehmen“, Meeting kam erst 05:23:22; danach stand im Meeting weiter „fehler: Teams reagiert nicht“.
    Jetzt: erneut drücken, wenn der Beitrittsbildschirm nach 10 s noch steht, Wartezeit 75 s statt 40 s; kommt das
    Meeting innerhalb 5 min doch noch („Beitritt: doch noch im Meeting“), wird der Status geleert und „Nur Redner“ gesetzt.
    **Noch nicht live geprüft** (Standby-Fall nicht nachstellbar) – beim nächsten Auftreten Log ansehen.
  - Fehler der Hauptschleife werden mit Befehl und Zeilennummer geloggt.
  - Last (gemessen, % eines Kerns): Skript ~2–3 %, Teams im Meeting ~27 % ohne / ~30 % mit Skript (UI-Automation-
    Abfragen), ohne Meeting/Teams zu ~0. `Close-AfterMeeting` läuft nur noch außerhalb des Meetings (vorher alle 5 s alle
    Buttons aller Teams-Fenster, im Meeting nutzlos). Schließt jetzt auch die Qualitäts-Abfrage nach dem Meeting
    („Hatte Probleme“/„Gut“, `cqf-dismiss-button`) – gesehen nach Verlassen direkt in Teams; Schließen selbst noch nicht
    live gesehen (Abfrage kommt nur zufällig).
  - Teams ganz geschlossen: „Teams-Meeting starten“ startet Teams über den Link (Beitritt in 12 s); Teams im Meeting
    beendet -> nach ~9 s `r5_t_in = 0`. Beides live geprüft.
  - Live getestet: Beitritt (3 s), Kamera an/aus (auch schnell hintereinander und beim Teilen), Teilen an/aus, Verlassen.
- Displays (ViewSonic, LAN) in Companion vorbereitet: Verbindungen `disp1`/`disp2` (Generic TCP, Port 5000, CR,
  **aus, ohne IP**) + Befehle in 1/0/1, 1/0/2, 1/2/6, 1/2/7, 1/3/7 (Details ANLEITUNG Abschnitt 8). Erzeugt mit
  `tools/displays-companion.py` (wiederholbar), getestet gegen `test/mock-viewsonic.py` (alle Befehle 401+,
  Warte-Schritte 8 s/10 s ok, Displays nicht erreichbar -> übrige Aktionen laufen normal).
  Im Live-Companion des Test-PCs per Import eingespielt (Sicherung vorher: `backup/companion-vor-displays-20261023.companionconfig`
  + Kopie der DB). **Wichtig:** Companion-Import übernimmt bei gleichnamigen Verbindungen deren *bestehende*
  Einstellungen (IP, Passwort) – Verbindungseinstellungen also in Companion selbst ändern, nicht per Import.
  Offen im Raum: IPs eintragen, einschalten, Display-ID/Energie-Einstellung prüfen, Modell CDE98G3 testen.
- HDMI-Matrix TESmart (HMA404-E23 geplant, 4×4) in Companion vorbereitet: Verbindung `matrix` (Generic TCP, Port 5000,
  CRLF, **aus, ohne IP**), Buttons 1/2/1–3 schalten **alle Ausgänge** auf Eingang 1 Raum-PC / 2 Laptop / 3 Kabellos
  (`MT00SW0100NT` …, Protokoll wie Companion-Modul `tesmart-hdmimatrix` 2.0.0 – Modul selbst nicht nötig).
  Erzeugt mit `tools/matrix-companion.py` (Eingänge/Ausgänge per Parameter), getestet gegen `test/mock-tesmart.py`.
  Offen im Raum: Verkabelung (welcher Eingang/Ausgang), IP; ob ein Ausgang zur Capture-Karte geht und anders
  geschaltet werden muss. „Raum an“ setzt die Quelle nicht zurück (Tablet merkt sich `S.src` lokal, liest `r5_src` nicht).
- „Raum an“ (1/0/1) setzt die Quelle auf Raum-PC (Matrix Eingang 1, `r5_src = pc`) – sonst bliebe morgens der Laptop
  von gestern (kein Bild). Die Aktionen stehen **vor** dem 8-s-Warten der Displays (Aktionen nach `wait` laufen in
  Companion verzögert und hätten eine in den ersten 8 s gewählte Quelle zurückgesetzt). Das Tablet liest `r5_src` jetzt
  mit (`srcVariable`), zeigt also auch Quellenwechsel vom Stream Deck. Tests: Mock 6/6, Tablet 88/88, Chaos 19/19,
  Konfig 49/49, live im Companion geprüft.
- Nach dem Meeting schaltet `teams-steuerung.ps1` die Kamera-Szene auf „Pausenbild“ (1/1/5), egal wie das Meeting
  endet (erst nach 8 s „kein Meeting“ am Stück, also nicht beim Umschalten des Teilens; nicht beim Skriptstart). Getestet:
  Verlassen am Tablet und direkt in Teams.
- Beobachtung: bei jeder Neuinstallation (Raumsteuerung.exe beendet) wird auch OBS beendet und von der Teams-Steuerung
  neu gestartet („OBS: Absturz-Abfrage“). Ursache im Code: `Dienste.cs` legt die Kindprozesse in ein Job-Objekt mit
  KILL_ON_JOB_CLOSE, und OBS wird von `teams-steuerung.ps1` gestartet -> gehört mit zum Job. Im Betrieb nur relevant,
  wenn die exe abstürzt/neu startet (Virtual Cam kurz weg). Noch nicht behoben.
- Redner-Kamera in Companion vorbereitet (Modell noch offen): Verbindung `kamera_r` (Generic TCP 5678, reines VISCA in
  Hex, **aus, ohne IP**). 3/0/1–3 Position 1–3 anfahren, 3/2/1–6 fahren/zoomen mit Stopp beim Loslassen („up“),
  3/2/7 Home, **neu 3/0/5–7 „Position 1/2/3 speichern“** (nur Companion, zum Einrichten im Raum). Erzeugt mit
  `tools/kamera-companion.py`, getestet gegen `test/mock-visca.py` – auch Ende-zu-Ende vom Tablet (Pfeil 1 s halten →
  rechts, Loslassen → Stopp nach 1,0 s). Offen: Tracking (herstellerabhängig), Sony-VISCA-over-IP bräuchte das
  Modul sony-visca.
- Git auf dem PC: kein `user.name`/`user.email` gesetzt -> Commits mit
  `git -c user.name=Claude -c user.email=noreply@anthropic.com commit …`; Push über den Credential Manager klappt.

## Nächster Schritt
Im Raum (Raum-PC):
1. OBS + Szenen-Backup, Companion + `Raum5_Companion.companionconfig` (vorher exportieren), `installieren.ps1`.
   Companion „Run at login“ + eigenes Admin-Passwort. Automatische Anmeldung des Raumkontos (für Teams-Steuerung).
2. AV-Netz, feste IPs, Netzwerkprofil „Privat“ (sonst erreicht das Tablet Port 8080/8000 nicht) – siehe `SICHERHEIT.md`.
3. Publikum-Kamera fest auf den ganzen Raum ausrichten, in OBS als Quelle eintragen (keine Automatik mehr).
4. `pruefen.cmd`, dann Checkliste ANLEITUNG Abschnitt 6 und 9 (Teams-Leiste) mit echtem Teams-Meeting.
5. Wenn Hardware kommt: Displays, Matrix und Redner-Kamera sind seit 23.10. in Companion eingetragen (Verbindungen
   `disp1`/`disp2`, `matrix`, `kamera_r`, ausgeschaltet) – nur IP eintragen, Schalter an, Kamera-Positionen 1–3 mit
   3/0/5–7 speichern (ANLEITUNG Abschnitt 8). Offen: Tracking der Redner-Kamera (herstellerabhängig), Display-Eingang.
6. Teams-Bild (Teilen) am Raum-PC einrichten, sobald Monitore und Capture-Karte feststehen:
   - Bildschirm für „Präsentation zeigen“: `pruefen.cmd` listet die Bildschirme mit Nummer; die Nummer des Bildschirms
     mit der Präsentation in `mikro-automatik.json` → `teilenBildschirm` eintragen (ohne Eintrag: Hauptbildschirm).
   - Laptop (HDMI) / Kabellos in Teams zeigen: nur, wenn deren Bild auf einem Raum-PC-Bildschirm landet (Capture-Karte
     im Vollbild oder Matrix) – mit der echten Hardware entscheiden.
   - Teams-Fenster: Sprecherplatz-Monitor per `teamsBildschirm` festlegen (exe → Einstellungen → Bildschirme; Nummer,
     Teil des Monitornamens oder `aus`). Große Teams-Fenster auf dem Präsentations-Bildschirm werden seit 1.5 auch
     dorthin verschoben (nur nicht während des Teilens). `pruefen.cmd` hat dafür die Zeile „Teams-Fenster“.
   - Danach `pruefen.cmd` (Zeile „Praesentation teilen“ grün) und Durchlauf Raum starten → Teams-Meeting starten →
     Präsentation zeigen/beenden → Verlassen, Ergebnis per Handy im Meeting prüfen.

## Hardware-Lücken (für Ausstattungsplan v7)
Tablet (Galaxy Tab A9+, ~209 €) + Halterung; HDMI-Matrix mit LAN (TESmart HMA404-E23, Companion-Modul vorhanden); 3. AOC-HDMI für Tisch-Laptop; LAN zu den ViewSonic-Displays. Laut `docs/NETZPLAN.md` (26.10.) **entfallen** WLAN-AP (EAP225) und 3. Netzwerkkarte; neu: Zusatz-Switch TP-Link TL-SG108E (25–35 €), Cat6 S/FTP (80–150 €), Tablet am Kabel über **USB-C-LAN-Adapter mit PD** (z. B. UGREEN 1000 Mbit/s mit PD 3.0 bis 100 W, ~36 €, oder Belkin INC019btBK) + USB-C-Netzteil PD ≥ 25 W (~15–20 €; Tablet lädt mit max. 15 W, Adapter braucht selbst etwas). Vor dem Einbau testen: Tablet lädt am Adapter, LAN bleibt stabil. Publikum-Kamera mittig über den Displays montieren (FoMaKo 60° reicht nicht für ganze Reihen → Zonen).

Recherche 23.10.2026 (Preise = Momentaufnahme, vor Bestellung prüfen; Vergleichstabellen mit Shops, Plus/Minus und
Quellen als Word-Datei `docs/Recherche-Kabellos-Publikumkamera-2026-10-23.docx`, Russisch):
- **Kabellos zeigen** (Windows, Mac, Android ohne App, HDMI → Matrix-Eingang 3): Empfehlung Barco ClickShare C-5 Gen2
  (R9861605EU, ~840–940 €, AirPlay/Google Cast/Miracast, Button optional); Mitte Yealink RoomCast (~570 €, AirPlay vor
  Kauf bestätigen lassen); günstig EZCast Pro Box II (~350 € brutto, ohne Abo). Nicht: Airtame (Jahreslizenz).
  Achtung: AirPlay/Google Cast nur im selben Netz wie der Empfänger (AV-WLAN mit IT klären); online in Teams nur mit
  Capture-Karte.
- **Publikum-Kamera** (fest, ganzer Raum, ≤ 500 €, USB → OBS): Empfehlung Yealink UVC30 **Room** (120°, 4K, ~224 €);
  Alternativen IPEVO Totem 120 (~194 €), AVer CAM130 (90/120°, nur US-Preise), Jabra PanaCast 180° (nur B-Ware ~399 €).
  Brio 4K (90°) vermutlich zu schmal. Aktive USB-Verlängerung einplanen, Auto-Framing aus. Vorher Raumbreite und
  Abstand Kamera → erste Reihe messen (120° diagonal ≈ Bildbreite 3 × Abstand).

## Tablet-Kiosk (26.10.2026)
- Android-App `android-kiosk/` (Java, ohne Bibliotheken): WebView auf `http://192.168.137.1:8080`, als Device Owner fester
  Kiosk (Lock Task, Startbildschirm, Autostart, kein Sperrbildschirm/Statusleiste). Ausgang: 5× oben links + Admin-PIN;
  PIN vergessen: Raumsteuerung.exe → Werkzeuge → „Tablet freigeben“ (schreibt `kiosk-freigabe.json`, Tablet fragt alle 10 s).
- Build: GitHub Actions `.github/workflows/kiosk-apk.yml` → Release `kiosk-latest` (`raumkiosk.apk`), Fehler → Release
  `kiosk-build-fehler` mit Log. Schlüssel `android-kiosk/kiosk.keystore` (bewusst im Repo, Signatur-Prüfsumme bleibt gleich).
- Einrichtung: `kiosk-einrichten.html` (QR-Code für Werksreset + 6× Tippen) oder adb `dpm set-device-owner`.
  Webserver liefert dafür `raumkiosk.apk` und `kiosk-freigabe.json` aus (sonst weiterhin keine JSON-Dateien).
- Noch nicht auf echtem Tablet getestet (Build, Signatur und QR-Inhalt geprüft).

## Stand 27.10.2026
- **Pausenbild neu:** `Raumsteuerung/pause.png` dunkelblau (#0B3A5B) wie der Szenen-Hintergrund, dezente Linien oben/unten,
  grüne Linie unten, kein Text, nur das Emsland-Zeichen in der Mitte (blendet auf 2× 98″ nicht). Vorlage
  `tools/pause-bild.html`, Logo mit ergänztem rechten Blatt `Raumsteuerung/emsland-logo-voll.png`.
  `installieren.ps1` ersetzt alte Standardbilder (weiß bzw. erste dunkle Fassung) per SHA256, ein eigenes Bild bleibt.
- **3D-Modell** `docs/sprechertisch-3d.html` (Artefakt „Sprechertisch Raum 5“): ganzer Raum nach Fotos/Videos,
  ca. 11 × 10 m (Breite geschritten, Tiefe geschätzt), 5 Reihen à 4 PC-Plätze (2 Monitore, 1 Stuhl), Fensterbrüstung
  45 cm mit Brüstungskanal (Strom + LAN), Bodenkonvektor, Bodentank, PTZ am alten Beamer-Halter, Eingang Seitenwand.
  Steuerung: WASD, Leertaste hoch, Shift runter, C schnell, L sperren, Strg+Z zurück.
- **Netzplan** geprüft und ergänzt (`docs/NETZPLAN.md`): ICS zuerst aus, Firewall nur 192.168.55.0/24, Tablet am Kabel
  (USB-C-LAN-Adapter mit PD + Netzteil ≥ 25 W), PTZ-Anforderungen. `SICHERHEIT.md` angepasst.
- **Teams-API:** auch mit Arsenijs Landkreis-Konto fehlt „API verwalten“ → M365-Admin fragen; API könnte ohnehin
  weder Beitritt noch Teilen.
- **PTZ-Vorschlag:** FoMaKo FMK20UH (NDI HX3, 20x, AI-Tracking, ~389 USD bei B&H) – PoE-Standard, VISCA-Port und
  Preis in DE vor Bestellung prüfen.
- **Kiosk-App Test** ohne Device Owner: APK https://github.com/GodzilaShow/raumsteuerung/releases/download/kiosk-latest/raumkiosk.apk
  Standard-URL 192.168.137.1 = Windows-Hotspot; Navigationsleiste nur mit Device Owner (adb) + Wischgesten ohne Hinweis weg.
- **AP2:** `docs/AP2/` (Prüf-Prompt, Vorgaben, Stand) + Doku-Gerüst https://claude.ai/artifact/8xyc9nko2rwYG1Jpyn27Z6
  (Tabs: Gerüst, Arbeitsstand, Einschätzung). Projekt = **ein Raum, Sitzungszimmer 5**; Angebote AN26-0893/-0926
  gehören dazu. Offen: genehmigter Projektantrag aus PAO, Prüfungstermin. Doku schreibt Arsenij selbst, Claude
  prüft; Fachgespräch wird auf Deutsch geübt.

## Stand 30.10.2026 (Test am Arbeitsplatz, Arsenijs PC)
- **Pfeifen (Rückkopplung) behoben:** RM-CR → Processing → Mixing Bus → Ausgang „ANALOG & DANTE SPEAKER OUT“:
  Analog Mic Ch. 1 + 2 **OFF** (Headset nur nach USB/Teams, nicht in die Saal-Lautsprecher). USB-Ausgang: Analog Mic,
  Dante, AUX IN = ON.
- **RM-CR Dante-IP** war auf DHCP → 169.254.6.54 (kein Ton zu den RM-TT). Jetzt **fest 192.168.137.253/24**
  (Settings → Network → Dante IP). Dante Controller: RM-CR ist primärer Taktgeber.
- **RM-TT-128DE3** (MAC …8D:E3, Dante 8D042B): Steuer-IP war DHCP (über ICS) → jetzt **fest 192.168.137.31/24**,
  Dante-IP 192.168.137.17 (fest). Im RM-CR unter Peripheral „connected“. Zweiter registrierter RM-TT (…8D:E5) und
  zwei neue RM-TT noch nicht angeschlossen → gleiche Prozedur, Steuer-IP .32/.33/.34.
- **Prozedur für neue Yamaha-Geräte:** ICS (WLAN → Freigabe für Ethernet) kurz an → Gerät bekommt 192.168.137.x →
  RM Device Finder (Netzwerkkarte 192.168.137.1) findet es → Web-UI → Network → DHCP aus, feste IP → ICS wieder aus,
  danach auf dem PC `New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.137.1 -PrefixLength 24`.
  Ohne ICS findet RM Device Finder per Suche nichts (nur „Search by IP address“).
- **Headset (Sennheiser EW-D):** XLR → RM-CR MIC IN 1 funktioniert (vorher Stecker nicht eingerastet). Empfänger:
  AF OUT war +6 dB → auf ca. 0 dB senken. Sender-Akku schwach (LINK blinkt rot) → laden.
- Ethernet-Profil „Privat“, Firewall-Regel für RM Device Finder angelegt. Mikrofon-Modi auf dem Tablet getestet: funktionieren.
- Netzplan (`docs/NETZPLAN.md`) plant 192.168.55.0/24 – im Test läuft alles noch auf 192.168.137.0/24.

