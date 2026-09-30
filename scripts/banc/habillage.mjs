// Banc « habillage » : mesure la fluidité de la page PGM d'urban-trail-2026 dans le Chromium du kiosque.
// Le serveur d'habillage d'ESSAI tourne sur 127.0.0.1:8799 (jamais celui de la régie).
// Pour chaque scénario : trace Chromium (images dessinées / perdues), accrocs de requestAnimationFrame,
// CPU des processus chromium, charge et fréquence du GPU (devfreq).
//   node habillage.mjs [scenario…]     (sans argument : tous)
import { readFileSync, readdirSync } from 'node:fs';
const SRV = process.env.SRV || 'http://127.0.0.1:8799';
const G = '/sys/class/devfreq/fde60000.gpu';
const attendre = ms => new Promise(r => setTimeout(r, ms));
const api = p => fetch(SRV + p).then(r => r.text()).catch(e => 'ERR ' + e.message);

const tabs = await (await fetch('http://127.0.0.1:9222/json')).json();
const page = tabs.find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 0; const att = new Map(); let trace = []; let finTrace;
ws.onmessage = e => { const m = JSON.parse(e.data);
  if (att.has(m.id)) { att.get(m.id)(m); att.delete(m.id); }
  else if (m.method === 'Tracing.dataCollected') trace.push(...m.params.value);
  else if (m.method === 'Tracing.tracingComplete') finTrace?.(); };
await new Promise(r => ws.onopen = r);
const cmd = (method, params = {}) => new Promise(r => { const i = ++id; att.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async x => (await cmd('Runtime.evaluate', { expression: x, returnByValue: true })).result.result?.value;

// Collecteur rAF dans la page (réinstallé à chaque scénario, la page peut se recharger toute seule).
const RAF = `(()=>{if(window.__inst)return 0;window.__inst=1;window.__g=[];let p=performance.now();const f=t=>{window.__g.push(t-p);p=t;requestAnimationFrame(f)};requestAnimationFrame(f);return 1})()`;

// CPU cumulé (jiffies) de tous les processus chromium.
function cpuChromium() { let s = 0;
  for (const d of readdirSync('/proc')) { if (!/^\d+$/.test(d)) continue;
    try { const st = readFileSync(`/proc/${d}/stat`, 'utf8'); if (!/\((chromium|chrome)/.test(st)) continue;
      const f = st.slice(st.lastIndexOf(')') + 2).split(' '); s += +f[11] + +f[12]; } catch {} }
  return s; }
const lire = f => { try { return readFileSync(f, 'utf8').trim(); } catch { return ''; } };

async function mesurer(nom, avant, pendantMs, apres = null, apresMs = 0) {
  trace = [];
  await ev(RAF);
  await cmd('Tracing.start', { categories: 'disabled-by-default-devtools.timeline.frame,benchmark,viz', transferMode: 'ReportEvents' });
  await attendre(300);
  const c0 = cpuChromium(), t0 = Date.now(); const gpu = [];
  const echant = setInterval(() => { const l = lire(`${G}/load`); if (l) gpu.push(l); }, 250);
  await ev('window.__g.length=0');
  for (const p of avant) await api(p);
  await attendre(pendantMs);
  if (apres) { for (const p of apres) await api(p); await attendre(apresMs); }
  clearInterval(echant);
  const dt = (Date.now() - t0) / 1000, cpu = (cpuChromium() - c0) / 100 / dt * 100;
  const g = (await ev('window.__g.slice(1)')) || [];
  await new Promise(r => { finTrace = r; cmd('Tracing.end'); });
  // Trace : images dessinées par viz, états du rapporteur de pipeline.
  const n = {}; const etats = {}; const draws = [];
  for (const e of trace) { n[e.name] = (n[e.name] || 0) + 1; if (e.name === 'DrawFrame') draws.push(e.ts / 1000);
    if (e.name === 'PipelineReporter' && e.ph === 'b') { const s = e.args?.chrome_frame_reporter?.state ?? e.args?.data?.state ?? '?'; etats[s] = (etats[s] || 0) + 1; } }
  const tri = [...g].sort((a, b) => a - b), q = x => tri.length ? +tri[Math.floor(x * (tri.length - 1))].toFixed(1) : null;
  const charges = gpu.map(x => x.split('@')), load = charges.map(x => +x[0]), freq = charges.map(x => parseInt(x[1]) / 1e6);
  const moy = a => a.length ? +(a.reduce((s, x) => s + x, 0) / a.length).toFixed(0) : null;
  draws.sort((a, b) => a - b); const dg = draws.slice(1).map((t, i) => t - draws[i]).filter(x => x < 250);
  const actifS = dg.reduce((a, x) => a + x, 0) / 1000;
  const r = { scenario: nom, secondes: +dt.toFixed(1),
    raf_par_s: +(g.length / dt).toFixed(1), raf_p50_ms: q(.5), raf_p95_ms: q(.95), raf_max_ms: q(1),
    raf_accrocs_sup_25ms: g.filter(x => x > 25).length,
    draw_total: draws.length, draw_actif_s: +actifS.toFixed(1), draw_ips_en_animation: actifS ? +(dg.length / actifS).toFixed(1) : null,
    draw_ecarts_sup_25ms: dg.filter(x => x > 25).length,
    pipeline: etats, cpu_chromium_pct: +cpu.toFixed(0), gpu_charge_moy: moy(load), gpu_charge_max: load.length ? Math.max(...load) : null,
    gpu_mhz_moy: moy(freq), temp_c: +(+lire('/sys/class/thermal/thermal_zone0/temp') / 1000).toFixed(0) };
  console.log(JSON.stringify(r));
  return r;
}

const C = '?course=solo';
const S = {
  repos:      [[], 6000],
  chronos:    [['/api/gfx/chronos/take'], 6000, ['/api/gfx/chronos/clear'], 3000],
  bandeau:    [['/api/follow/tete' + C, '/api/gfx/bandeau/take' + C], 6000, ['/api/gfx/bandeau/clear'], 3000],
  vitesse:    [['/api/follow/tete' + C, '/api/gfx/vitesse/take' + C], 6000, ['/api/gfx/vitesse/clear'], 3000],
  lieu:       [['/api/gfx/lieu/take'], 6000, ['/api/gfx/lieu/clear'], 3000],
  denivele:   [['/api/follow/tete' + C, '/api/gfx/denivele/take' + C], 6000, ['/api/gfx/denivele/clear'], 3000],
  carte:      [['/api/follow/tete' + C, '/api/gfx/carte/take' + C], 6000, ['/api/gfx/carte/clear'], 3000],
  tete:       [['/api/gfx/tete/take' + C], 6000, ['/api/gfx/tete/clear'], 3000],
  portique:   [['/api/gfx/portique/take' + C], 6000, ['/api/gfx/portique/clear'], 3000],
  classement: [['/api/gfx/classement/take' + C], 6000, ['/api/gfx/classement/clear'], 3000],
  grandclassement: [['/api/gfx/grandclassement/take' + C], 6000, ['/api/gfx/grandclassement/clear'], 3000],
  departs:    [['/api/gfx/departs/take' + C], 6000, ['/api/gfx/departs/clear'], 3000],
  // Le cas réaliste : l'habillage courant d'une séquence coureur, tout ensemble.
  sequence:   [['/api/follow/tete' + C, '/api/gfx/chronos/take', '/api/gfx/bandeau/take' + C, '/api/gfx/vitesse/take' + C,
                '/api/gfx/lieu/take', '/api/gfx/denivele/take' + C, '/api/gfx/carte/take' + C], 10000, ['/api/clear-all'], 4000],
};
const choix = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(S);
await cmd('Page.reload'); await attendre(6000);
await api('/api/clear-all'); await attendre(3000);
for (const k of choix) { const [a, t, b, tb] = S[k]; await mesurer(k, a, t, b, tb); await attendre(1500); }
await api('/api/clear-all');
ws.close();
