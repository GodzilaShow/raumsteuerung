# Raumsteuerung Kiosk (Android)

Kleine App für das Tablet im Sitzungszimmer 5: zeigt nur die Tablet-Seite des Raum-PCs
(`http://192.168.137.1:8080`), Vollbild, ohne Ausgang für normale Benutzer.

- Als **Geräteinhaber (Device Owner)**: fester Kiosk (Lock Task), App ist Startbildschirm, startet nach jedem
  Neustart von selbst, kein Sperrbildschirm, keine Statusleiste, Bildschirm bleibt beim Laden an.
- **Ausgang:** 5× schnell oben links tippen → Admin-PIN → Menü (neu laden, Adresse, PIN, pausieren, Kiosk entfernen).
  PIN vergessen: am Raum-PC in Raumsteuerung.exe „Tablet freigeben“ → Menü öffnet sich ohne PIN (innerhalb 10 s).
- Notfall: Werksreset per Tasten (Recovery). Ohne Google-/Samsung-Konto auf dem Tablet greift kein FRP.

## Einrichten
**A) QR-Code (ohne PC-Kabel):** Tablet auf Werkseinstellungen → Willkommensbildschirm 6× antippen →
QR von `http://<Raum-PC>:8080/kiosk-einrichten.html` scannen. Die APK muss als `raumkiosk.apk` im Ordner
`C:\Raumsteuerung` liegen.

**B) adb (Tablet ohne Konten, USB-Debugging kurz an):**
```
adb install raumkiosk.apk
adb shell dpm set-device-owner de.emsland.raumkiosk/.AdminReceiver
```
Danach USB-Debugging wieder ausschalten.

## Bauen
GitHub Actions (`.github/workflows/kiosk-apk.yml`) → Release `kiosk-latest` mit `raumkiosk.apk`.

`kiosk.keystore` (Passwort `raumkiosk`) liegt bewusst im Repo: damit bleiben Updates installierbar und die
Signatur-Prüfsumme im QR-Code gleich (`signatur-pruefsumme.txt`). Der Schlüssel schützt nichts Geheimes – eine
neue App kommt ohnehin nur per USB/adb oder Werksreset auf das Tablet.
