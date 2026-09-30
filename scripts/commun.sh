#!/bin/bash
# Chemins, versions et sources — UN seul endroit. Sourcé par tous les scripts.
#
# Tout ce que la recette dépose vit sous $KIOSQUE (hors /usr), sauf :
#   - les paquets apt listés dans APT_EXECUTION / APT_COMPILATION (purgeables) ;
#   - les fichiers système du manifeste ($ETAT/manifeste), que restaurer.sh supprime.

KIOSQUE=${KIOSQUE:-/opt/pxl-kiosk}
ETAT=$KIOSQUE/etat
SRC=$KIOSQUE/src

# ── Pilote noyau Mali (kbase) ────────────────────────────────────────────────
# Arbre dont ophub tire son noyau. Le pilote y est en g29p1 (UK 11.47).
KBASE_DEPOT=https://github.com/unifreq/linux-6.1.y-rockchip.git
KBASE_KO=$KIOSQUE/kbase/bifrost_kbase.ko

# ── Xorg patché Rockchip ─────────────────────────────────────────────────────
# Branche empaquetée Debian par Rockchip, même version que le Xorg de bookworm.
XORG_DEPOT=https://github.com/JeffyCN/xorg-xserver.git
XORG_BRANCHE=rockchip/debian/21.1.7
XORG_PREFIXE=$KIOSQUE/xorg
XORG_MODULES=$XORG_PREFIXE/lib/aarch64-linux-gnu/xorg/modules

# ── Paquets Radxa (dépôt rk3588-bookworm, arm64) ─────────────────────────────
RADXA=https://radxa-repo.github.io/rk3588-bookworm/pool/main
DEB_CHROMIUM=$RADXA/c/chromium-x11/chromium-x11_126.0.6478.126_arm64.deb
DEB_V4L_RKMPP=$RADXA/libv/libv4l-rkmpp/libv4l-rkmpp_1.7.0-1_arm64.deb
DEB_LIBV4L=$RADXA/v/v4l-utils/libv4l-0_1.22.1-5_arm64.deb          # porte le patch mmap
DEB_LIBMALI=$RADXA/libm/libmali/libmali-bifrost-g52-g13p0-x11-gbm_1.9-1_arm64.deb

RACINE=$KIOSQUE/racine                     # paquets Radxa décompressés (pas installés)
LIBMALI_LD=$RACINE/usr/lib/aarch64-linux-gnu/mali:$RACINE/usr/lib/aarch64-linux-gnu
CHROMIUM=$RACINE/usr/lib/chromium/chromium-wrapper

# ── Paquets apt ──────────────────────────────────────────────────────────────
APT_EXECUTION="xserver-xorg-core xinit x11-xserver-utils libxcb-dri2-0"
APT_COMPILATION="git make gcc meson ninja-build pkg-config bison flex xfonts-utils \
 x11proto-dev xtrans-dev libxau-dev libxdmcp-dev libxfont-dev libxkbfile-dev \
 libxcvt-dev libpixman-1-dev libpciaccess-dev libudev-dev libdrm-dev libgbm-dev \
 libepoxy-dev libxshmfence-dev nettle-dev libxcb1-dev libx11-dev"

# Services de la TurboNode qui tiennent l'affichage : arrêtés pendant le kiosque.
SERVICES_AFFICHAGE=${SERVICES_AFFICHAGE:-"turbohq.service turbohq-audio.service turbohq-osd.service turbohq-menu.service"}

dire() { printf '[%s] %s\n' "$(date +%T)" "$*"; }
meurs() { dire "ERREUR : $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || meurs "à lancer en root"
mkdir -p "$ETAT"
touch "$ETAT/manifeste"
