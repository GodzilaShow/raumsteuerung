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

## Noch offen (für die Oberfläche zu entscheiden)
- Soll das Tablet zusätzlich **Saal-Mikrofone (RM-CR) stummschalten** können – getrennt von Teams-Mikro?
  (z. B. „Publikum-Mikros aus“ während eines Vortrags; geht per RCP-Befehl in Companion wie „Ton aus“.)
- Headset (EW-D): Akku/Funkstatus ist **nicht** abfragbar (kein Netzwerk) – nur am Empfänger/in der App.
- Der Nutzer hat in anderen Chats weitere Wünsche zu Mikrofon-Knöpfen geäußert, die hier nicht protokolliert sind –
  **beim Nutzer nachfragen**, bevor Knöpfe gebaut werden.
