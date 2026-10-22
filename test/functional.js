// Funktionstest der Tablet-Seite gegen den Mock (node test/mock-companion.js muss laufen).
// Aufruf: NODE_PATH=$(npm root -g) node test/functional.js
const { chromium } = require('playwright');
const API = 'http://127.0.0.1:' + (process.env.API_PORT || 8000);
const PAGE = 'http://127.0.0.1:' + (process.env.PAGE_PORT || 8080) + '/?companion=' + encodeURIComponent(API);
let ok = 0, bad = 0;
const check = (cond, msg) => { if (cond) { ok++; console.log('  ✔ ' + msg); } else { bad++; console.log('  ✘ ' + msg); } };
const state = async () => (await fetch(API + '/_test/state')).json();
const set = (q) => fetch(API + '/_test/set?' + q);
const clear = () => fetch(API + '/_test/clear');
(async () => {
  await set('obs:scene_active=Alles im Blick&r5_vol_db=-1300&r5_live=1&r5_room=0&down=0');
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' }).catch(() => chromium.launch());
  const ctx = await b.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', e => errs.push(e.message));
  p.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|ERR_CONNECTION|ERR_EMPTY/.test(m.text())) errs.push(m.text()); });
  await p.goto(PAGE);
  await p.evaluate(() => localStorage.clear()); await p.reload(); await p.waitForTimeout(500);

  console.log('Start');
  await clear(); await p.click('[data-act=start]'); await p.waitForTimeout(600);
  let st0 = await state();
  check(st0.log.includes('1/0/1 press'), 'Raum starten drückt 1/0/1');
  check(!st0.log.includes('1/0/7 press'), 'Raum starten startet kein Teams-Meeting (nur über den Teams-Knopf)');
  await p.waitForTimeout(3500);
  check((await p.textContent('#tJoin')).includes('Teams-Meeting starten'), 'Kopf zeigt den Knopf „Teams-Meeting starten“');
  check((await p.textContent('#liveTxt')) === 'Nur im Raum', 'Live-Kachel: „Nur im Raum“ (nicht „Live“)');
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
  await clear(); await p.click('[data-act=volDown]'); await p.click('[data-act=volDown]'); await p.waitForTimeout(800);
  st = await state(); check(st.vars.r5_vol_db === '-700' && await p.textContent('#volNum') === '80', 'zweimal Leiser von 100 % -> 80 % = -700 (ist ' + st.vars.r5_vol_db + ')');
  check(!(await p.$('#bars')), 'Lautstärke ist eine Zeile „− % +“ (keine Balken)');

  console.log('Ton aus / an');
  await clear(); await p.click('#spkBtn'); await p.waitForTimeout(400);
  let sp = await state();
  check(sp.log.includes('1/1/6 press') && sp.vars.r5_spk_mute === '1', 'Ton aus -> 1/1/6, r5_spk_mute = 1');
  check((await p.textContent('#spkBtn')).includes('Ton ist aus') && await p.$eval('#spkBtn', e => e.classList.contains('muted')), 'Knopf rot „Ton ist aus“');
  if (sp.log.some(x => x.startsWith('rmcr:'))) check(sp.log.includes('rmcr: set RM:NeOut_Fader/Ch/On 0 0 0'), 'RM-CR bekommt „set RM:NeOut_Fader/Ch/On 0 0 0“');
  await clear(); await p.click('[data-act=volDown]'); await p.waitForTimeout(600);
  sp = await state();
  check(sp.log.includes('1/1/7 press') && sp.vars.r5_spk_mute === '0' && !(await p.$eval('#spkBtn', e => e.classList.contains('muted'))), 'Leiser bei stummem Ton schaltet den Ton wieder an (1/1/7)');
  await set('r5_spk_mute=1'); await p.waitForTimeout(7000);
  check(await p.$eval('#spkBtn', e => e.classList.contains('muted')), 'Ton von außen stumm (Stream Deck) -> Tablet zeigt „Ton ist aus“');
  await clear(); await p.click('#spkBtn'); await p.waitForTimeout(400);
  check((await state()).log.includes('1/1/7 press'), 'Ton an -> 1/1/7');

  console.log('Quelle / Displays');
  check(!(await p.textContent('#srcHint')).includes('[CODE]'), 'kein Platzhalter [CODE] im Hinweis');
  await p.click('[data-src=cast]');
  check(!(await p.textContent('#srcHint')).includes('[CODE]'), 'Hinweis „Kabellos“ ohne [CODE]');
  await p.click('#dispBtn');
  check(await p.$eval('#blankBtn', e => e.disabled), '„Präsentation ausblenden“ gesperrt, wenn Displays aus');
  await p.click('#dispBtn');

  console.log('Kamera');
  await p.click('#tabs [data-go=kamera]'); await p.waitForTimeout(400);
  await clear();
  const up = p.locator('[data-move=up]');
  const box = await up.boundingBox();
  await p.mouse.move(box.x + 20, box.y + 20); await p.mouse.down(); await p.waitForTimeout(200);
  st = await state(); check(st.log.includes('3/2/1 down'), 'Pfeil hoch halten -> 3/2/1 down');
  await p.evaluate(() => window.dispatchEvent(new Event('blur'))); await p.waitForTimeout(200);
  st = await state(); check(st.log.includes('3/2/1 up'), 'Fenster verliert Fokus -> Kamera stoppt (3/2/1 up)');
  await p.mouse.up(); await p.waitForTimeout(200);
  st = await state(); check(st.log.filter(x => x === '3/2/1 up').length === 1, 'kein doppeltes „up“');
  check(!(await p.$('[data-cam]')) && !(await p.$('.pplan')) && !(await p.$('#pAutoBtn')), 'keine Publikum-Kamera-Steuerung mehr (Kamera ist fest)');
  check((await p.textContent('.camhint')).includes('ganzen Raum'), 'Hinweis: Publikum-Kamera zeigt immer den ganzen Raum');
  await clear(); await p.click('[data-preset=r_displays]'); await p.waitForTimeout(300);
  st = await state();
  check(st.log.includes('3/0/2 press') && await p.$eval('[data-preset=r_displays]', e => e.classList.contains('on')), '„Bei den Displays“ -> 3/0/2, Kachel markiert');
  await p.locator('[data-move=zoomin]').dispatchEvent('pointerdown'); await p.locator('[data-move=zoomin]').dispatchEvent('pointerup'); await p.waitForTimeout(300);
  st = await state();
  check(st.log.includes('3/2/5 down') && st.log.includes('3/2/5 up') && !(await p.$eval('[data-preset=r_displays]', e => e.classList.contains('on'))), '„Näher ran“ -> 3/2/5 down/up, Preset nicht mehr markiert');
  const kcut = await p.$$eval('#s-kamera .panel, #s-kamera .zone, #s-kamera .btn', els => els.filter(e => e.offsetParent && (e.scrollHeight > e.clientHeight + 2 || e.scrollWidth > e.clientWidth + 2)).map(e => e.className + ' ' + e.textContent.trim().slice(0, 20)));
  check(kcut.length === 0, 'Kamera-Seite: nichts abgeschnitten ' + (kcut.length ? JSON.stringify(kcut) : ''));
  await clear(); await p.click('#homeBtn'); await p.waitForTimeout(200);
  check((await state()).log.includes('3/2/7 press'), '„Zurück auf Standard“ -> 3/2/7 (Redner-Kamera)');
  await p.waitForTimeout(2600);
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

  console.log('Teams');
  check(!(await p.isVisible('#teamsBar')), 'ohne Teams-Meeting keine Teams-Leiste');
  check(!(await p.isVisible('#tLeave')) && (await p.$eval('#tJoin', e => e.getBoundingClientRect().height)) >= 90, 'ohne Meeting: großer Knopf „Teams-Meeting starten“, kein „Verlassen“');
  await set('r5_t_status=fehler: Teams reagiert nicht'); await p.waitForTimeout(3500);
  check((await p.textContent('#tJoin')).includes('fehlgeschlagen'), 'Beitritt fehlgeschlagen -> Hinweis am Knopf');
  check((await p.textContent('#liveTxt')) === 'Teams-Start fehlgeschlagen' && await p.$eval('#live', e => e.classList.contains('warn')), 'Live-Kachel: „Teams-Start fehlgeschlagen“ (gelb)');
  await set('r5_t_status=warten: Wartebereich'); await p.waitForTimeout(3500);
  check((await p.textContent('#tJoin')).includes('Wartet auf Einlass') && (await p.textContent('#liveTxt')) === 'Wartet auf Einlass', 'Wartebereich -> „Wartet auf Einlass“ am Knopf und in der Live-Kachel');
  await clear(); await p.click('#tJoin'); await p.waitForTimeout(300);
  check(!(await state()).log.includes('1/0/7 press'), 'im Wartebereich startet ein Tippen keinen zweiten Beitritt');
  await set('r5_t_status=fehler: nicht eingelassen'); await p.waitForTimeout(3500);
  check((await p.textContent('#liveTxt')) === 'Nicht eingelassen', 'nicht eingelassen -> eigener Hinweis');
  await clear(); await set('r5_t_status='); await p.click('#tJoin'); await p.waitForTimeout(300);
  check((await state()).log.includes('1/0/7 press'), '„Teams-Meeting starten“ -> 1/0/7');
  await set('r5_t_in=1&r5_t_mute=0&r5_t_video=1'); await p.waitForTimeout(3500);
  check(!(await p.isVisible('#tJoin')), 'im Meeting verschwindet „Teams-Meeting starten“');
  check(await p.isVisible('#teamsBar'), 'teams-steuerung meldet Meeting -> Teams-Leiste erscheint');
  await set('r5_live=1'); await p.waitForTimeout(3500);
  check((await p.textContent('#liveTxt')) === 'Live in Teams', 'im Meeting + Virtual Cam + Bild an -> „Live in Teams“');
  await set('r5_t_video=0'); await p.waitForTimeout(3500);
  check((await p.textContent('#liveTxt')) === 'In Teams, Kamera aus' && await p.$eval('#live', e => e.classList.contains('warn')), 'Bild in Teams aus -> „In Teams, Kamera aus“ (gelb)');
  await set('r5_t_video=1&r5_live=0'); await p.waitForTimeout(3500);
  check((await p.textContent('#liveTxt')) === 'Teams sieht kein Bild', 'Virtual Cam aus im Meeting -> „Teams sieht kein Bild“');
  await set('r5_live=1'); await p.waitForTimeout(3500);
  check(!(await p.isVisible('#tShare')), 'Modus kamera: kein Knopf „Präsentation zeigen“');
  await set('r5_t_mode=teilen&r5_t_share=0'); await p.waitForTimeout(3500);
  check(await p.isVisible('#tShare') && (await p.textContent('#tShare')).includes('Präsentation zeigen'), 'Modus teilen: Knopf „Präsentation zeigen“ in der Teams-Leiste');
  check(!(await p.isVisible('[data-scene=alles]')) && !(await p.isVisible('[data-scene=folien]')) && await p.isVisible('[data-scene=diskussion]'),
        'Modus teilen: nur Personen-Ansichten (ohne „Alles im Blick“/„Folien groß“)');
  check((await p.textContent('#scenesH')) === 'Was zeigt die Kamera in Teams?', 'Modus teilen: Überschrift „Was zeigt die Kamera in Teams?“');
  check(await p.$$eval('.scenes .scene', els => els.filter(e => e.offsetParent).map(e => e.dataset.scene).sort((x, y) => 0) && els.filter(e => e.offsetParent)
        .sort((x, y) => x.getBoundingClientRect().top - y.getBoundingClientRect().top || x.getBoundingClientRect().left - y.getBoundingClientRect().left)[0].dataset.scene) === 'redner',
        'Modus teilen: „Nur Redner“ steht links oben');
  const big = await p.$$eval('#teamsBar .tbtn', els => els.filter(e => e.offsetParent).map(e => [e.id, Math.round(e.getBoundingClientRect().height)]));
  check(big.map(x => x[0]).join() === 'tMic,tCam,tShare' && big.every(x => x[1] >= 90), 'Modus teilen: Mikro, Kamera, Präsentation groß unter dem Kopf (' + JSON.stringify(big) + ')');
  check(await p.isVisible('header #tLeave') && !(await p.isVisible('#tJoin')), '„Verlassen“ klein im Kopf');
  const cut = await p.$$eval('#s-main .panel, #s-main .scene, #s-main .btn, #s-main .tbtn', els => els.filter(e => e.offsetParent && (e.scrollHeight > e.clientHeight + 2 || e.scrollWidth > e.clientWidth + 2)).map(e => (e.id || e.className) + ' ' + e.textContent.trim().slice(0, 20)));
  check(cut.length === 0, 'Steuerung im Meeting: nichts abgeschnitten ' + (cut.length ? JSON.stringify(cut) : ''));
  await clear(); await p.click('#tShare'); await p.waitForTimeout(300);
  check((await state()).vars.r5_tcmd === 'share_on' && (await p.textContent('#tShare')).includes('beenden'), '„Präsentation zeigen“ -> r5_tcmd = share_on, Knopf „Präsentation beenden“');
  await clear(); await p.click('#tShare'); await p.waitForTimeout(300);
  check((await state()).vars.r5_tcmd === 'share_off', '„Präsentation beenden“ -> r5_tcmd = share_off');
  await set('r5_t_status=fehler: kein Teilen-Bildschirm'); await p.waitForTimeout(3500);
  check((await p.textContent('#liveTxt')) === 'Präsentation nicht geteilt' && (await p.textContent('#liveSub')).includes('von Hand') === false
        && (await p.textContent('#liveSub')).includes('Teilen') && (await p.textContent('#tShare')).includes('zeigen'),
        'kein Teilen-Bildschirm -> Hinweis „in Teams von Hand teilen“, Knopf wieder „Präsentation zeigen“');
  await set('r5_t_status='); await p.waitForTimeout(3500);
  await set('r5_t_share=0&r5_t_mode=kamera'); await p.waitForTimeout(3500);
  check(await p.isVisible('[data-scene=alles]') && (await p.textContent('#scenesH')) === 'Was sehen die Online-Teilnehmer?', 'Modus kamera: wieder alle 5 Ansichten');
  await clear(); await p.click('#tMic'); await p.waitForTimeout(300);
  let ts = await state();
  check(ts.vars.r5_tcmd === 'mic_off', 'Mikro tippen -> Zielzustand r5_tcmd = mic_off (kein Umschalten)');
  check((await p.textContent('#tMic')).includes('Mikro aus') && await p.$eval('#tMic', e => e.classList.contains('off')), 'Knopf zeigt sofort „Mikro aus“ (rot)');
  await set('r5_t_mute=1'); await p.waitForTimeout(4000);
  check((await p.textContent('#tMic')).includes('Mikro aus'), 'Zustand aus Teams bestätigt „Mikro aus“');
  await clear(); await p.click('#tCam'); await p.waitForTimeout(300);
  check((await state()).vars.r5_tcmd === 'video_off' && (await p.textContent('#tCam')).includes('Kamera aus'), 'Bild tippen -> r5_tcmd = video_off, Knopf „Kamera aus“');
  await clear(); await p.click('#tLeave'); await p.waitForTimeout(300);
  check(!(await state()).log.includes('1/0/6 press') && (await p.textContent('#tLeave')).includes('Wirklich'), 'Verlassen: erstes Tippen fragt nur nach');
  await p.click('#tLeave'); await p.waitForTimeout(300);
  ts = await state();
  check(ts.log.includes('1/0/6 press') && ts.vars.r5_tcmd === 'leave', 'zweites Tippen -> 1/0/6, r5_tcmd = leave');
  await set('r5_t_in=0'); await p.waitForTimeout(4500);
  check(!(await p.isVisible('#teamsBar')), 'nach dem Meeting verschwindet die Leiste');
  check((await p.textContent('#liveTxt')) === 'Nur im Raum', 'kein Meeting -> Live-Kachel „Nur im Raum“');

  console.log('Ausschalten');
  await clear(); await p.click('[data-act=askOff]'); await p.waitForTimeout(400);
  check(await p.isVisible('#dlgOff'), 'Abfrage erscheint');
  await p.click('#dlgOff [data-act=off]'); await p.waitForTimeout(300);
  check((await state()).log.includes('1/0/2 press') && await p.isVisible('#s-start'), 'Ja, ausschalten -> 1/0/2 und Startbildschirm');
  check((await state()).vars.r5_tcmd === 'leave', 'Raum aus verlässt auch das Teams-Meeting (r5_tcmd = leave)');
  // Teams meldet noch „im Meeting“ (Verlassen dauert): sofort neu starten -> keine alte Teams-Leiste
  await set('r5_t_in=1&r5_t_mute=0&r5_t_video=1'); await p.click('[data-act=start]'); await p.waitForTimeout(3500);
  check(!(await p.isVisible('#teamsBar')) && await p.isVisible('#tJoin'), 'Raum aus -> sofort Raum starten: keine Leiste vom alten Meeting, „Teams-Meeting starten“ sichtbar');
  await set('r5_t_in=0'); await p.waitForTimeout(3500);
  await p.click('[data-act=askOff]'); await p.waitForTimeout(300); await p.click('#dlgOff [data-act=off]'); await p.waitForTimeout(300);

  console.log('Auto-Aus (nur abends)');
  await set('r5_t_in=0'); await p.click('[data-act=start]'); await p.waitForTimeout(3500);
  // tagsüber: nie fragen, auch wenn lange niemand getippt hat
  await p.evaluate(() => { CONFIG.eveningHour = 24; CONFIG.morningHour = 0; CONFIG.idleCountdown = 2; lastUse = 0; nextAsk = 0; });
  await p.waitForTimeout(16000);
  check(!(await p.isVisible('#dlgIdle')), 'tagsüber keine Abfrage, auch ohne Bedienung');
  // abends im Teams-Meeting: nicht fragen
  await set('r5_t_in=1'); await p.waitForTimeout(3500);
  await p.evaluate(() => { CONFIG.eveningHour = 0; lastUse = 0; nextAsk = 0; });
  await p.waitForTimeout(16000);
  check(!(await p.isVisible('#dlgIdle')), 'abends im Teams-Meeting keine Abfrage');
  // abends ohne Meeting, ohne Bedienung: Abfrage, nach Countdown Raum aus
  await set('r5_t_in=0'); await p.waitForTimeout(3500); await p.evaluate(() => { lastUse = 0; nextAsk = 0; });
  await p.waitForTimeout(16000);
  check(await p.isVisible('#dlgIdle') || await p.isVisible('#s-start'), 'abends ohne Meeting und Bedienung erscheint die Abfrage');
  await p.waitForTimeout(3000);
  check(await p.isVisible('#s-start'), 'Countdown abgelaufen -> Raum aus, Startbildschirm');
  // „Weiter nutzen“: Companion erfährt die Nutzung, nächste Frage erst nach einer Stunde
  await clear(); await p.click('[data-act=start]');
  await p.evaluate(() => { CONFIG.eveningHour = 0; CONFIG.idleCountdown = 30; lastUse = 0; nextAsk = 0; });
  await p.waitForTimeout(16000); await p.click('#dlgIdle [data-act=keepOn]'); await p.waitForTimeout(300);
  check((await state()).log.includes('1/3/8 press') && !(await p.isVisible('#dlgIdle')), '„Weiter nutzen“ meldet Companion die Nutzung (1/3/8)');
  await p.evaluate(() => { lastUse = 0; }); await p.waitForTimeout(16000);
  check(!(await p.isVisible('#dlgIdle')), 'nach „Weiter nutzen“ eine Stunde Ruhe');

  check(errs.length === 0, 'keine JavaScript-Fehler ' + (errs.length ? JSON.stringify(errs) : ''));
  await b.close();
  console.log(`\n${ok} bestanden, ${bad} fehlgeschlagen`);
  process.exit(bad ? 1 : 0);
})();
