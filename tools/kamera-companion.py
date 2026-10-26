#!/usr/bin/env python3
"""Redner-Kamera (PTZ, VISCA over IP) in eine Companion-Konfiguration eintragen.

VISCA ist der Standard der meisten PTZ-Kameras (PTZOptics, FoMaKo, Lumens, AVer, ...). Gesendet wird reines VISCA
(ohne Sony-Kopf) ueber eine Verbindung "Generic TCP/UDP" (Standard TCP 5678; manche Kameras: UDP 1259).
Sony-Kameras mit "VISCA over IP" (UDP 52381, eigener Kopf) brauchen stattdessen das Companion-Modul sony-visca.

Buttons (Tablet unveraendert, es sendet bei den Pfeilen "down" beim Druecken und "up" beim Loslassen):
  3/0/1-3  Position 1/2/3 anfahren (Sprecherplatz / bei den Displays / ganze Front)
  3/2/1-4  hoch / runter / links / rechts  (down: fahren, up: Stopp)
  3/2/5-6  Zoom rein / raus                 (down: zoomen, up: Stopp)
  3/2/7    Grundstellung (Home)
  3/0/5-7  NEU, nur in Companion: aktuelle Lage als Position 1/2/3 SPEICHERN (einmal im Raum einrichten)
Tracking (1/3/3-4) ist herstellerabhaengig und bleibt bei der Variable r5_track.
Erneut ausfuehren ist unschaedlich (alte Kamera-Aktionen werden vorher entfernt).

Aufruf: python -I tools/kamera-companion.py EIN.companionconfig AUS.companionconfig [--host IP] [--port 5678]
        [--udp] [--adresse 1] [--tempo 6] [--aktiv]
"""
import argparse, copy, gzip, json, secrets, string

LABEL = 'kamera_r'


def neue_id():
    abc = string.ascii_letters + string.digits + '_-'
    return ''.join(secrets.choice(abc) for _ in range(21))


def opt(v):
    return {'value': v, 'isExpression': False}


def befehle(adr, tempo):
    a = f'8{adr}'
    pt = f'{tempo:02X}{max(1, tempo - 1):02X}'           # Schwenk-/Neigegeschwindigkeit
    fahr = lambda xy: f'{a}010601{pt}{xy}FF'
    return {
        'hoch': fahr('0301'), 'runter': fahr('0302'), 'links': fahr('0103'), 'rechts': fahr('0203'),
        'stopp': fahr('0303'),
        'zoom_rein': f'{a}01040723FF', 'zoom_raus': f'{a}01040733FF', 'zoom_stopp': f'{a}01040700FF',
        'home': f'{a}010604FF',
        'abrufen': lambda n: f'{a}01043F02{n:02X}FF', 'speichern': lambda n: f'{a}01043F01{n:02X}FF',
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ein'); ap.add_argument('aus')
    ap.add_argument('--host', default=''); ap.add_argument('--port', default='5678')
    ap.add_argument('--udp', action='store_true'); ap.add_argument('--adresse', type=int, default=1)
    ap.add_argument('--tempo', type=int, default=6, help='Schwenken 1-24 (Standard 6 = ruhig)')
    ap.add_argument('--aktiv', action='store_true')
    a = ap.parse_args()
    B = befehle(a.adresse, a.tempo)
    d = json.loads(gzip.open(a.ein).read())

    inst = d['instances']
    vorlage = next(v for v in inst.values() if v['moduleId'] == 'generic-tcp-udp')
    cid = next((k for k, v in inst.items() if v.get('label') == LABEL), None)
    sort = inst[cid]['sortOrder'] if cid else max(v.get('sortOrder', 0) for v in inst.values()) + 1
    cid = cid or neue_id()
    inst[cid] = {
        'moduleInstanceType': 'connection', 'moduleId': 'generic-tcp-udp',
        'moduleVersionId': vorlage['moduleVersionId'], 'updatePolicy': 'stable', 'sortOrder': sort,
        'label': LABEL, 'isFirstInit': False,
        'config': {'port': a.port, 'prot': 'udp' if a.udp else 'tcp', 'broadcast': False, 'saveresponse': True,
                   'convertresponse': 'hex', 'host': a.host},
        'secrets': {}, 'lastUpgradeIndex': -1, 'enabled': bool(a.aktiv and a.host),
    }

    def hexakt(h):
        return {'type': 'action', 'id': neue_id(), 'connectionId': cid, 'definitionId': 'send_hex',
                'options': {'id_send_hex': opt(h), 'id_end': opt('')}, 'children': {}}

    seite = d['pages']['3']['controls']

    def setze(r, c, down, up=()):
        sets = seite[r][c]['steps']['0']['action_sets']
        for k in ('down', 'up'):
            sets[k] = [x for x in sets.get(k, []) if x.get('connectionId') != cid]
        sets['down'] += [hexakt(h) for h in down]
        sets['up'] += [hexakt(h) for h in up]

    for i in (1, 2, 3):
        setze('0', str(i), [B['abrufen'](i)])
    for c, rtg in zip('1234', ('hoch', 'runter', 'links', 'rechts')):
        setze('2', c, [B[rtg]], [B['stopp']])
    setze('2', '5', [B['zoom_rein']], [B['zoom_stopp']])
    setze('2', '6', [B['zoom_raus']], [B['zoom_stopp']])
    setze('2', '7', [B['home']])

    # Speichern-Buttons 3/0/5-7 (Kopie von 3/0/1 mit eigenem Text, ohne Variablen-Aktionen)
    for i in (1, 2, 3):
        c = copy.deepcopy(seite['0']['1'])
        for l in c['style']['layers']:
            if l['type'] == 'text':
                l['text'] = opt(f'Position {i} speichern')
            if l['type'] == 'box':
                l['color'] = opt(0x7A2E00)
        c['steps']['0']['action_sets'] = {'down': [hexakt(B['speichern'](i))], 'up': []}
        c['options']['notes'] = (f'Redner-Kamera: aktuelle Lage als Position {i} speichern (nur Companion, nicht Tablet). '
                                 '1 = Sprecherplatz, 2 = bei den Displays, 3 = ganze Front')
        seite['0'][str(i + 4)] = c

    with gzip.open(a.aus, 'wt', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False)
    print(f"Verbindung {LABEL} -> {a.host or '(IP fehlt)'}:{a.port}/{'udp' if a.udp else 'tcp'}",
          '| aktiv' if a.aktiv else '| aus', f'| VISCA-Adresse {a.adresse}, Tempo {a.tempo}')


if __name__ == '__main__':
    main()
