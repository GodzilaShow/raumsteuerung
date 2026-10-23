#!/usr/bin/env python3
"""Nachbildung von ViewSonic-Displays (LFD ueber TCP) fuer Tests ohne Hardware.
Je Port ein "Display": nimmt Befehle mit Zeilenende CR an, antwortet "401+" (ok) bzw. "401-" (unbekannt),
merkt sich Strom/Hintergrundlicht/Eingang und schreibt jede Zeile mit Uhrzeit ins Log.
Aufruf: python -I test/mock-viewsonic.py --ports 5001 5002 --log mock-viewsonic.log
"""
import argparse, asyncio, datetime, re

BEF = {'!': 'strom', '(': 'licht', '"': 'eingang'}


async def display(port, log):
    zustand = {'strom': '001', 'licht': '001', 'eingang': '004'}

    def schreib(t):
        with open(log, 'a', encoding='utf-8') as f:
            f.write(f"{datetime.datetime.now():%H:%M:%S.%f}"[:-3] + f" :{port} {t}\n")

    async def client(r, w):
        schreib('verbunden')
        puffer = b''
        while True:
            daten = await r.read(256)
            if not daten:
                break
            puffer += daten
            while b'\r' in puffer:
                zeile, puffer = puffer.split(b'\r', 1)
                zeile = zeile.decode('latin1').strip('\n')
                m = re.fullmatch(r'8(\d\d)s(.)(\d{3})', zeile)
                if m and m.group(2) in BEF:
                    zustand[BEF[m.group(2)]] = m.group(3)
                    antwort = '401+'
                else:
                    antwort = '401-'
                schreib(f"<- {zeile!r} -> {antwort}  {zustand}")
                w.write((antwort + '\r').encode()); await w.drain()
        schreib('getrennt')

    srv = await asyncio.start_server(client, '127.0.0.1', port)
    schreib('bereit')
    async with srv:
        await srv.serve_forever()


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ports', type=int, nargs='+', default=[5001, 5002])
    ap.add_argument('--log', default='mock-viewsonic.log')
    a = ap.parse_args()
    await asyncio.gather(*(display(p, a.log) for p in a.ports))

asyncio.run(main())
