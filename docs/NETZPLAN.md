# Netzplan Sitzungszimmer 5 (Vorschlag 26.10.2026, aus Datenblatt-Recherche, geprüft 26.10.)

Ergebnis von `docs/PROMPT-NETZPLANUNG.md`. Noch nicht umgesetzt. Punkte mit **unbestätigt** vor Ort prüfen.

## Entscheidungen
- **Ein AV-Netz**, nur am Yamaha-Switch + kleinem Zusatz-Switch. PC Karte 1 = Landkreis, Karte 2 = AV, **kein Routing, kein ICS**.
- **Feste IPs, kein DHCP** in `192.168.55.0/24` (vorher mit IT klären, dass frei), ohne Gateway/DNS.
- **Kein WLAN-AP** (EAP225 entfällt): Tablet **am Kabel** über USB-C-LAN-Adapter mit PD (siehe unten).
  Grund: Companion-API und RM-CR (RCP) haben kein Login – ein WLAN-Passwort, das weitergegeben wird, öffnet den Raum.
  WLAN nur, wenn das Tablet frei im Raum herumgetragen werden muss (dann EAP225 am TL-SG108E per PoE-Injektor, IT fragen).
- **3. Netzwerkkarte nicht nötig**: RM-CR Ether1 trägt Dante + Steuerung (RCP 49280) + Web-UI; Ether2/3 leer lassen.
- **EW-D EM** hat kein Ethernet/PoE (Netzteil 12 V, XLR → RM-CR MIC IN 1) → kein Netz.
- **EZCast Pro Dongle II**: nur eigener Hotspot (Security Code an), kein Netz. Gäste nie ins AV-Netz.
  Eigener Hotspot im Gebäude: mit IT klären (WLAN-Richtlinie, Störungen).

## Fakten (Quellen in der Recherche)
- SWR2311P-10G: Ports 9/10 sind **Kombo** (RJ45 *oder* SFP), PoE+ nur 1–8, 30 W/Port, **240 W gesamt**. DHCP-Server: unbestätigt.
- RM-CR PoE+ max 15 W · RM-TT PoE 802.3af max 4,5 W · VXL1B-16P PoE+ (bis 15 W Ausgang).
  (In Dante Controller heißt der Lautsprecher „VXL1-16P“ – dasselbe Gerät.)
- ViewSonic CDE98G3: RJ45 10/100, 230 V, bis 279 W · TESmart HMA404-E23: LAN/RS232, 12 V.
- Kiosk-App: URL in `Prefs` (Einstellungsdialog), Standard `STANDARD_URL` in `Prefs.java` = 192.168.137.1.

## Portbelegung
Yamaha SWR2311P-10G: 1 RM-CR · 2–5 RM-TT 1–4 (4 Stück, bestätigt) · 6–7 VXL L/R · 8 PTZ · 9 PC Karte 2 · 10 Uplink Zusatz-Switch.
PoE nach Klasse ≤ 181,6 W < 192 W (240 W − 20 %), real ~60 W. **Frei: 0** → kein weiteres PoE-Gerät möglich.
Zusatz-Switch TP-Link TL-SG108E (ohne PoE): 1 Uplink · 2 Display L · 3 Display R · 4 Matrix · 5 Tablet · 6–8 frei.
Yamaha: Dante-Optimierung an, EEE aus. TL-SG108E: **IGMP Snooping an, „Green Ethernet“ aus** (sonst Dante-Multicast
auf den 100-Mbit-Ports der Displays). Kabel Cat6 S/FTP (~100 m gesamt), dazu Strecke TL-SG108E → Sprecherplatz (Tablet).

## Tablet am Kabel
```
Netzteil USB-C PD ≥ 25 W ──┐
                            ├──► USB-C-LAN-Adapter mit PD ──► Tab A9+ (einziger USB-C-Port)
TL-SG108E Port 5 ── LAN ───┘
```
- Adapter braucht **eine eigene USB-C-Buchse „PD“ am Gehäuse** (Pass-Through). Adapter ohne diese Buchse passen nicht.
- Tablet lädt mit max. 15 W, der Adapter braucht selbst etwas → Netzteil ≥ 25 W.
- Tablet: Ethernet statisch `192.168.55.100/24`, ohne Gateway/DNS. **WLAN aus** (per Kiosk-App sperren): Android
  bevorzugt sonst das WLAN mit Internet und findet `192.168.55.1` nicht.
- Vorher testen (1 h): Akku steigt, LAN bricht nicht ab (manche Adapter trennen kurz beim Ein-/Ausstecken des Netzteils).

## IP-Plan 192.168.55.0/24
.1 PC Karte 2 · .10 Yamaha · .11 TL-SG108E · .20 RM-CR Steuerung · .21 RM-CR Dante · .31–.34 RM-TT ·
.41–.42 VXL · .51 PTZ · .61/.62 Displays · .70 Matrix · .100 Tablet.
PC Karte 2 zusätzlich: „In DNS registrieren“ aus, NetBIOS über TCP/IP aus.

## Einkauf (zusätzlich)
TL-SG108E 25–35 € · USB-C-LAN-Adapter Gigabit + PD (z. B. UGREEN, PD 3.0 bis 100 W, ~36 €; Belkin INC019btBK) · USB-C-Netzteil PD ≥ 25 W 15–20 € · Cat6 S/FTP 80–150 € · USB-Netzteil 5 V/1,5 A für EZCast ~10 €.
PTZ (offen): **PoE+ (≤ 25,5 W, kein PoE++/802.3bt)**, Video über LAN, VISCA over IP.
Video: NDI|HX bevorzugt (wenig Verzögerung; braucht OBS-Plugin DistroAV + NDI Runtime, Firewall auf Karte 2).
RTSP über „Medienquelle“ hat 0,5–2 s Verzögerung → Lippen nicht synchron zum Ton aus dem RM-CR.

## Umstellung ICS → Plan
1. IT: Subnetz frei? EZCast-Hotspot ok?
2. **Zuerst ICS aus** (Karte 1 → Eigenschaften → Freigabe). Solange ICS an ist, überschreibt Windows die Adresse von Karte 2.
   Dante-Geräte haben schon feste IPs in 137.x → Ton bleibt.
3. Dann PC Karte 2 = 192.168.55.1/24 ohne Gateway, übergangsweise zusätzlich 192.168.137.1/24.
4. RM-CR Web-UI: Steuerung .20.
5. Dante Controller: Dante-IPs (.21, .31–.34, .41–.42) **in einem Durchgang** (gemischt = kein Ton).
6. RM-CR: Peripherie prüfen (RM-TT noch „connected“? Falls nach IP registriert: neu registrieren).
7. Firewall: Regeln 8080/8000 **ersetzen** – alle Profile, aber nur `-RemoteAddress 192.168.55.0/24`
   (besser zusätzlich `-InterfaceAlias` Karte 2). Bisher (installieren.ps1) Domain/Private ohne Adressfilter
   → aus dem Landkreis-Netz (Profil Domain) erreichbar. Außerdem nach automatischen Regeln für Companion/`node.exe`
   suchen, die alles erlauben, und einschränken.
8. Companion: rmcr .20:49280, disp1/disp2 .61/.62, matrix .70, kamera_r .51:5678 (in Companion selbst, nicht per Import).
9. Raumsteuerung.exe: RM-CR-IP .20.
10. Tablet: Ethernet .100, WLAN aus, Kiosk-URL `http://192.168.55.1:8080`.
11. Displays/Matrix/Switches: IPs setzen.
12. `pruefen.cmd` + Test vom Tablet.
13. 192.168.137.1 entfernen, Doku anpassen. Alte Adresse steht noch in: `android-kiosk/.../Prefs.java` (`STANDARD_URL`),
    `MainActivity.java` (Hinweistext), `Raumsteuerung/kiosk-einrichten.html` (Feld IP), `Raumsteuerung/mikro-automatik.json`
    (`rmcrIp`), `Raumsteuerung/pruefen.ps1`, `tools/RaumsteuerungTray/Einstellungen.cs` (Standard), `Fenster.cs` (Hinweis),
    `installieren.ps1` (Firewall, siehe 7).

## Offen / vor Ort prüfen
Tab A9+ Ethernet mit statischer IP (Samsung: Weitere Verbindungseinstellungen → Ethernet, **unbestätigt**; sonst Mini-DHCP
nur auf Karte 2, nur für die MAC des Tablets) · PoE-Klassen im Yamaha LAN Monitor · RM-CR Steuer-IP auf Ether1 ·
ViewSonic LFD TCP 5000 · Matrix-Standard-IP · Netzprofil Karte 2 · EZCast Hotspot + AirPlay · PTZ-Modell.
