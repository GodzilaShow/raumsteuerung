#!/usr/bin/env python3
"""Nachbildung einer TESmart-HDMI-Matrix (LAN) fuer Tests ohne Hardware.
Versteht MT00SW<ein><aus>NT (aus 00 = alle) und MT00RD0000NT, antwortet mit dem Stand "LINK:O1I1;...;END",
unbekannte Befehle mit "ERR". Jede Zeile mit Uhrzeit ins Log.
Aufruf: python -I test/mock-tesmart.py --port 5003 --ausgaenge 4 --log mock-tesmart.log
"""
import argparse, asyncio, datetime, re

ap = argparse.ArgumentParser()
ap.add_argument('--port', type=int, default=5003)
ap.add_argument('--ausgaenge', type=int, default=4)
ap.add_argument('--log', default='mock-tesmart.log')
a = ap.parse_args()
route = {o: o for o in range(1, a.ausgaenge + 1)}


def schreib(t):
    with open(a.log, 'a', encoding='utf-8') as f:
        f.write(f"{datetime.datetime.now():%H:%M:%S.%f}"[:-3] + f" {t}\n")


def link():
    return 'LINK:' + ';'.join(f'O{o}I{i}' for o, i in route.items()) + ';END'


async def client(r, w):
    schreib('verbunden'); puffer = b''
    while True:
        daten = await r.read(256)
        if not daten:
            break
        puffer += daten
        while b'\n' in puffer:
            zeile, puffer = puffer.split(b'\n', 1)
            zeile = zeile.decode('latin1').strip('\r')
            m = re.fullmatch(r'MT00SW(\d\d)(\d\d)NT', zeile)
            if m:
                ein, aus = int(m.group(1)), int(m.group(2))
                for o in (route if aus == 0 else [aus]):
                    if o in route:
                        route[o] = ein
                antwort = link()
            elif zeile == 'MT00RD0000NT':
                antwort = link()
            else:
                antwort = 'ERR'
            schreib(f'<- {zeile!r} -> {antwort}')
            w.write((antwort + '\r\n').encode()); await w.drain()
    schreib('getrennt')


async def main():
    srv = await asyncio.start_server(client, '127.0.0.1', a.port)
    schreib(f'bereit, {a.ausgaenge} Ausgaenge')
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
