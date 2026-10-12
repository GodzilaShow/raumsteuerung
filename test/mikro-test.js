// Szenario-Test der Mikrofon-Automatik (mikro-automatik.ps1) gegen Mock-Companion und Mock-RM-CR.
// Vorher: node test/mock-companion.js & node test/mock-rmcr.js &     Aufruf: PWSH=/pfad/pwsh node test/mikro-test.js
const { spawn } = require('child_process'), fs = require('fs'), os = require('os'), path = require('path');
const API = 'http://127.0.0.1:8000', RM = 'http://127.0.0.1:8001';
let ok = 0, bad = 0;
const check = (c, m) => { c ? ok++ : bad++; console.log((c ? '  ✔ ' : '  ✘ ') + m); };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const state = async () => (await fetch(API + '/_test/state')).json();
const presses = async () => (await state()).log.filter(x => /press$/.test(x)).map(x => x.split(' ')[0]);
const lvl = q => fetch(RM + '/set?' + q);
const clear = () => fetch(API + '/_test/clear');
(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mikro-'));
  const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'Raumsteuerung', 'mikro-automatik.json'), 'utf8').replace(/^﻿/, ''));
  Object.assign(cfg, { rmcrIp: '127.0.0.1', mikrofone: { 1: [1], 2: [2], 3: [3], 4: [4], 5: [5, 6] }, freezeAn: '3/1/8', freezeAus: '3/1/9' });
  fs.writeFileSync(path.join(dir, 'cfg.json'), JSON.stringify(cfg));
  await lvl('1=61&2=61&3=61&4=61&5=61&6=61');
  await fetch(API + '/_test/set?r5_pauto=1&r5_pmic=0&down=0'); await clear();
  const ps = spawn(process.env.PWSH || 'pwsh', ['-NoProfile', '-File', path.join(__dirname, '..', 'Raumsteuerung', 'mikro-automatik.ps1'), '-Config', path.join(dir, 'cfg.json'), '-Log', path.join(dir, 'log.txt')]);
  let out = ''; ps.stdout.on('data', d => out += d); ps.stderr.on('data', d => out += d);

  console.log('Sofort nach dem Start');
  await lvl('2=76');
  let t0 = Date.now(); while (Date.now() - t0 < 6000 && (await state()).vars.r5_pmic !== '2') await sleep(100);
  check((await state()).vars.r5_pmic === '2', 'Pegel kommen gleich nach dem Start an (' + (Date.now() - t0) + ' ms inkl. Start von PowerShell)');
  await sleep(500); await clear(); await lvl('2=61');
  console.log('Mikrofon 2 verstummt');
  await sleep(6000);
  let p = await presses();
  check(p.includes('3/1/5'), 'nach Haltezeit + 3 s Stille: Ganzer Raum (3/1/5)');
  check(p.indexOf('3/1/8') >= 0 && p.indexOf('3/1/8') < p.indexOf('3/1/5'), 'vor dem Schwenk Bild einfrieren (3/1/8)');
  await sleep(1500);
  check((await presses()).includes('3/1/9'), 'nach dem Schwenk Bild wieder live (3/1/9)');

  console.log('Kurzes Geräusch an Mikrofon 3 (200 ms)');
  await clear(); await lvl('3=78'); await sleep(200); await lvl('3=61'); await sleep(1500);
  check(!(await presses()).includes('3/1/3'), 'kein Schwenk bei Husten/Klopfen');

  console.log('Mikrofon 1 spricht');
  await clear(); await lvl('1=75'); await sleep(1500);
  let st = await state();
  check(st.vars.r5_pmic === '1', 'r5_pmic = 1');
  check(st.log.includes('3/1/1 press'), 'Kamera auf Reihe 1–2 links (3/1/1)');

  console.log('Mikrofon 2 kommt dazu');
  await clear(); await lvl('2=74'); await sleep(1000);
  st = await state();
  check(st.vars.r5_pmic === '0', 'zwei gleichzeitig -> r5_pmic = 0');
  check(!st.log.includes('3/1/5 press'), 'aber noch kein Schwenk (höchstens 1 Bewegung / 4 s)');
  await sleep(3500);
  check((await presses()).includes('3/1/5'), 'nach Ablauf der Sperre: Ganzer Raum');

  console.log('Pause im Satz');
  await lvl('2=61'); await sleep(5000); await clear();
  await lvl('1=61'); await sleep(1500); await lvl('1=75'); await sleep(800);
  check(!(await presses()).includes('3/1/5'), 'kurze Sprechpause (< 3 s) bewegt nichts');

  console.log('Stille');
  await clear(); await lvl('1=61'); await sleep(5000);
  st = await state();
  check(st.log.includes('3/1/5 press') && st.vars.r5_pmic === '0', 'nach 3 s Stille wieder Ganzer Raum');

  console.log('Automatik aus (Tablet)');
  await clear(); await fetch(API + '/_test/set?r5_pauto=0'); await sleep(1500);
  await lvl('4=76'); await sleep(2000);
  st = await state();
  check(st.vars.r5_pmic === '4', 'Anzeige r5_pmic = 4 läuft weiter');
  check(!(await presses()).includes('3/1/4'), 'aber keine Kamerabewegung');
  await fetch(API + '/_test/set?r5_pauto=1'); await sleep(2000);
  check((await presses()).includes('3/1/4'), 'Automatik wieder an -> sofort Reihe 3–5 rechts (3/1/4)');

  console.log('Mikrofon 5 (zwei Kanäle, gleiche Zone wie 3)');
  await lvl('4=61'); await sleep(9000); await clear();   // Stille -> Ganzer Raum, dann 4 s Sperre abwarten
  await lvl('6=77'); await sleep(1500);
  st = await state();
  check(st.vars.r5_pmic === '5' && st.log.includes('3/1/3 press'), 'Kanal 6 gehört zu Mikrofon 5 -> 3/1/3');
  await sleep(4000); await clear(); await lvl('6=61&3=77'); await sleep(2500);
  check(!(await state()).log.includes('set r5_pmic=0'), 'Wortwechsel 5 -> 3: kein kurzes „mehrere“ dazwischen');
  st = await state();
  check(st.vars.r5_pmic === '3' && !st.log.includes('3/1/3 press'), 'Wechsel 5 -> 3 in derselben Zone: kein unnötiger Schwenk');

  console.log('Meter läuft länger als 10 s (Erneuerung)');
  check(/Verbunden/.test(out) && !/Keine Meter-Daten/.test(out), 'keine Unterbrechung der Pegel (' + Math.round(process.uptime()) + ' s Laufzeit)');
  check(!/Fehler/.test(out), 'keine Fehler im Protokoll');
  ps.kill();
  console.log('\n--- Protokoll ---\n' + out.split('\n').slice(-12).join('\n'));
  console.log(`\n${ok} bestanden, ${bad} fehlgeschlagen`);
  process.exit(bad ? 1 : 0);
})();
