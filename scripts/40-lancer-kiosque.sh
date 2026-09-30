#!/bin/bash
# Lance le kiosque : Xorg Rockchip + libmali + Chromium Radxa, en unité systemd
# transitoire « pxl-kiosque » (arrêt : systemctl stop pxl-kiosque).
#
#   40-lancer-kiosque.sh URL [MODE]      MODE par défaut : 1920x1080 (voir README § Sortie)
#
# DevTools écoute sur 127.0.0.1:9222 (sert au banc de mesure).
. "$(dirname "$0")/commun.sh"

URL=${1:?usage: $0 URL [MODE]}; MODE=${2:-1920x1080}
[ -c /dev/mali0 ] || meurs "kbase non chargé — 30-basculer-kbase.sh"
[ -x "$XORG_PREFIXE/bin/Xorg" ] || meurs "Xorg Rockchip absent — 20-compiler-xorg-rk.sh"
[ -e /dev/video-dec0 ] || dire "⚠️ /dev/video-dec0 absent : pas de décodage matériel (25-installer-pile.sh)"
D=$(cd "$(dirname "$0")/.." && pwd)

systemctl stop pxl-kiosque 2>/dev/null; systemctl reset-failed pxl-kiosque 2>/dev/null
# LD_LIBRARY_PATH vaut pour X ET Chromium : glamor comme Chromium doivent voir libmali.
systemd-run --unit=pxl-kiosque \
  -E LD_LIBRARY_PATH="$LIBMALI_LD" -E MODE="$MODE" -E URL="$URL" -E CHROMIUM="$CHROMIUM" \
  -E PROFIL="$KIOSQUE/profil" \
  xinit "$D/scripts/session.sh" -- "$XORG_PREFIXE/bin/Xorg" :0 vt7 -nolisten tcp \
    -modulepath "$XORG_MODULES" -config "$D/conf/xorg-rk.conf" \
    -xkbdir /usr/share/X11/xkb -logfile "$ETAT/Xorg.log" >/dev/null

for i in $(seq 30); do
  curl -s -o /dev/null http://127.0.0.1:9222/json/version && { dire "Chromium prêt en ${i} s"; exit 0; }
  sleep 1
done
meurs "Chromium ne répond pas — journalctl -u pxl-kiosque ; $ETAT/Xorg.log"
