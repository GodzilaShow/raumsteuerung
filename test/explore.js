// Screenshots + Layout-Prüfung aller Bildschirme. Aufruf: node test/explore.js <ausgabeordner> [tag]
const { chromium } = require('playwright');
const out = process.argv[2] || '.', tag = process.argv[3] || 'x';
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' }).catch(() => chromium.launch());
  for (const vp of [{ n: 'tabA9', w: 1067, h: 667, dpr: 1.8, touch: true }, { n: 'ipad', w: 1180, h: 820, dpr: 2, touch: true }, { n: 'full', w: 1280, h: 800, dpr: 1, touch: false }]) {
    const ctx = await b.newContext({ viewport: { width: vp.w, height: vp.h }, deviceScaleFactor: vp.dpr, hasTouch: vp.touch });
    const p = await ctx.newPage();
    const errs = [];
    p.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') errs.push(m.text()); });
    p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
    await p.goto('http://127.0.0.1:8080/');
    await p.waitForTimeout(1500);
    await p.screenshot({ path: `${out}/${tag}-${vp.n}-start.png` });
    if (vp.n !== 'full') { await ctx.close(); console.log(vp.n, 'errors:', errs); continue; }
    await p.click('[data-act=start]'); await p.waitForTimeout(900);
    await p.screenshot({ path: `${out}/${tag}-${vp.n}-main.png` });
    await p.click('#tabs [data-go=kamera]'); await p.waitForTimeout(900);
    await p.screenshot({ path: `${out}/${tag}-${vp.n}-kamera.png` });
    await p.click('#tabs [data-go=hilfe]'); await p.waitForTimeout(900);
    await p.screenshot({ path: `${out}/${tag}-${vp.n}-hilfe.png` });
    // Überlauf-Check: Elemente, deren Inhalt abgeschnitten wird
    const ov = await p.evaluate(() => {
      const r = [];
      document.querySelectorAll('.screen').forEach(s => {
        s.classList.add('active');
        s.querySelectorAll('.panel, .plan, .pplan, button, .body').forEach(el => {
          if (el.scrollHeight > el.clientHeight + 2 || el.scrollWidth > el.clientWidth + 2) r.push(s.id + ' ' + el.tagName + '.' + el.className + ' "' + (el.textContent || '').trim().slice(0, 30) + '" ' + el.scrollWidth + 'x' + el.scrollHeight + ' > ' + el.clientWidth + 'x' + el.clientHeight);
        });
        s.classList.remove('active');
      });
      return r;
    });
    console.log('overflow:', ov);
    console.log(vp.n, 'errors:', errs);
    await ctx.close();
  }
  await b.close();
})();
