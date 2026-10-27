# Prompt: Gesamtprüfung des Projekts + Projektdokumentation und Präsentation (AP2)

In einen neuen Claude-Code-Chat einfügen (Repo `GodzilaShow/raumsteuerung`, Branch `claude/modest-mayer-tbnbre`).
Alles unter der Linie ist der Auftrag.

---

Du arbeitest am Abschlussprojekt (AP2, Fachinformatiker Systemintegration, IHK Osnabrück – Emsland – Grafschaft Bentheim)
von Arsenij, Landkreis Emsland, FB 10. Antworte auf **Russisch, kurz**. Dokumente, Code, Kommentare und Commits auf
**Deutsch, einfache Sätze** (B2, keine Schachtelsätze). Commit-Betreff ohne Umlaute. Vor jeder Arbeit `git pull`.

## Teil A – Gesamtprüfung (zuerst, ohne etwas zu ändern)

Ziel: ein ehrliches Bild, was fertig ist, was nur geplant ist und was sich widerspricht. Nichts beschönigen.

1. **Lesen:** `UEBERGABE.md`, `ANLEITUNG.txt`, `TECHNIK.md`, `SICHERHEIT.md`, `docs/NETZPLAN.md`, `docs/KONTEXT-Raum-PC.md`,
   `docs/AP2/VORGABEN.md`, dann den Code: `Raumsteuerung/` (HTML, PS1), `tools/RaumsteuerungTray/` (C#), `android-kiosk/`,
   `test/`, `tools/*.py`, `Raum5_Companion.companionconfig` (nur Struktur), `docs/sprechertisch-3d.html` (Raum- und Kabelmodell).
2. **Tests laufen lassen:** `bash test/alle-tests.sh`. Ergebnis mit Zahlen festhalten. Fehlschläge nicht reparieren, nur melden.
3. **Prüfen und als Tabelle ausgeben** (Spalten: Bereich · Befund · Beleg Datei:Zeile · Schwere hoch/mittel/niedrig · Vorschlag):
   - Widersprüche zwischen Dokumenten (z. B. IPs, Ports, Gerätenamen, Raummaße, WLAN-AP ja/nein, Anzahl RM-TT,
     Netz 192.168.137.x vs. 192.168.55.x, Zahl der Sitzplätze, Branch-Namen).
   - Stellen, an denen Doku etwas behauptet, das der Code nicht tut (oder umgekehrt).
   - Sicherheit: offene Ports, Firewall-Profile, Passwörter im Repo, Kiosk-Freigabe, Companion ohne Login.
   - Robustheit: Fehlerbehandlung in `teams-steuerung.ps1`, Neustartverhalten der exe (bekannt: OBS stirbt mit, Job-Objekt).
   - Was nur geplant ist (Hardware fehlt): Displays, Matrix, PTZ, Netz-Umstellung, Kiosk auf echtem Tablet.
   - Offene Entscheidungen (PTZ-Modell, Kabellos-Empfänger, Saal-Kamera, Raumtiefe/Reihenabstand).
4. **Zusammenfassung** in 10 Zeilen: Stand, die 5 wichtigsten Risiken, was vor der Prüfung noch erledigt sein muss.
5. Erst nach Rückmeldung von Arsenij Fehler beheben (einzeln, mit Commit).

## Teil B – Projektdokumentation (schrittweise)

**Grundregeln (unbedingt):**
- Maßstab ist der **genehmigte Projektantrag** aus dem IHK-Portal PAO. Titel, Ziel, Umfang und Zeitplan der Doku
  müssen dazu passen. Ohne den Antrag nicht weiterschreiben, sondern danach fragen.
- Projektzeit **höchstens 40 Stunden** inklusive Dokumentation. Nur Arsenijs eigene Arbeit zählt. Die Doku beschreibt
  den Teil des Gesamtvorhabens, der im Antrag steht – nicht alles, was im Repo existiert.
- **Eigenleistung:** Die Doku schreibt Arsenij. Claude liefert Gliederung, Stichpunkte, Formulierungshilfen, Prüfung
  und Korrektur – keine fertigen Kapitel zum Abschreiben. Jede Formulierung muss er im Fachgespräch erklären können.
- **KI-Nutzung offenlegen:** Viele IHKs werten fehlende Angaben als Täuschung. Im Anhang eine Tabelle „Verwendete
  KI-Werkzeuge“ (Werkzeug, Anbieter, Zweck, Kapitel/Folie) vorsehen und die aktuelle Regel der IHK Osnabrück vorher
  prüfen (Ansprechpartner Prüfungsabteilung IT: Niklas Frütel, 0541 353-446).
- Formvorgaben und Gliederung: `docs/AP2/VORGABEN.md`. Werte, die dort als „bei der IHK bestätigen“ markiert sind,
  nicht als feste Regel behandeln.
- Nur echte Zahlen: Angebote (Datatech AN26-0893, AN26-0926), Ticketzahlen, Stunden aus dem Antrag. Fehlt eine Zahl,
  Platzhalter `[[FEHLT: …]]` setzen und Arsenij fragen. Nichts erfinden.

**Vorgehen pro Sitzung (ein Kapitel nach dem anderen):**
1. Kapitel aus der Gliederung wählen, benötigte Fakten aus Repo, Antrag und Arsenijs Angaben sammeln.
2. Stichpunkte + Leitfragen liefern („Was war das Problem? Wer war beteiligt? Warum diese Lösung?“).
3. Arsenij schreibt seinen Text, Claude prüft: Inhalt, Fachbegriffe, Satzbau, Rechtschreibung, Bezug zum Antrag,
   Seitenbudget. Korrekturen als Liste (alt → neu, kurze Begründung).
4. Grafiken vorschlagen, die Text sparen: Netzplan, Anschlussplan, Raumplan (aus `docs/sprechertisch-3d.html`),
   Gantt, Nutzwertanalyse, Soll-Ist-Vergleich.
5. Am Ende jeder Sitzung `docs/AP2/STAND.md` aktualisieren (fertig / in Arbeit / fehlt, Seitenzahl je Kapitel).

## Teil C – Präsentation (erst wenn die Doku steht)

- 15 Minuten, danach ca. 15 Minuten Fachgespräch (bei der IHK bestätigen). Etwa 10–12 Folien.
- Aufbau: Titel → Ausgangslage/Problem → Ziel → Planung (Zeit, Kosten) → Entscheidungen (Nutzwertanalyse) →
  Umsetzung (Netzplan, Steuerung, Demo-Screenshots) → Tests/Qualität → Soll-Ist → Fazit/Ausblick.
- Folien: wenig Text, große Grafiken, Foliennummer „x / n“, Gliederung sichtbar. Emsland-Farben
  (#0071BC, #8DC63F, #0E2A3F).
- Zusätzlich eine Liste mit 20 wahrscheinlichen Fachgesprächsfragen (PoE-Budget, Dante/Multicast, VLAN vs. eigenes
  Netz, warum feste IPs, warum keine Teams-API, Datenschutz, Ausfallsicherheit, Wirtschaftlichkeit) mit Stichpunkt-
  Antworten zum Üben.

## Was du nicht tust
- Keine Doku-Kapitel komplett für Arsenij formulieren.
- Keine Zahlen erfinden, keine Quellen erfinden.
- Nichts außerhalb des Antrags als Projektleistung verkaufen.
