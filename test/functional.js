// Funktionstest der Tablet-Seite gegen den Mock (node test/mock-companion.js muss laufen).
// Aufruf: NODE_PATH=$(npm root -g) node test/functional.js
const { chromium } = require('playwright');
const API = 'http://127.0.0.1:8000';
let ok = 0, bad = 0;
const check = (cond, msg) => { if (cond) { ok++; console.log('  ✔ ' + msg); } else { bad++; console.log('  ✘ ' + msg); } };
const state = async () => (await fetch(API + '/_test/state')).json();
const set = (q) => fetch(API + '/_test/set?' + q);
const clear = () => fetch(API + '/_test/clear');
(async () => {
  await set('obs:scene_active=Alles im Blick&r5_vol_db=-1300&r5_live=1&r5_pauto=1&r5_pmic=0&r5_room=0&down=0');
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', e => errs.push(e.message));
  p.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|ERR_CONNECTION|ERR_EMPTY/.test(m.text())) errs.push(m.text()); });
  await p.goto('http://127.0.0.1:8080/');
  await p.evaluate(() => localStorage.clear()); await p.reload(); await p.waitForTimeout(500);

  console.log('Start');
  await clear(); await p.click('[data-act=start]'); await p.waitForTimeout(300);
  check((await state()).log.includes('1/0/1 press'), 'Raum starten drückt 1/0/1');
  check(await p.isVisible('#s-main'), 'Steuerung wird angezeigt');
  check(!(await p.isVisible('#conn')), 'kein Fehlerbanner');

  console.log('Szenen');
  await clear(); await p.click('[data-scene=folien]'); await p.waitForTimeout(300);
  check((await state()).log.includes('1/1/2 press'), 'Folien groß drückt 1/1/2');
  await set('obs:scene_active=Nur Redner'); await p.waitForTimeout(8000);
  check(await p.$eval('[data-scene=redner]', e => e.classList.contains('on')), 'Szenenwechsel direkt in OBS erscheint auf dem Tablet');

  console.log('Lautstärke');
  await clear();
  for (let i = 0; i < 4; i++) await p.click('[data-act=volUp]');
  await p.waitForTimeout(800);
  let st = await state();
  check(st.vars.r5_vol_db === '0', 'viermal Lauter von 60 % -> 100 % = 0 dB (ist ' + st.vars.r5_vol_db + ')');
  check(st.log.filter(x => / press$/.test(x)).pop() === '1/3/1 press', 'zuletzt wird der Pegel angewendet');
  if (st.log.some(x => x.startsWith('rmcr:'))) check(st.log.includes('rmcr: set RM:NeOut_Fader/Ch/Level 0 0 0'), 'RM-CR bekommt „set RM:NeOut_Fader/Ch/Level 0 0 0“');
  check(await p.$eval('[data-act=volUp]', e => e.disabled), '„Lauter“ bei 100 % gesperrt');
  check(await p.textContent('#volNum') === '100', 'Anzeige 100');
  await clear(); await p.click('#bars button:nth-child(3)'); await p.waitForTimeout(500);
  st = await state(); check(st.vars.r5_vol_db === '-2600', 'Balken 30 % setzt -2600 (ist ' + st.vars.r5_vol_db + ', ' + st.log.join(',') + ')');

  console.log('Quelle / Displays');
  check(!(await p.textContent('#srcHint')).includes('[CODE]'), 'kein Platzhalter [CODE] im Hinweis');
  await p.click('[data-src=cast]');
  check(!(await p.textContent('#srcHint')).includes('[CODE]'), 'Hinweis „Kabellos“ ohne [CODE]');
  await p.click('#dispBtn');
  check(await p.$eval('#blankBtn', e => e.disabled), '„Präsentation ausblenden“ gesperrt, wenn Displays aus');
  await p.click('#dispBtn');

  console.log('Kamera');
  await p.click('#tabs [data-go=kamera]'); await p.waitForTimeout(400);
  await clear(); await p.click('[data-cam=r]');
  const up = p.locator('[data-move=up]');
  const box = await up.boundingBox();
  await p.mouse.move(box.x + 20, box.y + 20); await p.mouse.down(); await p.waitForTimeout(200);
  st = await state(); check(st.log.includes('3/2/1 down'), 'Pfeil hoch halten -> 3/2/1 down');
  await p.evaluate(() => window.dispatchEvent(new Event('blur'))); await p.waitForTimeout(200);
  st = await state(); check(st.log.includes('3/2/1 up'), 'Fenster verliert Fokus -> Kamera stoppt (3/2/1 up)');
  await p.mouse.up(); await p.waitForTimeout(200);
  st = await state(); check(st.log.filter(x => x === '3/2/1 up').length === 1, 'kein doppeltes „up“');
  await clear(); await p.click('[data-cam=p]');
  check(await p.$eval('#pAutoBtn', e => e.classList.contains('on')), 'Publikum-Automatik ist an');
  await p.locator('[data-move=left]').dispatchEvent('pointerdown'); await p.locator('[data-move=left]').dispatchEvent('pointerup');
  await p.waitForTimeout(300); st = await state();
  check(st.log.includes('3/1/7 press') && st.log.includes('3/3/3 down') && st.log.includes('3/3/3 up'), 'Publikum von Hand bewegen schaltet Automatik aus');
  check(!(await p.$eval('#pAutoBtn', e => e.classList.contains('on'))), 'Schalter „Automatisch“ zeigt aus');
  await clear(); await p.click('#pAutoBtn'); await p.waitForTimeout(200);
  check((await state()).log.includes('3/1/6 press'), 'Automatik wieder an -> 3/1/6');
  await set('r5_pmic=4'); await p.waitForTimeout(3500);
  check(await p.$eval('[data-mic="4"]', e => e.classList.contains('talk')), 'Mikrofon 4 leuchtet');
  check(await p.$eval('.pz[data-preset=p_hr]', e => e.classList.contains('auto')), 'Zone Reihe 3–5 rechts markiert');
  await clear(); await p.click('.pz[data-preset=p_vl]'); await p.waitForTimeout(200);
  st = await state(); check(st.log.includes('3/1/7 press') && st.log.includes('3/1/1 press'), 'Zone antippen: Automatik aus + Preset 3/1/1');
  const home = '#homeBtn', homeTxt = await p.textContent(home);
  await p.click(home); await p.click(home); await p.waitForTimeout(2800);
  check(await p.textContent(home) === homeTxt, '„Zurück auf Standard“ zweimal tippen -> Text kommt zurück');

  console.log('Hilfe');
  await p.click('#tabs [data-go=hilfe]'); await p.waitForTimeout(300);
  const fx = p.locator('[data-fix=fix_ton]'); const fxTxt = await fx.textContent();
  await clear(); await fx.click(); await fx.click(); await p.waitForTimeout(4300);
  check(await fx.textContent() === fxTxt, 'Hilfe-Knopf zweimal tippen -> Text kommt zurück');
  check((await state()).log.filter(x => x === '1/3/6 press').length === 1, 'Ton zurücksetzen nur einmal gesendet');
  await p.click('.fix [data-go=kamera]'); await p.waitForTimeout(300);
  check(await p.isVisible('#s-kamera'), '„Zur Kamera“ öffnet die Kamera-Seite');

  console.log('Verbindung');
  await set('down=1'); await p.waitForTimeout(9000);
  check(await p.isVisible('#conn'), 'Companion weg -> Hinweis erscheint');
  await p.click('#tabs [data-go=main]'); await p.waitForTimeout(300);
  check((await p.textContent('#liveTxt')) === 'Status unbekannt', 'Live-Kachel zeigt „Status unbekannt“ (nicht mehr „Live“)');
  await set('down=0'); await p.waitForTimeout(4000);
  check(!(await p.isVisible('#conn')), 'Companion zurück -> Hinweis verschwindet');

  console.log('Raum-Status von außen');
  await set('r5_room=1'); await p.waitForTimeout(3500);
  await set('r5_room=0'); await p.waitForTimeout(3500);
  check(await p.isVisible('#s-start'), 'r5_room 1 -> 0 (Stream Deck / Auto-Aus) -> Startbildschirm');
  await set('r5_room=1'); await p.waitForTimeout(3500);
  check(await p.isVisible('#s-main'), 'r5_room 0 -> 1 -> Steuerung');

  console.log('Ausschalten');
  await clear(); await p.click('[data-act=askOff]'); await p.waitForTimeout(400);
  check(await p.isVisible('#dlgOff'), 'Abfrage erscheint');
  await p.click('#dlgOff [data-act=off]'); await p.waitForTimeout(300);
  check((await state()).log.includes('1/0/2 press') && await p.isVisible('#s-start'), 'Ja, ausschalten -> 1/0/2 und Startbildschirm');

  console.log('Auto-Aus');
  await p.click('[data-act=start]');
  await p.evaluate(() => { CONFIG.idleMinutes = 0.001; CONFIG.idleCountdown = 2; lastUse = 0; });
  await p.waitForTimeout(16000);
  check(await p.isVisible('#dlgIdle') || await p.isVisible('#s-start'), 'Nach Inaktivität erscheint die Abfrage');
  await p.waitForTimeout(3000);
  check(await p.isVisible('#s-start'), 'Countdown abgelaufen -> Raum aus, Startbildschirm');
  await clear(); await p.click('[data-act=start]'); await p.evaluate(() => { CONFIG.idleMinutes = 0.001; CONFIG.idleCountdown = 30; lastUse = 0; });
  await p.waitForTimeout(16000); await p.click('#dlgIdle [data-act=keepOn]'); await p.waitForTimeout(300);
  check((await state()).log.includes('1/3/8 press') && !(await p.isVisible('#dlgIdle')), '„Weiter nutzen“ meldet Companion die Nutzung (1/3/8)');

  check(errs.length === 0, 'keine JavaScript-Fehler ' + (errs.length ? JSON.stringify(errs) : ''));
  await b.close();
  console.log(`\n${ok} bestanden, ${bad} fehlgeschlagen`);
  process.exit(bad ? 1 : 0);
})();
