// Lance MotionMark 1.3.1 dans le Chromium du kiosque (DevTools 9222) et rend le score + le détail par test.
const URL = 'https://browserbench.org/MotionMark1.3.1/';
const attendre = ms => new Promise(r => setTimeout(r, ms));
const page = (await (await fetch('http://127.0.0.1:9222/json')).json()).find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 0; const att = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); att.get(m.id)?.(m); att.delete(m.id); };
await new Promise(r => ws.onopen = r);
const cmd = (method, params = {}) => new Promise(r => { const i = ++id; att.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async x => (await cmd('Runtime.evaluate', { expression: x, returnByValue: true, awaitPromise: true })).result.result?.value;
await cmd('Page.navigate', { url: URL }); await attendre(8000);
console.log('taille', await ev('innerWidth+"x"+innerHeight+" dpr "+devicePixelRatio'));
console.log('demarrage', await ev('typeof benchmarkController !== "undefined" ? (benchmarkController.startBenchmark(), "ok") : "pas de benchmarkController"'));
const t0 = Date.now();
for (;;) {
  await attendre(15000);
  const s = await ev('(() => { const r = document.querySelector("#results"); if (!r || !document.body.classList.contains("showing-results") && !(r.offsetParent)) return null; return document.querySelector("#results .score")?.textContent || r.innerText.slice(0, 400); })()');
  if (s) { console.log('score', s.trim()); break; }
  if (Date.now() - t0 > 20 * 60000) { console.log('délai dépassé'); break; }
}
console.log('detail', JSON.stringify(await ev(`(() => { const t = document.querySelector("#results-tables") || document.querySelector("#results"); return t ? t.innerText.slice(0, 1500) : null; })()`)));
console.log('duree_s', Math.round((Date.now() - t0) / 1000));
ws.close();
