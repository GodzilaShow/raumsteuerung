#!/usr/bin/env python3
"""Saal-Mikrofone (Yamaha RM-CR) in eine Companion-Konfiguration eintragen.

Drei Modi für das Tablet (Zeile „Mikrofone | Lautsprecher“):
  1/4/1 Alle sprechen  -> Tischmikrofone RM-TT 1-4 und Headset (EW-D, MIC IN 1) an
  1/4/2 Nur Sprecher   -> Headset an, RM-TT stumm. Ein Gast kann am RM-TT die Taste drücken und sprechen
                          (RM-TT im Modus „Mute Toggle“).
  1/4/3 Alle stumm     -> alle Mikrofone stumm
Jeder Button setzt r5_mic_mode (alle | sprecher | stumm). Das Tablet liest die Variable zurück.
„Raum an“ (1/0/1) drückt den Button für den Start-Modus (--start, Standard alle), „Raum aus“ (1/0/2) drückt „Alle stumm“.
Die Mikrofone gehen nur nach Teams (USB), nicht auf die Lautsprecher im Saal – das ist eine Einstellung im RM-CR.

RCP-Befehle (TCP 49280, Verbindung „rmcr“): Mute-Gruppen des RM-CR (RM:MicMute/Group, X 0-8) und RM:MicMute/All.
Dafür im RM-CR (Web-UI) jedes RM-TT in eine eigene Mute-Gruppe legen und das Headset in eine weitere Gruppe.
ACHTUNG: Parameternamen stammen aus `prminfo`, Index und Wert (1 = stumm?) sind am Gerät NICHT geprüft.
Vor dem Einsatz im Raum mit `get RM:MicMute/Group 0 0` usw. prüfen und hier anpassen (--tt-gruppen, --headset-gruppe).

Erneut ausführen ist unschädlich (Buttons werden ersetzt, Raum an/aus nicht doppelt ergänzt).
Aufruf: python -I tools/mikrofone-companion.py EIN.companionconfig AUS.companionconfig
        [--tt-gruppen 0,1,2,3] [--headset-gruppe 4] [--start alle|sprecher|stumm]
"""
import argparse, copy, gzip, json, secrets, string

TEXT = 'Raumsteuerung Sitzungszimmer 5 – Saal-Mikrofone (automatisch erzeugt)'
MODI = {'alle': ('1/4/1', 'Mikros alle'), 'sprecher': ('1/4/2', 'Mikros Sprecher'), 'stumm': ('1/4/3', 'Mikros stumm')}


def neue_id():
    abc = string.ascii_letters + string.digits + '_-'
    return ''.join(secrets.choice(abc) for _ in range(21))


def opt(value, expr=False):
    return {'value': value, 'isExpression': expr}


def befehle(modus, tt, headset):
    """RCP-Befehle je Modus. Wert 1 = stumm (am Gerät prüfen)."""
    gruppe = lambda g, stumm: 'set RM:MicMute/Group %d 0 %d' % (g, stumm)
    if modus == 'stumm':
        return ['set RM:MicMute/All 0 0 1']
    tt_stumm = 1 if modus == 'sprecher' else 0
    return ['set RM:MicMute/All 0 0 0', gruppe(headset, 0)] + [gruppe(g, tt_stumm) for g in tt]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ein'); ap.add_argument('aus')
    ap.add_argument('--tt-gruppen', default='0,1,2,3')
    ap.add_argument('--headset-gruppe', type=int, default=4)
    ap.add_argument('--start', default='alle', choices=MODI)
    a = ap.parse_args()
    tt = [int(x) for x in a.tt_gruppen.split(',') if x.strip()]

    with gzip.open(a.ein, 'rt', encoding='utf-8') as f:
        d = json.load(f)
    rmcr = next(k for k, v in d['instances'].items() if v.get('label') == 'rmcr')
    p1 = d['pages']['1']['controls']
    vorlage = copy.deepcopy(p1['1']['1'])

    def act(definition, conn, options):
        x = {'id': neue_id(), 'definitionId': definition, 'connectionId': conn, 'options': options, 'type': 'action', 'children': {}}
        if conn != 'internal':
            x['upgradeIndex'] = 8
        return x

    def button(text, down):
        c = copy.deepcopy(vorlage)
        c['feedbacks'] = []; c['localVariables'] = []
        for layer in c['style']['layers']:
            if layer['type'] == 'text':
                layer['text'] = opt(text)
        c['steps'] = {'0': {'action_sets': {'down': down, 'up': []}, 'options': {'runWhileHeld': []}}}
        c['options']['notes'] = TEXT
        return c

    cv = d['custom_variables']
    if 'r5_mic_mode' not in cv:
        cv['r5_mic_mode'] = {'description': 'Saal-Mikrofone: alle / sprecher / stumm (Tablet, RM-CR)', 'defaultValue': 'stumm',
                             'persistCurrentValue': True, 'sortOrder': len(cv)}

    for modus, (loc, text) in MODI.items():
        _, r, c = loc.split('/')
        down = [act('send', rmcr, {'id_send': opt(b), 'id_end': opt('\n')}) for b in befehle(modus, tt, a.headset_gruppe)]
        down.append(act('custom_variable_set_value', 'internal', {'name': opt('r5_mic_mode'), 'create': opt(False), 'value': opt(modus)}))
        down.append(act('custom_variable_set_value', 'internal', {'name': opt('r5_last_use'), 'create': opt(False),
                                                                  'value': opt('$(internal:time_unix)', True)}))
        p1.setdefault(r, {})[c] = button(text, down)

    # Raum an / aus: alte Mikrofon-Drücke entfernen, dann neu anhängen
    locs = {loc for loc, _ in MODI.values()}
    for col, modus in (('1', a.start), ('2', 'stumm')):
        down = p1['0'][col]['steps']['0']['action_sets']['down']
        down[:] = [x for x in down if not (x['definitionId'] == 'button_pressrelease' and x['options']['location']['value'] in locs)]
        down.append(act('button_pressrelease', 'internal', {'location': opt(MODI[modus][0]), 'force': opt(False)}))

    with gzip.open(a.aus, 'wt', encoding='utf-8', compresslevel=9) as f:
        json.dump(d, f, ensure_ascii=False, indent='\t')
    print('Mikrofon-Buttons 1/4/1-3, Start-Modus', a.start, '| RM-TT-Gruppen', tt, '| Headset-Gruppe', a.headset_gruppe)


if __name__ == '__main__':
    main()
