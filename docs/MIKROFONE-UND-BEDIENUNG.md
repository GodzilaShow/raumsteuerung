# Mikrofone, Ton und Bedienung – Kontext für andere Chats (Stand 27.10.2026)

In einen anderen Chat einfügen, damit er Ton/Mikrofone und die Tablet-Oberfläche versteht. Details: `UEBERGABE.md`,
`ANLEITUNG.txt`, `docs/NETZPLAN.md`, Repo GodzilaShow/raumsteuerung, Branch `claude/modest-mayer-tbnbre`.

---

## Ton-Hardware im Saal (Sitzungszimmer 5)
| Gerät | Was | Anschluss |
|---|---|---|
| **Yamaha ADECIA RM-CR** | Audio-Prozessor (DSP, Echo-Unterdrückung), Herz der Tonanlage | PoE+ am Yamaha-Switch, Dante; USB zum Raum-PC = Mikrofon/Lautsprecher für **Teams** |
| **4 × Yamaha RM-TT** | Tischmikrofone im **Publikum** (Reihen) | je PoE am Switch, Dante → RM-CR |
| **Sennheiser EW-D** | **Headset des Sprechers** (Funk): Taschensender + Empfänger EW-D EM | Empfänger **XLR → RM-CR MIC IN 1**, eigenes Netzteil, **kein Netzwerk** (Einstellung per Smart-Assist-App/Bluetooth) |
| **2 × Yamaha VXL1B-16P** | Säulenlautsprecher links/rechts vorne (in Dante Controller „VXL1-16P“) | je PoE+ am Switch, Dante ← RM-CR |
| HDMI-Matrix → RM-CR AUX IN | Ton von Laptop/PC-Präsentation in den Saal | Audio-Ausgang Matrix → RM-CR |

Signalweg: Mikrofone (RM-TT + Headset) → RM-CR → Lautsprecher im Saal **und** per USB → Raum-PC → **Teams** (online).
Teams-Ton von außen → USB → RM-CR → Lautsprecher. Steuerung des RM-CR: Companion per **RCP, TCP 49280** (ohne Login).

## Was die Tablet-Seite heute kann (raumsteuerung.html)
- **Lautstärke** Saal: „−  60 %  +“ (Companion setzt `r5_vol_db`, RM-CR Ausgangspegel). Keine Balken – Wunsch des Nutzers.
- **„Ton aus“** (Lautsprecher stumm, Pegel bleibt; `r5_spk_mute`, Buttons 1/1/6 aus, 1/1/7 an). Lauter/leiser schaltet Ton wieder an.
- **Teams-Leiste (nur im Meeting):** drei große Knöpfe **Mikro an/aus · Kamera an/aus · Präsentation zeigen**,
  „Verlassen“ klein im Kopf. „Mikro“ = **Teams-Stummschaltung** (nicht der RM-CR!): Tablet schickt `r5_tcmd = mic_on/mic_off`,
  `teams-steuerung.ps1` drückt den Knopf in Teams, Zustand zurück über `r5_t_mute`.
- Nutzer-Wunsch zur Oberfläche: Hauptknöpfe sind **Präsentation, Kamera, Mikro** – groß, klar, mit kleinen Symbolen,
  nicht überladen.
- **Kamera-Seite:** nur Redner-Kamera (PTZ, 3 Presets). Publikum-Kamera ist **fest** (ganzer Raum), keine Steuerung.
- Werkzeuge in Raumsteuerung.exe / `pruefen.ps1` zeigen die **Mikrofon-Pegel des RM-CR** (Hilfe bei Tonproblemen).

## Was es NICHT mehr gibt (bewusst entfernt, 22.10.2026)
- **Mikrofon-Automatik** (`mikro-automatik.ps1`): Publikum-Kamera schwenkte zum sprechenden Tischmikrofon. Entfernt,
  weil die Publikum-Kamera fest ist. Der Dateiname `mikro-automatik.json` ist nur historisch (enthält allgemeine Einstellungen).

## Bekannte Fakten / Stolpersteine
- RM-TT müssen im RM-CR unter **Settings → Peripheral** registriert sein, sonst kein Signal.
- Ohne feste IPs bekamen RM-TT/VXL nach Neustart 169.254.x.x → **kein Ton**. Feste Dante-IPs nötig (siehe NETZPLAN).
- Ein RM-TT liefert ggf. 2 Kanäle; Zuordnung Kanal ↔ Mikrofon im RM-CR prüfen.
- Hat Windows **kein Mikrofon** (RM-CR-USB fehlt), sperrt Teams „Mikro an“ → Tablet-Knopf wirkt nicht.

## Saal-Mikrofone auf dem Tablet (eingebaut 27.10.2026)
- Zeile „Mikrofone | Lautsprecher“: links **Alle sprechen · Nur Sprecher · Alle stumm** (gewählt blau, „Alle stumm“ rot),
  rechts „Lautsprecher − 60 % + Ton aus“. Der Teams-Knopf „Mikro“ ist ausgeblendet (sonst zwei „Mikro aus“).
- Companion: Buttons 1/4/1–3, Variable `r5_mic_mode` (alle/sprecher/stumm), erzeugt mit `tools/mikrofone-companion.py`.
  „Raum an“ → Alle sprechen, „Raum aus“ → Alle stumm, Teams-Ende → keine Änderung.
- Nur Sprecher: Headset an, RM-TT stumm; ein Gast drückt die Taste am RM-TT (Modus „Mute Toggle“) und spricht.
- RCP: Mute-Gruppen `RM:MicMute/Group` (je RM-TT eine Gruppe 0–3, Headset Gruppe 4) und `RM:MicMute/All`.
  **Am Gerät noch nicht geprüft** (Index, Wert 1 = stumm?): `get RM:MicMute/Group 0 0`; sonst Parameter des Skripts anpassen.
- Mikrofone nur nach Teams (USB), nicht auf die Saal-Lautsprecher – Einstellung im RM-CR.
- Später: Start-Modus in den Einstellungen von Raumsteuerung.exe (heute Skript-Parameter `--start`).
- Headset (EW-D): Akku/Funkstatus ist **nicht** abfragbar (kein Netzwerk) – nur am Empfänger/in der App.
