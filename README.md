# Raumsteuerung Sitzungszimmer 5 (KH II)

Tablet-Seite (`Raumsteuerung/raumsteuerung.html`, Vanilla JS) → Bitfocus Companion (HTTP-API) → OBS + Yamaha RM-CR.
Einrichtung auf dem Raum-PC: siehe `ANLEITUNG.txt`. Projektstand: `UEBERGABE.md`.

## Companion-Konfiguration

`Raum5_Companion.companionconfig` wird erzeugt aus dem Export vom 05.10. (`tools/Raum5_Companion_Export_2026-10-05.companionconfig`):

```
python3 -I tools/companion_config.py tools/Raum5_Companion_Export_2026-10-05.companionconfig Raum5_Companion.companionconfig
```

Mit einem neueren Export aus dem Raum geht es genauso (erster Parameter = neuer Export).

## Testen ohne Raum-PC

```
PWSH=pwsh test/alle-tests.sh     # Konfiguration (64), Tablet (39), Mikrofon-Automatik (20)
```

Die Mocks (`test/mock-companion.js --config …`, `test/mock-rmcr.js`) führen die Buttons aus der
echten Konfiguration aus. Einzeln: `node test/mock-companion.js --config Raum5_Companion.companionconfig`,
Seite unter http://127.0.0.1:8080/, Zustand ändern z. B. `curl "127.0.0.1:8000/_test/set?r5_pmic=3"`,
Companion „abstürzen“ lassen mit `?down=1`, Pegel `curl "127.0.0.1:8001/set?1=78"`.
