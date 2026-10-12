# Übergabe: Raumsteuerung Sitzungszimmer 5 (KH II) – Stand 12.10.2026

Diese Datei + `Raum5_Paket.zip` + `raumsteuerung.html` in einem neuen Chat hochladen und schreiben:
„Wir machen hier weiter. Lies die Übergabe und setz bei ‚Nächster Schritt‘ an. Antworte auf Russisch."

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
- Synchronisiert alle 3 s: obs:scene_active, custom r5_vol_db, r5_live, r5_pauto, r5_pmic.
- Animationen per CSS; Regel `prefers-reduced-motion` schaltet sie ab (evtl. entfernen).
- Offene Design-Entscheidung: Schrift (Empfehlung Source Sans 3 eingebettet statt Google Fonts Asap).

## Companion (Ist-Stand)
- Verbindungen: `obs` (OBS Studio, 127.0.0.1:4455, Passwort gesetzt), `rmcr` (Generic TCP 192.168.137.185:49280, Save Response → $(rmcr:tcp_response)).
- Custom Variables: r5_cmd (RCP-Befehl für Button 1/0/3 „send“), r5_vol_db, r5_live, r5_room, r5_last_use, r5_vol.
- Buttons Seite 1: 1/0/1 Raum an, 1/0/2 Raum aus, 1/0/3 RCP-Befehl aus r5_cmd senden, 1/1/1–5 Szenen, 1/3/1 Lautstärke anwenden, 1/3/6 Ton reset (On=1, Level −10 dB, r5_vol_db=−1000).
- Trigger: „Raum 5: Auto-Aus nach 2 h“, „Raum 5: Live-Status an/aus“ (alle 2–3 s, Bedingung obs Output Active Virtual Camera → r5_live 1/0).
- Noch NICHT angelegt: Quellen/Displays/Kamera-Buttons (Hardware fehlt), 3/1/6–7, r5_pauto, r5_pmic, Mikro-Automatik.

## OBS
- Szenen mit Platzhaltern (Hintergrund #0B3A5B, Präsentation/Redner/Publikum als Farbflächen, Pausentext), gesperrt. Backup: Desktop `Raum5_OBS_Szenen_Backup.json`. OBS immer über Datei → Beenden schließen.

## Yamaha RM-CR (Prozessor) – Erkenntnisse
- IP 192.168.137.185 (statisch), Firmware V3.0.1. Web-UI: http://192.168.137.185 (Arsenij loggt sich selbst ein).
- RM-TT Mikrofone: 192.168.137.92 (MAC …8D:E3) und 192.168.137.205 (…8D:E5). **Am 12.10. im RM-CR unter Settings → Peripheral registriert (beide „connected“, SUBMIT).** Vorher: „No devices have been added“ → kein Ton an den Eingängen.
- RCP: `prmnum` = 166 Parameter, `prminfo N` listet sie. Kein Parameter „Taste gedrückt“. Relevante:
  - RM:NeOut_Fader/Ch/Level|On (X5) = Lautsprecher (Kanal 0+1 gekoppelt)
  - RM:AllMic_Mute/Ch/On (X5), RM:MicMute/All, RM:MicMute/Group (X9)
- Meter: `mtrnum` = 26, `mtrstart <ID> <ms>` (alle ≤10 s erneuern), Antwort `NOTIFY mtr <ID> level <hex…>` (7E = 0 dBFS). Wichtig: RM:NeInPostFader (16 Kanäle), RM:InputPort (26), RM:NeInAutomixGain (16).
- Nach der Registrierung kam Signal: InputPort #11/#12 und NeInPostFader #1/#2 (Grundpegel ~0x61, Spitzen ~0x78). Zuordnung Kanal ↔ Mikrofon noch nicht sicher (ein RM-TT kann 2 Kanäle liefern).

## Nächster Schritt
1. Zuordnung testen: Meter RM:NeInPostFader laufen lassen, nacheinander in Mikro 1 und 2 sprechen, Kanäle notieren.
2. Mikro-Automatik in Companion: Pegel-Erkennung → r5_pmic setzen → Publikum-Preset (Mikro→Zone: 1→p_vl, 2→p_vr, 3→p_hl, 4→p_hr, 5→p_hl). Regeln: 3 s Stille → p_all, zwei gleichzeitig → p_all, max. 1 Bewegung / 4 s, OBS-Freeze-Filter beim Schwenk.
3. Buttons 3/1/6–7 + Variablen r5_pauto/r5_pmic anlegen; Paket (Companion-Export ohne OBS-Passwort) neu bauen.

## Hardware-Lücken (für Ausstattungsplan v7)
Tablet (Galaxy Tab A9+, ~209 €) + Halterung; HDMI-Matrix mit LAN (TESmart HMA404-E23, Companion-Modul vorhanden); 3. AOC-HDMI für Tisch-Laptop; WLAN-AP fürs AV-Netz (TP-Link EAP225 ~57 €); 3. Netzwerkkarte für RM-CR-Steuerung; LAN zu den ViewSonic-Displays. Publikum-Kamera mittig über den Displays montieren (FoMaKo 60° reicht nicht für ganze Reihen → Zonen).
