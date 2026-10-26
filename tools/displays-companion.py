#!/usr/bin/env python3
"""ViewSonic-Displays (LAN, LFD-Protokoll) in eine Companion-Konfiguration eintragen.

Legt je Display eine Verbindung "Generic TCP/UDP" an (TCP 5000, Zeilenende CR) und haengt die Befehle an die
vorhandenen Buttons (Tablet unveraendert):
  1/0/1 Raum an        Display an (aus Standby) + Hintergrundlicht an, nach 8 s Hintergrundlicht noch einmal
  1/0/2 Raum aus       Standby
  1/2/6 Displays an    wie Raum an
  1/2/7 Displays aus   nur Hintergrundlicht aus (Bild schwarz, Display bleibt im Netz -> sofort wieder an)
  1/3/7 neu starten    Standby, 10 s warten, dann wie Raum an
Befehle laut ViewSonic CDE9830 (ANLEITUNG Abschnitt 8): "8" + ID "01" + "s" + Befehl + Wert, Antwort 401+ = ok.
Erneut ausfuehren ist unschaedlich (alte Display-Aktionen werden vorher entfernt).

Aufruf: python -I tools/displays-companion.py EIN.companionconfig AUS.companionconfig [--host1 IP] [--host2 IP]
        [--port 5000] [--aktiv]
Ohne --aktiv bleiben die Verbindungen ausgeschaltet (IP der Displays im Raum noch unbekannt).
"""
import argparse, gzip, json, secrets, string

BEFEHLE = {
    'an':    ['801s!001', '801s(001'],   # Einschalten (aus Standby), Hintergrundlicht an
    'aus':   ['801s!000'],               # Standby
    'dunkel': ['801s(000'],              # Hintergrundlicht aus
}
BEFEHLE['licht'] = ['801s(001']
# Nach dem Einschalten aus Standby startet das Display noch einige Sekunden und kann "Hintergrundlicht an"
# verpassen (war es vorher nur dunkel, bliebe es schwarz) -> nach 8 s noch einmal (schadet nicht)
AN = ['an', ('warten', 8000), 'licht']
BUTTONS = {   # Button -> Liste von Befehlsgruppen bzw. ('warten', ms)
    ('1', '0', '1'): AN,
    ('1', '0', '2'): ['aus'],
    ('1', '2', '6'): AN,
    ('1', '2', '7'): ['dunkel'],
    ('1', '3', '7'): ['aus', ('warten', 10000)] + AN,
}
LABELS = ['disp1', 'disp2']


def neue_id():
    abc = string.ascii_letters + string.digits + '_-'
    return ''.join(secrets.choice(abc) for _ in range(21))


def opt(v):
    return {'value': v, 'isExpression': False}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ein'); ap.add_argument('aus')
    ap.add_argument('--host1', default=''); ap.add_argument('--host2', default='')
    ap.add_argument('--port', default='5000'); ap.add_argument('--port2', default='')
    ap.add_argument('--aktiv', action='store_true')
    a = ap.parse_args()
    d = json.loads(gzip.open(a.ein).read())

    inst = d['instances']
    vorlage = next(v for v in inst.values() if v['moduleId'] == 'generic-tcp-udp')
    hosts = [a.host1, a.host2]; ports = [a.port, a.port2 or a.port]
    ids = []
    for i, label in enumerate(LABELS):
        cid = next((k for k, v in inst.items() if v.get('label') == label), None) or neue_id()
        inst[cid] = {
            'moduleInstanceType': 'connection', 'moduleId': 'generic-tcp-udp',
            'moduleVersionId': vorlage['moduleVersionId'], 'updatePolicy': 'stable',
            'sortOrder': max(v.get('sortOrder', 0) for v in inst.values()) + 1 if cid not in inst else inst[cid]['sortOrder'],
            'label': label, 'isFirstInit': False,
            'config': {'port': ports[i], 'prot': 'tcp', 'broadcast': False, 'saveresponse': True,
                       'convertresponse': 'string', 'host': hosts[i]},
            'secrets': {}, 'lastUpgradeIndex': -1, 'enabled': bool(a.aktiv and hosts[i]),
        }
        ids.append(cid)

    for (p, r, c), folge in BUTTONS.items():
        down = d['pages'][p]['controls'][r][c]['steps']['0']['action_sets']['down']
        down[:] = [x for x in down if x.get('connectionId') not in ids and
                   not (x.get('connectionId') == 'internal' and x.get('definitionId') == 'wait')]
        for schritt in folge:
            if isinstance(schritt, tuple):
                down.append({'type': 'action', 'id': neue_id(), 'connectionId': 'internal', 'definitionId': 'wait',
                             'options': {'time': opt(schritt[1])}, 'children': {}})
                continue
            for cid in ids:
                for cmd in BEFEHLE[schritt]:
                    down.append({'type': 'action', 'id': neue_id(), 'connectionId': cid, 'definitionId': 'send',
                                 'options': {'id_send': opt(cmd), 'id_end': opt('\r')}, 'children': {}})

    with gzip.open(a.aus, 'wt', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False)
    print('Verbindungen:', ', '.join(f"{l} -> {hosts[i] or '(IP fehlt)'}:{ports[i]}" for i, l in enumerate(LABELS)),
          '| aktiv' if a.aktiv else '| aus')


if __name__ == '__main__':
    main()
