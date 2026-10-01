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
. /etc/pxl-kiosk.conf
. /etc/os-release
PPA=liujianfeng1994/rockchip-multimedia
LIB=/usr/local/lib/pxl-kiosk
EN_LIGNE=1; [ -d /run/systemd/system ] || EN_LIGNE=0   # 0 = dans une image en fabrication

verifier() {
  local ok=0
  v() { if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; else echo "  🔴 $1"; ok=1; fi; }
  echo "== vérification"
  v "pxl-serveur actif"                     "systemctl is-active -q pxl-serveur"
  v "serveur d'habillage répond (:$APP_PORT)" "curl -sf -o /dev/null http://127.0.0.1:$APP_PORT/api/sante"
  v "pxl-preview actif"                     "systemctl is-active -q pxl-preview"
  v "pxl-sante répond (:$SANTE_PORT)"       "curl -sf -o /dev/null http://127.0.0.1:$SANTE_PORT/sante"
  v "/dev/mpp_service (décodeur matériel)"  "test -c /dev/mpp_service"
  v "/dev/video-dec0 (posé par udev)"       "test -f /dev/video-dec0"
  v "/usr/lib64/libv4l2.so (libv4l patchée)" "test -f /usr/lib64/libv4l2.so"
  v "Chromium (DevTools :9222)"             "curl -sf -o /dev/null http://127.0.0.1:9222/json/version"
  v "sortie HDMI en $SORTIE_MODE"           "grep -q 'Display mode: ${SORTIE_MODE%@*}p${SORTIE_MODE#*@}' /sys/kernel/debug/dri/0/summary"
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
dire "paquets (Chromium rkmpp, MPP, libv4l, Weston, seatd)…"
apt-get install -y -qq --no-install-recommends \
  chromium chromium-sandbox libv4l-rkmpp libv4l-0t64 v4l-utils librockchip-mpp1 rockchip-multimedia-config \
  weston seatd libgl1-mesa-dri libegl-mesa0 libgbm1 fonts-dejavu-core fonts-liberation chrony bluez >/dev/null
apt-cache policy chromium | grep -q 'Installed:.*rkmpp' || meurs "chromium installé n'est pas celui du PPA (rkmpp)"

# ---- 2. Node 22 officiel (empreinte vérifiée) --------------------------------------------------
NODE_IDX=https://nodejs.org/dist/latest-v22.x
NODE_TAR=$(curl -fsS $NODE_IDX/SHASUMS256.txt | awk '/linux-arm64\.tar\.xz$/{print $2}')
NODE_VER=${NODE_TAR%-linux-arm64.tar.xz}
if [ "$(/opt/node/bin/node -v 2>/dev/null)" != "${NODE_VER#node-}" ]; then
  dire "Node ${NODE_VER#node-}…"
  T=$(mktemp -d); curl -fsS -o "$T/$NODE_TAR" "$NODE_IDX/$NODE_TAR"
  (cd "$T" && curl -fsS $NODE_IDX/SHASUMS256.txt | grep " $NODE_TAR\$" | sha256sum -c --quiet) || meurs "empreinte Node fausse"
  tar xJf "$T/$NODE_TAR" -C /opt && ln -sfn "/opt/$NODE_VER-linux-arm64" /opt/node && rm -rf "$T"
fi

# ---- 3. Tailscale officiel ---------------------------------------------------------------------
if ! command -v tailscale >/dev/null; then
  dire "Tailscale…"
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg > /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list > /etc/apt/sources.list.d/tailscale.list
  apt-get update -qq && apt-get install -y -qq tailscale >/dev/null
fi
systemctl enable -q tailscaled
mkdir -p /etc/pxl-kiosk
if [ $EN_LIGNE = 0 ]; then
  # Dans l'image : la clé attend le premier démarrage (pxl-premier-demarrage), qui l'utilise puis l'efface.
  [ -n "${TS_AUTHKEY:-}" ] && { ( umask 077; printf '%s' "$TS_AUTHKEY" > /etc/pxl-kiosk/ts-authkey ); dire "clé Tailscale posée pour le premier démarrage"; }
elif [ -n "${TS_AUTHKEY:-}" ]; then
  systemctl start tailscaled
  tailscale up --auth-key="$TS_AUTHKEY" --hostname="$NOM_MACHINE" --ssh ${TS_TAGS:+--advertise-tags=$TS_TAGS}
else
  tailscale status >/dev/null 2>&1 || dire "⚠️ Tailscale non connecté : relancer avec TS_AUTHKEY=… (ou « tailscale up --ssh » à la main)"
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
mode=$SORTIE_MODE
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
# Journal persistant mais borné (une coupure de courant ne doit pas effacer la cause de la panne).
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=persistent\nSystemMaxUse=200M\n' > /etc/systemd/journald.conf.d/pxl.conf
# Au premier démarrage, armbian-fix (ophub, lancé par armbian-firstrun) RÉGÉNÈRE le machine-id après le départ de
# journald : celui-ci écrit sous l'ancien identifiant et `journalctl` ne trouve rien (vu le 02/10/2026). On le
# relance alors, pour qu'il rouvre son journal sous le bon nom. Sans effet les démarrages suivants.
mkdir -p /etc/systemd/system/armbian-firstrun.service.d
printf '[Service]\nExecStartPost=-/bin/sh -c '"'"'test -d "/var/log/journal/$$(cat /etc/machine-id)" || systemctl restart systemd-journald'"'"'\n' \
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

# ---- 7. application, puis démarrage -----------------------------------------------------------
[ $EN_LIGNE = 1 ] && { systemctl daemon-reload; systemctl restart systemd-journald; }
dire "application depuis $APP_SOURCE…"
/usr/local/bin/pxl-kiosk maj-app >/dev/null || meurs "copie de l'application impossible"
if [ $EN_LIGNE = 0 ]; then
  systemctl enable -q seatd pxl-serveur pxl-preview pxl-sante pxl-premier-demarrage
  dire "✅ image préparée — tout démarrera au premier démarrage de la box"; exit 0
fi
systemctl enable -q pxl-premier-demarrage
udevadm trigger --subsystem-match=misc --action=change 2>/dev/null || true   # pose /dev/video-dec0 tout de suite
systemctl enable -q seatd pxl-serveur pxl-preview pxl-sante
systemctl restart seatd pxl-serveur pxl-sante
sleep 3
systemctl restart pxl-preview
dire "attente du démarrage (30 s)…"; sleep 30
verifier && dire "✅ box prête — santé : http://$NOM_MACHINE:$SANTE_PORT/sante.txt (par le tailnet)" \
         || dire "🔴 vérification incomplète — journalctl -u pxl-serveur -u pxl-preview"
