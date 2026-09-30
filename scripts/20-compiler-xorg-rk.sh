#!/bin/bash
# Compile le serveur Xorg PATCHÉ ROCKCHIP (JeffyCN/xorg-xserver, rockchip/debian/21.1.7)
# dans $XORG_PREFIXE — le Xorg système n'est pas touché.
#
# Pourquoi : libmali en X11 exige un écran DRI2 ; le modesetting n'offre DRI2 qu'avec
# glamor ; et glamor sur libmali FAIT UN SEGFAULT avec le Xorg de Debian (mesuré
# 30/09/2026). Le fork Rockchip, lui, démarre : « glamor X acceleration enabled on
# Mali-G52 » + « [DRI2] Setup complete ». Mesuré : 9 min 39 de compilation sur la box.
. "$(dirname "$0")/commun.sh"

export DEBIAN_FRONTEND=noninteractive
dire "dépendances de compilation (purgeables par restaurer.sh)"
apt-get install -y -qq --no-install-recommends $APT_COMPILATION >/dev/null

D=$SRC/xorg
[ -d "$D/.git" ] || git clone -q --depth 1 -b "$XORG_BRANCHE" "$XORG_DEPOT" "$D"
cd "$D"
rm -rf b
# Uniquement le serveur Xorg : pas de Xvfb/Xnest/Xephyr, pas de GLX (Chromium passe
# par EGL). ⚠️ sans xfonts-utils, meson échoue sur « fontutil not found ».
meson setup b --prefix="$XORG_PREFIXE" \
  -Dxorg=true -Dxephyr=false -Dxnest=false -Dxvfb=false -Dxwin=false \
  -Dglamor=true -Dglx=false -Ddri1=false -Ddri2=true -Ddri3=true \
  -Dudev=true -Dsystemd_logind=false -Dsuid_wrapper=false -Dlibunwind=false \
  -Dsha1=libnettle -Ddocs=false -Ddevel-docs=false > "$SRC/xorg-meson.log" 2>&1 \
  || { grep -E 'ERROR' "$SRC/xorg-meson.log"; meurs "meson setup échoué"; }
dire "compilation (≈ 10 min sur 4×A55)"
nice -n 19 ninja -C b -j"$(nproc)" > "$SRC/xorg-build.log" 2>&1 || meurs "ninja échoué (voir $SRC/xorg-build.log)"
ninja -C b install > "$SRC/xorg-install.log" 2>&1

# 🔴 Piège — ce Xorg cherche xkbcomp dans SON bin/ et les règles XKB dans SON share/.
# Sans ça : « Failed to activate virtual core keyboard », erreur fatale. On le renvoie
# vers ceux du système (le lancement passe aussi -xkbdir /usr/share/X11/xkb).
ln -sf /usr/bin/xkbcomp "$XORG_PREFIXE/bin/xkbcomp"
"$XORG_PREFIXE/bin/Xorg" -version 2>&1 | head -1
ls "$XORG_MODULES/drivers/modesetting_drv.so" >/dev/null && dire "Xorg Rockchip prêt : $XORG_PREFIXE"
