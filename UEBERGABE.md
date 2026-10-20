# Übergabe: Raumsteuerung Sitzungszimmer 5 (KH II) – Stand 13.10.2026

Neuer Chat: Repo https://github.com/godzilashow/raumsteuerung, Branch `claude/website-testing-fixes-ahd51r`.
Schreiben: „Wir machen hier weiter. Lies UEBERGABE.md und setz bei ‚Nächster Schritt‘ an. Antworte auf Russisch."

## Projekt
- Hybrider Teams-Raum „Sitzungszimmer 5", Landkreis Emsland. Tablet-Steuerung (eine HTML-Datei, Vanilla JS) → Bitfocus Companion 5.0.6 (HTTP-API) → OBS (WebSocket 4455) + Yamaha RM-CR (RCP, TCP 49280).
- Test-PC = privater PC von Arsenij (nicht der Raum-PC). Companion: http://127.0.0.1:8000.
- Design: Emsland-Farben (Blau #0071BC, Grün #3B6D11/#8DC63F, Ink #0E2A3F), 1280×800 Bühne, skaliert.

## Tablet-Seite (raumsteuerung.html)
- Screens: Start (mit „So starten Sie ein Teams-Meeting“ in 4 Schritten), Steuerung, Kamera, Hilfe. Navigation nur über Tabs unten.
- Steuerung: 5 Szenen (Alles im Blick, Folien Groß, Diskussion, Nur Redner, Pausenbild) + Live-Kachel, Lautstärke 0–100 % (Schritte → r5_vol_db), Quelle (Raum-PC/Laptop/Kabellos), Präsentation ausblenden, Displays.
- Kamera:
  - Redner-Kamera: Am Sprecherplatz (r_pult 3/0/1), Bei den Displays (r_displays 3/0/2), Ganze Front (r_front 3/0/3); Pfeile/Zoom halten (3/2/x), „Zurück auf Standard“ (r_home 3/2/7, p_home 3/3/7); Schalter „Kamera folgt der sprechenden Person“.
  - Publikum-Kamera: grafischer Saalplan (5 Reihen, 3 Tischblöcke, 5 Mikrofon-Symbole). 4 Zonen antippen: p_vl/p_vr = Reihe 1–2 links/rechts, p_hl/p_hr = Reihe 3–5 links/rechts, p_all = Ganzer Raum. Schalter „Automatisch – folgt dem Tischmikrofon“ (p_auto_on 3/1/6, p_auto_off 3/1/7). Aktives Mikro pulsiert grün.
- Teams-Leiste im Kopf der Steuerung (nur im Meeting): Mikro an/aus, Bild an/aus, Verlassen (zweimal tippen).
- Synchronisiert alle 3 s: obs:scene_active, custom r5_vol_db, r5_live, r5_pauto, r5_pmic, r5_room, r5_t_in/_mute/_video.
- Animationen per CSS; Regel `prefers-reduced-motion` schaltet sie ab (evtl. entfernen).
- Schrift: Source Sans 3 (variabel, SIL OFL) als base64 eingebettet, ersetzt Asap (12.10.).

## Companion (Ist-Stand)
- Verbindungen: `obs` (OBS Studio, 127.0.0.1:4455, Passwort gesetzt), `rmcr` (Generic TCP 192.168.137.185:49280, Save Response → $(rmcr:tcp_response)).
- Custom Variables: r5_cmd (RCP-Befehl für Button 1/0/3 „send“), r5_vol_db, r5_live, r5_room, r5_last_use, r5_vol.
- Buttons Seite 1: 1/0/1 Raum an, 1/0/2 Raum aus, 1/0/3 RCP-Befehl aus r5_cmd senden, 1/1/1–5 Szenen, 1/3/1 Lautstärke anwenden, 1/3/6 Ton reset (On=1, Level −10 dB, r5_vol_db=−1000).
- Teams-Bild in zwei Kanälen (seit 20.10.2026): Präsentation = OBS-Szene „Inhalt“ als Vollbild-Projektor auf virtuellem Bildschirm (Virtual Display Driver), von Teams geteilt; Personen = Virtuelle Kamera (Nur Redner/Diskussion/Pausenbild); Companion 1/3/9 öffnet den Projektor (r5_proj_mon). Details ANLEITUNG 9 j–o.
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

## Nächster Schritt
Im Raum (Raum-PC):
1. OBS + Szenen-Backup, Companion + `Raum5_Companion.companionconfig` (vorher exportieren), `installieren.ps1`.
   Companion „Run at login“ + eigenes Admin-Passwort. Automatische Anmeldung des Raumkontos (für Teams-Steuerung).
2. AV-Netz, feste IPs, Netzwerkprofil „Privat“ (sonst erreicht das Tablet Port 8080/8000 nicht) – siehe `SICHERHEIT.md`.
3. `mikrofone-testen.cmd` mit Mikros an ihren echten Plätzen -> Kanäle + Grundrauschen in `mikro-automatik.json`,
   danach Aufgabe „Raumsteuerung Mikrofon-Automatik“ neu starten.
4. `pruefen.cmd`, dann Checkliste ANLEITUNG Abschnitt 6 und 9 (Teams-Leiste) mit echtem Teams-Meeting.
5. Wenn Hardware kommt: Geräte-Aktionen in die vorhandenen Buttons legen (ANLEITUNG Abschnitt 8).

## Hardware-Lücken (für Ausstattungsplan v7)
Tablet (Galaxy Tab A9+, ~209 €) + Halterung; HDMI-Matrix mit LAN (TESmart HMA404-E23, Companion-Modul vorhanden); 3. AOC-HDMI für Tisch-Laptop; WLAN-AP fürs AV-Netz (TP-Link EAP225 ~57 €); 3. Netzwerkkarte für RM-CR-Steuerung; LAN zu den ViewSonic-Displays. Publikum-Kamera mittig über den Displays montieren (FoMaKo 60° reicht nicht für ganze Reihen → Zonen).
