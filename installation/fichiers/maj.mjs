// Mises à jour depuis GitHub : l'application d'habillage (« app »), la recette de la box (« box ») et la brique TurboHQ
// (« turbohq » : relais + client, 04/10/2026).
// Utilisé par admin.mjs (section « Mises à jour » de /admin) et en ligne de commande :
//   node maj.mjs verifier app|box|turbohq     node maj.mjs appliquer …     node maj.mjs revenir …
//
// Accès : une CLÉ DE DÉPLOIEMENT par dépôt (GitHub n'accepte pas la même clé sur deux dépôts), générée ici, en
// lecture seule. La clé privée ne quitte jamais la box ; on colle la clé publique dans GitHub → dépôt → Settings →
// Deploy keys. Aucun jeton à taper ni à faire transiter.
// Les clones vivent dans /opt/pxl-depots (petits : quelques Mo). L'application est RECOPIÉE de son clone vers
// APP_DIR, en gardant ce qui appartient à la box : etat-local/ (l'état de la régie), pages/photos/ et les listes de la prod
// donnees/engages-*.csv (hors git, données personnelles : sans cette exception, chaque mise à jour les EFFAÇAIT — 04/10).
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
  // TurboHQ (04/10/2026, Eliott : « mettre à jour la brique TurboHQ depuis GitHub, comme un bloc ») : le relais de la box
  // et le client qui publie le flux writeback. Jusque-là deux copies posées à la main (VERSION-PXL) — la box a tourné un
  // viewer plus récent que la branche qu'on croyait déployée sans que rien ne le dise. Pas de fichier VERSION : la
  // version est le commit. Dépôt volumineux (bancs, notes) : clone PARTIEL, seuls les deux dossiers sont lus.
  turbohq: { nom: 'TurboHQ (relais + client)', depot: conf.MAJ_DEPOT_THQ || 'DeeJayMX/PXL-TurboHQ', version: null,
    branche: conf.MAJ_BRANCHE_THQ || 'master', partiel: true },
};
const BRANCHE = conf.MAJ_BRANCHE || 'main';
const brancheDe = c => CIBLES[c].branche || BRANCHE;
const THQ = { relais: { src: 'pxl-turbohq-relay', dst: '/usr/local/lib/turbohq-relay', service: 'pxl-relais' },
  client: { src: 'pxl-turbohq-client', dst: '/usr/local/lib/pxl-kiosk/turbohq-client', service: 'pxl-wb' } };

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
    const partiel = CIBLES[c].partiel ? ['--filter=blob:none'] : [];
    let r = await run('git', ['clone', '-q', '--no-checkout', ...partiel, url(c), clone(c)], { env: gitEnv(c) });
    if (!r.ok) { r = await run('git', ['clone', '-q', '--no-checkout', ...partiel, url443(c), clone(c)], { env: gitEnv(c) }); }
    exiger(r.ok, refusLisible(c, r.err));
  }
  let r = await git(c, ['fetch', '-q', '--prune', 'origin']);
  if (!r.ok) { await git(c, ['remote', 'set-url', 'origin', url443(c)]); r = await git(c, ['fetch', '-q', '--prune', 'origin']); }
  exiger(r.ok, refusLisible(c, r.err));
}
const refusLisible = (c, err) => /Permission denied|publickey|Repository not found|not appear to be a git/i.test(err)
  ? `GitHub refuse la clé de la box pour ${CIBLES[c].depot} : colle la clé publique dans le dépôt (Settings → Deploy keys, lecture seule)`
  : /Could not resolve|timed out|Network is unreachable|Connection refused/i.test(err) ? 'GitHub injoignable (pas d\'Internet ?)' : err.slice(0, 300);

const versionDe = async (c, ref) => CIBLES[c].version ? (await git(c, ['show', `${ref}:${CIBLES[c].version}`])).out.trim() || null
  : (await git(c, ['log', '-1', '--format=%h du %cs', ref])).out.trim() || null;
// TurboHQ : « PXL-TurboHQ master 1dac63d (installé le …) », écrit dans chaque copie (à la main avant le 04/10, par poser() depuis)
const thqInstalle = () => (lire(join(THQ.relais.dst, 'VERSION-PXL')) || '').match(/^PXL-TurboHQ (\S+) ([0-9a-f]{7,40})/);
const installee = c => c === 'app' ? lire(join(APP_DIR, 'VERSION'))
  : c === 'turbohq' ? (m => m ? `${m[1]} ${m[2].slice(0, 7)}` : null)(thqInstalle())
  : (lire('/etc/pxl-kiosk/version') || '').match(/^recette=(.*)$/m)?.[1] || null;

// ---- état sans réseau : ce qui est installé, et les clés publiques à coller dans GitHub
export async function etat() {
  const n = note(), r = {};
  for (const c of Object.keys(CIBLES)) r[c] = { ...CIBLES[c], installee: installee(c), commit: n[c]?.commit || null,
    precedent: n[c]?.precedent || null, le: n[c]?.le || null, cle: await assurerCle(c), verifie: n[c]?.verifie || null };
  return r;
}

// ---- module Companion de l'habillage (04/10/2026, Eliott : « la box embarque le module directement accessible ») : construit
// par GitHub Actions et rangé sur la branche « companion-module » du dépôt de l'habillage (un .tgz + info.json). Le fetch
// habituel la ramène avec la même clé de déploiement ; on la dépose dans etat-local/companion-module/ — hors de ce que la
// mise à jour réécrit — et le serveur d'habillage la sert sur sa page d'accueil (/companion-module.tgz). Jamais bloquant :
// une branche absente (pas encore construite) ou une erreur n'empêchent pas la mise à jour de l'habillage.
const MODULE_DIR = join(APP_DIR, 'etat-local', 'companion-module');
async function moduleCompanion() {
  const ref = 'origin/companion-module';
  // explicite : un clone dont le refspec ne suivrait que main ne verrait jamais la branche (vu sur un clone de travail)
  await git('app', ['fetch', '-q', 'origin', '+refs/heads/companion-module:refs/remotes/origin/companion-module']);
  const i = await git('app', ['show', `${ref}:info.json`]);
  if (!i.ok) return null;
  let info; try { info = JSON.parse(i.out); } catch { return null; }
  let deja = {}; try { deja = JSON.parse(readFileSync(join(MODULE_DIR, 'info.json'), 'utf8')); } catch {}
  if (deja.source === info.source && deja.construit === info.construit && info.fichier && existsSync(join(MODULE_DIR, info.fichier))) return info;
  const t = MODULE_DIR + '.nouveau';
  const r = await run('bash', ['-c', `set -o pipefail; rm -rf '${t}' && mkdir -p '${t}' '${MODULE_DIR}' && git -C '${clone('app')}' archive '${ref}' | tar -x -C '${t}'`
    + ` && rm -f '${MODULE_DIR}'/*.tgz && mv '${t}'/* '${MODULE_DIR}'/ && rmdir '${t}' && chown -R pxl:pxl '${MODULE_DIR}'`]);
  if (!r.ok) return { erreur: r.err.slice(0, 200) };
  await run('sync', []);
  return info;
}

// ---- vérifier : ce qui est disponible sur GitHub, et ce que l'application coûterait au direct
export async function verifier(c) {
  exiger(CIBLES[c], 'cible inconnue');
  await recuperer(c);
  const cible = `origin/${brancheDe(c)}`, n = note();
  // TurboHQ jamais mis à jour par ici : on part du commit écrit dans VERSION-PXL (copie posée à la main)
  let depuis = n[c]?.commit;
  if (!depuis && c === 'turbohq' && thqInstalle()) depuis = (await git(c, ['rev-parse', '--verify', '-q', thqInstalle()[2] + '^{commit}'])).out.trim() || null;
  const tete = (await git(c, ['rev-parse', cible])).out.trim();
  const journal = depuis ? (await git(c, ['log', '--format=%h %s', `${depuis}..${cible}`])).out.trim()
    : (await git(c, ['log', '--format=%h %s', '-8', cible])).out.trim();
  const fichiers = depuis ? (await git(c, ['diff', '--name-only', depuis, cible])).out.trim().split('\n').filter(Boolean) : null;
  // app : ne toucher que pages/ (et la doc, et VERSION — relue par le serveur) n'oblige pas à relancer le serveur — les
  // pages se rechargent seules
  // (04/10) ni le module Companion (construit par GitHub, servi depuis etat-local/), ni les outils, ni la CI ne sont lus par
  // le serveur : les relancer renverrait l'antenne au PVW pour rien (vu en livrant le module 1.8.2 en pleine répétition)
  const sansRelance = f => f.startsWith('pages/') || /\.md$/.test(f) || f.startsWith('docs/') || f === 'VERSION'
    || f.startsWith('companion-module-urban-trail/') || (f.startsWith('outils/') && f !== 'outils/zip.js') || f.startsWith('.github/') || f.startsWith('.claude/');
  const relance = c === 'app' ? (fichiers == null || fichiers.some(f => !sansRelance(f))) : true;
  const v = { commit: tete, version: await versionDe(c, cible), a_jour: depuis === tete, journal: journal ? journal.split('\n').slice(0, 30) : [],
    fichiers: fichiers ? fichiers.length : null, relance, le: new Date().toISOString() };
  if (c === 'turbohq') Object.assign(v, await bilanThq(depuis, cible, fichiers));
  if (c === 'app') { try { const m = await moduleCompanion(); v.module = m && (m.version || m.erreur) || null; } catch (e) { v.module = 'erreur : ' + e.message; } }
  noter({ ...note(), [c]: { ...(note()[c] || {}), verifie: v } });
  return v;
}

// ---- TurboHQ : ce que coûte la mise à jour. Le relais relit ses pages (.html, .js servis) à CHAQUE requête : seules ses
// .mjs / package*.json obligent à le relancer (viewers coupés ~3 s). Le client ne sert qu'au flux writeback (pxl-wb) : ses
// bin/ et src/ obligent à relancer le flux. Le reste du dépôt (bancs, notes, autres briques) n'est jamais posé.
// 🔴 Dépendances du relais (ws) : la box n'a pas de registre npm le jour J — si elles changent, on REFUSE au lieu de
// poser un relais qui ne démarrerait pas.
async function bilanThq(depuis, cible, fichiers) {
  const de = (d, f) => (fichiers || []).filter(x => x.startsWith(d + '/')).map(x => x.slice(d.length + 1)).filter(f);
  const relais = fichiers == null || de(THQ.relais.src, x => /\.(mjs|cjs)$|^package(-lock)?\.json$/.test(x)).length > 0;
  const flux = fichiers == null || de(THQ.client.src, x => /^(bin|src)\/|^package\.json$/.test(x)).length > 0;
  const deps = async ref => { try { return JSON.stringify(JSON.parse((await git('turbohq', ['show', `${ref}:${THQ.relais.src}/package.json`])).out).dependencies || {}); } catch { return null; } };
  let ici = null; try { ici = JSON.stringify(JSON.parse(readFileSync(join(THQ.relais.dst, 'package.json'), 'utf8')).dependencies || {}); } catch {}
  const la = await deps(cible);
  return { relanceRelais: relais, relanceFlux: flux, touche: fichiers == null ? null : de(THQ.relais.src, () => true).length + de(THQ.client.src, () => true).length,
    dependances: ici != null && la != null && ici !== la ? `dépendances du relais changées (${ici} → ${la}) : npm install requis, mise à jour refusée` : null };
}

// ---- appliquer un commit (le dernier vérifié, ou un précédent pour revenir en arrière)
async function poser(c, commit) {
  if (c === 'turbohq') return poserThq(commit);
  const r = await git(c, ['-c', 'advice.detachedHead=false', 'checkout', '-q', '-f', commit]); exiger(r.ok, r.err);
  if (c === 'app') {
    const s = await run('rsync', ['-a', '--delete', '--exclude', '.git', '--exclude', 'etat-local', '--exclude', 'pages/photos',
      '--exclude', 'donnees/engages-*.csv', '--exclude', 'node_modules', clone(c) + '/', APP_DIR + '/']);
    exiger(s.ok, `rsync : ${s.err}`);
    await run('chown', ['-R', 'pxl:pxl', APP_DIR]);
    // et la SOURCE locale que installer.sh recopie (APP_SOURCE) : sinon une réinstallation de la box ramènerait
    // l'application d'avant cette mise à jour (vu au premier essai de « box » depuis /admin, 02/10)
    const src = conf.APP_SOURCE;
    if (src && src.startsWith('/') && src !== APP_DIR && existsSync(src)) {
      const t = await run('rsync', ['-a', '--delete', '--exclude', '.git', '--exclude', 'etat-local', '--exclude', 'pages/photos',
        '--exclude', 'donnees/engages-*.csv', '--exclude', 'node_modules', clone(c) + '/', src + '/']);
      exiger(t.ok, `rsync (source) : ${t.err}`);
    }
  }
}
// TurboHQ : les deux dossiers seulement, extraits par « git archive » (le clone partiel va chercher leurs fichiers, et
// rien d'autre). Recopiés SANS --delete : la copie de la box porte ce qui lui appartient (node_modules, .mbx2/,
// sauvegardes/, *.avant-*) — un fichier retiré du dépôt reste, inerte, plutôt que de risquer d'effacer de l'état.
async function poserThq(commit) {
  const t = join(DEPOTS, 'turbohq.extrait'), court = (await git('turbohq', ['rev-parse', '--short=7', commit])).out.trim();
  const a = await run('bash', ['-c', `set -o pipefail; rm -rf '${t}' && mkdir -p '${t}' && git -C '${clone('turbohq')}' archive '${commit}' ${THQ.relais.src} ${THQ.client.src} | tar -x -C '${t}'`], { env: gitEnv('turbohq') });
  exiger(a.ok, `extraction : ${a.err.slice(0, 200)}`);
  const marque = `PXL-TurboHQ ${brancheDe('turbohq')} ${court} (installé le ${new Date().toISOString()})\n`;
  for (const b of Object.values(THQ)) {
    exiger(existsSync(join(t, b.src)), `${b.src} absent du dépôt à ce commit`);
    const s = await run('rsync', ['-a', '--exclude', 'node_modules', '--exclude', '.mbx2', '--exclude', 'sauvegardes', '--exclude', 'VERSION-PXL', join(t, b.src) + '/', b.dst + '/']);
    exiger(s.ok, `rsync ${b.src} : ${s.err}`);
    writeFileSync(join(b.dst, 'VERSION-PXL'), marque);
  }
  await run('rm', ['-rf', t]);
}
// la carte SD de la box est montée en commit=600 : sans sync, une coupure de courant dans les 10 min qui suivent efface
// la mise à jour (vu le 02/10 : v1.2.6 appliquée, alimentation coupée, la box est revenue en v1.2.5)
const graver = () => run('sync', []);
// avancement affiché en popup sur l'écran de la box (le serveur d'habillage lit ce fichier) — /run : rien sur la carte SD.
// Pour « box », installer.sh prend le relais et écrit lui-même la suite.
const PROGRES = '/run/pxl-maj.json';
const progres = (cible, pct, texte, ok = null) => { try {
  writeFileSync(PROGRES + '.part', JSON.stringify({ cible, pct, texte, maj: Date.now(), fin: ok == null ? null : Date.now(), ok }), { mode: 0o644 });
  renameSync(PROGRES + '.part', PROGRES); } catch {} };
export async function appliquer(c, { commit = null, relancer = null } = {}) {
  exiger(CIBLES[c], 'cible inconnue');
  const n = note(), v = n[c]?.verifie;
  const vise = commit || v?.commit; exiger(vise, 'vérifier d\'abord ce qui est disponible');
  if (c === 'turbohq') exiger(commit || !v?.dependances, v?.dependances);
  const avant = n[c]?.commit || null;
  // TurboHQ : pas de popup sur l'écran de la box (la popup dit « Box » ou « Habillage », et rien de l'antenne ne bouge)
  if (c !== 'turbohq') progres(c, 5, c === 'app' ? 'récupération' : 'préparation');
  try { await poser(c, vise); } catch (e) { if (c !== 'turbohq') progres(c, 100, 'échec : ' + e.message.slice(0, 80), false); throw e; }
  if (c === 'app') try { await moduleCompanion(); } catch {}   // le module Companion embarqué (jamais bloquant)
  if (c !== 'turbohq') progres(c, c === 'app' ? 60 : 3, c === 'app' ? 'enregistrement' : 'préparation');
  await graver();
  noter({ ...note(), [c]: { ...(note()[c] || {}), commit: vise, precedent: avant && avant !== vise ? avant : n[c]?.precedent || null, le: new Date().toISOString() } });
  if (c === 'app') {
    await graver();
    if (relancer ?? v?.relance ?? true) {
      progres(c, 85, 'redémarrage du serveur');
      const r = await run('systemctl', ['restart', 'pxl-serveur']);
      progres(c, 100, r.ok ? 'habillage à jour' : 'redémarrage en échec', r.ok); exiger(r.ok, r.err); return { relance: true };
    }
    progres(c, 100, 'habillage à jour', true);
    return { relance: false };
  }
  if (c === 'turbohq') {
    const tout = !!commit, relances = [];   // revenir : on ne sait pas ce qui diffère, on relance les deux
    for (const [k, b] of Object.entries(THQ)) {
      if (!(tout || (k === 'relais' ? v?.relanceRelais : v?.relanceFlux) !== false)) continue;
      if ((await run('systemctl', ['is-active', b.service])).out.trim() !== 'active') continue;
      const r = await run('systemctl', ['restart', b.service]); exiger(r.ok, `${b.service} : ${r.err}`); relances.push(b.service);
    }
    return { relance: relances.length > 0, relances };
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
  if (!f) { console.log('usage : maj.mjs etat | verifier app|box|turbohq | appliquer app|box|turbohq | revenir app|box|turbohq'); process.exit(2); }
  f(c).then(r => { console.log(JSON.stringify(r, null, 1)); }).catch(e => { console.error('🔴', e.message); process.exit(1); });
}
export { Refus };
