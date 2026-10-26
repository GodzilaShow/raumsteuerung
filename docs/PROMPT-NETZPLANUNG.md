# Prompt: Netz- und Verkabelungsplanung Sitzungszimmer 5

In einen neuen Claude-Chat (mit Websuche) einfügen. Antwort auf Russisch.

---

Du planst Netzwerk, Stromversorgung (PoE) und Verkabelung für einen hybriden Besprechungsraum. Ich will EINE durchdachte,
optimierte Lösung – keine Vorschläge, die du zwei Nachrichten später zurücknimmst. Arbeite deshalb so:

## Vorgehen (Pflicht)
1. **Erst Fakten, dann Plan.** Prüfe jedes Gerät unten im Datenblatt des Herstellers (Websuche): Ports, PoE-Klasse und
   Leistung in Watt, Stromversorgung, ob es DHCP-Server/-Client kann, Netzwerk-Pflicht oder optional. Gib zu jeder
   Angabe die Quelle an. Was du nicht belegen kannst, markierst du als **„unbestätigt“** – nie als Tatsache formulieren.
2. **Für jedes Gerät die Frage „braucht es das wirklich?“** Braucht es Netzwerk? Muss es im AV-Netz sein oder gehört es
   woanders hin (Gäste, Landkreis)? Braucht es PoE oder hat es Netzteil? Nichts in ein Netz hängen, was dort nichts
   zu suchen hat (z. B. Gästegeräte nie ins AV-Netz).
3. **Mindestens zwei Varianten** durchrechnen (z. B. Tablet per WLAN vs. per Kabel; DHCP vom PC vs. feste IPs vs.
   Switch-DHCP), mit Vor-/Nachteilen und Kosten – dann **eine empfehlen** und begründen.
4. **Nachrechnen statt schätzen:** Portzählung (belegt/frei je Switch), PoE-Budget (Summe Watt vs. Budget des
   Switches, mit 20 % Reserve), Kabellängen grob.
5. **Selbstprüfung vor der Antwort:** Liste alle Behauptungen auf, prüfe jede gegen die Quellen und gegen die anderen
   Teile deines Plans (Widersprüche? doppelt belegte Ports? Gerät ohne Strom? Gast im AV-Netz?). Korrigiere, dann
   erst antworten. Am Ende ein Abschnitt **„Was ich nicht sicher weiß“** mit konkreten Prüfschritten für mich.

## Bekannt
- Raum ca. 10 × 7,5 m, 20 Plätze (5 Reihen), vorne 2 Displays.
- Raum-PC (Windows 11) mit **2 Netzwerkkarten**: Karte 1 → Netz Landkreis (Internet, Teams, Domäne), Karte 2 → AV-Netz.
  Auf dem PC laufen Bitfocus Companion (steuert alles im AV-Netz), OBS, Teams. Der PC soll NICHT zwischen den Netzen routen.
- Im Gebäude gibt es: interne DSL-Leitung (Internet), normales WLAN mit Internet (Gäste), geschlossenes WLAN (Landkreis).
- Aktuell (Test): Windows-Internetverbindungsfreigabe (ICS) auf Karte 2 vergibt 192.168.137.x; RM-CR hat 192.168.137.185.
- Geräte:
  - Yamaha SWR2311P-10G Switch: 8× RJ45 mit PoE+ (Ports 1–8), Ports 9–10 RJ45 ohne PoE, darunter SFP-Schächte
    (prüfen: Kombo-Ports zu 9/10 oder eigenständig?). PoE-Budget: im Datenblatt prüfen.
  - Yamaha ADECIA RM-CR (Audio-Prozessor, PoE+, Dante), 4× Yamaha RM-TT (Tischmikrofone, PoE, Dante),
    2× Yamaha VXL1B-16P (Lautsprecher, PoE, Dante).
  - Sennheiser EW-D (Headset-Funkstrecke): Empfänger EW-D EM → XLR in RM-CR MIC IN 1. Prüfen: Netzteil/PoE,
    Netzwerk nötig oder nur für Control Cockpit?
  - PTZ-Kamera an der Decke (Speaker-Cam, folgt dem Referenten), ein Kabel PoE+ – Kabel läuft über die Decke im
    Leitungsweg des früheren Beamers. Prüfen: Leistung, ob Bild über LAN (NDI/RTSP) oder USB/HDMI zum PC.
  - Saal-Kamera (USB am PC, fest, ganzer Raum).
  - 2× ViewSonic CDE98G3-1C (98″), Steuerung per LAN (LFD-Protokoll, TCP 5000), Netzteil.
  - HDMI-Matrix TESmart HMA404-E23 (4×4), Steuerung per LAN, Netzteil.
  - EZCast Pro Dongle II (kabellos zeigen für Gäste) – prüfen: eigener Hotspot und/oder Anbindung an Gäste-WLAN.
  - Tablet Galaxy Tab A9+ (Bedienung, ruft Companion/Webseite am PC auf).
  - WLAN-AP TP-Link EAP225 (geplant, PoE) – prüfen: DHCP-Server ja/nein; brauchen wir ihn überhaupt?
  - Stream Deck (USB am PC).
- Abhängigkeiten, die eine IP-Änderung betreffen:
  - Tablet-Kiosk-App (`android-kiosk/`) öffnet fest `http://192.168.137.1:8080` (PC im ICS-Netz) – bei neuem IP-Plan
    muss die App (oder ihre Einstellung) mit geändert werden.
  - Companion-Verbindungen: RM-CR (TCP 49280), Displays disp1/disp2 (TCP 5000), Matrix, Redner-Kamera `kamera_r`
    (VISCA, TCP 5678; Modell noch offen) – alle mit IP-Adressen.
  - In `UEBERGABE.md` steht als Hardware-Lücke eine **3. Netzwerkkarte für die RM-CR-Steuerung** – prüfen, ob das
    nötig ist oder ob RM-CR-Steuerung und Dante im selben AV-Netz laufen können (Yamaha-Doku).
- Kabellos zeigen ist noch nicht entschieden (Recherche: Barco ClickShare C-5 Gen2, Yealink RoomCast, EZCast Pro Box II).
  AirPlay/Google Cast funktionieren nur, wenn Gast und Empfänger im selben Netz sind – das muss in die WLAN-Entscheidung
  (Gäste nie ins AV-Netz; also: eigener Hotspot des Empfängers, Gäste-WLAN mit IT, oder Button/Dongle ohne Netz).
- Repo zum Nachlesen: https://github.com/GodzilaShow/raumsteuerung, Branch `claude/modest-mayer-tbnbre`
  (`UEBERGABE.md`, `ANLEITUNG.txt`, `SICHERHEIT.md`).

## Gewünschtes Ergebnis
1. Geräteliste mit: Netz (AV / Landkreis / Gäste / keins), Strom (PoE-Port / Netzteil / USB), IP (fest / DHCP).
2. **Portbelegung** jedes Switches als Tabelle (Port → Gerät → PoE W), freie Ports, PoE-Summe vs. Budget.
3. **IP-Plan** AV-Netz (Subnetz, feste Adressen, wer DHCP macht oder warum keiner nötig ist).
4. WLAN-Entscheidung (AP ja/nein, SSID, wer darf rein) und EZCast-Lösung für Gäste.
5. Einkaufsliste (nur was zusätzlich nötig ist) mit grober Preisspanne.
6. Umstellung von ICS auf den neuen Plan: Schritt für Schritt, inkl. was in Companion / Raumsteuerung.exe
   (RM-CR-IP) / Android-Tablet geändert werden muss.
7. „Was ich nicht sicher weiß“ + wie ich es vor Ort prüfe.
