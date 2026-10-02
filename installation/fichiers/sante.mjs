// Santé de la box, en JSON, pour la surveillance à distance (tailnet). Node ≥ 22, aucune dépendance.
//   GET /sante      → JSON complet
//   GET /sante.txt  → résumé lisible (curl depuis un terminal)
// Lecture seule : ce serveur ne commande rien.
import { createServer } from 'node:http';
import { readFileSync, readdirSync, statfsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { hostname, uptime, loadavg, totalmem, freemem } from 'node:os';

const conf = Object.fromEntries(readFileSync('/etc/pxl-kiosk.conf', 'utf8').split('\n')
  .map(l => l.match(/^\s*([A-Z_]+)=("?)(.*)\2\s*$/)).filter(Boolean).map(m => [m[1], m[3]]));
const PORT = +conf.SANTE_PORT || 8790;
const SERVICES = ['pxl-serveur', 'pxl-preview', 'pxl-sante', 'pxl-admin', 'pxl-facade', 'pxl-telecommande', 'pxl-relais', 'seatd', 'chrony', 'tailscaled'];
const lire = f => { try { return readFileSync(f, 'utf8').trim(); } catch { return null; } };

function temperatures() {
  const t = {};
  for (const z of readdirSync('/sys/class/thermal').filter(d => d.startsWith('thermal_zone'))) {
    const v = lire(`/sys/class/thermal/${z}/temp`), n = lire(`/sys/class/thermal/${z}/type`) || z;
    if (v) t[n] = +(v / 1000).toFixed(1);
  }
  return t;
}
function services() {
  const r = {};
  for (const s of SERVICES) {
    try {
      const o = execFileSync('systemctl', ['show', s, '-p', 'ActiveState,SubState,NRestarts,ActiveEnterTimestamp'], { encoding: 'utf8' });
      r[s] = Object.fromEntries(o.trim().split('\n').map(l => l.split(/=(.*)/s).slice(0, 2)));
    } catch { r[s] = null; }
  }
  return r;
}
async function serveurHabillage() {
  const url = `http://127.0.0.1:${conf.APP_PORT || 8765}/api/sante`;
  try { const r = await fetch(url, { signal: AbortSignal.timeout(2000) }); return { ok: r.ok, ...(await r.json()) }; }
  catch (e) { return { ok: false, erreur: e.message }; }
}
async function etat() {
  const d = statfsSync('/');
  return {
    machine: hostname(), heure: new Date().toISOString(), depuis_s: Math.round(uptime()),
    charge: loadavg().map(x => +x.toFixed(2)),
    memoire_mo: { totale: Math.round(totalmem() / 2 ** 20), libre: Math.round(freemem() / 2 ** 20) },
    disque_go: { total: +(d.blocks * d.bsize / 2 ** 30).toFixed(1), disponible: +(d.bavail * d.bsize / 2 ** 30).toFixed(1) },
    temperatures_c: temperatures(),
    gpu: { freq_mhz: Math.round((+lire('/sys/class/devfreq/fde60000.gpu/cur_freq') || 0) / 1e6), charge: lire('/sys/class/devfreq/fde60000.gpu/load') },
    services: services(),
    serveur_habillage: await serveurHabillage(),
  };
}
function resume(e) {
  const s = Object.entries(e.services).map(([k, v]) => `${k}: ${v ? v.ActiveState + (+v.NRestarts ? ` (${v.NRestarts} relances)` : '') : '?'}`);
  return [`${e.machine} — ${e.heure} — en marche depuis ${Math.round(e.depuis_s / 60)} min`,
    `charge ${e.charge.join(' ')} · mémoire libre ${e.memoire_mo.libre}/${e.memoire_mo.totale} Mo · disque ${e.disque_go.disponible}/${e.disque_go.total} Go`,
    `températures ${Object.entries(e.temperatures_c).map(([k, v]) => `${k} ${v}°C`).join(' · ')}`,
    `serveur d'habillage : ${e.serveur_habillage.ok ? 'OK' : 'EN PANNE — ' + (e.serveur_habillage.erreur || '')}`,
    ...s].join('\n') + '\n';
}
createServer(async (req, res) => {
  if (req.url === '/sante' || req.url === '/sante.txt') {
    const e = await etat(), txt = req.url.endsWith('.txt');
    res.writeHead(200, { 'content-type': txt ? 'text/plain; charset=utf-8' : 'application/json' });
    res.end(txt ? resume(e) : JSON.stringify(e, null, 1));
  } else if (req.url === '/admin' || req.url.startsWith('/admin/')) {   // l'administration vit sur son propre service
    const hote = (req.headers.host || '127.0.0.1').replace(/:\d+$/, '');
    res.writeHead(302, { location: `http://${hote}:${+conf.ADMIN_PORT || 8791}/` }); res.end();
  } else { res.writeHead(404); res.end(); }
}).listen(PORT, () => console.log(`santé sur :${PORT}/sante`));
