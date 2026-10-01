// pxl-telecommande — les touches de la télécommande (infrarouge, et TV par HDMI-CEC) deviennent des gestes
// d'exploitation. Ces périphériques sont retirés à Weston/Chromium par une règle udev (LIBINPUT_IGNORE_DEVICE) :
// sans elle, « Retour » faisait quitter la preview à Chromium et « Power » éteignait la box (logind).
//   OK                → recharge la preview (DevTools 127.0.0.1:9222), façade « rELd »
//   Menu / Accueil    → l'adresse IP défile sur la façade, octet par octet
//   Power maintenu 3 s → redémarrage (compte à rebours 3-2-1 sur la façade, « boot ») ; relâché avant : rien
// Node ≥ 22, aucune dépendance. Tourne en root (lecture de /dev/input, redémarrage).
import { readdirSync, readFileSync, writeFileSync, createReadStream } from 'node:fs';
import { execFile } from 'node:child_process';
import { networkInterfaces } from 'node:os';

const NOMS = /^(gpio_ir_recv|dw_hdmi|hdmi_cec_key|bt-powerkey)$/;   // ce que la box appelle « télécommande »
const K = { POWER: 116, OK: 352, ENTER: 28, REPLY: 232, SELECT: 0x161, HOME: 102, MENU: 139 };
const FACADE = '/run/turbohq-facade';
const dire = m => console.log(m);
const facade = t => { try { writeFileSync(FACADE, t + '\n'); } catch {} };

async function rechargerPreview() {
  try {
    const page = (await (await fetch('http://127.0.0.1:9222/json')).json()).find(t => t.type === 'page');
    const ws = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((ok, ko) => { ws.onopen = ok; ws.onerror = ko; });
    ws.send(JSON.stringify({ id: 1, method: 'Page.reload', params: { ignoreCache: true } }));
    setTimeout(() => ws.close(), 500);
    facade('rELd'); dire('preview rechargée');
  } catch (e) { facade('Err'); dire('rechargement impossible : ' + e.message); }
}

let defilement = null;
function montrerIP() {
  const ip = Object.entries(networkInterfaces())
    .filter(([n]) => /^(eth|wlan|en|wl)/.test(n)).flatMap(([, a]) => a)
    .find(a => a.family === 'IPv4' && !a.internal)?.address;
  clearInterval(defilement);
  if (!ip) { facade('noIP'); return; }
  const pas = ['IP', ...ip.split('.')]; let i = 0;
  facade(pas[i++]);
  defilement = setInterval(() => { if (i < pas.length) facade(pas[i++]); else clearInterval(defilement); }, 1300);
  dire('IP ' + ip);
}

let compte = null;
function powerEnfonce() {
  let n = 3; facade(String(n));
  compte = setInterval(() => {
    if (--n > 0) { facade(String(n)); return; }
    clearInterval(compte); compte = null; facade('boot'); dire('redémarrage demandé (Power 3 s)');
    execFile('systemctl', ['reboot']);
  }, 1000);
}
function powerRelache() { if (compte) { clearInterval(compte); compte = null; facade('----'); } }

function ecouter(dev) {
  dire('écoute ' + dev);
  let reste = Buffer.alloc(0);
  createReadStream(dev).on('data', b => {
    reste = Buffer.concat([reste, b]);
    for (; reste.length >= 24; reste = reste.subarray(24)) {   // struct input_event, 64 bits : timeval(16) type code value
      const type = reste.readUInt16LE(16), code = reste.readUInt16LE(18), val = reste.readInt32LE(20);
      if (type !== 1) continue;                                   // EV_KEY
      if (code === K.POWER) { if (val === 1) powerEnfonce(); else if (val === 0) powerRelache(); continue; }
      if (val !== 1) continue;                                    // le reste : à l'appui seulement
      if ([K.OK, K.ENTER, K.REPLY, K.SELECT].includes(code)) rechargerPreview();
      else if (code === K.HOME || code === K.MENU) montrerIP();
    }
  }).on('error', e => { dire(`${dev} : ${e.message}`); process.exit(1); });   // systemd relance
}

const devs = readdirSync('/sys/class/input').filter(e => e.startsWith('event'))
  .filter(e => NOMS.test((() => { try { return readFileSync(`/sys/class/input/${e}/device/name`, 'utf8').trim(); } catch { return ''; } })()))
  .map(e => '/dev/input/' + e);
if (!devs.length) { dire('aucune télécommande trouvée'); setTimeout(() => process.exit(1), 30000); }
devs.forEach(ecouter);
