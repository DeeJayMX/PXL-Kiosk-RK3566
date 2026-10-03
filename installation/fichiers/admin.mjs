// Administration de la box, par le navigateur : réseau (Ethernet, Wi-Fi), heure (serveurs NTP locaux, mise à l'heure),
// machine (services, journal, redémarrage). Node ≥ 22, aucune dépendance. Page : admin.html, à côté de ce fichier.
//
//   node admin.mjs              le service (pxl-admin.service, en root : nmcli, chronyc, date, systemctl)
//   node admin.mjs --mdp        lit un mot de passe sur l'entrée standard et écrit son empreinte (pxl-kiosk mdp-admin)
//   node admin.mjs --retour F   remet le réglage réseau sauvé dans F — lancé par un minuteur systemd quand personne
//                               n'a confirmé un changement à temps (voir RETOUR_S)
//
// Sécurité : mot de passe dédié, haché (scrypt) dans /etc/pxl-kiosk/admin.mdp ; session par cookie signé (HttpOnly,
// SameSite=Strict) ; toute écriture exige l'en-tête x-pxl-admin (une page d'un autre site ne peut pas le poser) ;
// 5 essais ratés ⇒ 60 s d'attente pour cette adresse. Aucune commande n'est composée par un shell : execFile seulement,
// et chaque valeur est vérifiée avant de partir (adresses, noms, SSID).
//
// Écritures sur la carte SD : seulement quand on ENREGISTRE un réglage (décision du 02/10/2026 : le minimum d'écritures).
import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync, renameSync, chmodSync, readdirSync } from 'node:fs';
import { randomBytes, randomUUID, scryptSync, timingSafeEqual, createHmac, createHash } from 'node:crypto';
import { hostname, uptime, release } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import * as maj from './maj.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));
const MDP = '/etc/pxl-kiosk/admin.mdp';
const RUN = '/run/pxl-admin';
const RETOUR = `${RUN}/retour.json`;
const RETOUR_S = 90;                       // délai pour confirmer un changement réseau, sinon retour à l'ancien réglage
const NTP_LOCAUX = '/etc/chrony/sources.d/pxl-local.sources';
const NM_DIR = '/etc/NetworkManager/system-connections';
const PROFIL_ETH = 'pxl-ethernet';
const JOURNAUX = ['pxl-maj-box', 'pxl-serveur', 'pxl-preview', 'pxl-admin', 'pxl-sante', 'chrony', 'NetworkManager', 'tailscaled'];
const RELANCABLES = ['pxl-serveur', 'pxl-preview'];

const lireConf = () => { try { return Object.fromEntries(readFileSync('/etc/pxl-kiosk.conf', 'utf8').split('\n')
  .map(l => l.match(/^\s*([A-Z_]+)=("?)(.*)\2\s*$/)).filter(Boolean).map(m => [m[1], m[3]])); } catch { return {}; } };
const conf = lireConf();
const PORT = +conf.ADMIN_PORT || 8791;

// ---------------------------------------------------------------- commandes (jamais de shell)
const run = (cmd, args, { timeout = 20000 } = {}) => new Promise(res =>
  execFile(cmd, args, { timeout, maxBuffer: 4e6, env: { ...process.env, LC_ALL: 'C' } },
    (e, out, err) => res({ ok: !e, out: String(out || ''), err: String(err || (e && e.message) || '').trim() })));
const lire = f => { try { return readFileSync(f, 'utf8').trim(); } catch { return null; } };
// nmcli -t : champs séparés par « : », les « : » des valeurs échappés en « \: »
const champs = l => l.split(/(?<!\\):/).map(s => s.replace(/\\(.)/g, '$1'));
const nmVal = v => (v == null || v === '--') ? '' : v;

// ---------------------------------------------------------------- vérification des valeurs
const IPV4 = /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;
const estIp = s => IPV4.test(String(s || '').trim());
const estHote = s => /^(?=.{1,253}$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/i.test(String(s || '').trim());
function prefixe(m) {   // « 24 » ou « 255.255.255.0 » → 24
  m = String(m || '').trim().replace(/^\//, '');
  if (/^\d{1,2}$/.test(m) && +m <= 32) return +m;
  if (!estIp(m)) return null;
  const bits = m.split('.').map(n => (+n).toString(2).padStart(8, '0')).join('');
  return /^1*0*$/.test(bits) ? bits.indexOf('0') === -1 ? 32 : bits.indexOf('0') : null;
}
const liste = s => String(s || '').split(/[\s,;]+/).map(x => x.trim()).filter(Boolean);
class Refus extends Error {}
const exiger = (cond, msg) => { if (!cond) throw new Refus(msg); };

// ---------------------------------------------------------------- mot de passe et sessions
function empreinte(mdp) {
  const sel = randomBytes(16);
  return `scrypt$${sel.toString('base64')}$${scryptSync(mdp, sel, 32).toString('base64')}`;
}
function verifierMdp(mdp) {
  const e = lire(MDP); if (!e) return false;
  const [algo, sel, h] = e.split('$'); if (algo !== 'scrypt') return false;
  const attendu = Buffer.from(h, 'base64'), calcule = scryptSync(String(mdp), Buffer.from(sel, 'base64'), attendu.length);
  return timingSafeEqual(attendu, calcule);
}
function ecrireMdp(mdp) {
  exiger(String(mdp).length >= 8, 'mot de passe trop court (8 caractères au moins)');
  mkdirSync(dirname(MDP), { recursive: true });
  writeFileSync(MDP + '.part', empreinte(String(mdp)) + '\n', { mode: 0o600 }); chmodSync(MDP + '.part', 0o600); renameSync(MDP + '.part', MDP);
}
const CLE = randomBytes(32);                        // un redémarrage du service déconnecte : voulu
const DUREE_SESSION = 12 * 3600e3;
const signer = s => createHmac('sha256', CLE).update(s).digest('base64url');
const jeton = () => { const exp = String(Date.now() + DUREE_SESSION); return `${exp}.${signer(exp)}`; };
function sessionValide(req) {
  const c = (req.headers.cookie || '').split(/;\s*/).find(x => x.startsWith('pxladmin='));
  if (!c) return false;
  const [exp, sig] = c.slice(9).split('.');
  if (!exp || !sig || +exp < Date.now()) return false;
  const a = Buffer.from(sig), b = Buffer.from(signer(exp));
  return a.length === b.length && timingSafeEqual(a, b);
}
const essais = new Map();   // adresse → { n, jusqua }

// ---------------------------------------------------------------- état
async function ethernet() {
  const r = await run('nmcli', ['-t', '-f', 'NAME,UUID,TYPE,AUTOCONNECT,DEVICE,FILENAME', 'con', 'show']);
  const profils = r.out.trim().split('\n').filter(Boolean).map(champs)
    .filter(([, , t]) => t === '802-3-ethernet').map(([nom, uuid, , auto, dev, f]) => ({ nom, uuid, auto: auto === 'yes', dev,
      // permanent : un fichier de /etc, ou un profil netplan (Ubuntu : NetworkManager écrit /etc/netplan/90-NM-<uuid>.yaml et
      // n'en montre que la copie générée, /run/…/netplan-NM-<uuid>.nmconnection — mesuré le 02/10)
      permanent: (f || '').startsWith('/etc/') || /\/netplan-/.test(f || '') }));
  // Seul un profil permanent est le NÔTRE. Les autres de /run sont temporaires (mesuré le 02/10) : « Wired connection 1 »
  // est le DHCP automatique d'Ubuntu, et « eth0 » naît quand la veille de secours pose son adresse hors de NetworkManager.
  // Les modifier ne survivrait pas à un redémarrage. Au premier réglage, on crée donc « pxl-ethernet » (voir regleEthernet).
  const p = profils.find(x => x.permanent && x.nom === PROFIL_ETH) || profils.find(x => x.permanent) || null;
  let ipv4 = { method: 'auto', addresses: '', gateway: '', dns: '' };
  if (p) {
    const s = await run('nmcli', ['-t', '-f', 'ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns', 'con', 'show', p.uuid]);
    ipv4 = Object.fromEntries(s.out.trim().split('\n').filter(Boolean).map(l => { const i = l.indexOf(':'); return [l.slice(0, i).replace('ipv4.', ''), nmVal(l.slice(i + 1))]; }));
  }
  return { profil: p, ipv4, cable: lire('/sys/class/net/eth0/carrier') === '1',
    secours: (conf.SECOURS_ADR || lire('/etc/default/pxl-secours-reseau')?.match(/SECOURS_ADR=(\S+)/)?.[1] || null) };
}
async function wifi() {
  const [c, v] = await Promise.all([
    run('nmcli', ['-t', '-f', 'NAME,UUID,TYPE,AUTOCONNECT,AUTOCONNECT-PRIORITY,ACTIVE,FILENAME', 'con', 'show']),
    run('nmcli', ['-t', '-f', 'IN-USE,SSID,SIGNAL', 'dev', 'wifi', 'list', '--rescan', 'no']),
  ]);
  const signal = Object.fromEntries(v.out.trim().split('\n').filter(Boolean).map(champs).map(([, s, sig]) => [s, +sig]));
  const connus = c.out.trim().split('\n').filter(Boolean).map(champs).filter(x => x[2] === '802-11-wireless' && x[6])
    .map(([nom, uuid, , auto, prio, actif]) => ({ nom, uuid, auto: auto === 'yes', priorite: +prio || 0, actif: actif === 'yes', signal: signal[nom] ?? null }))
    .sort((a, b) => b.priorite - a.priorite);
  return { connus };
}
async function heure() {
  const [t, s] = await Promise.all([run('chronyc', ['-n', 'tracking']), run('chronyc', ['-c', '-n', 'sources'])]);
  const tr = Object.fromEntries(t.out.split('\n').map(l => l.split(/\s+:\s+/)).filter(x => x.length === 2).map(([k, v]) => [k.trim(), v.trim()]));
  const ETATS = { '*': 'utilisée', '+': 'combinée', '-': 'en réserve', '?': 'injoignable', x: 'en désaccord', '~': 'trop instable' };
  const locaux = lireNtpLocaux();
  const sources = s.out.trim().split('\n').filter(Boolean).map(l => l.split(',')).map(([mode, etat, adr, strate, , reach, dernier, , decalage]) => ({
    adresse: adr, etat: ETATS[etat] || etat, utilisee: etat === '*', strate: +strate, joignable: reach !== '0',
    dernier_s: +dernier, decalage_ms: decalage != null ? Math.round(+decalage * 1e6) / 1e3 : null, local: locaux.includes(adr), mode }));
  // « 0.000000115 seconds slow of NTP time » → « −0,000 ms » (la box retarde = négatif)
  const m = (tr['System time'] || '').match(/^([\d.]+) seconds (slow|fast)/);
  const ecart = m ? `${m[2] === 'slow' ? '−' : '+'}${(+m[1] * 1e3).toLocaleString('fr-FR', { maximumFractionDigits: 3 })} ms` : null;
  return { synchro: tr['Leap status'] === 'Normal', reference: tr['Reference ID'] || null, ecart,
    maintenant: Date.now(), fuseau: lire('/etc/timezone'), sources, locaux };
}
function lireNtpLocaux() {
  return (lire(NTP_LOCAUX) || '').split('\n').map(l => l.match(/^\s*server\s+(\S+)/)).filter(Boolean).map(m => m[1]);
}
async function reseau() {
  const [a, r, d] = await Promise.all([run('ip', ['-j', '-4', 'addr']), run('ip', ['-j', 'route', 'show', 'default']), run('resolvectl', ['dns'])]);
  let adresses = [], routes = [];
  try { adresses = JSON.parse(a.out).filter(i => i.ifname !== 'lo').map(i => ({ nom: i.ifname, etat: i.operstate,
    adresses: (i.addr_info || []).map(x => `${x.local}/${x.prefixlen}`) })); } catch {}
  try { routes = JSON.parse(r.out).map(x => ({ via: x.gateway, dev: x.dev, metrique: x.metric })); } catch {}
  const dns = [...new Set(d.out.split('\n').flatMap(l => (l.split(':')[1] || '').trim().split(/\s+/)).filter(estIp))];
  let internet = false;
  try { internet = (await fetch('http://connectivity-check.ubuntu.com/', { signal: AbortSignal.timeout(3000) })).status === 204; } catch {}
  const ts = await run('tailscale', ['ip', '-4'], { timeout: 4000 });
  return { adresses, routes, dns, internet, tailscale: ts.ok ? ts.out.trim() : null };
}
// ---------------------------------------------------------------- versions : chaque morceau dit ce qu'il est
// recette (ce dépôt, installation/VERSION, recopiée par installer.sh dans /etc/pxl-kiosk/version), application
// (VERSION à sa racine), image, et les briques du système. Chromium est lu une fois : la commande coûte ~1 s.
let chromiumV = null;
async function versions() {
  if (chromiumV == null) { const r = await run('chromium', ['--version'], { timeout: 8000 }); chromiumV = (r.out.match(/[\d.]{5,}/) || [''])[0]; }
  const recette = Object.fromEntries((lire('/etc/pxl-kiosk/version') || '').split('\n').map(l => l.split(/=(.*)/s).slice(0, 2)).filter(x => x[1]));
  return { recette: recette.recette || null, installee: recette.installee || null, appli: lire(join(APP_DIR, 'VERSION')),
    image: lire('/etc/pxl-kiosk/image'), noyau: release(), node: process.version.slice(1), chromium: chromiumV || null };
}

// ---------------------------------------------------------------- mode du serveur d'habillage
// Course (config.json) · Démo (config.demo.json, un trail terminé) · Répétition (config.chaumont2025.json, l'édition
// 2025 rejouée depuis une heure choisie : REJOUER/VITESSE, voir serveur.js). Chaque config a son propre fichier
// d'état : une démo ne touche pas aux réglages de la course.
// 🔴 Posé en drop-in d'EXÉCUTION (/run) : il disparaît au redémarrage, la box repart TOUJOURS en mode Course — une
// répétition oubliée ne peut pas se retrouver à l'antenne le jour J. Et rien n'est écrit sur la carte SD.
const APP_DIR = conf.APP_DIR || '/opt/pxl-app';
const MODE_DIR = '/run/systemd/system/pxl-serveur.service.d', MODE_F = `${MODE_DIR}/pxl-mode.conf`;
const MODES = { demo: 'config.demo.json', repetition: 'config.chaumont2025.json' };
const VITESSES = [1, 2, 5, 10, 30, 60];
function mode() {
  const dispo = Object.fromEntries(Object.entries(MODES).map(([m, f]) => [m, existsSync(join(APP_DIR, f))]));
  let m = { mode: 'course' };
  try { m = JSON.parse((readFileSync(MODE_F, 'utf8').match(/^# pxl-mode (.*)$/m) || [])[1]); } catch {}
  return { ...m, disponibles: dispo, vitesses: VITESSES };
}
async function regleMode(q) {
  if (q.mode === 'course') { try { unlinkSync(MODE_F); } catch {} }
  else {
    exiger(MODES[q.mode], 'mode inconnu'); exiger(existsSync(join(APP_DIR, MODES[q.mode])), `${MODES[q.mode]} absent de l'application`);
    const info = { mode: q.mode, depuis: new Date().toISOString() };
    const lignes = ['[Service]', 'ExecStart=', `ExecStart=${existsSync('/opt/node/bin/node') ? '/opt/node/bin/node' : process.execPath} serveur.js ${MODES[q.mode]}`];
    if (q.mode === 'repetition') {
      // heure saisie « 2025-10-11T19:50 » : heure LOCALE de la box (Europe/Paris), celle de la course
      exiger(/^\d{4}-\d\d-\d\dT\d\d:\d\d$/.test(q.rejouer || ''), 'heure de départ invalide');
      const t = new Date(q.rejouer); exiger(t > new Date('2020-01-01') && t < new Date('2100-01-01'), 'heure de départ invalide');
      const v = +q.vitesse; exiger(VITESSES.includes(v), 'vitesse invalide');
      Object.assign(info, { rejouer: q.rejouer, vitesse: v });
      lignes.push(`Environment=REJOUER=${t.toISOString()} VITESSE=${v}`);
    } else lignes.push('UnsetEnvironment=REJOUER VITESSE');
    mkdirSync(MODE_DIR, { recursive: true });
    writeFileSync(MODE_F, `# pxl-mode ${JSON.stringify(info)}\n# posé par /admin — disparaît au redémarrage (retour au mode Course)\n${lignes.join('\n')}\n`);
  }
  await run('systemctl', ['daemon-reload']);
  const r = await run('systemctl', ['restart', 'pxl-serveur']); exiger(r.ok, r.err);
  return {};
}

// ---------------------------------------------------------------- sortie HDMI du PXLnode (résolution physique)
// Gardée dans /etc/pxl-kiosk.conf (SORTIE_MODE) : installer.sh la relit et régénère weston.ini — un réglage fait ici
// survit donc à une réinstallation. On réécrit aussi la ligne mode= de weston.ini tout de suite, puis on relance
// pxl-preview (Weston relit sa sortie à son démarrage). 720p : Chromium dessine 2,25× moins de pixels qu'en 1080p.
// CE QUI s'affiche (Preview / Multiview) se choisit dans la console de l'habillage (⚙ Réglages) : la box ouvre /ecran.
const CONF = '/etc/pxl-kiosk.conf', WESTON_INI = '/etc/pxl-kiosk/weston.ini';
// « i » = entrelacé : Weston ne sait pas le choisir, pxl-mode le pose avant lui (preview.sh) et weston.ini dit « current »
const MODES_HDMI = ['1280x720@25', '1280x720@50', '1920x1080@25', '1920x1080@50', '1920x1080i@50'];
// En entrelacé : « 50i » (Weston à la trame, mouvement fluide à l'écran) ou « psf » (Weston à l'IMAGE, 25 img/s : chaque
// image tient ses deux trames, donc écran ET flux writeback propres en mouvement — preview.sh pose PXL_PSF=1).
const ENTRELACES = ['50i', 'psf'];
const ecran = () => { const c = lireConf();
  return { mode: c.SORTIE_MODE || null, modes: MODES_HDMI, entrelace: ENTRELACES.includes(c.ENTRELACE) ? c.ENTRELACE : 'psf', entrelaces: ENTRELACES }; };
const poserLigne = (texte, cle, valeur) => { const re = new RegExp(`^\\s*${cle}=.*$`, 'm'), l = `${cle}=${valeur}`;
  return re.test(texte) ? texte.replace(re, l) : texte.replace(/\n?$/, '\n') + l + '\n'; };
const ecrireAtomique = (f, t) => { writeFileSync(f + '.part', t); renameSync(f + '.part', f); };
async function regleEcran(q) {
  exiger(MODES_HDMI.includes(q.mode), 'mode HDMI inconnu');
  exiger(q.entrelace === undefined || ENTRELACES.includes(q.entrelace), 'cadence d\'entrelacé inconnue');
  let conf = poserLigne(readFileSync(CONF, 'utf8'), 'SORTIE_MODE', q.mode);
  if (q.entrelace !== undefined) conf = poserLigne(conf, 'ENTRELACE', q.entrelace);
  ecrireAtomique(CONF, conf);
  if (existsSync(WESTON_INI)) ecrireAtomique(WESTON_INI, poserLigne(readFileSync(WESTON_INI, 'utf8'), 'mode', q.mode.includes('i@') ? 'current' : q.mode));
  const r = await run('systemctl', ['restart', 'pxl-preview']); exiger(r.ok, r.err);
  return {};
}

// ---------------------------------------------------------------- flux TurboHQ de la sortie HDMI (service pxl-wb)
// Weston patché écrit l'image du HDMI (writeback du VOP2) dans des tampons que l'encodeur MPP lit SANS COPIE, puis
// thq-publish l'envoie à un relais TurboHQ. Réglages dans /etc/pxl-kiosk.conf (WB_*), comme la sortie HDMI.
const WB_FPS = [25, 30, 50];
async function wb() {
  const c = lireConf();
  const act = (await run('systemctl', ['is-active', 'pxl-wb'])).out.trim();
  const j = await run('journalctl', ['-u', 'pxl-wb', '-n', '40', '--no-pager', '-o', 'cat']);
  const lignes = j.out.split('\n').filter(l => /pxl-wb-enc :|thq|pxl-wb :/.test(l));
  const stats = [...lignes].reverse().find(l => /img\/s ·/.test(l)) || null;
  const patche = !!lire('/etc/pxl-kiosk/weston-pxl');
  const client = existsSync('/usr/local/lib/pxl-kiosk/turbohq-client/bin/thq-publish.js');
  return { actif: c.WB_ACTIF === '1', url: c.WB_URL || 'ws://127.0.0.1:8080', canal: c.WB_CANAL || 'pxlnode',
    fps: +(c.WB_FPS || 25), debit: +(c.WB_DEBIT || 6000), service: act, stats, derniere: lignes.slice(-1)[0] || null,
    patche, client, fpsPossibles: WB_FPS };
}
async function regleWb(q) {
  const actif = q.actif === '1' || q.actif === true || q.actif === 'true';
  const url = String(q.url || '').trim(), canal = String(q.canal || '').trim();
  exiger(/^wss?:\/\/[^\s"'`$\\]+$/.test(url), 'adresse du relais invalide (ws://hôte:port)');
  exiger(/^[A-Za-z0-9_.-]{1,40}$/.test(canal), 'nom de canal invalide (lettres, chiffres, - _ .)');
  const fps = +q.fps, debit = Math.round(+q.debit);
  exiger(WB_FPS.includes(fps), 'cadence invalide'); exiger(debit >= 500 && debit <= 20000, 'débit entre 500 et 20000 kbit/s');
  exiger(!actif || lire('/etc/pxl-kiosk/weston-pxl'), 'Weston patché absent : refaire la mise à jour « box »');
  exiger(!actif || existsSync('/usr/local/lib/pxl-kiosk/turbohq-client/bin/thq-publish.js'), 'client TurboHQ absent sur la box (/usr/local/lib/pxl-kiosk/turbohq-client)');
  let t = readFileSync(CONF, 'utf8');
  for (const [k, v] of [['WB_ACTIF', actif ? 1 : 0], ['WB_URL', `"${url}"`], ['WB_CANAL', canal], ['WB_FPS', fps], ['WB_DEBIT', debit]])
    t = poserLigne(t, k, v);
  ecrireAtomique(CONF, t);
  const r = actif ? await run('systemctl', ['enable', '--now', 'pxl-wb']).then(async x => x.ok ? run('systemctl', ['restart', 'pxl-wb']) : x)
    : await run('systemctl', ['disable', '--now', 'pxl-wb']);
  exiger(r.ok, r.err);
  return {};
}

async function machine() {
  const etats = {};
  for (const s of [...RELANCABLES, 'pxl-sante', 'pxl-facade', 'pxl-telecommande', 'pxl-relais', 'seatd', 'chrony', 'tailscaled', 'pxl-admin']) {
    const r = await run('systemctl', ['show', s, '-p', 'ActiveState,NRestarts']);
    etats[s] = Object.fromEntries(r.out.trim().split('\n').map(l => l.split(/=(.*)/s).slice(0, 2)));
  }
  return { nom: hostname(), depuis_s: Math.round(uptime()), image: lire('/etc/pxl-kiosk/image'), services: etats };
}
// Matériel, mesuré sur la box le 02/10 : deux sondes de température (SoC, GPU) avec les seuils du noyau ; le bridage
// thermique (cooling devices) ; les fréquences. Pas de tensions : AUCUNE n'est mesurée sur cette box (la saradc n'est
// reliée à rien qui mesure l'alimentation, pas de détection de sous-tension) — les régulateurs n'exposent que leur
// consigne, et l'afficher ressemblerait à un relevé (retiré le 02/10, à la demande d'Eliott).
const lireNb = f => { const v = lire(f); return v == null || v === '' || isNaN(+v) ? null : +v; };
const dossiers = d => { try { return readdirSync(d).map(x => join(d, x)); } catch { return []; } };
function materiel() {
  const temperatures = dossiers('/sys/class/thermal').filter(z => /thermal_zone\d+$/.test(z)).map(z => {
    // seuils typés : « passive » = le noyau commence à brider, « critical » = coupure d'urgence (le GPU n'a que celui-là)
    const seuils = dossiers(z).filter(f => /trip_point_\d+_temp$/.test(f)).map(f => ({
      type: lire(f.replace(/_temp$/, '_type')), c: lireNb(f) / 1000 })).sort((x, y) => x.c - y.c);
    const premier = t => (seuils.find(x => x.type === t) || {}).c ?? null;
    return { nom: (lire(`${z}/type`) || '').replace(/-thermal$/, ''), c: (lireNb(`${z}/temp`) ?? NaN) / 1000,
      bridage: premier('passive'), coupure: premier('critical') };
  }).filter(t => isFinite(t.c));
  const bridage = dossiers('/sys/class/thermal').filter(z => /cooling_device\d+$/.test(z)).map(z => ({
    nom: (lire(`${z}/type`) || '').replace(/^(devfreq-|cpufreq-)/, '').replace(/^fde60000\.gpu$/, 'GPU').replace(/^cpu0$/, 'CPU')
      .replace(/^fdf40000\.rkvenc$/, 'encodeur vidéo').replace(/^fdf80200\.rkvdec$/, 'décodeur vidéo'),
    niveau: lireNb(`${z}/cur_state`), max: lireNb(`${z}/max_state`) }));
  const freq = f => { const v = lireNb(f); return v == null ? null : v; };
  return {
    temperatures, bridage,
    cpu_mhz: (freq('/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq') ?? 0) / 1e3,
    cpu_max_mhz: (freq('/sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq') ?? 0) / 1e3,
    gpu_mhz: (freq('/sys/class/devfreq/fde60000.gpu/cur_freq') ?? 0) / 1e6,
  };
}
// ---------------------------------------------------------------- surveillance : carte SD, liaisons, HDMI, preview
// Écritures sur la carte depuis le démarrage (champ 7 de /sys/block/<dev>/stat, en secteurs de 512 o), et rythme moyen
// sur les 30 dernières minutes : c'est le témoin de la règle « le minimum d'écritures » (02/10). ⚠️ Pas sur une fenêtre
// courte : ext4 (commit=600) n'écrit que par paquets toutes les 10 min, une fenêtre de quelques secondes affiche 0 ou un pic.
const echantillons = [];   // { t, octets }, relevés à chaque lecture de l'état, gardés 30 min
function carteSd() {
  const dev = 'mmcblk0', st = (lire(`/sys/block/${dev}/stat`) || '').split(/\s+/);
  const octets = +st[6] * 512, t = Date.now();
  echantillons.push({ t, octets });
  while (echantillons.length > 1 && t - echantillons[1].t >= 30 * 60e3) echantillons.shift();
  const ancien = echantillons[0], fenetre = t - ancien.t;
  return { ecrit_o: octets, depuis_s: Math.round(uptime()),
    rythme_o_min: fenetre >= 60e3 ? Math.max(0, octets - ancien.octets) / (fenetre / 60e3) : null, fenetre_min: Math.round(fenetre / 60e3),
    fabrication: lire(`/sys/block/${dev}/device/date`), nom: lire(`/sys/block/${dev}/device/name`) };
}
// échantillon toutes les 5 min même sans page ouverte : le rythme est disponible dès la première visite
setInterval(() => { if (process.argv.length <= 2) carteSd(); }, 5 * 60e3).unref();
async function liaisons() {
  const w = await run('iw', ['dev', 'wlan0', 'link'], { timeout: 4000 });
  const v = re => (w.out.match(re) || [])[1];
  const freq = +v(/freq:\s*([\d.]+)/);
  const wifi = /Connected to/.test(w.out) ? { ssid: v(/SSID:\s*(.+)/), signal_dbm: +v(/signal:\s*(-?\d+)/),
    reception_mbit: +v(/rx bitrate:\s*([\d.]+)/), emission_mbit: +v(/tx bitrate:\s*([\d.]+)/),
    bande: freq ? (freq > 5900 ? '6 GHz' : freq > 4000 ? '5 GHz' : '2,4 GHz') : null } : null;
  const cable = lire('/sys/class/net/eth0/carrier') === '1', vitesse = lireNb('/sys/class/net/eth0/speed');
  return { wifi, ethernet: { cable, vitesse_mbit: cable && vitesse > 0 ? vitesse : null, duplex: cable ? lire('/sys/class/net/eth0/duplex') : null } };
}
function hdmi() {
  const c = '/sys/class/drm/card0-HDMI-A-1', branche = lire(`${c}/status`) === 'connected';
  let ecran = null;
  try {   // EDID : fabricant (3 lettres sur 15 bits, octets 8-9) + nom (descripteur 0xFC)
    const e = readFileSync(`${c}/edid`);
    if (e.length >= 128) {
      const m = e.readUInt16BE(8), lettre = n => String.fromCharCode(64 + (n & 31));
      let nom = '';
      for (let o = 54; o < 126; o += 18) if (e[o] === 0 && e[o + 1] === 0 && e[o + 3] === 0xfc) nom = e.subarray(o + 5, o + 18).toString('latin1').replace(/\n.*$/s, '').trim();
      ecran = `${lettre(m >> 10)}${lettre(m >> 5)}${lettre(m)}${nom ? ' ' + nom : ''}`;
    }
  } catch {}
  const resume = lire('/sys/kernel/debug/dri/0/summary') || '';
  const mode = (resume.match(/Display mode:\s*(\S+)/) || [])[1] || null;
  // débranchements vus par Weston depuis le lancement de la preview (son journal est en RAM, dans /run)
  const log = lire('/run/pxl-preview/weston.log') || '';
  return { branche, ecran, mode, debranchements: (log.match(/is disconnected/g) || []).length };
}
// Images par seconde RÉELLES de la page affichée : requestAnimationFrame compté pendant 1 s, par DevTools (:9222, local)
async function preview() {
  try {
    const cibles = await (await fetch('http://127.0.0.1:9222/json', { signal: AbortSignal.timeout(1500) })).json();
    const p = cibles.find(t => t.type === 'page'); if (!p) return { page: null };
    const ws = new WebSocket(p.webSocketDebuggerUrl);
    const ips = await new Promise((res, rej) => {
      const t = setTimeout(() => { ws.close(); rej(new Error('délai')); }, 4000);
      ws.onerror = () => { clearTimeout(t); rej(new Error('DevTools')); };
      ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id === 1) { clearTimeout(t); ws.close(); res(m.result?.result?.value); } };
      ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { awaitPromise: true, returnByValue: true,
        expression: 'new Promise(r=>{let n=0;const t0=performance.now();const f=()=>{n++;performance.now()-t0<1000?requestAnimationFrame(f):r(n*1000/(performance.now()-t0))};requestAnimationFrame(f)})' } }));
    });
    return { page: p.url, ips: Math.round(ips * 10) / 10 };
  } catch (e) { return { page: null, erreur: e.message }; }
}
async function surveillance() {
  const [l, p] = await Promise.all([liaisons(), preview()]);
  return { sd: carteSd(), ...l, hdmi: hdmi(), preview: p };
}
function retourEnCours() {
  try { const r = JSON.parse(readFileSync(RETOUR, 'utf8')); return { quoi: r.quoi, expire: r.expire }; } catch { return null; }
}

// ---------------------------------------------------------------- changements réseau, avec retour automatique
async function armerRetour(sauve) {
  mkdirSync(RUN, { recursive: true });
  await run('systemctl', ['stop', 'pxl-admin-retour.timer', 'pxl-admin-retour.service']);
  await run('systemctl', ['reset-failed', 'pxl-admin-retour.service', 'pxl-admin-retour.timer']);
  writeFileSync(RETOUR, JSON.stringify({ ...sauve, expire: Date.now() + RETOUR_S * 1e3 }), { mode: 0o600 });
  // minuteur systemd et non setTimeout : le retour a lieu même si ce service tombe entre-temps
  const r = await run('systemd-run', ['--unit=pxl-admin-retour', `--on-active=${RETOUR_S}`, '--timer-property=AccuracySec=1s',
    process.execPath, fileURLToPath(import.meta.url), '--retour', RETOUR]);
  if (!r.ok) throw new Error(`minuteur de retour impossible : ${r.err}`);
}
async function confirmer() {
  await run('systemctl', ['stop', 'pxl-admin-retour.timer']);
  try { unlinkSync(RETOUR); } catch {}
}
async function revenir(fichier) {   // remet le réglage d'avant (appelé par le minuteur, ou par « Annuler maintenant »)
  let r; try { r = JSON.parse(readFileSync(fichier, 'utf8')); } catch { return; }
  if (r.quoi === 'ethernet') {
    const cable = lire('/sys/class/net/eth0/carrier') === '1';
    if (r.cree) {   // le profil n'existait pas avant : on le retire, le DHCP automatique d'Ubuntu reprend la main
      await run('nmcli', ['con', 'delete', r.uuid]);
      if (cable) await run('nmcli', ['dev', 'connect', 'eth0'], { timeout: 40000 });
    } else {
      const a = r.avant;
      await run('nmcli', ['con', 'modify', r.uuid, 'ipv4.method', a.method || 'auto', 'ipv4.addresses', a.addresses || '',
        'ipv4.gateway', a.gateway || '', 'ipv4.dns', a.dns || '']);
      if (cable) await run('nmcli', ['con', 'up', r.uuid], { timeout: 40000 });
    }
  } else if (r.quoi === 'wifi' && r.avant) {
    await run('nmcli', ['con', 'up', r.avant], { timeout: 40000 });
  }
  try { unlinkSync(fichier); } catch {}
}

async function regleEthernet(q) {
  // 1. vérifier la demande AVANT de toucher à quoi que ce soit (sinon un refus laisse un profil créé derrière lui — vécu)
  const reglage = [];
  if (q.mode === 'dhcp') reglage.push('ipv4.method', 'auto', 'ipv4.addresses', '', 'ipv4.gateway', '', 'ipv4.dns', '');
  else {
    exiger(q.mode === 'fixe', 'mode inconnu');
    exiger(estIp(q.adresse), 'adresse IP invalide');
    const p = prefixe(q.masque); exiger(p != null && p >= 8 && p <= 30, 'masque invalide (ex. 24 ou 255.255.255.0)');
    exiger(!q.passerelle || estIp(q.passerelle), 'passerelle invalide');
    const dns = liste(q.dns); exiger(dns.every(estIp), 'DNS invalide (adresses IP séparées par des espaces)');
    reglage.push('ipv4.method', 'manual', 'ipv4.addresses', `${q.adresse.trim()}/${p}`, 'ipv4.gateway', (q.passerelle || '').trim(), 'ipv4.dns', dns.join(','));
  }
  // 2. le profil : le nôtre s'il existe ; au premier réglage, on le crée, prioritaire sur le DHCP automatique d'Ubuntu
  const e = await ethernet();
  let profil = e.profil, cree = false;
  if (!profil) {
    exiger(q.mode !== 'dhcp', 'déjà en automatique (DHCP) : rien à changer');
    const c = await run('nmcli', ['con', 'add', 'type', 'ethernet', 'ifname', 'eth0', 'con-name', PROFIL_ETH,
      'connection.autoconnect', 'yes', 'connection.autoconnect-priority', '100', 'ipv4.route-metric', '100']);
    exiger(c.ok, `profil Ethernet impossible à créer : ${c.err}`);
    profil = (await ethernet()).profil; exiger(profil, 'profil Ethernet introuvable après création'); cree = true;
  }
  const args = ['con', 'modify', profil.uuid, ...reglage];
  await armerRetour({ quoi: 'ethernet', uuid: profil.uuid, cree, avant: e.ipv4 });
  const m = await run('nmcli', args);
  if (!m.ok) { await run('systemctl', ['stop', 'pxl-admin-retour.timer']); await revenir(RETOUR); throw new Refus(`refusé par NetworkManager : ${m.err}`); }
  if (e.cable) { const u = await run('nmcli', ['con', 'up', profil.uuid], { timeout: 40000 }); if (!u.ok) return { avertissement: `enregistré, mais l'activation a échoué : ${u.err}` }; }
  else return { avertissement: 'enregistré — aucun câble branché : le réglage s\'appliquera au branchement' };
  return {};
}
function echapperCle(s) { return String(s).replace(/\\/g, '\\\\'); }   // fichier clé de NetworkManager (format GLib)
async function ajouterWifi(q) {
  const ssid = String(q.ssid || ''), psk = String(q.psk || '');
  exiger(ssid.length >= 1 && Buffer.byteLength(ssid) <= 32 && !/[\x00-\x1f\x7f]/.test(ssid), 'SSID invalide');
  exiger(psk === '' || (/^[\x20-\x7e]{8,63}$/.test(psk) || /^[0-9a-f]{64}$/i.test(psk)), 'mot de passe Wi-Fi invalide (8 à 63 caractères)');
  const prio = Math.max(-999, Math.min(999, Math.round(+q.priorite || 0)));
  const nom = `pxl-wifi-${createHash('sha1').update(ssid).digest('hex').slice(0, 10)}.nmconnection`, f = join(NM_DIR, nom);
  // fichier écrit directement (et non `nmcli … wifi-sec.psk <mdp>`) : le mot de passe ne passe jamais dans une ligne de commande
  const contenu = [`[connection]`, `id=${echapperCle(ssid)}`, `uuid=${randomUUID()}`, 'type=wifi', 'interface-name=wlan0', 'autoconnect=true',
    `autoconnect-priority=${prio}`, '', '[wifi]', 'mode=infrastructure', `ssid=${echapperCle(ssid)}`, '',
    ...(psk ? ['[wifi-security]', 'key-mgmt=wpa-psk', `psk=${echapperCle(psk)}`, ''] : []),
    '[ipv4]', 'method=auto', 'route-metric=600', '', '[ipv6]', 'method=auto', ''].join('\n');
  writeFileSync(f, contenu, { mode: 0o600 }); chmodSync(f, 0o600);
  const r = await run('nmcli', ['con', 'load', f]);
  if (!r.ok) { try { unlinkSync(f); } catch {} throw new Refus(`refusé par NetworkManager : ${r.err}`); }
  return {};
}
async function wifiParUuid(uuid) {
  const w = await wifi(), c = w.connus.find(x => x.uuid === uuid);
  exiger(c, 'réseau Wi-Fi inconnu'); return { w, c };
}

// ---------------------------------------------------------------- mises à jour : une à la fois, refus lisibles
let majEnCours = false;
const enRefus = pr => pr.catch(e => { throw e instanceof maj.Refus ? new Refus(e.message) : e; });
async function uneMaj(f) {
  exiger(!majEnCours, 'une mise à jour est déjà en cours');
  majEnCours = true; try { return await enRefus(f()); } finally { majEnCours = false; }
}

// ---------------------------------------------------------------- routes
async function api(req, u, q) {
  const p = u.pathname;
  if (p === '/api/etat') {
    const [r, e, w, h, m, s, v] = await Promise.all([reseau(), ethernet(), wifi(), heure(), machine(), surveillance(), versions()]);
    return { reseau: r, ethernet: e, wifi: w, heure: h, machine: m, materiel: materiel(), surveillance: s, versions: v, mode: mode(), ecran: ecran(), wb: await wb(), retour: retourEnCours(), retour_s: RETOUR_S };
  }
  if (p === '/api/wifi/scan') {
    const r = await run('nmcli', ['-t', '-f', 'SSID,SIGNAL,SECURITY', 'dev', 'wifi', 'list', '--rescan', 'yes'], { timeout: 30000 });
    const vus = new Map();
    for (const [ssid, sig, secu] of r.out.trim().split('\n').filter(Boolean).map(champs))
      if (ssid && (!vus.has(ssid) || vus.get(ssid).signal < +sig)) vus.set(ssid, { ssid, signal: +sig, securite: secu || 'ouvert' });
    return { reseaux: [...vus.values()].sort((a, b) => b.signal - a.signal) };
  }
  if (p === '/api/journal') {
    exiger(JOURNAUX.includes(q.u), 'journal inconnu');
    const r = await run('journalctl', ['-u', q.u, '-n', '200', '--no-pager', '-o', 'short-iso']);
    return { texte: r.out || r.err };
  }
  if (p === '/api/maj') return enRefus(maj.etat());
  if (req.method !== 'POST') throw new Refus('méthode');
  try { return await actionPost(p, q); }
  // tout réglage est gravé aussitôt : la carte SD est en commit=600, une coupure de courant effacerait 10 min de réglages
  finally { await run('sync', []); }
}
async function actionPost(p, q) {
  switch (p) {
    case '/api/ethernet': return regleEthernet(q);
    case '/api/confirmer': await confirmer(); return {};
    case '/api/annuler': await run('systemctl', ['stop', 'pxl-admin-retour.timer']); await revenir(RETOUR); return {};
    case '/api/wifi/ajouter': return ajouterWifi(q);
    case '/api/wifi/supprimer': { const { c } = await wifiParUuid(q.uuid);
      exiger(!c.actif || q.forcer, 'c\'est le réseau Wi-Fi actif : confirme la suppression');
      const r = await run('nmcli', ['con', 'delete', c.uuid]); exiger(r.ok, r.err); return {}; }
    case '/api/wifi/priorite': { const { c } = await wifiParUuid(q.uuid);
      const r = await run('nmcli', ['con', 'modify', c.uuid, 'connection.autoconnect-priority', String(Math.max(-999, Math.min(999, Math.round(+q.priorite || 0))))]);
      exiger(r.ok, r.err); return {}; }
    case '/api/wifi/connecter': { const { w, c } = await wifiParUuid(q.uuid);
      await armerRetour({ quoi: 'wifi', avant: (w.connus.find(x => x.actif) || {}).uuid || null });
      const r = await run('nmcli', ['con', 'up', c.uuid], { timeout: 45000 });
      if (!r.ok) { await run('systemctl', ['stop', 'pxl-admin-retour.timer']); await revenir(RETOUR); throw new Refus(`connexion impossible : ${r.err}`); }
      return {}; }
    case '/api/ntp': {
      const s = liste(q.serveurs); exiger(s.length <= 6, '6 serveurs au plus'); exiger(s.every(x => estIp(x) || estHote(x)), 'adresse de serveur invalide');
      if (s.length) writeFileSync(NTP_LOCAUX, '# Serveurs de temps locaux (page /admin de la box) — ex. le PC vMix\n' + s.map(x => `server ${x} iburst\n`).join(''));
      else try { unlinkSync(NTP_LOCAUX); } catch {}
      const r = await run('chronyc', ['reload', 'sources']); exiger(r.ok, `chrony : ${r.err}`);
      await run('chronyc', ['burst', '4/4']);
      return {}; }
    case '/api/heure': {
      const ms = +q.ms; exiger(Number.isFinite(ms) && ms > Date.UTC(2024, 0, 1) && ms < Date.UTC(2100, 0, 1), 'heure invalide');
      const r = await run('date', ['-s', `@${(ms / 1000).toFixed(3)}`]); exiger(r.ok, r.err);
      return { avant_ms: Date.now() - ms }; }
    case '/api/service': exiger(RELANCABLES.includes(q.nom), 'service inconnu');
      { const r = await run('systemctl', ['restart', q.nom]); exiger(r.ok, r.err); return {}; }
    case '/api/redemarrer': setTimeout(() => run('systemctl', ['reboot']), 1500); return {};
    // extinction PROPRE : systemd arrête tout et démonte la carte SD, la façade s'éteint (pxl-facade --off) — c'est
    // le signal qu'on peut débrancher. La box ne se rallume qu'en rebranchant l'alimentation.
    case '/api/eteindre': setTimeout(() => run('systemctl', ['poweroff']), 1500); return {};
    case '/api/mode': return regleMode(q);
    case '/api/ecran': return regleEcran(q);
    case '/api/wb': return regleWb(q);
    // mises à jour depuis GitHub (maj.mjs) — une seule à la fois
    case '/api/maj/verifier': return uneMaj(() => maj.verifier(q.cible));
    case '/api/maj/appliquer': return uneMaj(() => maj.appliquer(q.cible));
    case '/api/maj/revenir': return uneMaj(() => maj.revenir(q.cible));
    case '/api/mdp': exiger(verifierMdp(q.ancien), 'ancien mot de passe faux'); ecrireMdp(q.nouveau); return {};
  }
  throw new Refus('route inconnue');
}

const corps = req => new Promise((res, rej) => { let s = ''; req.on('data', d => { s += d; if (s.length > 16384) { rej(new Refus('trop gros')); req.destroy(); } });
  req.on('end', () => { try { res(s ? JSON.parse(s) : {}); } catch { rej(new Refus('JSON invalide')); } }); });
const ENTETES = { 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'x-frame-options': 'DENY', 'referrer-policy': 'no-referrer' };
const json = (res, code, o) => { res.writeHead(code, { ...ENTETES, 'content-type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(o)); };

function serveur() {
  createServer(async (req, res) => {
    const u = new URL(req.url, 'http://x'), ip = req.socket.remoteAddress;
    try {
      if (u.pathname === '/' || u.pathname === '/admin') {
        res.writeHead(200, { ...ENTETES, 'content-type': 'text/html; charset=utf-8',
          'content-security-policy': "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'" });
        return res.end(readFileSync(join(ICI, 'admin.html')));
      }
      if (!u.pathname.startsWith('/api/')) return json(res, 404, { erreur: 'introuvable' });
      // toute écriture porte l'en-tête maison : une page d'un autre site ne peut pas l'envoyer sans autorisation CORS
      if (req.method === 'POST' && req.headers['x-pxl-admin'] !== '1') return json(res, 403, { erreur: 'en-tête manquant' });
      const q = req.method === 'POST' ? await corps(req) : Object.fromEntries(u.searchParams);
      if (u.pathname === '/api/connexion') {
        const e = essais.get(ip);
        if (e && e.jusqua > Date.now()) return json(res, 429, { erreur: `trop d'essais : réessaie dans ${Math.ceil((e.jusqua - Date.now()) / 1000)} s` });
        if (!existsSync(MDP)) return json(res, 503, { erreur: 'aucun mot de passe posé : sur la box, « pxl-kiosk mdp-admin »' });
        if (!verifierMdp(q.mdp)) {
          const n = (e?.n || 0) + 1; essais.set(ip, { n: n >= 5 ? 0 : n, jusqua: n >= 5 ? Date.now() + 60e3 : 0 });
          await new Promise(r => setTimeout(r, 500));
          return json(res, 401, { erreur: 'mot de passe faux' });
        }
        essais.delete(ip);
        res.setHeader('set-cookie', `pxladmin=${jeton()}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${DUREE_SESSION / 1000}`);
        return json(res, 200, { ok: true });
      }
      if (u.pathname === '/api/deconnexion') { res.setHeader('set-cookie', 'pxladmin=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0'); return json(res, 200, { ok: true }); }
      if (!sessionValide(req)) return json(res, 401, { erreur: 'connexion requise' });
      const r = await api(req, u, q);
      if (req.method === 'POST') console.log(`${ip} ${u.pathname}${q.mode ? ' ' + q.mode : ''}`);
      return json(res, 200, { ok: true, ...r });
    } catch (e) {
      if (!(e instanceof Refus)) console.error(e);
      return json(res, e instanceof Refus ? 400 : 500, { erreur: e.message });
    }
  }).listen(PORT, '0.0.0.0', () => console.log(`administration sur :${PORT}`));
}

// ---------------------------------------------------------------- point d'entrée
const a = process.argv.slice(2);
if (a[0] === '--mdp') {
  let s = ''; process.stdin.on('data', d => s += d).on('end', () => {
    try { ecrireMdp(s.replace(/\r?\n$/, '')); console.log('mot de passe d\'administration enregistré'); }
    catch (e) { console.error(e.message); process.exit(1); } });
} else if (a[0] === '--retour') {
  await revenir(a[1]); console.log('réglage réseau d\'avant remis');
} else serveur();
