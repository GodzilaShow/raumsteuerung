# Netzplan Sitzungszimmer 5 (Vorschlag 26.10.2026, aus Datenblatt-Recherche)

Ergebnis von `docs/PROMPT-NETZPLANUNG.md`. Noch nicht umgesetzt. Punkte mit **unbestätigt** vor Ort prüfen.

## Entscheidungen
- **Ein AV-Netz**, nur am Yamaha-Switch + kleinem Zusatz-Switch. PC Karte 1 = Landkreis, Karte 2 = AV, **kein Routing, kein ICS**.
- **Feste IPs, kein DHCP** in `192.168.55.0/24` (vorher mit IT klären, dass frei), ohne Gateway/DNS.
- **Kein WLAN-AP** (EAP225 entfällt): Tablet per **USB-C-Hub mit LAN + PD** am Kabel.
- **3. Netzwerkkarte nicht nötig**: RM-CR Ether1 trägt Dante + Steuerung (RCP 49280) + Web-UI; Ether2/3 leer lassen.
- **EW-D EM** hat kein Ethernet/PoE (Netzteil 12 V, XLR → RM-CR MIC IN 1) → kein Netz.
- **EZCast Pro Dongle II**: nur eigener Hotspot (Security Code an), kein Netz. Gäste nie ins AV-Netz.

## Fakten (Quellen in der Recherche)
- SWR2311P-10G: Ports 9/10 sind **Kombo** (RJ45 *oder* SFP), PoE+ nur 1–8, 30 W/Port, **240 W gesamt**. DHCP-Server: unbestätigt.
- RM-CR PoE+ max 15 W · RM-TT PoE 802.3af max 4,5 W · VXL1B-16P PoE+ (bis 15 W Ausgang).
- ViewSonic CDE98G3: RJ45 10/100, 230 V, bis 279 W · TESmart HMA404-E23: LAN/RS232, 12 V.
- Kiosk-App: URL in `Prefs` (Einstellungsdialog), Standard `STANDARD_URL` in `Prefs.java` = 192.168.137.1.

## Portbelegung
Yamaha SWR2311P-10G: 1 RM-CR · 2–5 RM-TT 1–4 · 6–7 VXL L/R · 8 PTZ · 9 PC Karte 2 · 10 Uplink Zusatz-Switch.
PoE nach Klasse ≤ 181,6 W < 192 W (240 W − 20 %), real ~60 W. Frei: 0.
Zusatz-Switch TP-Link TL-SG108E (ohne PoE): 1 Uplink · 2 Display L · 3 Display R · 4 Matrix · 5 Tablet · 6–8 frei.
Yamaha: Dante-Optimierung an, EEE aus. Kabel Cat6 S/FTP (~100 m gesamt).

## IP-Plan 192.168.55.0/24
.1 PC Karte 2 · .10 Yamaha · .11 TL-SG108E · .20 RM-CR Steuerung · .21 RM-CR Dante · .31–.34 RM-TT ·
.41–.42 VXL · .51 PTZ · .61/.62 Displays · .70 Matrix · .100 Tablet.

## Einkauf (zusätzlich)
TL-SG108E 25–35 € · USB-C-Hub Gigabit-LAN + PD 25–40 € · Cat6 S/FTP 80–150 € · USB-Netzteil 5 V/1,5 A für EZCast ~10 €.
PTZ (offen): PoE+, Video über LAN (NDI|HX oder RTSP für OBS), VISCA over IP.

## Umstellung ICS → Plan
1. IT: Subnetz frei? 2. PC Karte 2 = 192.168.55.1/24 ohne Gateway (übergangsweise zusätzlich 192.168.137.1).
3. ICS aus (Karte 1 → Freigabe). 4. RM-CR Web-UI: Steuerung .20. 5. Dante Controller: Dante-IPs (.21, .31–.34, .41–.42).
6. RM-CR: Peripherie prüfen. 7. Firewall 8080/8000 auch für Profil Public, aber nur `-RemoteAddress 192.168.55.0/24`.
8. Companion: rmcr .20:49280, disp1/disp2 .61/.62, matrix .70, kamera_r .51:5678. 9. Raumsteuerung.exe: RM-CR-IP .20.
10. Tablet: Ethernet .100, Kiosk-URL `http://192.168.55.1:8080`; `STANDARD_URL` in Prefs.java anpassen.
11. Displays/Matrix/Switches: IPs setzen. 12. `pruefen.cmd` + Test vom Tablet. 13. 192.168.137.1 entfernen, Doku anpassen.

## Offen / vor Ort prüfen
Tab A9+ Ethernet mit statischer IP (sonst Mini-DHCP nur auf Karte 2) · PoE-Klassen im Yamaha LAN Monitor ·
RM-CR Steuer-IP auf Ether1 · ViewSonic LFD TCP 5000 · Matrix-Standard-IP · Netzprofil Karte 2 · EZCast Hotspot + AirPlay ·
PTZ-Modell.
