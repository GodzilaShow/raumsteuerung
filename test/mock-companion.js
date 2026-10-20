// Mini-Companion zum Testen der Tablet-Seite ohne Raum-PC.
// Start: node test/mock-companion.js  -> Seite: http://127.0.0.1:8080/  Companion-API: http://127.0.0.1:8000
// Liefert die Variablen wie Companion 5 (HTTP-API) und protokolliert jeden Button-Druck.
// Mit  --config Raum5_Companion.companionconfig  werden die Buttons aus der echten Konfiguration ausgeführt
// (Variablen setzen, OBS-Szene, Virtual Cam, Warten, Gruppen, Button drücken) – so wird der Export mitgetestet.
// Ports per Umgebung aenderbar (z. B. wenn echter Companion/Webserver auf 8000/8080 laufen)
const API_PORT = +process.env.API_PORT || 8000, PAGE_PORT = +process.env.PAGE_PORT || 8080;
const http = require('http'), fs = require('fs'), path = require('path'), zlib = require('zlib');
const ci = process.argv.indexOf('--config');
const CC = ci > 0 ? JSON.parse(zlib.gunzipSync(fs.readFileSync(process.argv[ci + 1])).toString('utf8')) : null;
const root = path.join(__dirname, '..', 'Raumsteuerung');
const vars = { 'obs:scene_active': 'Alles im Blick', r5_vol_db: '-1300', r5_live: '1', r5_pauto: '1', r5_pmic: '0', r5_room: '0' };
const log = [];
if (CC) {
  for (const [k, v] of Object.entries(CC.custom_variables)) vars[k] = String(v.defaultValue);
  Object.assign(vars, { 'obs:scene_active': 'Pausenbild', r5_live: '0' });
}
const conn = id => (CC && CC.instances[id] && CC.instances[id].label) || id;
const sub = t => String(t).replace(/\$\((custom|obs|internal):(\w+)\)/g, (m, a, b) =>
  a === 'internal' && b === 'time_unix' ? String(Math.floor(Date.now() / 1000)) : (vars[a === 'custom' ? b : a + ':' + b] ?? ''));
function control(loc) { const [p, r, c] = loc.split('/'); return CC.pages[p]?.controls?.[r]?.[c] || null; }
async function runActions(list) {
  for (const a of list || []) {
    const o = a.options || {}, v = k => o[k] && o[k].value;
    switch (a.definitionId) {
      case 'custom_variable_set_value': {
        let val = v('value');
        if (o.value.isExpression) { if (/^\$\(internal:time_unix\)$/.test(val)) val = sub(val); else { log.push('expr? ' + val); break; } }
        else val = sub(val);
        if (v('name') in vars) vars[v('name')] = String(val); else log.push('FEHLT Variable ' + v('name'));
        break;
      }
      case 'set_scene': vars['obs:scene_active'] = v('scene'); break;
      case 'start_output': if (v('output') === 'virtualcam_output') vars.r5_live = '1'; break;   // wie Trigger „Live-Status“
      case 'stop_output': if (v('output') === 'virtualcam_output') vars.r5_live = '0'; break;
      case 'wait': await new Promise(r => setTimeout(r, Math.min(+v('time') || 0, 3000))); break;
      case 'action_group': await runActions(a.children && a.children.default); break;
      case 'button_pressrelease': await pressLoc(v('location')); break;
      case 'send': log.push(conn(a.connectionId) + ': ' + sub(v('id_send'))); break;
      default: log.push('Aktion ' + conn(a.connectionId) + ':' + a.definitionId);
    }
  }
}
async function pressLoc(loc, kind = 'press') {
  const c = control(loc); if (!c) return false;
  const st = c.steps['0'].action_sets;
  if (kind !== 'up') await runActions(st.down);
  if (kind !== 'down') await runActions(st.up);
  return true;
}
let down = false; // true = Companion "abgestürzt"
// Störungen für den Chaos-Test (test/chaos.js), alle per /_test/set:
//   hang=1      Verbindung annehmen, nie antworten (Companion hängt / WLAN weg ohne Verbindungsabbruch)
//   slow=ms     jede API-Antwort so viel später
//   flaky=0.3   Anteil der Anfragen, deren Verbindung abbricht
//   lagdown=ms  Kamera-„down“ kommt so viel später an (Netz überholt: „up“ vor „down“)
//   dropup=n    die nächsten n Kamera-„up“ gehen verloren
const fault = { hang: false, slow: 0, flaky: 0, lagdown: 0, dropup: 0 };
const SCENES = { '1/1/1': 'Alles im Blick', '1/1/2': 'Folien Groß', '1/1/3': 'Diskussion', '1/1/4': 'Nur Redner', '1/1/5': 'Pausenbild' };
function cors(res) { res.setHeader('Access-Control-Allow-Origin', '*'); }
http.createServer((req, res) => {
  cors(res);
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/_test/state') { res.end(JSON.stringify({ vars, log })); return; }
  if (u.pathname === '/_test/set') {
    for (const [k, v] of u.searchParams) {
      if (k === 'down') down = v === '1'; else if (k === 'hang') fault.hang = v === '1'; else if (k in fault) fault[k] = +v || 0; else vars[k] = v;
    }
    res.end('ok'); return;
  }
  if (u.pathname === '/_test/clear') { log.length = 0; res.end('ok'); return; }
  if (down) { req.socket.destroy(); return; }
  if (fault.hang) return;                                    // nie antworten
  if (fault.flaky && Math.random() < fault.flaky) { req.socket.destroy(); return; }
  const cm = /^\/api\/location\/(3\/[23]\/\d+)\/(down|up)$/.exec(u.pathname);
  if (cm && cm[2] === 'up' && fault.dropup > 0) { fault.dropup--; req.socket.destroy(); return; }
  const lag = fault.slow + (cm && cm[2] === 'down' ? fault.lagdown : 0);
  if (lag) { setTimeout(() => api(req, res, u), lag); return; }
  api(req, res, u);
}).listen(API_PORT, '127.0.0.1');
function api(req, res, u) {
  let m;
  if (req.method === 'POST' && (m = /^\/api\/location\/(\d+\/\d+\/\d+)\/(press|down|up)$/.exec(u.pathname))) {
    log.push(m[1] + ' ' + m[2]);
    if (CC) {
      if (!control(m[1])) { log.push('FEHLT Button ' + m[1]); res.statusCode = 204; res.end(); return; }
      pressLoc(m[1], m[2]).then(() => res.end('ok')); return;
    }
    if (m[2] !== 'up' && SCENES[m[1]]) vars['obs:scene_active'] = SCENES[m[1]];
    if (m[1] === '1/0/1') { vars.r5_live = '1'; vars['obs:scene_active'] = 'Alles im Blick'; }
    if (m[1] === '1/0/2') { vars.r5_live = '0'; vars['obs:scene_active'] = 'Pausenbild'; }
    if (m[1] === '3/1/6') vars.r5_pauto = '1';
    if (m[1] === '3/1/7') vars.r5_pauto = '0';
    res.end('ok'); return;
  }
  if ((m = /^\/api\/custom-variable\/([\w]+)\/value$/.exec(u.pathname))) {
    if (req.method === 'POST') {
      if (CC && !(m[1] in vars)) { log.push('FEHLT Variable ' + m[1]); res.statusCode = 404; res.end('Not found'); return; }
      vars[m[1]] = u.searchParams.get('value'); log.push('set ' + m[1] + '=' + vars[m[1]]); res.end('ok'); return;
    }
    if (!(m[1] in vars)) { res.statusCode = 404; res.end('Not found'); return; }
    res.end(vars[m[1]]); return;
  }
  if ((m = /^\/api\/variable\/([\w]+)\/([\w]+)\/value$/.exec(u.pathname))) {
    const k = m[1] + ':' + m[2];
    if (!(k in vars)) { res.statusCode = 404; res.end('Not found'); return; }
    res.end(vars[k]); return;
  }
  res.statusCode = 404; res.end('Not found');
}
const types = { '.html': 'text/html; charset=utf-8', '.json': 'application/manifest+json', '.png': 'image/png' };
http.createServer((req, res) => {
  let name = path.basename(decodeURIComponent(new URL(req.url, 'http://x').pathname)) || 'raumsteuerung.html';
  const f = path.join(root, name), ext = path.extname(name);
  if (!types[ext] || !fs.existsSync(f)) { res.statusCode = 404; res.end('Nicht gefunden'); return; }
  res.setHeader('Content-Type', types[ext]); res.end(fs.readFileSync(f));
}).listen(PAGE_PORT, '127.0.0.1');
console.log(CC ? 'Konfiguration geladen: ' + Object.keys(CC.pages).length + ' Seiten' : 'ohne Konfiguration');
console.log('Mock: Seite http://127.0.0.1:' + PAGE_PORT + '/  Companion http://127.0.0.1:' + API_PORT);
