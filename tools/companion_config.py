#!/usr/bin/env python3
"""Baut Raum5_Companion.companionconfig aus einem Companion-Export (Companion 5, Dateiformat 12).

Aufruf:  python3 -I tools/companion_config.py <export.companionconfig> <ziel.companionconfig>

Ergänzt alle Buttons, Variablen und Trigger, die die Tablet-Seite und die
Mikrofon-Automatik erwarten. Verbindungen (OBS, RM-CR) und ihre Einstellungen
bleiben unverändert; das OBS-Passwort ist im Export ohnehin leer.
Wo noch Hardware fehlt (HDMI-Matrix, Displays, PTZ-Kameras), setzen die Buttons
nur die Zustandsvariable – die Geräte-Aktion wird später dort ergänzt.
"""
import copy
import gzip
import json
import secrets
import string
import sys

ALPHA = string.ascii_letters + string.digits + '_-'


def nid():
    return ''.join(secrets.choice(ALPHA) for _ in range(21))


def opt(value, expr=False):
    return {'value': value, 'isExpression': expr}


def act(definition, connection, options, children=None):
    a = {'id': nid(), 'definitionId': definition, 'connectionId': connection,
         'options': options, 'type': 'action', 'children': children or {}}
    if connection != 'internal':
        a['upgradeIndex'] = 8
    return a


def setvar(name, value, expr=False):
    return act('custom_variable_set_value', 'internal',
               {'name': opt(name), 'create': opt(False), 'value': opt(value, expr)})


def touch():
    """Letzte Bedienung merken (für den Auto-Aus-Trigger in Companion)."""
    return setvar('r5_last_use', '$(internal:time_unix)', True)


def press(location):
    return act('button_pressrelease', 'internal', {'location': opt(location), 'force': opt(False)})


def wait(ms):
    return act('wait', 'internal', {'time': opt(str(ms), True)})


def sequence(*actions):
    return act('action_group', 'internal', {'execution_mode': opt('sequential')}, {'default': list(actions)})


def main(src, dst):
    with gzip.open(src, 'rt', encoding='utf-8') as f:
        d = json.load(f)
    assert d.get('version') == 12, 'Erwartet Companion-Exportformat 12 (Companion 5)'

    obs = next(k for k, v in d['instances'].items() if v.get('label') == 'obs')
    rmcr = next(k for k, v in d['instances'].items() if v.get('label') == 'rmcr')
    p1 = d['pages']['1']['controls']
    template = copy.deepcopy(p1['1']['1'])          # Szene-Button als Vorlage für Stil/Optionen

    def obs_act(definition, options):
        return act(definition, obs, options)

    def button(text, down, up=None):
        c = copy.deepcopy(template)
        c['feedbacks'] = []
        c['localVariables'] = []
        for layer in c['style']['layers']:
            if layer['type'] == 'text':
                layer['text'] = opt(text)
        c['steps'] = {'0': {'action_sets': {'down': down, 'up': up or []}, 'options': {'runWhileHeld': []}}}
        c['options']['notes'] = 'Raumsteuerung Sitzungszimmer 5 (automatisch erzeugt)'
        return c

    def put(page, row, col, control):
        d['pages'][str(page)]['controls'].setdefault(str(row), {})[str(col)] = control

    def extend(page, row, col, *actions):
        c = d['pages'][str(page)]['controls'][str(row)][str(col)]
        down = c['steps']['0']['action_sets']['down']
        names = {(a['definitionId'], json.dumps(a['options'].get('name'))) for a in down}
        for a in actions:      # mehrfaches Ausführen des Skripts fügt nichts doppelt hinzu
            if (a['definitionId'], json.dumps(a['options'].get('name'))) not in names:
                down.append(a)

    # ---------- Variablen ----------
    cv = d['custom_variables']
    def var(name, desc, default, persist):
        old = cv.get(name, {})
        cv[name] = {'description': desc, 'defaultValue': old.get('defaultValue', default) if old.get('defaultValue') not in ('', None) else default,
                    'persistCurrentValue': persist, 'sortOrder': old.get('sortOrder', len(cv))}
    var('r5_cmd', 'RCP-Befehl für Button 1/0/3', '', False)
    var('r5_vol_db', 'Lautsprecherpegel in 0,01 dB (vom Tablet gesetzt)', '-1300', True)
    var('r5_pauto', 'Publikum-Kamera folgt dem Tischmikrofon (1/0)', '1', True)
    var('r5_pmic', 'Sprechendes Tischmikrofon (0 = keins/mehrere)', '0', False)
    var('r5_tcmd', 'Teams-Befehl an teams-steuerung.ps1 (mute/video/leave, danach leer)', '', False)
    var('r5_t_in', 'Teams-Meeting offen (1/0, von teams-steuerung.ps1)', '0', False)
    var('r5_t_mute', 'Teams-Mikro stumm (1/0)', '0', False)
    var('r5_t_video', 'Teams-Bild an (1/0)', '0', False)
    var('r5_t_status', 'Teams-Beitritt: start / fehler: ... / leer', '', False)
    var('r5_spk_mute', 'Lautsprecher stumm (1) / an (0)', '0', True)
    var('r5_proj_mon', 'OBS-Monitornummer des Teilen-Bildschirms (von teams-steuerung.ps1)', '1', False)

    # ---------- Seite 1: Tablet ----------
    extend(1, 0, 1, setvar('r5_room', '1'), setvar('r5_disp', '1'), setvar('r5_blank', '0'), touch())
    extend(1, 0, 2, setvar('r5_room', '0'), setvar('r5_disp', '0'), setvar('r5_blank', '0'))
    for col, scene in enumerate(['alles', 'folien', 'diskussion', 'redner', 'pause'], start=1):
        extend(1, 1, col, setvar('r5_scene', scene), touch())
    for col, (src, label) in enumerate([('pc', 'Quelle Raum-PC'), ('laptop', 'Quelle Laptop'), ('cast', 'Quelle Kabellos')], start=1):
        put(1, 2, col, button(label, [setvar('r5_src', src), touch()]))       # später: TESmart-Matrix umschalten
    # Ton aus/an: Lautsprecher-Ausgang des RM-CR stumm schalten (Pegel bleibt) – für Video, Werbung, Rückkopplung
    def rcp(cmd):
        return act('send', rmcr, {'id_send': opt(cmd), 'id_end': opt('\n')})
    put(1, 1, 6, button('Ton aus', [rcp('set RM:NeOut_Fader/Ch/On 0 0 0'), setvar('r5_spk_mute', '1'), touch()]))
    put(1, 1, 7, button('Ton an', [rcp('set RM:NeOut_Fader/Ch/On 0 0 1'), setvar('r5_spk_mute', '0'), touch()]))
    extend(1, 0, 1, rcp('set RM:NeOut_Fader/Ch/On 0 0 1'), setvar('r5_spk_mute', '0'))   # Raum an: Ton immer an
    extend(1, 3, 6, setvar('r5_spk_mute', '0'))                                           # Ton zurücksetzen schaltet On=1

    # Präsentation ausblenden: in OBS die Szene „Präsentation pausiert“ (Logo + Text) über den Präsentations-Rahmen legen.
    # Teams sieht dann die Pause-Fläche statt des Bildschirms, die Kameras bleiben. (Später zusätzlich: Matrix/Displays.)
    def blank(visible):
        return [obs_act('toggle_scene_item', {'scene': opt(sc), 'all': opt(False), 'source': opt('Präsentation pausiert'),
                                              'visible': opt(visible)}) for sc in ('Alles im Blick', 'Folien Groß')]
    put(1, 2, 4, button('Präsentation aus', [setvar('r5_blank', '1'), *blank('true'), touch()]))
    put(1, 2, 5, button('Präsentation an', [setvar('r5_blank', '0'), *blank('false'), touch()]))
    # Raum aus setzt r5_blank = 0 -> auch in OBS die Pause-Fläche wegnehmen, sonst sähe Teams sie beim nächsten Start
    off = d['pages']['1']['controls']['0']['2']['steps']['0']['action_sets']['down']
    if not any(a['definitionId'] == 'toggle_scene_item' for a in off):
        off.extend(blank('false'))
    put(1, 2, 6, button('Displays an', [setvar('r5_disp', '1'), touch()]))  # später: ViewSonic per LAN
    put(1, 2, 7, button('Displays aus', [setvar('r5_disp', '0'), touch()]))
    extend(1, 3, 1, touch())
    put(1, 3, 3, button('Tracking an', [setvar('r5_track', '1'), touch()]))
    put(1, 3, 4, button('Tracking aus', [setvar('r5_track', '0'), touch()]))
    vc = {'output': opt('virtualcam_output')}
    put(1, 3, 5, button('Kamera neu starten', [sequence(
        obs_act('stop_output', copy.deepcopy(vc)), wait(2000), obs_act('start_output', copy.deepcopy(vc))), touch()]))
    extend(1, 3, 6, touch())
    put(1, 3, 7, button('Displays neu starten', [setvar('r5_disp', '1'), touch()]))
    put(1, 3, 8, button('Noch in Benutzung', [touch()]))                   # Tablet: „Weiter nutzen“ / Bedienung
    # Teams-Bild per Bildschirm teilen: OBS-Programm als Vollbild-Projektor auf den (virtuellen) Teilen-Bildschirm.
    # teams-steuerung.ps1 setzt r5_proj_mon und drückt diesen Button, wenn der Projektor fehlt.
    put(1, 3, 9, button('OBS Projektor', [obs_act('custom_command', {
        'command': opt('OpenVideoMixProjector'),
        'arg': opt('{"videoMixType": "OBS_WEBSOCKET_VIDEO_MIX_TYPE_PROGRAM", "monitorIndex": $(custom:r5_proj_mon)}')})]))

    # ---------- Teams: Befehle an teams-steuerung.ps1 (UI Automation, keine Teams-API nötig) ----------
    # Das Skript liest r5_tcmd, drückt den Button im Teams-Meetingfenster und leert r5_tcmd wieder.
    for col, (label, cmd) in enumerate([('Teams Mikro', 'mute'), ('Teams Bild', 'video'), ('Teams verlassen', 'leave'),
                                        ('Teams beitreten', 'join')], start=4):
        put(1, 0, col, button(label, [setvar('r5_tcmd', cmd), touch()]))
    # Raum aus verlässt auch das Teams-Meeting (auch beim Auto-Aus-Trigger, der 1/0/2 drückt)
    extend(1, 0, 2, setvar('r5_tcmd', 'leave'))

    # ---------- Seite 3: Kamera (alte Belegung ab Spalte 0 ersetzen) ----------
    d['pages']['3']['controls'] = {}
    d['pages']['3']['name'] = 'R5 Kamera'
    for col, (p, label) in enumerate([('r_pult', 'Redner Sprecherplatz'), ('r_displays', 'Redner Displays'), ('r_front', 'Redner Front')], start=1):
        put(3, 0, col, button(label, [setvar('r5_rpreset', p), touch()]))   # später: PTZ-Preset abrufen
    for col, (p, label) in enumerate([('p_vl', 'Reihe 1-2 links'), ('p_vr', 'Reihe 1-2 rechts'), ('p_hl', 'Reihe 3-5 links'),
                                      ('p_hr', 'Reihe 3-5 rechts'), ('p_all', 'Ganzer Raum')], start=1):
        put(3, 1, col, button(label, [setvar('r5_ppreset', p)]))           # kein touch: drückt auch die Automatik
    put(3, 1, 6, button('Publikum Auto an', [setvar('r5_pauto', '1'), touch()]))
    put(3, 1, 7, button('Publikum Auto aus', [setvar('r5_pauto', '0'), touch()]))
    for row, cam in ((2, 'Redner'), (3, 'Publikum')):
        for col, move in enumerate(['hoch', 'runter', 'links', 'rechts', 'naeher', 'weiter'], start=1):
            put(3, row, col, button(f'{cam} {move}', [touch()], []))       # später: PTZ fahren (down) / stoppen (up)
        put(3, row, 7, button(f'{cam} Standard', [touch()]))

    # ---------- Trigger ----------
    for t in d['triggers'].values():
        name = t['options']['name']
        if name.startswith('Raum 5: Auto-Aus'):
            # Sicherheitsnetz für die Nacht, falls das Tablet ausfällt: zwischen 23 und 5 Uhr Raum aus (echter
            # Raum-aus-Button), aber nur ohne Teams-Meeting und wenn 2 h niemand am Tablet war. Das Tablet fragt
            # selbst ab 20 Uhr stündlich; „Weiter nutzen“ meldet sich über 1/3/8 (setzt r5_last_use).
            t['options']['name'] = 'Raum 5: Auto-Aus nachts (Sicherheitsnetz)'
            t['actions'] = [press('1/0/2')]
            for c in t['condition']:
                if c['definitionId'] == 'check_expression':
                    c['options']['expression'] = opt('$(custom:r5_room) == 1 && $(custom:r5_t_in) != 1'
                                                     ' && ($(internal:time_h) >= 23 || $(internal:time_h) < 5)'
                                                     ' && ($(internal:time_unix) - $(custom:r5_last_use)) > 7200', True)

    with gzip.open(dst, 'wt', encoding='utf-8', compresslevel=9) as f:
        json.dump(d, f, ensure_ascii=False, indent='\t')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
