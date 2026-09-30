// Client DevTools minimal (WebSocket natif de Node ≥ 22, aucune dépendance).
// Ouvre v.html?src=<clip> dans le Chromium du kiosque (port 9222), chauffe 6 s,
// puis mesure sur <durée> s : images présentées (requestVideoFrameCallback),
// décodées et perdues (getVideoPlaybackQuality), avance réelle du média.
//   node mesure.mjs <clip dans media/> [durée_s=20]
import { dirname } from 'node:path'; import { fileURLToPath } from 'node:url';
const BANC = dirname(fileURLToPath(import.meta.url));
const [,, clip, dureeS='20'] = process.argv;
const tabs = await (await fetch('http://127.0.0.1:9222/json')).json();
const page = tabs.find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 0; const att = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); if (att.has(m.id)) { att.get(m.id)(m); att.delete(m.id); } };
await new Promise(r => ws.onopen = r);
const cmd = (method, params={}) => new Promise(r => { const i=++id; att.set(i, r); ws.send(JSON.stringify({id:i, method, params})); });
const ev = async x => (await cmd('Runtime.evaluate', {expression:x, returnByValue:true})).result.result.value;
await cmd('Page.navigate', {url:`file://${BANC}/v.html?src=${clip}`});
await new Promise(r => setTimeout(r, 6000));
const a = await ev('snap()');
await new Promise(r => setTimeout(r, +dureeS*1000));
const b = await ev('snap()');
const gaps = await ev('(()=>{const g=window.gaps.slice(-600);const h={};g.forEach(x=>h[x]=(h[x]||0)+1);return h})()');
const s = (b.t-a.t)/1000;
console.log(JSON.stringify({clip, secondes:+s.toFixed(1), resolution:`${b.w}x${b.h}`,
  img_par_s_rvfc:+((b.rvfc-a.rvfc)/s).toFixed(1), images_decodees_par_s:+((b.total-a.total)/s).toFixed(1),
  perdues:b.dropped-a.dropped, avance_media_s:+(b.ct-a.ct).toFixed(1), ecarts_presentedFrames:gaps, erreur:b.err, pause:b.paused}));
ws.close();
