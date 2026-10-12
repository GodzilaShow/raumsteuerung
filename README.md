# Raumsteuerung Sitzungszimmer 5 (KH II)

Tablet-Seite (`Raumsteuerung/raumsteuerung.html`, Vanilla JS) → Bitfocus Companion (HTTP-API) → OBS + Yamaha RM-CR.
Einrichtung auf dem Raum-PC: siehe `ANLEITUNG.txt`. Projektstand: `UEBERGABE.md`.

## Testen ohne Raum-PC

```
node test/mock-companion.js                                   # Seite :8080, Mini-Companion :8000
node test/mock-rmcr.js                                        # Mini-RM-CR: RCP :49280, Pegel per :8001/set?1=78
NODE_PATH=$(npm root -g) node test/functional.js              # 37 Funktionstests (Playwright)
NODE_PATH=$(npm root -g) node test/explore.js <ordner> <tag>  # Screenshots + Layout-Prüfung
PWSH=pwsh node test/mikro-test.js                             # 20 Szenarien der Mikrofon-Automatik
```

Der Mock protokolliert jeden Button-Druck; Zustand ändern z. B. mit
`curl "127.0.0.1:8000/_test/set?r5_pmic=3"` oder Companion „abstürzen“ lassen mit `?down=1`.
