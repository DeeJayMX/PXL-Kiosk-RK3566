// Mises à jour depuis GitHub : l'application d'habillage (« app ») et la recette de la box (« box »).
// Utilisé par admin.mjs (section « Mises à jour » de /admin) et en ligne de commande :
//   node maj.mjs verifier app|box     node maj.mjs appliquer app|box     node maj.mjs revenir app|box
//
// Accès : une CLÉ DE DÉPLOIEMENT par dépôt (GitHub n'accepte pas la même clé sur deux dépôts), générée ici, en
// lecture seule. La clé privée ne quitte jamais la box ; on colle la clé publique dans GitHub → dépôt → Settings →
// Deploy keys. Aucun jeton à taper ni à faire transiter.
// Les clones vivent dans /opt/pxl-depots (petits : quelques Mo). L'application est RECOPIÉE de son clone vers
// APP_DIR, en gardant ce qui appartient à la box : etat-local/ (l'état de la régie) et pages/photos/.
// Ce qui est installé (commit, et le précédent pour revenir en arrière) est noté dans /etc/pxl-kiosk/maj.json.
import { execFile } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync, renameSync } from 'node:fs';
import { join } from 'node:path';
import { hostname } from 'node:os';

const lireConf = () => { try { return Object.fromEntries(readFileSync('/etc/pxl-kiosk.conf', 'utf8').split('\n')
  .map(l => l.match(/^\s*([A-Z_]+)=("?)(.*)\2\s*$/)).filter(Boolean).map(m => [m[1], m[3]])); } catch { return {}; } };
const conf = lireConf();
const CLES = '/etc/pxl-kiosk/github', NOTE = '/etc/pxl-kiosk/maj.json', DEPOTS = '/opt/pxl-depots';
const APP_DIR = conf.APP_DIR || '/opt/pxl-app';
export const CIBLES = {
  app: { nom: 'Application d\'habillage', depot: conf.MAJ_DEPOT_APP || 'DeeJayMX/urban-trail-2026', version: 'VERSION' },
  box: { nom: 'Box (recette)', depot: conf.MAJ_DEPOT_BOX || 'DeeJayMX/PXL-Kiosk-RK3566', version: 'installation/VERSION' },
};
const BRANCHE = conf.MAJ_BRANCHE || 'main';

const run = (cmd, args, { timeout = 120000, env = {} } = {}) => new Promise(res =>
  execFile(cmd, args, { timeout, maxBuffer: 2e7, env: { ...process.env, LC_ALL: 'C', ...env } },
    (e, out, err) => res({ ok: !e, out: String(out || ''), err: String(err || (e && e.message) || '').trim() })));
class Refus extends Error {}
const exiger = (c, m) => { if (!c) throw new Refus(m); };
const lire = f => { try { return readFileSync(f, 'utf8').trim(); } catch { return null; } };
const note = () => { try { return JSON.parse(readFileSync(NOTE, 'utf8')); } catch { return {}; } };
const noter = n => { writeFileSync(NOTE + '.part', JSON.stringify(n, null, 1)); renameSync(NOTE + '.part', NOTE); };

// ---- clés de déploiement : une par dépôt, ed25519, sans phrase de passe (la box doit s'en servir seule)
const cle = c => join(CLES, `deploiement-${c}`);
async function assurerCle(c) {
  mkdirSync(CLES, { recursive: true, mode: 0o700 });
  if (!existsSync(cle(c))) {
    const r = await run('ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-C', `${hostname()} — lecture ${CIBLES[c].depot}`, '-f', cle(c)]);
    exiger(r.ok, `ssh-keygen : ${r.err}`);
  }
  return lire(cle(c) + '.pub');
}
// ssh vers GitHub : port 22, et repli sur ssh.github.com:443 si un réseau bloque le 22 (Wi-Fi d'hôtel, car régie)
const gitEnv = c => ({ GIT_SSH_COMMAND: `ssh -i ${cle(c)} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 `
  + `-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=${CLES}/known_hosts -F /dev/null` });
const url = c => `git@github.com:${CIBLES[c].depot}.git`;
const url443 = c => `ssh://git@ssh.github.com:443/${CIBLES[c].depot}.git`;
const clone = c => join(DEPOTS, c);
const git = (c, args, o = {}) => run('git', ['-C', clone(c), ...args], { ...o, env: gitEnv(c) });

async function recuperer(c) {
  await assurerCle(c);
  if (!existsSync(join(clone(c), '.git'))) {
    mkdirSync(DEPOTS, { recursive: true });
    let r = await run('git', ['clone', '-q', '--no-checkout', url(c), clone(c)], { env: gitEnv(c) });
    if (!r.ok) { r = await run('git', ['clone', '-q', '--no-checkout', url443(c), clone(c)], { env: gitEnv(c) }); }
    exiger(r.ok, refusLisible(c, r.err));
  }
  let r = await git(c, ['fetch', '-q', '--prune', 'origin']);
  if (!r.ok) { await git(c, ['remote', 'set-url', 'origin', url443(c)]); r = await git(c, ['fetch', '-q', '--prune', 'origin']); }
  exiger(r.ok, refusLisible(c, r.err));
}
const refusLisible = (c, err) => /Permission denied|publickey|Repository not found|not appear to be a git/i.test(err)
  ? `GitHub refuse la clé de la box pour ${CIBLES[c].depot} : colle la clé publique dans le dépôt (Settings → Deploy keys, lecture seule)`
  : /Could not resolve|timed out|Network is unreachable|Connection refused/i.test(err) ? 'GitHub injoignable (pas d\'Internet ?)' : err.slice(0, 300);

const versionDe = async (c, ref) => (await git(c, ['show', `${ref}:${CIBLES[c].version}`])).out.trim() || null;
const installee = c => c === 'app' ? lire(join(APP_DIR, 'VERSION'))
  : (lire('/etc/pxl-kiosk/version') || '').match(/^recette=(.*)$/m)?.[1] || null;

// ---- état sans réseau : ce qui est installé, et les clés publiques à coller dans GitHub
export async function etat() {
  const n = note(), r = {};
  for (const c of Object.keys(CIBLES)) r[c] = { ...CIBLES[c], installee: installee(c), commit: n[c]?.commit || null,
    precedent: n[c]?.precedent || null, le: n[c]?.le || null, cle: await assurerCle(c), verifie: n[c]?.verifie || null };
  return r;
}

// ---- vérifier : ce qui est disponible sur GitHub, et ce que l'application coûterait au direct
export async function verifier(c) {
  exiger(CIBLES[c], 'cible inconnue');
  await recuperer(c);
  const cible = `origin/${BRANCHE}`, n = note(), depuis = n[c]?.commit;
  const tete = (await git(c, ['rev-parse', cible])).out.trim();
  const journal = depuis ? (await git(c, ['log', '--format=%h %s', `${depuis}..${cible}`])).out.trim()
    : (await git(c, ['log', '--format=%h %s', '-8', cible])).out.trim();
  const fichiers = depuis ? (await git(c, ['diff', '--name-only', depuis, cible])).out.trim().split('\n').filter(Boolean) : null;
  // app : ne toucher que pages/ (et la doc, et VERSION — relue par le serveur) n'oblige pas à relancer le serveur — les
  // pages se rechargent seules
  const relance = c === 'app' ? (fichiers == null || fichiers.some(f => !f.startsWith('pages/') && !/\.md$/.test(f) && !f.startsWith('docs/') && f !== 'VERSION')) : true;
  const v = { commit: tete, version: await versionDe(c, cible), a_jour: depuis === tete, journal: journal ? journal.split('\n').slice(0, 30) : [],
    fichiers: fichiers ? fichiers.length : null, relance, le: new Date().toISOString() };
  noter({ ...note(), [c]: { ...(note()[c] || {}), verifie: v } });
  return v;
}

// ---- appliquer un commit (le dernier vérifié, ou un précédent pour revenir en arrière)
async function poser(c, commit) {
  const r = await git(c, ['-c', 'advice.detachedHead=false', 'checkout', '-q', '-f', commit]); exiger(r.ok, r.err);
  if (c === 'app') {
    const s = await run('rsync', ['-a', '--delete', '--exclude', '.git', '--exclude', 'etat-local', '--exclude', 'pages/photos',
      '--exclude', 'node_modules', clone(c) + '/', APP_DIR + '/']);
    exiger(s.ok, `rsync : ${s.err}`);
    await run('chown', ['-R', 'pxl:pxl', APP_DIR]);
    // et la SOURCE locale que installer.sh recopie (APP_SOURCE) : sinon une réinstallation de la box ramènerait
    // l'application d'avant cette mise à jour (vu au premier essai de « box » depuis /admin, 02/10)
    const src = conf.APP_SOURCE;
    if (src && src.startsWith('/') && src !== APP_DIR && existsSync(src)) {
      const t = await run('rsync', ['-a', '--delete', '--exclude', '.git', '--exclude', 'etat-local', '--exclude', 'pages/photos',
        '--exclude', 'node_modules', clone(c) + '/', src + '/']);
      exiger(t.ok, `rsync (source) : ${t.err}`);
    }
  }
}
// la carte SD de la box est montée en commit=600 : sans sync, une coupure de courant dans les 10 min qui suivent efface
// la mise à jour (vu le 02/10 : v1.2.6 appliquée, alimentation coupée, la box est revenue en v1.2.5)
const graver = () => run('sync', []);
export async function appliquer(c, { commit = null, relancer = null } = {}) {
  exiger(CIBLES[c], 'cible inconnue');
  const n = note(), v = n[c]?.verifie;
  const vise = commit || v?.commit; exiger(vise, 'vérifier d\'abord ce qui est disponible');
  const avant = n[c]?.commit || null;
  await poser(c, vise);
  await graver();
  noter({ ...note(), [c]: { ...(note()[c] || {}), commit: vise, precedent: avant && avant !== vise ? avant : n[c]?.precedent || null, le: new Date().toISOString() } });
  if (c === 'app') {
    await graver();
    if (relancer ?? v?.relance ?? true) { const r = await run('systemctl', ['restart', 'pxl-serveur']); exiger(r.ok, r.err); return { relance: true }; }
    return { relance: false };
  }
  // box : on rejoue installer.sh depuis le clone, dans une unité à part (elle relance aussi pxl-admin : la page perd
  // la main un moment, l'installation, elle, continue). Journal : journalctl -u pxl-maj-box
  await run('systemctl', ['reset-failed', 'pxl-maj-box']);
  const r = await run('systemd-run', ['--unit=pxl-maj-box', '--collect', 'bash', '-c', `bash ${join(clone(c), 'installation/installer.sh')}; r=$?; sync; exit $r`]);
  exiger(r.ok, r.err);
  return { relance: true, journal: 'pxl-maj-box' };
}
export async function revenir(c) {
  const p = note()[c]?.precedent; exiger(p, 'aucune version précédente notée');
  return appliquer(c, { commit: p, relancer: true });
}

// ---- ligne de commande (pxl-kiosk maj …)
if (process.argv[1] && process.argv[1].endsWith('maj.mjs')) {
  const [quoi, c] = process.argv.slice(2);
  const f = { verifier, appliquer, revenir, etat: () => etat() }[quoi];
  if (!f) { console.log('usage : maj.mjs etat | verifier app|box | appliquer app|box | revenir app|box'); process.exit(2); }
  f(c).then(r => { console.log(JSON.stringify(r, null, 1)); }).catch(e => { console.error('🔴', e.message); process.exit(1); });
}
export { Refus };
