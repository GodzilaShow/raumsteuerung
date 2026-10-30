#!/usr/bin/env python3
"""Lautsprecher-Befehle im Companion-Export für beide Kanäle des RM-CR setzen.

Der RM-CR hat zwei Near-End-Fader (im Web-UI unter Processing): links = Kanal 0/1
(analoger SP OUT), rechts = Kanal 2/3 (Dante-Lautsprecher, hier die VXL1B). Am Gerät
geprüft 30.10.2026: „set RM:NeOut_Fader/Ch/Level 2 0 …“ bewegt den rechten Fader.
Zu jeder Aktion „set RM:NeOut_Fader/Ch/... 0 0 …“ kommen dieselben für Kanal 1, 2, 3 dazu.

Aufruf:  python3 -I tools/rmcr_stereo.py <ein.companionconfig> <aus.companionconfig>
"""
import copy, gzip, json, re, secrets, string, sys

ALPHA = string.ascii_letters + string.digits + '_-'
PAT = re.compile(r'^set RM:NeOut_Fader/Ch/(Level|On) 0 0 (.*)$')


def nid():
    return ''.join(secrets.choice(ALPHA) for _ in range(21))


def walk(obj, stats):
    if isinstance(obj, dict):
        for v in obj.values():
            walk(v, stats)
    elif isinstance(obj, list):
        i = 0
        while i < len(obj):
            a = obj[i]
            walk(a, stats)
            if isinstance(a, dict) and a.get('definitionId') == 'send':
                cmd = (a.get('options', {}).get('id_send') or {}).get('value', '')
                m = PAT.match(cmd)
                if m:
                    vorhanden = set()
                    j = i + 1
                    while j < len(obj) and isinstance(obj[j], dict) and \
                            (obj[j].get('options', {}).get('id_send') or {}).get('value', '').startswith('set RM:NeOut_Fader/Ch/%s ' % m.group(1)):
                        vorhanden.add(obj[j]['options']['id_send']['value'])
                        j += 1
                    pos = j
                    for ch in (1, 2, 3):
                        want = 'set RM:NeOut_Fader/Ch/%s %d 0 %s' % (m.group(1), ch, m.group(2))
                        if want in vorhanden:
                            continue
                        b = copy.deepcopy(a)
                        b['id'] = nid()
                        b['options']['id_send']['value'] = want
                        obj.insert(pos, b)
                        pos += 1
                        stats.append(want)
                    i = pos - 1
            i += 1


def main(src, dst):
    raw = open(src, 'rb').read()
    gz = raw[:2] == b'\x1f\x8b'
    data = json.loads(gzip.decompress(raw) if gz else raw)
    stats = []
    walk(data, stats)
    out = json.dumps(data, ensure_ascii=False).encode()
    open(dst, 'wb').write(gzip.compress(out) if gz else out)
    print('%d Aktionen für Kanal 1–3 ergänzt' % len(stats))
    for s in stats:
        print('  ' + s)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
