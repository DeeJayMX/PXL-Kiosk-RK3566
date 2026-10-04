#!/bin/bash
# Companion Satellite (Bitfocus) sur la box : les Stream Deck branchés en USB apparaissent comme surfaces dans un
# Companion distant. Build OFFICIEL, version épinglée et empreinte vérifiée — rien de compilé, rien de patché.
#
#   satellite-installer.sh            (appelé par installer.sh ; refait l'installation si la version épinglée a changé)
#
# Variables : SAT_PREFIX (/opt/companion-satellite), SAT_NODE (/opt/node/bin/node), SAT_CIBLE (linux-arm64-tgz ;
# linux-tgz pour un essai sur x64), SAT_SHA256 (empreinte du paquet de la cible), SAT_UTILISATEUR (satellite ; vide = ne
# pas créer d'utilisateur ni de service, pour un essai), SAT_CONFIG (/var/lib/pxl-satellite/satellite-config.json).
#
# Ce que fait le paquet officiel et que l'on reprend (lu dans companion-satellite 3.4.1, pi-image/update.sh, 04/10/2026) :
#   resources/app.asar → satellite/ (asar extrait) · resources/webui → webui/dist · node-runtimes/ (Node 22 et 26 des
#   modules de surface, lancés à part) · assets/ · modules/ (modules de surface intégrés, dont elgato-stream-deck).
# Le processus principal exige Node ^24.13 : c'est le Node de la box (installer.sh pose Node 24).
set -euo pipefail
SAT_VERSION=${SAT_VERSION:-v3.4.1}
SAT_CIBLE=${SAT_CIBLE:-linux-arm64-tgz}
# empreinte du paquet arm64 v3.4.1 (companion-satellite-arm64-746-e1a1dae.tar.gz), relevée le 04/10/2026
SAT_SHA256=${SAT_SHA256:-d3465ac9cf3fbebe4b72cd5804dd44f3a79a59cfcc8fb43f1592af4a3a8a0817}
SAT_PREFIX=${SAT_PREFIX:-/opt/companion-satellite}
SAT_NODE=${SAT_NODE:-/opt/node/bin/node}
SAT_UTILISATEUR=${SAT_UTILISATEUR-satellite}
SAT_CONFIG=${SAT_CONFIG:-/var/lib/pxl-satellite/satellite-config.json}
# le nom qui remonte à Companion, dans sa découverte des surfaces (mDNS) — décision d'Eliott, 04/10/2026
SAT_NOM=${SAT_NOM:-PixelMasters PXLnode}
dire()  { echo "[$(date +%T)] satellite : $*"; }
meurs() { echo "🔴 satellite : $*" >&2; exit 1; }

NODE_DIR=$(dirname "$SAT_NODE")
"$SAT_NODE" -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a > 24 || (a === 24 && b >= 13) ? 0 : 1)' \
  || meurs "Node $("$SAT_NODE" -v) : Satellite $SAT_VERSION exige Node ≥ 24.13"

if [ "$(cat "$SAT_PREFIX/BUILD" 2>/dev/null)" != "$SAT_VERSION" ]; then
  dire "Companion Satellite $SAT_VERSION ($SAT_CIBLE)…"
  URL=$(curl -fsS "https://api.bitfocus.io/v1/product/companion-satellite/packages?branch=stable&limit=20&target=$SAT_CIBLE" \
    | "$SAT_NODE" -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const p=JSON.parse(s).packages.find(p=>p.version===process.argv[1]);process.stdout.write(p?p.uri:"")})' "$SAT_VERSION")
  [ -n "$URL" ] || meurs "version $SAT_VERSION introuvable chez Bitfocus pour $SAT_CIBLE"
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  curl -fsS -o "$T/sat.tgz" "$URL" || meurs "téléchargement impossible : $URL"
  echo "$SAT_SHA256  $T/sat.tgz" | sha256sum -c --quiet || meurs "empreinte du paquet fausse ($URL)"
  mkdir "$T/x" && tar -xzf "$T/sat.tgz" --strip-components=1 -C "$T/x" --wildcards '*/resources/*' '*/50-satellite.rules'
  R="$T/x/resources"
  PATH="$NODE_DIR:$PATH" "$NODE_DIR/npx" --yes @electron/asar@3 e "$R/app.asar" "$T/app" >/dev/null || meurs "extraction de app.asar impossible"
  rm -rf "$SAT_PREFIX.nouveau"; mkdir -p "$SAT_PREFIX.nouveau/webui"
  mv "$T/app" "$SAT_PREFIX.nouveau/satellite"
  mv "$R/webui" "$SAT_PREFIX.nouveau/webui/dist"
  for d in node-runtimes assets modules; do [ -d "$R/$d" ] && mv "$R/$d" "$SAT_PREFIX.nouveau/$d"; done
  # règles udev : à la RACINE du paquet (pas dans app.asar — vu le 04/10 : satellite/assets/linux n'existe que dans les sources)
  mv "$T/x/50-satellite.rules" "$SAT_PREFIX.nouveau/50-satellite.rules"
  echo "$SAT_VERSION" > "$SAT_PREFIX.nouveau/BUILD"
  rm -rf "$SAT_PREFIX.ancien"; [ -d "$SAT_PREFIX" ] && mv "$SAT_PREFIX" "$SAT_PREFIX.ancien"
  mv "$SAT_PREFIX.nouveau" "$SAT_PREFIX"; rm -rf "$SAT_PREFIX.ancien"
fi

# configuration de départ : écrite UNE fois (ensuite c'est /admin qui la règle). API REST et interface web COUPÉES :
# elles écoutent sur toutes les interfaces sans aucun mot de passe (rest.ts, 3.4.1) — /admin écrit ce fichier et relance.
mkdir -p "$(dirname "$SAT_CONFIG")"
[ -f "$SAT_CONFIG" ] || "$SAT_NODE" -e '
  require("fs").writeFileSync(process.argv[1], JSON.stringify({ remoteProtocol: "tcp", remoteIp: "127.0.0.1", remotePort: 16622,
    remoteWsAddress: "ws://127.0.0.1:16623", installationName: process.argv[2], restEnabled: false, mdnsEnabled: true }, null, "\t") + "\n")' \
  "$SAT_CONFIG" "$SAT_NOM"

[ -n "$SAT_UTILISATEUR" ] || { dire "installé dans $SAT_PREFIX (essai : ni utilisateur ni service)"; exit 0; }

id -u "$SAT_UTILISATEUR" >/dev/null 2>&1 || useradd --system --home-dir "$(dirname "$SAT_CONFIG")" --shell /usr/sbin/nologin "$SAT_UTILISATEUR"
getent group dialout >/dev/null && usermod -aG dialout "$SAT_UTILISATEUR"   # surfaces sur port série
getent group plugdev >/dev/null && usermod -aG plugdev "$SAT_UTILISATEUR"
chown -R "$SAT_UTILISATEUR": "$(dirname "$SAT_CONFIG")"
# accès aux surfaces USB (hidraw / usb) : règles du paquet officiel, groupe « satellite »
cp "$SAT_PREFIX/50-satellite.rules" /etc/udev/rules.d/50-satellite.rules
udevadm control --reload-rules 2>/dev/null || true
cat > /etc/systemd/system/pxl-satellite.service <<EOF
[Unit]
Description=PXL — Companion Satellite (Stream Deck USB vers un Companion distant)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SAT_UTILISATEUR
WorkingDirectory=$SAT_PREFIX/satellite
ExecStart=$SAT_NODE $SAT_PREFIX/satellite/dist/main.js $SAT_CONFIG
Restart=always
RestartSec=3
KillSignal=SIGINT
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload 2>/dev/null || true
dire "prêt ($SAT_VERSION) — activé par /admin › Companion"
