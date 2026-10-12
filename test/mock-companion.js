// Mini-Companion zum Testen der Tablet-Seite ohne Raum-PC.
// Start: node test/mock-companion.js  -> Seite: http://127.0.0.1:8080/  Companion-API: http://127.0.0.1:8000
// Liefert die Variablen wie Companion 5 (HTTP-API) und protokolliert jeden Button-Druck.
const http = require('http'), fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', 'Raumsteuerung');
const vars = { 'obs:scene_active': 'Alles im Blick', r5_vol_db: '-1300', r5_live: '1', r5_pauto: '1', r5_pmic: '0', r5_room: '0' };
const log = [];
let down = false; // true = Companion "abgestürzt"
const SCENES = { '1/1/1': 'Alles im Blick', '1/1/2': 'Folien Groß', '1/1/3': 'Diskussion', '1/1/4': 'Nur Redner', '1/1/5': 'Pausenbild' };
function cors(res) { res.setHeader('Access-Control-Allow-Origin', '*'); }
http.createServer((req, res) => {
  cors(res);
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/_test/state') { res.end(JSON.stringify({ vars, log })); return; }
  if (u.pathname === '/_test/set') { for (const [k, v] of u.searchParams) { if (k === 'down') down = v === '1'; else vars[k] = v; } res.end('ok'); return; }
  if (u.pathname === '/_test/clear') { log.length = 0; res.end('ok'); return; }
  if (down) { req.socket.destroy(); return; }
  let m;
  if (req.method === 'POST' && (m = /^\/api\/location\/(\d+\/\d+\/\d+)\/(press|down|up)$/.exec(u.pathname))) {
    log.push(m[1] + ' ' + m[2]);
    if (m[2] !== 'up' && SCENES[m[1]]) vars['obs:scene_active'] = SCENES[m[1]];
    if (m[1] === '1/0/1') { vars.r5_live = '1'; vars['obs:scene_active'] = 'Alles im Blick'; }
    if (m[1] === '1/0/2') { vars.r5_live = '0'; vars['obs:scene_active'] = 'Pausenbild'; }
    if (m[1] === '3/1/6') vars.r5_pauto = '1';
    if (m[1] === '3/1/7') vars.r5_pauto = '0';
    res.end('ok'); return;
  }
  if ((m = /^\/api\/custom-variable\/([\w]+)\/value$/.exec(u.pathname))) {
    if (req.method === 'POST') { vars[m[1]] = u.searchParams.get('value'); log.push('set ' + m[1] + '=' + vars[m[1]]); res.end('ok'); return; }
    if (!(m[1] in vars)) { res.statusCode = 404; res.end('Not found'); return; }
    res.end(vars[m[1]]); return;
  }
  if ((m = /^\/api\/variable\/([\w]+)\/([\w]+)\/value$/.exec(u.pathname))) {
    const k = m[1] + ':' + m[2];
    if (!(k in vars)) { res.statusCode = 404; res.end('Not found'); return; }
    res.end(vars[k]); return;
  }
  res.statusCode = 404; res.end('Not found');
}).listen(8000, '127.0.0.1');
const types = { '.html': 'text/html; charset=utf-8', '.json': 'application/manifest+json', '.png': 'image/png' };
http.createServer((req, res) => {
  let name = path.basename(decodeURIComponent(new URL(req.url, 'http://x').pathname)) || 'raumsteuerung.html';
  const f = path.join(root, name), ext = path.extname(name);
  if (!types[ext] || !fs.existsSync(f)) { res.statusCode = 404; res.end('Nicht gefunden'); return; }
  res.setHeader('Content-Type', types[ext]); res.end(fs.readFileSync(f));
}).listen(8080, '127.0.0.1');
console.log('Mock: Seite http://127.0.0.1:8080/  Companion http://127.0.0.1:8000');
