// Mini-RM-CR: RCP auf TCP 49280, liefert Meter-Pegel. Steuerung: http://127.0.0.1:8001/set?1=78&2=61  (Kanal=Hex)
// Start: node test/mock-rmcr.js [rcpPort] [httpPort]
const net = require('net'), http = require('http');
const rcpPort = +process.argv[2] || 49280, httpPort = +process.argv[3] || 8001;
const lv = new Array(16).fill(0x61);
const meters = new Map();   // socket -> {id, iv, until}
net.createServer(sock => {
  let buf = '';
  sock.on('data', d => {
    buf += d; let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      const m = /^mtrstart (\S+) (\d+)$/.exec(line);
      if (!m) { sock.write('ERROR unknown command\n'); continue; }
      const old = meters.get(sock); if (old) clearInterval(old.iv);
      const st = { until: Date.now() + 10000 };
      st.iv = setInterval(() => {
        if (Date.now() > st.until) return;   // wie das Gerät: ohne Erneuern nach 10 s Schluss
        sock.write(`NOTIFY mtr ${m[1]} level ${lv.map(v => v.toString(16).toUpperCase().padStart(2, '0')).join(' ')}\n`);
      }, +m[2]);
      meters.set(sock, st);
      sock.write(`OK mtrstart ${m[1]} ${m[2]}\n`);
    }
  });
  const end = () => { const s = meters.get(sock); if (s) clearInterval(s.iv); meters.delete(sock); };
  sock.on('close', end); sock.on('error', end);
}).listen(rcpPort, '127.0.0.1');
http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  for (const [k, v] of u.searchParams) lv[+k - 1] = parseInt(v, 16);
  res.end(lv.map(v => v.toString(16)).join(' '));
}).listen(httpPort, '127.0.0.1');
console.log('Mock RM-CR: RCP ' + rcpPort + ', Steuerung http://127.0.0.1:' + httpPort + '/set?1=78');
