#!/usr/bin/env python3
"""HDMI-Matrix TESmart (LAN) in eine Companion-Konfiguration eintragen.

Legt eine Verbindung "Generic TCP/UDP" an (TCP 5000, Zeilenende CRLF) und haengt den Umschaltbefehl an die
vorhandenen Quellen-Buttons (Tablet unveraendert):
  1/2/1 Raum-PC   1/2/2 Laptop   1/2/3 Kabellos   ->  "MT00SW<Eingang><Ausgang>NT"
Protokoll wie im Companion-Modul "tesmart-hdmimatrix" (v2.0.0): Eingang/Ausgang zweistellig, Ausgang 00 = alle
Ausgaenge. Antwort/Status der Matrix: "LINK:O1I1;O2I1;...;END" (Abfrage MT00RD0000NT).
Erneut ausfuehren ist unschaedlich (alte Matrix-Aktionen werden vorher entfernt).

Aufruf: python -I tools/matrix-companion.py EIN.companionconfig AUS.companionconfig [--host IP] [--port 5000]
        [--pc 1] [--laptop 2] [--kabellos 3] [--ausgaenge 00 | 1,2] [--aktiv]
Ohne --aktiv bleibt die Verbindung ausgeschaltet (IP der Matrix im Raum noch unbekannt).
"""
import argparse, gzip, json, secrets, string

LABEL = 'matrix'


def neue_id():
    abc = string.ascii_letters + string.digits + '_-'
    return ''.join(secrets.choice(abc) for _ in range(21))


def opt(v):
    return {'value': v, 'isExpression': False}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ein'); ap.add_argument('aus')
    ap.add_argument('--host', default=''); ap.add_argument('--port', default='5000')
    ap.add_argument('--pc', type=int, default=1); ap.add_argument('--laptop', type=int, default=2)
    ap.add_argument('--kabellos', type=int, default=3)
    ap.add_argument('--ausgaenge', default='00', help='00 = alle, sonst z. B. 1,2')
    ap.add_argument('--aktiv', action='store_true')
    a = ap.parse_args()
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
        'config': {'port': a.port, 'prot': 'tcp', 'broadcast': False, 'saveresponse': True,
                   'convertresponse': 'string', 'host': a.host},
        'secrets': {}, 'lastUpgradeIndex': -1, 'enabled': bool(a.aktiv and a.host),
    }

    ausg = ['00'] if a.ausgaenge.strip() == '00' else [f'{int(x):02d}' for x in a.ausgaenge.split(',')]
    for col, eingang in (('1', a.pc), ('2', a.laptop), ('3', a.kabellos)):
        down = d['pages']['1']['controls']['2'][col]['steps']['0']['action_sets']['down']
        down[:] = [x for x in down if x.get('connectionId') != cid]
        for o in ausg:
            down.append({'type': 'action', 'id': neue_id(), 'connectionId': cid, 'definitionId': 'send',
                         'options': {'id_send': opt(f'MT00SW{eingang:02d}{o}NT'), 'id_end': opt('\r\n')}, 'children': {}})

    with gzip.open(a.aus, 'wt', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False)
    print(f"Verbindung {LABEL} -> {a.host or '(IP fehlt)'}:{a.port}", '| aktiv' if a.aktiv else '| aus',
          f"| Eingaenge PC={a.pc} Laptop={a.laptop} Kabellos={a.kabellos}, Ausgaenge {','.join(ausg)}")


if __name__ == '__main__':
    main()
