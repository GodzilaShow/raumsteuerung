#!/usr/bin/env bash
# Alle Tests: Companion-Konfiguration, Tablet-Seite und Mikrofon-Automatik.
# Die Mocks führen die Buttons aus Raum5_Companion.companionconfig aus.
# Voraussetzungen: node, Playwright (global), PowerShell (pwsh, Pfad über $PWSH).
set -uo pipefail
cd "$(dirname "$0")/.."
export NODE_PATH="${NODE_PATH:-$(npm root -g)}"
node test/mock-companion.js --config Raum5_Companion.companionconfig > /dev/null 2>&1 & M1=$!
node test/mock-rmcr.js > /dev/null 2>&1 & M2=$!
trap 'kill $M1 $M2 2>/dev/null' EXIT
sleep 1
rc=0
echo "== Companion-Konfiguration";  python3 -I test/check-companion-config.py | tail -1 || rc=1
echo "== Tablet-Seite";             node test/functional.js | tail -1 || rc=1
echo "== Chaos (Störungen + Zufallsbedienung)"; node test/chaos.js | tail -1 || rc=1
echo "== Mikrofon-Automatik";       PWSH="${PWSH:-pwsh}" node test/mikro-test.js | tail -1 || rc=1
exit $rc
