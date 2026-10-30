#!/usr/bin/env python3
"""Lautsprecher-Befehle im Companion-Export für beide Kanäle des RM-CR setzen.

Der RM-CR hat zwei Near-End-Ausgänge (L/R). Die Tablet-Lautstärke und „Ton aus“
änderten bisher nur Kanal 0; die VXL-Lautsprecher hängen auch an Kanal 1.
Zu jeder Aktion „set RM:NeOut_Fader/Ch/... 0 0 …“ kommt dieselbe für Kanal 1 dazu.

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
                    want = 'set RM:NeOut_Fader/Ch/%s 1 0 %s' % (m.group(1), m.group(2))
                    nxt = obj[i + 1] if i + 1 < len(obj) else None
                    have = isinstance(nxt, dict) and (nxt.get('options', {}).get('id_send') or {}).get('value') == want
                    if not have:
                        b = copy.deepcopy(a)
                        b['id'] = nid()
                        b['options']['id_send']['value'] = want
                        obj.insert(i + 1, b)
                        stats.append(want)
                        i += 1
            i += 1


def main(src, dst):
    raw = open(src, 'rb').read()
    gz = raw[:2] == b'\x1f\x8b'
    data = json.loads(gzip.decompress(raw) if gz else raw)
    stats = []
    walk(data, stats)
    out = json.dumps(data, ensure_ascii=False).encode()
    open(dst, 'wb').write(gzip.compress(out) if gz else out)
    print('%d Aktionen für Kanal 1 ergänzt' % len(stats))
    for s in stats:
        print('  ' + s)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
