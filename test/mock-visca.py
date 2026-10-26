#!/usr/bin/env python3
"""Nachbildung einer PTZ-Kamera mit VISCA over IP (reines VISCA, TCP) fuer Tests ohne Hardware.
Liest Pakete bis 0xFF, antwortet ACK (90 41 FF) + Fertig (90 51 FF), uebersetzt den Befehl ins Log und merkt
gespeicherte Positionen. Aufruf: python -I test/mock-visca.py --port 5678 --log mock-visca.log
"""
import argparse, asyncio, datetime

ap = argparse.ArgumentParser()
ap.add_argument('--port', type=int, default=5678)
ap.add_argument('--log', default='mock-visca.log')
a = ap.parse_args()
positionen = set()
RICHTUNG = {(3, 1): 'hoch', (3, 2): 'runter', (1, 3): 'links', (2, 3): 'rechts', (3, 3): 'STOPP'}


def schreib(t):
    with open(a.log, 'a', encoding='utf-8') as f:
        f.write(f"{datetime.datetime.now():%H:%M:%S.%f}"[:-3] + f" {t}\n")


def deute(p):
    b = list(p)
    if b[1:4] == [1, 6, 1] and len(b) == 9:
        return f'Schwenken {RICHTUNG.get((b[6], b[7]), "?")} (Tempo {b[4]}/{b[5]})'
    if b[1:4] == [1, 4, 7]:
        return {0x00: 'Zoom STOPP'}.get(b[4], f"Zoom {'rein' if b[4] >> 4 == 2 else 'raus'} (Tempo {b[4] & 15})")
    if b[1:4] == [1, 6, 4]:
        return 'Home'
    if b[1:4] == [1, 4, 0x3F]:
        if b[4] == 1:
            positionen.add(b[5]); return f'Position {b[5]} GESPEICHERT'
        if b[4] == 2:
            return f'Position {b[5]} anfahren' + ('' if b[5] in positionen else ' (noch nicht gespeichert)')
    return None


async def client(r, w):
    schreib('verbunden'); puffer = b''
    while True:
        daten = await r.read(256)
        if not daten:
            break
        puffer += daten
        while b'\xff' in puffer:
            paket, puffer = puffer.split(b'\xff', 1)
            paket += b'\xff'
            text = deute(paket)
            schreib(f"<- {paket.hex(' ').upper()}  {text or 'UNBEKANNT'}")
            w.write(bytes.fromhex('9041FF9051FF') if text else bytes.fromhex('906002FF')); await w.drain()
    schreib('getrennt')


async def main():
    srv = await asyncio.start_server(client, '127.0.0.1', a.port)
    schreib('bereit')
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
