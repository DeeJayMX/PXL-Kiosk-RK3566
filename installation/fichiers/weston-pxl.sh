#!/bin/bash
# weston-pxl.sh — Weston avec le FLUX WRITEBACK SANS COPIE (installation/patches/weston-writeback-flux.patch).
#
#   weston-pxl.sh             construire et poser le module patché si besoin (idempotent)
#   weston-pxl.sh --forcer    reconstruire même si le marqueur dit que c'est fait
#   weston-pxl.sh --retirer   revenir au module d'Ubuntu
#
# On ne reconstruit QUE le module d'affichage drm-backend.so, depuis la source Ubuntu de la version de Weston
# INSTALLÉE, avec notre patch. Il remplace celui d'Ubuntu par dpkg-divert (apt ne l'écrase pas), et Weston est tenu
# (apt-mark hold) : une mise à jour d'Ubuntu ne passe que par ce script.
# Suivre une mise à jour d'Ubuntu : `apt-mark unhold weston libweston-13-0 && apt-get install weston`, puis ce script.
# Si le patch ne s'applique plus, on GARDE le module d'Ubuntu (l'écran marche, le flux est indisponible) et on le dit :
# il faut alors fusionner le patch à la main (comme un merge), dans installation/patches/.
# Construction dans /dev/shm (RAM) : rien d'écrit sur la carte SD hormis le module (≈ 250 Kio). ≈ 1 min sur la box.
set -euo pipefail
ICI=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
PATCH=${WESTON_PXL_PATCH:-$ICI/patches/weston-writeback-flux.patch}
[ -f "$PATCH" ] || PATCH=/usr/local/lib/pxl-kiosk/weston-writeback-flux.patch
MOD=/usr/lib/aarch64-linux-gnu/libweston-13/drm-backend.so
MARQ=/etc/pxl-kiosk/weston-pxl
B=/dev/shm/weston-pxl
dire() { echo "[weston-pxl] $*"; }

if [ "${1:-}" = --retirer ]; then
  if dpkg-divert --list "$MOD" | grep -q .; then rm -f "$MOD"; dpkg-divert --quiet --remove --rename "$MOD"; fi
  apt-mark unhold weston libweston-13-0 >/dev/null 2>&1 || true
  rm -f "$MARQ"; sync; dire "module d'Ubuntu rétabli (relancer l'écran : systemctl restart pxl-preview)"; exit 0
fi

V=$(dpkg-query -W -f '${Version}' weston)
VOULU="$V $(sha256sum < "$PATCH" | cut -c1-16)"
if [ "${1:-}" != --forcer ] && [ "$(cat "$MARQ" 2>/dev/null)" = "$VOULU" ] && dpkg-divert --list "$MOD" | grep -q .; then
  dire "déjà en place ($VOULU)"; exit 0
fi

# sources Ubuntu (deb-src) et dépendances de construction — une fois
if [ ! -f /etc/apt/sources.list.d/ubuntu-src.sources ]; then
  printf 'Types: deb-src\nURIs: http://ports.ubuntu.com/\nSuites: noble noble-updates noble-security\nComponents: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
    > /etc/apt/sources.list.d/ubuntu-src.sources
  apt-get update -qq || true
fi
export DEBIAN_FRONTEND=noninteractive
dire "dépendances de construction de Weston $V…"
apt-get build-dep -y -qq "weston=$V" >/dev/null 2>&1 || apt-get build-dep -y -qq weston >/dev/null

rm -rf "$B"; mkdir -p "$B"; cd "$B"
dire "source Weston $V…"
apt-get source -qq "weston=$V" >/dev/null 2>&1
cd weston-*/
if ! patch -p1 --dry-run -s < "$PATCH" >/dev/null; then
  dire "🔴 le patch ne s'applique plus sur Weston $V — module d'Ubuntu GARDÉ, flux indisponible. Fusionner $PATCH à la main."
  rm -rf "$B"; exit 1
fi
patch -p1 -s < "$PATCH"
dire "construction du module…"
meson setup build --prefix=/usr --libdir=lib/aarch64-linux-gnu --buildtype=plain -Dc_args=-O2 \
  -Dbackend-rdp=false -Dbackend-vnc=false -Dremoting=false -Dpipewire=false -Dbackend-pipewire=false \
  -Dscreenshare=true -Dsystemd=true >/dev/null
ninja -C build libweston/backend-drm/drm-backend.so >/dev/null

dpkg-divert --list "$MOD" | grep -q . || dpkg-divert --quiet --add --rename --divert "$MOD.ubuntu" "$MOD"
install -m 644 build/libweston/backend-drm/drm-backend.so "$MOD"
apt-mark hold weston libweston-13-0 >/dev/null
echo "$VOULU" > "$MARQ"
cd /; rm -rf "$B"; sync
dire "✅ Weston $V patché (flux writeback sans copie) — effectif au prochain démarrage de l'écran"
