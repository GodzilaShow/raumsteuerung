#!/usr/bin/env python3
"""Prüft Raum5_Companion.companionconfig gegen Tablet-Seite und Mikrofon-Automatik.
Aufruf: python3 -I test/check-companion-config.py"""
import gzip, json, re, sys, os
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
d = json.load(gzip.open(os.path.join(root, 'Raum5_Companion.companionconfig'), 'rt', encoding='utf-8'))
html = open(os.path.join(root, 'Raumsteuerung', 'raumsteuerung.html'), encoding='utf-8').read()
mic = json.load(open(os.path.join(root, 'Raumsteuerung', 'mikro-automatik.json'), encoding='utf-8-sig'))
ok = bad = 0
def check(c, m):
    global ok, bad
    ok += bool(c); bad += not c
    print(('  ✔ ' if c else '  ✘ ') + m)

def control(loc):
    p, r, c = loc.split('/')
    return d['pages'].get(p, {}).get('controls', {}).get(r, {}).get(c)

def walk(actions):
    for a in actions:
        yield a
        for ch in (a.get('children') or {}).values():
            yield from walk(ch)

cfg = html[html.index('var CONFIG'):html.index('/* Companion-Adresse')]
buttons = dict(re.findall(r"(\w+):\s*'(\d+/\d+/\d+)'", cfg))
print('Tablet-Buttons (%d)' % len(buttons))
for name, loc in buttons.items():
    c = control(loc)
    check(c is not None and c['steps']['0']['action_sets']['down'], f'{name} -> {loc} vorhanden und mit Aktion')

print('Mikrofon-Automatik')
for loc in list(mic['zonen'].values()) + [mic['ganzerRaum']]:
    check(control(loc) is not None, f'Zone {loc} vorhanden')
for v in (mic['autoVariable'], mic['micVariable']):
    check(v in d['custom_variables'], f'Variable {v} vorhanden')

print('Variablen')
for v in re.findall(r"(\w+Variable):\s*'(\w+)'", cfg):
    if v[0] != 'obsConnection':
        check(v[1] in d['custom_variables'], f'{v[0]} = {v[1]} vorhanden')
used = set(); ids = []; conns = set(d['instances']) | {'internal'}
allacts = []
for p in d['pages'].values():
    for row in p['controls'].values():
        for c in row.values():
            if not c or 'steps' not in c: continue
            for st in c['steps'].values():
                for s in st['action_sets'].values():
                    allacts += list(walk(s))
for t in d['triggers'].values():
    allacts += list(walk(t['actions']))
for a in allacts:
    ids.append(a['id'])
    if a['definitionId'] == 'custom_variable_set_value':
        used.add(a['options']['name']['value'])
missing = sorted(u for u in used if u not in d['custom_variables'])
check(not missing, 'alle gesetzten Variablen existieren ' + str(missing))
check(len(ids) == len(set(ids)), 'Aktions-IDs eindeutig (%d)' % len(ids))
check(all(a['connectionId'] in conns for a in allacts), 'alle Aktionen gehören zu vorhandenen Verbindungen')
for a in allacts:
    if a['definitionId'] == 'button_pressrelease':
        check(control(a['options']['location']['value']) is not None, 'Trigger/Button drückt vorhandenen Button ' + a['options']['location']['value'])

print('OBS-Szenen')
scenes = {a['options']['scene']['value'] for a in allacts if a['definitionId'] == 'set_scene'}
tab = set(re.findall(r"'([^']+)': '(?:alles|folien|diskussion|redner|pause)'", cfg))
check(scenes <= tab, 'jede Szene aus Companion kennt das Tablet ' + str(sorted(scenes - tab)))
print('Sicherheit')
check(all(not v['config'].get('pass') for v in d['instances'].values()), 'kein Passwort im Paket')
print(f'\n{ok} bestanden, {bad} fehlgeschlagen'); sys.exit(1 if bad else 0)
