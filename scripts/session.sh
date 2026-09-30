#!/bin/bash
# Session X lancée par xinit (via 40-lancer-kiosque.sh). Variables : MODE, URL,
# CHROMIUM, PROFIL, LD_LIBRARY_PATH.
xset s off -dpms s noblank 2>/dev/null
SORTIE=$(xrandr | awk '/ connected/{print $1; exit}')
xrandr --output "$SORTIE" --mode "${MODE:-1920x1080}" --rate 60 2>&1

# Le lanceur Radxa ajoute déjà : --use-gl=angle --use-angle=gles-egl
# --use-cmd-decoder=passthrough --no-sandbox --ignore-gpu-blocklist
# --enable-gpu-rasterization --enable-accelerated-video-decode.
# ⚠️ --no-sandbox est hérité du paquet Radxa : acceptable sur une page de confiance,
# pas pour naviguer sur le web ouvert.
exec "$CHROMIUM" --kiosk --no-first-run --noerrdialogs --disable-infobars \
  --user-data-dir="$PROFIL" --remote-debugging-port=9222 \
  --autoplay-policy=no-user-gesture-required \
  --enable-features=AcceleratedVideoDecoder,VaapiVideoDecoder \
  "$URL"
