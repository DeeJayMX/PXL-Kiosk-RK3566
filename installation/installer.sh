#!/bin/bash
# Installe une box RK3566 « serveur d'habillage + preview » sur Armbian/ophub **Ubuntu 24.04 (noble)**.
#
#   1. flasher l'image Ubuntu noble de la box, la démarrer, se connecter en root ;
#   2. cp installation/pxl-kiosk.conf.exemple /etc/pxl-kiosk.conf  et l'adapter ;
#   3. TS_AUTHKEY=tskey-… bash installation/installer.sh       (TS_AUTHKEY facultatif, jamais écrit sur disque)
#
# Idempotent : se relance sans dommage (mise à jour de la pile, de l'application, des services).
#   installer.sh --verifier     ne refait rien, vérifie seulement
#
# Fonctionne aussi DANS UNE IMAGE (chroot, sans systemd en marche — fabriquer-image.sh) : rien n'est démarré,
# tout est seulement activé, et Tailscale rejoint le tailnet au PREMIER DÉMARRAGE de la box.
#
# La pile (mesurée en chroot sur la TurboNode le 01/10/2026, docs/recherche/ppa_rockchip_multimedia.md) :
#   Panfrost (pilote libre du noyau) + Mesa de noble · Weston kiosk-shell · Chromium 132 rkmpp du PPA
#   liujianfeng1994/rockchip-multimedia (MPP + Wayland) · Node 22 officiel · Tailscale officiel.
# Règle d'exploitation : le SERVEUR passe avant la PREVIEW (priorités systemd), chacun relancé seul.
set -euo pipefail
ICI=$(cd "$(dirname "$0")" && pwd)
dire()  { echo "[$(date +%T)] $*"; }
meurs() { echo "🔴 $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || meurs "à lancer en root"
[ -f /etc/pxl-kiosk.conf ] || { cp "$ICI/pxl-kiosk.conf.exemple" /etc/pxl-kiosk.conf; meurs "/etc/pxl-kiosk.conf créé depuis l'exemple : l'adapter, puis relancer"; }
# 02/10 : l'écran de la box ouvre /ecran (page choisie dans la console : Preview ou Multiview) ; une conf qui pointait
# encore sur /preview y passe — même page par défaut, mais pilotable depuis la console.
sed -i -E 's#^(PREVIEW_URL="?http://127\.0\.0\.1:[0-9]+)/preview("?)$#\1/ecran\2#' /etc/pxl-kiosk.conf
. /etc/pxl-kiosk.conf
NOM_PXLNET=${NOM_PXLNET:-$NOM_MACHINE}   # nom sur le tailnet (PXLnet) : peut différer du hostname
ADMIN_PORT=${ADMIN_PORT:-8791}; SANTE_PORT=${SANTE_PORT:-8790}
. /etc/os-release
PPA=liujianfeng1994/rockchip-multimedia
LIB=/usr/local/lib/pxl-kiosk
EN_LIGNE=1; [ -d /run/systemd/system ] || EN_LIGNE=0   # 0 = dans une image en fabrication
# Avancement lu par le serveur d'habillage, qui l'affiche en popup sur l'écran de la box (preview, multiview) : /run, rien
# sur la carte SD. Un arrêt en route (set -e, meurs) le termine en erreur, sinon la popup resterait à l'écran.
PROGRES=/run/pxl-maj.json
progres() { [ $EN_LIGNE = 1 ] || return 0; local fin=null ok=null; [ "${3:-}" ] && { fin=$(date +%s%3N); ok=$3; }
  printf '{"cible":"box","pct":%s,"texte":"%s","maj":%s,"fin":%s,"ok":%s}\n' "$1" "$2" "$(date +%s%3N)" "$fin" "$ok" > "$PROGRES.part" \
    && chmod 644 "$PROGRES.part" && mv -f "$PROGRES.part" "$PROGRES"; }
PROGRES_FINI=0
trap '[ $PROGRES_FINI = 1 ] || progres 100 "mise à jour interrompue" false' EXIT
progres 3 "préparation"

verifier() {
  local ok=0
  v() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; else echo "  🔴 $1"; ok=1; fi; }
  echo "== vérification"
  v "pxl-serveur actif"                     "systemctl is-active -q pxl-serveur"
  v "serveur d'habillage répond (:$APP_PORT)" "curl -sf -o /dev/null http://127.0.0.1:$APP_PORT/api/sante"
  v "pxl-preview actif"                     "systemctl is-active -q pxl-preview"
  v "pxl-sante répond (:$SANTE_PORT)"       "curl -sf -o /dev/null http://127.0.0.1:$SANTE_PORT/sante"
  v "pxl-admin répond (:$ADMIN_PORT)"       "curl -sf -o /dev/null http://127.0.0.1:$ADMIN_PORT/"
  v "mot de passe d'administration posé"    "test -s /etc/pxl-kiosk/admin.mdp"
  v "/dev/mpp_service (décodeur matériel)"  "test -c /dev/mpp_service"
  v "/dev/video-dec0 (posé par udev)"       "test -f /dev/video-dec0"
  v "/usr/lib64/libv4l2.so (libv4l patchée)" "test -f /usr/lib64/libv4l2.so"
  v "Chromium (DevTools :9222)"             "curl -sf -o /dev/null http://127.0.0.1:9222/json/version"
  local dm; case "$SORTIE_MODE" in auto) dm= ;; *i@*) dm="${SORTIE_MODE%@*}${SORTIE_MODE#*@}" ;; *) dm="${SORTIE_MODE%@*}p${SORTIE_MODE#*@}" ;; esac
  v "sortie HDMI en $SORTIE_MODE"           "grep -q 'Display mode: $dm' /sys/kernel/debug/dri/0/summary"
  # Le rendu de la page passe-t-il par le GPU (Panfrost) et pas par SwiftShader ?
  local gl; gl=$(/opt/node/bin/node --input-type=module -e '
    const t=(await (await fetch("http://127.0.0.1:9222/json")).json()).find(t=>t.type==="page");
    const ws=new WebSocket(t.webSocketDebuggerUrl); await new Promise(r=>ws.onopen=r);
    ws.onmessage=e=>{const m=JSON.parse(e.data); if(m.id===1){console.log(m.result.result.value); process.exit(0);}};
    ws.send(JSON.stringify({id:1,method:"Runtime.evaluate",params:{returnByValue:true,expression:
      "(()=>{const g=document.createElement(\"canvas\").getContext(\"webgl\");const x=g&&g.getExtension(\"WEBGL_debug_renderer_info\");return x?g.getParameter(x.UNMASKED_RENDERER_WEBGL):\"pas de WebGL\"})()"}}));
    setTimeout(()=>process.exit(1),5000);' 2>/dev/null || true)
  echo "  rendu Chromium : ${gl:-inconnu}"
  case "$gl" in *Mali*|*Panfrost*) echo "  ✅ rendu GPU" ;; *) echo "  🔴 rendu GPU non confirmé"; ok=1 ;; esac
  tailscale status --self --peers=false 2>/dev/null | head -1 | sed 's/^/  tailscale : /' || true
  return $ok
}
[ "${1:-}" = --verifier ] && { verifier; exit $?; }

# ---- 0. la machine ------------------------------------------------------------------------------
[ "${VERSION_CODENAME:-}" = noble ] || meurs "Ubuntu 24.04 (noble) requis — ici : ${PRETTY_NAME:-?}. Les paquets du PPA demandent libc ≥ 2.38."
[ "$(uname -m)" = aarch64 ] || meurs "arm64 requis"
grep -qa rk356 /proc/device-tree/compatible || dire "⚠️ pas une RK356x (compatible : $(tr '\0' ' ' < /proc/device-tree/compatible)) — on continue"
[ -c /dev/mpp_service ] || dire "⚠️ /dev/mpp_service absent : noyau sans MPP Rockchip, pas de décodage vidéo matériel (la preview marche quand même)"
if [ $EN_LIGNE = 1 ]; then hostnamectl set-hostname "$NOM_MACHINE"
else echo "$NOM_MACHINE" > /etc/hostname; sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $NOM_MACHINE/" /etc/hosts; fi
# Fuseau : le serveur d'habillage affiche l'heure LOCALE ; l'image ophub arrive en Asia/Shanghai (vu le 01/10).
FUSEAU=${FUSEAU:-Europe/Paris}
ln -sfn "/usr/share/zoneinfo/$FUSEAU" /etc/localtime && echo "$FUSEAU" > /etc/timezone

# ---- 1. paquets : PPA Rockchip + pile d'affichage -----------------------------------------------
export DEBIAN_FRONTEND=noninteractive
progres 5 "liste des paquets"
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg rsync git xz-utils >/dev/null
if [ ! -s /etc/apt/keyrings/rockchip-multimedia.asc ]; then
  FP=$(curl -fsS "https://api.launchpad.net/1.0/~${PPA%%/*}/+archive/ubuntu/${PPA#*/}" | grep -o '"signing_key_fingerprint": "[0-9A-F]*"' | grep -o '[0-9A-F]\{40\}')
  [ -n "$FP" ] || meurs "empreinte de clé du PPA introuvable"
  mkdir -p /etc/apt/keyrings
  curl -fsS "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$FP" > /etc/apt/keyrings/rockchip-multimedia.asc
fi
echo "deb [signed-by=/etc/apt/keyrings/rockchip-multimedia.asc] https://ppa.launchpadcontent.net/$PPA/ubuntu noble main" > /etc/apt/sources.list.d/rockchip-multimedia.list
# Le PPA gagne sur Ubuntu pour ses paquets (libv4l patchée, MPP, chromium) ; il n'ajoute rien d'autre.
printf 'Package: *\nPin: release o=LP-PPA-liujianfeng1994-rockchip-multimedia\nPin-Priority: 600\n' > /etc/apt/preferences.d/rockchip-multimedia
apt-get update -qq
dire "paquets (Chromium rkmpp, MPP, libv4l, Weston, seatd)…"; progres 10 "paquets système"
# l'avancement d'apt (APT::Status-Fd : « dlstatus/pmstatus:paquet:pourcentage:… ») fait avancer la barre de 10 à 60 % :
# une étape qui installe de nouveaux paquets peut durer plusieurs minutes, et une barre figée se lit comme un plantage
apt_progres() { local t pct dernier=10 _; while IFS=: read -r t _ pct _; do case $t in dlstatus|pmstatus)
  pct=${pct%%.*}; pct=$((10 + ${pct:-0} * 50 / 100)); [ $pct -gt $dernier ] && { dernier=$pct; progres $pct "paquets système"; } ;; esac; done; }
apt-get install -y -qq --no-install-recommends -o APT::Status-Fd=3 \
  chromium chromium-sandbox libv4l-rkmpp libv4l-0t64 v4l-utils librockchip-mpp1 rockchip-multimedia-config \
  weston seatd libgl1-mesa-dri libegl-mesa0 libgbm1 fonts-dejavu-core fonts-liberation chrony bluez \
  plymouth plymouth-label gcc libc6-dev libdrm-dev librockchip-mpp-dev librga-dev \
  dnsmasq-base usbmuxd iw >/dev/null 3> >(apt_progres)   # dnsmasq-base : point d'accès de secours ; usbmuxd : partage USB iPhone   # gcc + libdrm-dev : pxl-mode (1080i), compilé ici
progres 60 "paquets système"
apt-cache policy chromium | grep -q 'Installed:.*rkmpp' || meurs "chromium installé n'est pas celui du PPA (rkmpp)"

# ---- 2. Node 24 officiel (empreinte vérifiée) --------------------------------------------------
# 24 et non plus 22 (04/10/2026) : Companion Satellite 3.4 exige Node ≥ 24.13 — un seul Node pour toute la box plutôt
# qu'un second à côté. Le serveur d'habillage et /admin ont été essayés sous 24.21 (VM, x64).
NODE_IDX=https://nodejs.org/dist/latest-v24.x
NODE_TAR=$(curl -fsS $NODE_IDX/SHASUMS256.txt | awk '/linux-arm64\.tar\.xz$/{print $2}')
NODE_VER=${NODE_TAR%-linux-arm64.tar.xz}
if [ "$(/opt/node/bin/node -v 2>/dev/null)" != "${NODE_VER#node-}" ]; then
  dire "Node ${NODE_VER#node-}…"; progres 30 "Node"
  T=$(mktemp -d); curl -fsS -o "$T/$NODE_TAR" "$NODE_IDX/$NODE_TAR"
  (cd "$T" && curl -fsS $NODE_IDX/SHASUMS256.txt | grep " $NODE_TAR\$" | sha256sum -c --quiet) || meurs "empreinte Node fausse"
  tar xJf "$T/$NODE_TAR" -C /opt && ln -sfn "/opt/$NODE_VER-linux-arm64" /opt/node && rm -rf "$T"
fi
# node / npm / npx aussi à la ligne de commande (les services, eux, appellent /opt/node/bin/node en dur) — 04/10
for b in node npm npx; do ln -sfn "/opt/node/bin/$b" "/usr/local/bin/$b"; done

# ---- 2 bis. Companion Satellite (Stream Deck USB → Companion de la régie), installé mais ARRÊTÉ : /admin l'active --
progres 33 "Companion Satellite"
SAT_NODE=/opt/node/bin/node bash "$ICI/fichiers/satellite-installer.sh" \
  || dire "⚠️ Companion Satellite non installé (Bitfocus injoignable ?) : la box marche sans, /admin le dira"

# ---- 3. Tailscale officiel ---------------------------------------------------------------------
if ! command -v tailscale >/dev/null; then
  dire "Tailscale…"; progres 35 "PXLnet"
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg > /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list > /etc/apt/sources.list.d/tailscale.list
  apt-get update -qq && apt-get install -y -qq tailscale >/dev/null
fi
systemctl enable -q tailscaled
mkdir -p /etc/pxl-kiosk
# Version de la recette (installation/VERSION) : affichée par /admin et l'écran de démarrage. Celle de l'application
# est le fichier VERSION à sa racine, recopié avec elle.
printf 'recette=%s\ninstallee=%s\n' "$(cat "$ICI/VERSION" 2>/dev/null || echo inconnue)" "$(date -Is)" > /etc/pxl-kiosk/version
if [ $EN_LIGNE = 0 ]; then
  # Dans l'image : la clé attend le premier démarrage (pxl-premier-demarrage), qui l'utilise puis l'efface.
  [ -n "${TS_AUTHKEY:-}" ] && { ( umask 077; printf '%s' "$TS_AUTHKEY" > /etc/pxl-kiosk/ts-authkey ); dire "clé Tailscale posée pour le premier démarrage"; }
elif [ -n "${TS_AUTHKEY:-}" ]; then
  systemctl start tailscaled
  tailscale up --auth-key="$TS_AUTHKEY" --hostname="$NOM_PXLNET" --ssh ${TS_TAGS:+--advertise-tags=$TS_TAGS}
else
  if tailscale status >/dev/null 2>&1; then tailscale set --hostname="$NOM_PXLNET" || dire "⚠️ nom PXLnet non posé"
  else dire "⚠️ Tailscale non connecté : relancer avec TS_AUTHKEY=… (ou « tailscale up --ssh » à la main)"; fi
fi

# ---- 4. utilisateur, application, fichiers -------------------------------------------------------
id pxl >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/pxl --shell /usr/sbin/nologin pxl
usermod -aG video,render,input pxl
mkdir -p "$LIB" /etc/pxl-kiosk "$APP_DIR"
install -m 755 "$ICI/fichiers/preview.sh" "$LIB/preview.sh"
# Règles Chromium imposées : pas de bulle de traduction sur la preview (signalée à l'écran le 02/10/2026).
mkdir -p /etc/chromium/policies/managed
printf '{\n  "TranslateEnabled": false\n}\n' > /etc/chromium/policies/managed/pxl.json
install -m 644 "$ICI/fichiers/sante.mjs"  "$LIB/sante.mjs"
install -m 644 "$ICI/fichiers/admin.mjs"  "$LIB/admin.mjs"
install -m 644 "$ICI/fichiers/admin.html" "$LIB/admin.html"
install -m 644 "$ICI/fichiers/maj.mjs"    "$LIB/maj.mjs"     # mises à jour depuis GitHub (section de /admin, pxl-kiosk maj)
install -m 755 "$ICI/fichiers/pxl-kiosk"  /usr/local/bin/pxl-kiosk
install -m 755 "$ICI/fichiers/premier-demarrage.sh" "$LIB/premier-demarrage.sh"
# require-input=false : sans clavier branché (télécommandes IR/CEC retirées à Weston), Weston refuse sinon de
# démarrer (« failed to create input devices », mesuré sur la box le 02/10/2026).
cat > /etc/pxl-kiosk/weston.ini <<EOF
[core]
require-input=false
shell=kiosk-shell.so
idle-time=0
[shell]
cursor-size=1
[output]
name=$SORTIE_NOM
mode=$(case "$SORTIE_MODE" in *i@*|auto) echo current ;; *) echo "$SORTIE_MODE" ;; esac)
max-bpc=8
EOF
{ echo "HOST=$APP_HOST"; echo "PORT=$APP_PORT"; for e in $APP_ENV; do echo "$e"; done; } > /etc/pxl-kiosk/serveur.env

# ---- 5. services : le serveur d'abord, la preview ensuite ---------------------------------------
cat > /etc/systemd/system/pxl-serveur.service <<EOF
[Unit]
Description=PXL — serveur d'habillage (pages pour vMix, console, preview)
After=network-online.target time-sync.target
Wants=network-online.target time-sync.target
[Service]
User=pxl
Group=pxl
WorkingDirectory=$APP_DIR
EnvironmentFile=/etc/pxl-kiosk/serveur.env
ExecStart=/opt/node/bin/node $APP_CMD
Restart=always
RestartSec=2
# Priorité : vMix dépend de ce processus, la preview non.
Nice=-5
CPUWeight=400
OOMScoreAdjust=-800
[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/pxl-preview.service <<EOF
[Unit]
Description=PXL — preview à l'écran (Weston + Chromium)
After=pxl-serveur.service seatd.service
Wants=seatd.service
[Service]
User=pxl
Group=pxl
SupplementaryGroups=video render input
RuntimeDirectory=pxl-preview
RuntimeDirectoryMode=0700
Environment=XDG_RUNTIME_DIR=/run/pxl-preview
# flux writeback sans copie (Weston patché, weston-pxl.sh) : socket où l'encodeur pxl-wb-enc se branche — sans
# encodeur branché, Weston n'en fait rien et ne coûte rien
Environment=PXL_WB_SOCKET=/run/pxl-preview/pxl-wb.sock
# en root (+) : referme l'écran de démarrage PXL (Plymouth tient l'affichage) une fois le serveur prêt
ExecStartPre=+$LIB/fin-ecran-demarrage.sh
TimeoutStartSec=150
ExecStart=$LIB/preview.sh
Restart=always
RestartSec=3
# Secondaire : cède le processeur au serveur, et c'est elle qu'on tue en premier si la mémoire manque.
Nice=10
CPUWeight=50
OOMScoreAdjust=500
[Install]
WantedBy=multi-user.target
EOF
# Sortie HDMI publiée en TurboHQ (réglée dans /admin : WB_ACTIF, WB_URL, WB_CANAL, WB_FPS, WB_DEBIT)
cat > /etc/systemd/system/pxl-wb.service <<EOF
[Unit]
Description=PXL — sortie HDMI de la box publiée en TurboHQ (writeback sans copie)
After=pxl-preview.service
[Service]
User=pxl
Group=pxl
SupplementaryGroups=video render
ExecStart=$LIB/pxl-wb.sh
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
# Garde HDMI : un écran rebranché laisse Weston sans image (premier commit refusé, jamais réessayé) — relance la preview
cat > /etc/systemd/system/pxl-hdmi-garde.service <<EOF
[Unit]
Description=PXL — garde HDMI : écran branché mais rien balayé ⇒ relance de la preview
After=pxl-preview.service
[Service]
ExecStart=$LIB/pxl-hdmi-garde.sh
Restart=always
RestartSec=5
Nice=5
[Install]
WantedBy=multi-user.target
EOF
# Point d'accès de secours + partage de connexion USB (pxl-reseau-secours.sh ; réglé dans /admin : AP_MODE, AP_NOM,
# AP_BANDE, mot de passe dans /etc/pxl-kiosk/ap.mdp). La veille ramène sur un Wi-Fi connu dès qu'il réapparaît.
cat > /etc/systemd/system/pxl-ap-veille.service <<EOF
[Unit]
Description=PXL — Wi-Fi : retour sur un réseau connu, sinon point d'accès de secours
After=NetworkManager.service
[Service]
Type=oneshot
ExecStart=$LIB/pxl-reseau-secours.sh veille
EOF
cat > /etc/systemd/system/pxl-ap-veille.timer <<EOF
[Unit]
Description=PXL — veille du Wi-Fi de secours (toutes les 2 min)
[Timer]
OnBootSec=90
OnUnitActiveSec=120
[Install]
WantedBy=timers.target
EOF
cat > /etc/systemd/system/pxl-sante.service <<EOF
[Unit]
Description=PXL — santé de la box en JSON (:$SANTE_PORT/sante)
After=network-online.target
[Service]
User=pxl
Group=pxl
ExecStart=/opt/node/bin/node $LIB/sante.mjs
Restart=always
RestartSec=5
Nice=5
[Install]
WantedBy=multi-user.target
EOF
# Administration par le navigateur (:$ADMIN_PORT, et :$SANTE_PORT/admin) : réseau, heure, machine. En root (nmcli,
# chronyc, date, systemctl), protégée par un mot de passe dédié — ADMIN_MDP=… à l'installation, sinon « pxl-kiosk mdp-admin ».
cat > /etc/systemd/system/pxl-admin.service <<EOF
[Unit]
Description=PXL — administration de la box (:$ADMIN_PORT) : réseau, heure, machine
After=network-online.target NetworkManager.service chrony.service
[Service]
ExecStart=/opt/node/bin/node $LIB/admin.mjs
Restart=always
RestartSec=3
Nice=5
MemoryMax=150M
[Install]
WantedBy=multi-user.target
EOF
if [ -n "${ADMIN_MDP:-}" ]; then
  printf '%s' "$ADMIN_MDP" | /opt/node/bin/node "$LIB/admin.mjs" --mdp
elif [ ! -s /etc/pxl-kiosk/admin.mdp ]; then
  dire "⚠️ pas de mot de passe d'administration : le poser avec « pxl-kiosk mdp-admin » (ou ADMIN_MDP=… à l'installation)"
fi
cat > /etc/systemd/system/pxl-premier-demarrage.service <<EOF
[Unit]
Description=PXL — premier démarrage (clés SSH propres à la box, entrée dans le tailnet)
After=network-online.target tailscaled.service
Wants=network-online.target
Before=ssh.service
[Service]
Type=oneshot
ExecStart=$LIB/premier-demarrage.sh
[Install]
WantedBy=multi-user.target
EOF
# seatd donne l'accès DRM/entrées à Weston sans session de bureau. Le paquet Ubuntu fournit l'unité ; sinon on la pose.
# Chemin LU, jamais écrit en dur : noble le met dans /usr/sbin, et /usr/bin/seatd faisait échouer seatd (203/EXEC)
# en boucle, donc la preview — vécu au premier démarrage de la box, le 02/10/2026.
SEATD=$(command -v seatd)
if ! systemctl cat seatd.service >/dev/null 2>&1; then
  printf '[Unit]\nDescription=seatd\n[Service]\nExecStart=%s -g video\nRestart=always\n[Install]\nWantedBy=multi-user.target\n' "$SEATD" > /etc/systemd/system/seatd.service
fi
mkdir -p /etc/systemd/system/seatd.service.d
printf '[Service]\nExecStart=\nExecStart=%s -g video\n' "$SEATD" > /etc/systemd/system/seatd.service.d/pxl.conf

# ---- 6. robustesse « car régie » ---------------------------------------------------------------
# Pas de bureau ni d'écran de connexion : la box démarre directement sur la preview.
systemctl set-default -q multi-user.target
couper() { for u in "$@"; do systemctl disable -q "$u" 2>/dev/null || true; [ $EN_LIGNE = 1 ] && systemctl stop "$u" 2>/dev/null || true; done; }
couper gdm3 lightdm sddm getty@tty1
# Aucune mise à jour automatique pendant une exploitation : on met à jour quand on le décide (installer.sh).
couper unattended-upgrades apt-daily.timer apt-daily-upgrade.timer
# ÉCRITURES SUR LA CARTE SD : le minimum (décision d'Eliott, 02/10/2026 — « je ne veux pas que ça écrive sans fin »).
# Mesuré sur la box le 02/10 : 856 Kio en 120 s (≈ 600 Mo/jour) — journal persistant écrit sur la carte (armbian-ramlog
# ne remonte /var/log en RAM qu'au premier démarrage), sa copie par rsyslog, le tampon de journaux de tailscaled et
# vnstat. Après les réglages ci-dessous : 0 Kio en 150 s. Le prix : le journal ne survit pas à un redémarrage.
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=64M\nForwardToSyslog=no\n' > /etc/systemd/journald.conf.d/pxl.conf
rm -rf /var/log/journal/* 2>/dev/null || true
couper rsyslog vnstat
# fake-hwclock : l'image ophub sauvegarde l'heure toutes les heures sur la carte mais a MASQUÉ sa restauration au
# démarrage (mesuré le 02/10) — des écritures qui ne servent à rien. L'heure vient de chrony (Internet ou NTP local).
couper fake-hwclock-save.timer
systemctl mask -q fake-hwclock-save.timer fake-hwclock-save.service 2>/dev/null || true
mkdir -p /etc/systemd/system/tailscaled.service.d   # tampon des journaux de Tailscale en RAM (/run/tailscale)
printf '[Service]\nEnvironment=TS_LOGS_DIR=/run/tailscale\n' > /etc/systemd/system/tailscaled.service.d/pxl-logs.conf
rm -f /var/lib/tailscale/tailscaled.log*.txt /var/lib/tailscale/tailscaled.log.conf
# Au premier démarrage, armbian-fix (ophub, lancé par armbian-firstrun) RÉGÉNÈRE le machine-id après le départ de
# journald : celui-ci écrit sous l'ancien identifiant et `journalctl` ne trouve rien (vu le 02/10/2026). On le
# relance alors, pour qu'il rouvre son journal sous le bon nom. Sans effet les démarrages suivants.
mkdir -p /etc/systemd/system/armbian-firstrun.service.d
printf '[Service]\nExecStartPost=-/bin/sh -c '"'"'test -d "/run/log/journal/$$(cat /etc/machine-id)" || systemctl restart systemd-journald'"'"'\n' \
  > /etc/systemd/system/armbian-firstrun.service.d/pxl-journal.conf
# Chien de garde matériel : si le noyau se fige, la box redémarre seule (et relance tout).
if [ -e /dev/watchdog ] || [ -e /dev/watchdog0 ]; then
  mkdir -p /etc/systemd/system.conf.d
  printf '[Manager]\nRuntimeWatchdogSec=30s\nRebootWatchdogSec=2min\n' > /etc/systemd/system.conf.d/pxl-watchdog.conf
  # Un seul maître du chien de garde : systemd. Le démon `watchdog` de l'image Armbian tournait à vide à côté, et
  # son arrêt lance wd_keepalive, qui échoue (périphérique tenu) et met le système en « degraded » (vu le 02/10).
  systemctl mask -q watchdog.service wd_keepalive.service 2>/dev/null || true
fi

# ---- 6 bis. l'heure : la box n'a PAS d'horloge sauvegardée (aucun /dev/rtc, mesuré sur la TurboNode le 01/10) ----
# Sources : Observatoire de Paris (SYRTE, référence nationale du temps), Sorbonne Université, pool français —
# testées en NTP depuis la box le 01/10 (strate 2, 5 à 6 ms). Le NTP annoncé par DHCP est déjà pris en compte
# par Ubuntu (dispatcher NetworkManager 20-chrony-dhcp → /run/chrony-dhcp).
mkdir -p /etc/chrony/sources.d
printf 'server ntp.obspm.fr iburst prefer\nserver ntp1.jussieu.fr iburst\npool fr.pool.ntp.org iburst maxsources 2\n' > /etc/chrony/sources.d/pxl-paris.sources
# Le serveur d'habillage attend l'heure (au plus 60 s : sans Internet, il démarre quand même).
systemctl enable -q chrony chrony-wait.service
mkdir -p /etc/systemd/system/chrony-wait.service.d
printf '[Service]\nTimeoutStartSec=60\n' > /etc/systemd/system/chrony-wait.service.d/pxl.conf

# ---- 6 ter. l'écran de démarrage PXL : grand logo + étapes (réseau, heure, Tailscale, serveur, preview) ----------
# Thème Plymouth « pxl » (module script). Plymouth est lancé DEPUIS LE SYSTÈME (pxl-plymouth.service) et non depuis
# l'initramfs : le paramètre « splash » ferait démarrer celui de l'initramfs, qui ne contient que le module texte, et
# reconstruire l'initramfs (uInitrd) est le seul geste de cette recette qui pourrait empêcher la box de démarrer.
# Prix : l'écran apparaît ~15 s après l'allumage (avant : le logo du U-Boot Android, en eMMC — on n'y touche pas).
T=/usr/share/plymouth/themes/pxl
mkdir -p "$T"
install -m 644 "$ICI/fichiers/plymouth-pxl/pxl.plymouth" "$ICI/fichiers/plymouth-pxl/pxl.script" "$T/"
# le logo : SVG rendu en PNG par le Chromium de la box (aucun binaire dans le dépôt), fond transparent.
# ⚠️ en 100vw/100vh et pas en 1400×780 px : en --headless=new la zone utile est plus petite que --window-size, et un
# logo en pixels fixes y sortait rogné en bas et à droite (mesuré 02/10 : « mstrs » coupé, le point manquant)
R=$(mktemp -d)
cp "$ICI/fichiers/plymouth-pxl/logo-pxl.svg" "$R/"
printf '<!doctype html><style>html,body{margin:0;background:transparent}img{display:block;width:100vw;height:100vh;object-fit:contain}</style><img src="logo-pxl.svg">' > "$R/l.html"
chromium --headless=new --no-sandbox --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --user-data-dir="$R/profil" --window-size=1400,780 --screenshot="$R/logo.png" "file://$R/l.html" >/dev/null 2>&1 || true
if [ -s "$R/logo.png" ]; then install -m 644 "$R/logo.png" "$T/logo.png"; else dire "⚠️ logo de démarrage non rendu (Chromium) : l'écran montrera « pxl mstrs. » en texte"; fi
rm -rf "$R"
printf '[Daemon]\nTheme=pxl\nShowDelay=0\nDeviceTimeout=8\n' > /etc/plymouth/plymouthd.conf
install -m 755 "$ICI/fichiers/demarrage-etapes.sh"    "$LIB/demarrage-etapes.sh"
# pxl-mode : pose un mode que Weston ne sait pas choisir (1080i50) — compilé sur la box, jamais de binaire dans le dépôt
gcc -O2 -I/usr/include/libdrm -o "$LIB/pxl-mode" "$ICI/fichiers/pxl-mode.c" -ldrm || meurs "compilation de pxl-mode impossible"
# flux TurboHQ de la sortie HDMI : encodeur (MPP, sans copie), client TurboHQ embarqué, Weston patché
gcc -O2 -o "$LIB/pxl-wb-enc" "$ICI/fichiers/pxl-wb-enc.c" -lrockchip_mpp -lrga || meurs "compilation de pxl-wb-enc impossible"
install -m 755 "$ICI/fichiers/pxl-wb.sh" "$LIB/pxl-wb.sh"
install -m 755 "$ICI/fichiers/pxl-reseau-secours.sh" "$LIB/pxl-reseau-secours.sh"
install -m 755 "$ICI/fichiers/pxl-hdmi-garde.sh" "$LIB/pxl-hdmi-garde.sh"
# le pays de la radio : sans lui (« 00 »), les canaux permis en point d'accès sont les plus restreints
echo "options cfg80211 ieee80211_regdom=FR" > /etc/modprobe.d/pxl-wifi-pays.conf
install -m 755 "$ICI/fichiers/weston-pxl.sh" "$LIB/weston-pxl.sh"
install -m 644 "$ICI/patches/weston-writeback-flux.patch" "$LIB/weston-writeback-flux.patch"
# Le client TurboHQ (thq-publish.js) vient du dépôt TurboHQ, PRIVÉ : il n'est pas dans cette recette publique. Il est
# posé à part dans $LIB/turbohq-client (copie de pxl-turbohq-client) ; absent, le flux ne démarre pas et l'admin le dit.
[ -f "$LIB/turbohq-client/bin/thq-publish.js" ] || dire "⚠️ client TurboHQ absent ($LIB/turbohq-client) : flux TurboHQ indisponible"
install -m 755 "$ICI/fichiers/fin-ecran-demarrage.sh" "$LIB/fin-ecran-demarrage.sh"
cat > /etc/systemd/system/pxl-plymouth.service <<'EOF'
[Unit]
Description=PXL — écran de démarrage (Plymouth, thème pxl), lancé depuis le système
DefaultDependencies=no
After=systemd-udev-trigger.service systemd-udevd.service
Before=pxl-etapes.service
ConditionKernelCommandLine=!plymouth.enable=0
[Service]
Type=forking
# --ignore-serial-consoles : sinon la console série (ttyS2) impose le thème texte intégré (« details forced », vu le 02/10)
ExecStart=/usr/sbin/plymouthd --mode=boot --pid-file=/run/plymouth/pid --attach-to-session --ignore-serial-consoles
ExecStartPost=-/usr/bin/plymouth show-splash
RemainAfterExit=yes
KillMode=mixed
SendSIGKILL=no
[Install]
WantedBy=sysinit.target
EOF
cat > /etc/systemd/system/pxl-etapes.service <<EOF
[Unit]
Description=PXL — étapes du démarrage sur l'écran de démarrage
After=pxl-plymouth.service
[Service]
Type=simple
ExecStart=$LIB/demarrage-etapes.sh
[Install]
WantedBy=multi-user.target
EOF
# Ubuntu referme Plymouth dès multi-user.target (bien avant l'heure et le serveur) : c'est la preview qui le referme
systemctl mask -q plymouth-quit.service plymouth-quit-wait.service 2>/dev/null || true
systemctl enable -q pxl-plymouth.service pxl-etapes.service
# Démarrage sans texte : noyau muet, pas de pingouin, pas de curseur, pas d'état systemd à l'écran (armbianEnv.txt, idempotent)
E=/boot/armbianEnv.txt
if [ -f "$E" ]; then
  # console=serial : le noyau n'écrit plus sur l'écran HDMI (le pilote Wi-Fi SKW y imprimait ses traces malgré loglevel=1,
  # et elles réapparaissaient entre les étapes et à la fermeture de l'écran de démarrage). Le port série garde tout.
  sed -i 's/^verbosity=.*/verbosity=1/; s/^bootlogo=.*/bootlogo=false/; s/^console=.*/console=serial/; /^consoleargs=/d' "$E"
  # ⚠️ une ligne « consoleargs=… console=tty0 » laissée dans armbianEnv.txt est importée telle quelle par boot.scr et
  # remet l'écran comme console malgré console=serial (mesuré 02/10 : /proc/cmdline la portait encore) — d'où le /d
  # plymouth.graphical : sans lui, plymouthd reste en mode texte (« renderers are being explicitly skipped », vu le 02/10) ;
  # PAS « splash », qui réveillerait aussi le Plymouth de l'initramfs (texte seulement)
  ARGS="quiet logo.nologo vt.global_cursor_default=0 systemd.show_status=false plymouth.ignore-serial-consoles plymouth.graphical"
  grep -q '^extraargs=' "$E" || echo 'extraargs=' >> "$E"
  for a in $ARGS; do grep -q "^extraargs=.*\b${a%%=*}\b" "$E" || sed -i "s|^extraargs=\(.*\)|extraargs=\1 $a|; s|^extraargs= |extraargs=|" "$E"; done
fi

# ---- 7. application, puis démarrage -----------------------------------------------------------
[ $EN_LIGNE = 1 ] && { systemctl daemon-reload; systemctl restart systemd-journald; }
dire "application depuis $APP_SOURCE…"; progres 65 "application d'habillage"
/usr/local/bin/pxl-kiosk maj-app >/dev/null || meurs "copie de l'application impossible"
if [ $EN_LIGNE = 0 ]; then
  systemctl enable -q seatd pxl-serveur pxl-preview pxl-sante pxl-admin pxl-hdmi-garde pxl-premier-demarrage pxl-ap-veille.timer
  dire "✅ image préparée — tout démarrera au premier démarrage de la box"; exit 0
fi
systemctl enable -q pxl-premier-demarrage
udevadm trigger --subsystem-match=misc --action=change 2>/dev/null || true   # pose /dev/video-dec0 tout de suite
systemctl enable -q seatd pxl-serveur pxl-preview pxl-sante pxl-admin pxl-hdmi-garde
# Weston patché (flux writeback sans copie) : reconstruit seulement si la version de Weston ou le patch ont changé.
# Un échec n'arrête rien : l'écran garde le Weston d'Ubuntu, seul le flux TurboHQ est indisponible.
progres 68 "Weston (flux sans copie)"
WESTON_PXL_PATCH="$ICI/patches/weston-writeback-flux.patch" bash "$ICI/fichiers/weston-pxl.sh" || dire "⚠️ Weston patché indisponible — flux TurboHQ désactivé"
if [ "${WB_ACTIF:-0}" = 1 ]; then systemctl enable -q pxl-wb; else systemctl disable -q --now pxl-wb 2>/dev/null || true; fi
# Wi-Fi de secours + partage USB : profils écrits maintenant (en « auto », la box reste sur son Wi-Fi connu)
"$LIB/pxl-reseau-secours.sh" appliquer || dire "⚠️ point d'accès de secours non configuré"
systemctl enable -q --now pxl-ap-veille.timer
progres 75 "redémarrage des services"
systemctl restart seatd pxl-serveur pxl-sante pxl-admin
sleep 3
systemctl restart pxl-preview
[ "${WB_ACTIF:-0}" = 1 ] && systemctl restart pxl-wb
systemctl restart pxl-hdmi-garde
progres 80 "démarrage de l'écran"
# attente ACTIVE : on vérifie dès que le serveur et Chromium répondent, au plus 30 s (c'était 30 s fixes, même prêts en 5)
dire "attente du démarrage (30 s au plus)…"
for i in $(seq 30); do
  # le contrôle « rendu GPU » lit une PAGE ouverte : on attend qu'il y en ait une (puis 2 s pour qu'elle se charge)
  curl -sf -o /dev/null "http://127.0.0.1:$APP_PORT/api/sante" && curl -sf http://127.0.0.1:9222/json 2>/dev/null | grep -q '"type": "page"' && { sleep 2; break; }
  sleep 1; progres $((80 + i * 15 / 30)) "démarrage de l'écran"
done
PROGRES_FINI=1
if verifier; then dire "✅ box prête — santé : http://$NOM_PXLNET:$SANTE_PORT/sante.txt (par le tailnet)"; progres 100 "box à jour" true
else dire "🔴 vérification incomplète — journalctl -u pxl-serveur -u pxl-preview"; progres 100 "vérification incomplète" false; fi
