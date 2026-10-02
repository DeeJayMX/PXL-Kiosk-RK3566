#!/bin/bash
# pxl-wb.sh — la sortie HDMI de la box publiée en canal TurboHQ (service pxl-wb, réglé dans /admin).
#
#   Weston (patché) → writeback NV12, sans copie → pxl-wb-enc (H.264, MPP) → thq-publish → relais TurboHQ
#
# Réglages dans /etc/pxl-kiosk.conf : WB_URL (relais, défaut celui de la box), WB_CANAL, WB_FPS, WB_DEBIT (kbit/s).
# Si l'un des deux processus meurt, l'autre suit (pipefail) et systemd relance le tout.
set -o pipefail
. /etc/pxl-kiosk.conf
URL=${WB_URL:-ws://127.0.0.1:8080}
CANAL=${WB_CANAL:-pxlnode}
FPS=${WB_FPS:-25}
DEBIT=${WB_DEBIT:-6000}
SOCK=${XDG_RUNTIME_DIR_PREVIEW:-/run/pxl-preview}/pxl-wb.sock
echo "pxl-wb : sortie HDMI → H.264 ${FPS} img/s ${DEBIT} kbit/s → $URL canal $CANAL"
/usr/local/lib/pxl-kiosk/pxl-wb-enc --socket "$SOCK" --fps "$FPS" --debit "$DEBIT" \
  | /opt/node/bin/node /usr/local/lib/pxl-kiosk/turbohq-client/bin/thq-publish.js \
      --url "$URL" --channel "$CANAL" --fps "$FPS" --pts arrivee
