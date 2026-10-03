#!/bin/bash
# Session preview : Weston (kiosk-shell, sortie fixée par weston.ini) puis Chromium en Wayland.
# Lancé par pxl-preview.service (utilisateur pxl). Si l'un des deux meurt, on sort : systemd relance le tout.
. /etc/pxl-kiosk.conf
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/pxl-preview}
export LIBSEAT_BACKEND=seatd

# Mode entrelacé (1080i50) : Weston ne sait pas le choisir (il prend le 1080p50) — pxl-mode le pose d'abord, et weston.ini
# porte alors « mode=current » (installer.sh, /admin). Échec ⇒ on continue : Weston prendra le mode courant, quel qu'il soit.
case "$SORTIE_MODE" in *i@*) /usr/local/lib/pxl-kiosk/pxl-mode "$SORTIE_MODE" "${SORTIE_NOM:-HDMI-A-1}" || true ;; esac
# Entrelacé en PsF (ENTRELACE=psf, réglé dans /admin) : Weston patché se cadence à l'IMAGE (25 Hz en 1080i50) au lieu de
# la trame — Chromium dessine 25 img/s, chaque image occupe ses deux trames (écran et flux propres en mouvement). Sans le
# Weston patché, la variable est ignorée.
# ⚠ Et Weston y compose avec une fenêtre de 15 ms au lieu de 7 : à 7, une image sur ~5 ratait sa trame et retombait
# sur une trame du bas (recalage, flux à 22-23 img/s) ; mesuré 03/10 : 7 ms → 43 glissements / 10 s, 12 → 3, 15 → 1 à
# 3, 18 → 0 mais Chromium perd une image. Seulement en PsF : en 50i une trame dure 20 ms, 15 affameraient Chromium.
INI=/etc/pxl-kiosk/weston.ini
if [ "${ENTRELACE:-psf}" = psf ]; then   # PsF par défaut (décision d'Eliott, 03/10)
  export PXL_PSF=1
  INI="$XDG_RUNTIME_DIR/weston-psf.ini"
  sed '/^repaint-window=/d; s/^\[core\]$/[core]\nrepaint-window=15/' /etc/pxl-kiosk/weston.ini > "$INI"
fi

weston --config="$INI" --log="$XDG_RUNTIME_DIR/weston.log" &
WESTON=$!
for i in $(seq 100); do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 0.1; done
[ -S "$XDG_RUNTIME_DIR/wayland-1" ] || { echo "Weston n'a pas ouvert son socket — $XDG_RUNTIME_DIR/weston.log"; exit 1; }
export WAYLAND_DISPLAY=wayland-1

# Attendre le serveur d'habillage (sinon la page s'ouvre sur une erreur et ne se recharge pas d'elle-même)
for i in $(seq 60); do curl -s -o /dev/null "$PREVIEW_URL" && break; sleep 1; done

# Profil en mémoire (/run) : pas d'usure de l'eMMC, et un état neuf à chaque démarrage.
# DevTools sur 127.0.0.1:9222 seulement : sert au banc de mesure (scripts/banc/) et au diagnostic.
# Les drapeaux de décodage matériel et --ozone-platform-hint=wayland viennent de /etc/chromium.d (paquet PPA).
# --lang/--accept-lang : pages servies en français (dates, Accept-Language) et plus de bulle « traduire » sur une page
# française ; la traduction est en plus coupée par règle (/etc/chromium/policies/managed/pxl.json). Les menus de
# Chromium restent en anglais : le paquet du PPA ne livre que en-US.pak (vu le 02/10/2026) — aucun ne s'affiche en kiosque.
chromium --kiosk --no-first-run --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --lang=fr --accept-lang=fr-FR,fr \
  --user-data-dir="$XDG_RUNTIME_DIR/profil" --remote-debugging-port=9222 \
  --autoplay-policy=no-user-gesture-required "$PREVIEW_URL" &
CHROMIUM=$!

wait -n "$WESTON" "$CHROMIUM"
echo "Weston ou Chromium s'est arrêté — sortie pour relance par systemd"
kill "$WESTON" "$CHROMIUM" 2>/dev/null
exit 1
