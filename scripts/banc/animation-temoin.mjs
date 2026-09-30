// Contrôle : une animation CSS triviale (un carré qui glisse, transform seul) — si elle aussi tombe à 30 img/s,
// c'est la chaîne d'affichage, pas la page d'habillage. Affiche aussi l'état des fonctions GPU de Chromium.
const attendre = ms => new Promise(r => setTimeout(r, ms));
const v = await (await fetch('http://127.0.0.1:9222/json/version')).json();
const bws = new WebSocket(v.webSocketDebuggerUrl);
let bid = 0; const batt = new Map(); bws.onmessage = e => { const m = JSON.parse(e.data); batt.get(m.id)?.(m); };
await new Promise(r => bws.onopen = r);
const bcmd = (method, params = {}) => new Promise(r => { const i = ++bid; batt.set(i, r); bws.send(JSON.stringify({ id: i, method, params })); });
const info = (await bcmd('SystemInfo.getInfo')).result;
console.log(JSON.stringify({ featureStatus: info.gpu.featureStatus, driverBugWorkarounds: info.gpu.driverBugWorkarounds?.length }));
bws.close();

const tabs = await (await fetch('http://127.0.0.1:9222/json')).json();
const page = tabs.find(t => t.type === 'page'); const retour = page.url;
const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 0; const att = new Map(); let trace = []; let fin;
ws.onmessage = e => { const m = JSON.parse(e.data); if (att.has(m.id)) { att.get(m.id)(m); att.delete(m.id); }
  else if (m.method === 'Tracing.dataCollected') trace.push(...m.params.value); else if (m.method === 'Tracing.tracingComplete') fin?.(); };
await new Promise(r => ws.onopen = r);
const cmd = (method, params = {}) => new Promise(r => { const i = ++id; att.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const pages = {
  transform: `<body style="margin:0;background:#707880"><div style="width:300px;height:300px;background:#ea2a82;animation:a 2s linear infinite alternate"></div><style>@keyframes a{to{transform:translateX(1500px)}}</style>`,
  largeur: `<body style="margin:0;background:#707880"><div style="height:300px;background:#ea2a82;animation:a 2s linear infinite alternate"></div><style>@keyframes a{from{width:100px}to{width:1800px}}</style>`,
  raf: `<body style="margin:0;background:#707880"><canvas id=c width=1920 height=1080></canvas><script>const x=c.getContext('2d');let t=0;(function f(){x.fillStyle='#707880';x.fillRect(0,0,1920,1080);x.fillStyle='#ea2a82';x.fillRect((t+=12)%1600,300,300,300);requestAnimationFrame(f)})()</script>`,
};
for (const [nom, html] of Object.entries(pages)) {
  await cmd('Page.navigate', { url: 'data:text/html,' + encodeURIComponent(html) }); await attendre(3000);
  trace = []; await cmd('Tracing.start', { categories: 'disabled-by-default-devtools.timeline.frame,benchmark,viz', transferMode: 'ReportEvents' });
  await attendre(5000); await new Promise(r => { fin = r; cmd('Tracing.end'); });
  const d = trace.filter(e => e.name === 'DrawFrame').map(e => e.ts / 1000).sort((a, b) => a - b);
  const g = d.slice(1).map((t, i) => t - d[i]); const tri = [...g].sort((a, b) => a - b);
  console.log(JSON.stringify({ page: nom, draw_ips: +(d.length / ((d.at(-1) - d[0]) / 1000)).toFixed(1), ecart_p50_ms: +tri[tri.length >> 1]?.toFixed(1), ecarts_sup_25ms: g.filter(x => x > 25).length, n: d.length }));
}
await cmd('Page.navigate', { url: retour }); ws.close();
