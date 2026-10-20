// Chaos-Test der Tablet-Seite: Störungen (Companion hängt, langsam, Verbindungsabbrüche, Kamera-Befehle
// überholen sich / gehen verloren) und Hunderte zufällige Tipps. Danach muss sich alles wieder fangen.
// Mock wie bei functional.js (node test/mock-companion.js --config …). Aufruf: NODE_PATH=$(npm root -g) node test/chaos.js [Seed]
const { chromium } = require('playwright');
const API = 'http://127.0.0.1:' + (process.env.API_PORT || 8000);
const PAGE = 'http://127.0.0.1:' + (process.env.PAGE_PORT || 8080) + '/?companion=' + encodeURIComponent(API);
const SEED = +process.argv[2] || 20261020, STEPS = +process.env.CHAOS_STEPS || 500;
let ok = 0, bad = 0;
const check = (cond, msg) => { if (cond) { ok++; console.log('  ✔ ' + msg); } else { bad++; console.log('  ✘ ' + msg); } };
const state = async () => (await fetch(API + '/_test/state')).json();
const set = (q) => fetch(API + '/_test/set?' + q);
const clear = () => fetch(API + '/_test/clear');
const NOFAULT = 'down=0&hang=0&slow=0&flaky=0&lagdown=0&dropup=0';
let seed = SEED; const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
const pick = a => a[Math.floor(rnd() * a.length)];
// Kamera: für jeden Bewegungs-Button muss das letzte angekommene Ereignis „up“ sein (sonst fährt sie weiter)
const camStuck = log => {
  const last = {};
  for (const x of log) { const m = /^(3\/[23]\/\d) (down|up)$/.exec(x); if (m) last[m[1]] = m[2]; }
  return Object.keys(last).filter(k => last[k] === 'down');
};

(async () => {
  await set(NOFAULT + '&obs:scene_active=Nur Redner&r5_vol_db=-1300&r5_live=1&r5_pauto=1&r5_pmic=0&r5_room=0&r5_t_in=0&r5_t_mode=kamera&r5_t_share=0&r5_t_status=');
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' }).catch(() => chromium.launch());
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', e => errs.push(e.message));
  p.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|ERR_|net::/.test(m.text())) errs.push(m.text()); });
  await p.goto(PAGE);
  await p.evaluate(() => localStorage.clear()); await p.reload(); await p.waitForTimeout(800);

  console.log('Raum starten, während Companion weg ist');
  await set('down=1'); await p.click('[data-act=start]'); await p.waitForTimeout(2500);
  check(await p.isVisible('#s-start') && await p.isVisible('#conn'), 'Startbildschirm bleibt, Hinweis „Keine Verbindung“ (Raum ist nicht an)');
  await set('down=0'); await p.waitForTimeout(4000);
  if (!(await p.isVisible('#s-start'))) await p.evaluate(() => go('start'));
  await clear(); await p.click('[data-act=start]'); await p.waitForTimeout(800);
  check(await p.isVisible('#s-main') && (await state()).log.includes('1/0/1 press'), 'Companion zurück -> Raum starten klappt');

  console.log('Companion hängt (antwortet nicht)');
  await set('hang=1'); await p.click('[data-act=volUp]'); await p.waitForTimeout(300); await p.click('[data-act=volUp]');
  await p.waitForTimeout(7000);
  check(await p.isVisible('#conn'), 'Hinweis „Keine Verbindung“ erscheint');
  await set('hang=0'); await p.waitForTimeout(4000);
  await clear(); await p.click('[data-act=volDown]'); await p.waitForTimeout(1500);
  let st = await state(), want = await p.evaluate(() => String(CONFIG.volSteps[S.vol]));
  check(st.vars.r5_vol_db === want && st.log.includes('1/3/1 press'), 'danach geht die Lautstärke wieder (r5_vol_db ' + st.vars.r5_vol_db + ', soll ' + want + ')');
  check(!(await p.isVisible('#conn')), 'Hinweis verschwindet wieder');

  console.log('Teams starten, während Companion weg ist');
  await set('down=1'); await p.click('#tJoin'); await p.waitForTimeout(2000);
  check(!(await p.textContent('#tJoin')).includes('startet'), 'kein „Teams-Meeting startet …“, wenn der Befehl nicht ankam');
  await set('down=0'); await p.waitForTimeout(4000);

  console.log('Kamera-Befehle');
  await p.click('#tabs [data-go=kamera]'); await p.click('[data-cam=r]'); await p.waitForTimeout(300);
  const tap = async (sel, ms) => { const l = p.locator(sel); await l.dispatchEvent('pointerdown'); await p.waitForTimeout(ms); await l.dispatchEvent('pointerup'); };
  await clear(); await set('lagdown=600'); await tap('[data-move=up]', 80); await p.waitForTimeout(2000); await set('lagdown=0');
  check(camStuck((await state()).log).length === 0, 'kurzes Tippen, „down“ kommt verspätet an -> Kamera hält trotzdem an');
  await clear(); await set('dropup=3'); await tap('[data-move=left]', 200); await p.waitForTimeout(4500);
  st = await state();
  check(camStuck(st.log).length === 0 && st.log.includes('3/2/3 up'), '„up“ geht dreimal verloren -> wird wiederholt, Kamera hält an');
  await clear(); await set('slow=1500'); await tap('[data-move=right]', 50); await tap('[data-move=right]', 50); await tap('[data-move=down]', 50);
  await p.waitForTimeout(8000); await set('slow=0');   // 6 s reichten auf einem ausgelasteten Laptop nicht immer
  check(camStuck((await state()).log).length === 0, 'langsamer Companion, schnelles Tippen -> keine Kamera fährt weiter');

  console.log('Zufällige Bedienung mit Störungen (' + STEPS + ' Schritte, Seed ' + SEED + ')');
  await clear();
  const faults = [NOFAULT, NOFAULT, 'down=1', 'hang=1', 'slow=900', 'flaky=0.2', 'lagdown=400', 'slow=300&flaky=0.1'];
  const world = ['r5_t_in=1&r5_t_mute=0&r5_t_video=1', 'r5_t_in=0', 'r5_t_mode=teilen', 'r5_t_mode=kamera', 'r5_t_share=1', 'r5_room=0', 'r5_room=1',
                 'obs:scene_active=Diskussion', 'r5_pmic=3', 'r5_spk_mute=1', 'r5_t_status=fehler: Teams reagiert nicht', 'r5_t_status=', 'r5_live=0', 'r5_live=1'];
  let fault = NOFAULT;
  for (let i = 0; i < STEPS; i++) {
    const r = rnd();
    try {
      if (r < 0.06) { fault = pick(faults); await set(NOFAULT + '&' + fault); }
      else if (r < 0.12) await set(pick(world));
      else if (r < 0.27) {
        const mv = await p.$$('[data-move]:visible');
        if (mv.length) { const el = pick(mv); await el.dispatchEvent('pointerdown'); await p.waitForTimeout(Math.floor(rnd() * 500));
                         if (rnd() < 0.1) await p.evaluate(() => window.dispatchEvent(new Event('blur'))); await el.dispatchEvent('pointerup'); }
      } else {
        const bs = await p.$$('#stage button:visible:not([disabled])');
        if (bs.length) { const el = pick(bs); await el.click({ timeout: 1000, force: true }); if (rnd() < 0.15) await el.click({ timeout: 1000, force: true }); }
      }
    } catch (e) { /* Element verschwand zwischen Suchen und Tippen – normal bei Zufallsbedienung */ }
    await p.waitForTimeout(Math.floor(rnd() * 250));
  }

  console.log('Nach den Störungen');
  await set(NOFAULT); await p.waitForTimeout(9000);   // alle Wiederholungen abgeschlossen
  const stuck = camStuck((await state()).log);
  check(stuck.length === 0, 'keine Kamera fährt weiter' + (stuck.length ? ' (' + stuck.join(', ') + ')' : ''));
  // Zustand von außen setzen; das Tablet muss ihm folgen (Abfrage läuft noch, nichts hängt)
  for (const d of ['#dlgOff [data-act=cancelOff]', '#dlgIdle [data-act=keepOn]']) if (await p.isVisible(d)) await p.click(d);
  await set('r5_room=0&r5_t_in=0'); await p.waitForTimeout(4000); await set('r5_room=1'); await p.waitForTimeout(4000);   // wie echt: Raum aus verlässt das Meeting
  await set('obs:scene_active=Diskussion&r5_vol_db=-1000&r5_spk_mute=0&r5_t_in=1&r5_t_mute=1&r5_t_video=1&r5_t_mode=kamera&r5_t_share=0&r5_t_status=&r5_live=1');
  await p.waitForTimeout(8000);
  await p.click('#tabs [data-go=main]', { force: true }); await p.waitForTimeout(500);
  check(await p.isVisible('#s-main'), 'Raum an von außen -> Steuerung');
  check(!(await p.isVisible('#conn')), 'kein Fehlerbanner mehr');
  check(await p.textContent('#volNum') === '70', 'Lautstärke folgt Companion (70 %, ist ' + await p.textContent('#volNum') + ')');
  check(await p.$eval('[data-scene=diskussion]', e => e.classList.contains('on')), 'Szene folgt OBS (Diskussion)');
  check(await p.isVisible('#teamsBar') && (await p.textContent('#tMic')).includes('Mikro aus'), 'Teams-Leiste folgt Teams (im Meeting, Mikro aus)');
  check((await p.textContent('#liveTxt')) === 'Live in Teams', 'Live-Kachel „Live in Teams“');
  await clear(); await p.click('[data-act=volUp]'); await p.waitForTimeout(1500); st = await state();
  check(st.vars.r5_vol_db === '-700' && st.log.includes('1/3/1 press'), 'Lauter wird noch gesendet (r5_vol_db ' + st.vars.r5_vol_db + ')');
  await clear(); await p.click('[data-scene=redner]'); await p.waitForTimeout(800);
  check((await state()).log.includes('1/1/4 press'), 'Szenen-Knopf wird noch gesendet');
  check(errs.length === 0, 'keine JavaScript-Fehler ' + (errs.length ? JSON.stringify(errs.slice(0, 5)) : ''));
  await b.close();
  console.log(`\n${ok} bestanden, ${bad} fehlgeschlagen`);
  process.exit(bad ? 1 : 0);
})();
