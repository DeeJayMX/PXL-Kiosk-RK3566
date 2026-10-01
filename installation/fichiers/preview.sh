#!/bin/bash
# Session preview : Weston (kiosk-shell, sortie fixée par weston.ini) puis Chromium en Wayland.
# Lancé par pxl-preview.service (utilisateur pxl). Si l'un des deux meurt, on sort : systemd relance le tout.
. /etc/pxl-kiosk.conf
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/pxl-preview}
export LIBSEAT_BACKEND=seatd

weston --config=/etc/pxl-kiosk/weston.ini --log="$XDG_RUNTIME_DIR/weston.log" &
WESTON=$!
for i in $(seq 100); do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 0.1; done
[ -S "$XDG_RUNTIME_DIR/wayland-1" ] || { echo "Weston n'a pas ouvert son socket — $XDG_RUNTIME_DIR/weston.log"; exit 1; }
export WAYLAND_DISPLAY=wayland-1

# Attendre le serveur d'habillage (sinon la page s'ouvre sur une erreur et ne se recharge pas d'elle-même)
for i in $(seq 60); do curl -s -o /dev/null "$PREVIEW_URL" && break; sleep 1; done

# Profil en mémoire (/run) : pas d'usure de l'eMMC, et un état neuf à chaque démarrage.
# DevTools sur 127.0.0.1:9222 seulement : sert au banc de mesure (scripts/banc/) et au diagnostic.
# Les drapeaux de décodage matériel et --ozone-platform-hint=wayland viennent de /etc/chromium.d (paquet PPA).
chromium --kiosk --no-first-run --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
  --user-data-dir="$XDG_RUNTIME_DIR/profil" --remote-debugging-port=9222 \
  --autoplay-policy=no-user-gesture-required "$PREVIEW_URL" &
CHROMIUM=$!

wait -n "$WESTON" "$CHROMIUM"
echo "Weston ou Chromium s'est arrêté — sortie pour relance par systemd"
kill "$WESTON" "$CHROMIUM" 2>/dev/null
exit 1
