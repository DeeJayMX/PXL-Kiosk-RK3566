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
SOCK=${XDG_RUNTIME_DIR_PREVIEW:-/run/pxl-preview}/pxl-wb.sock
# AUTO (04/10/2026, demande d'Eliott) : la cadence de la SORTIE, image pour image — 1080p50 → 50, 1080p60 → 60, 1080p25
# → 25 ; en entrelacé, la cadence des IMAGES (1080i50 → 25 : le flux tisse deux trames en une image). Une cadence fixe
# qui ne divise pas celle de la sortie saccade : 25 img/s demandées sur une sortie 60 Hz donnaient 14,9 img/s mesurées.
# Lue dans « mode-sortie », écrit par preview.sh après avoir posé le mode (le summary du VOP2 est en debugfs, réservé à
# root ; pxl-wb tourne en « pxl »). On attend d'abord le socket de Weston : le dossier disparaît avec la preview
# (RuntimeDirectory), donc ce qu'on lit est le mode de CETTE preview — et pxl-wb est relancé avec elle (PartOf=).
if [ "$FPS" = auto ]; then
  for i in $(seq 60); do [ -S "$SOCK" ] && break; sleep 1; done
  M=$(cat "${SOCK%/*}/mode-sortie" 2>/dev/null)       # « 1920x1080i@50 », « 1280x720@60 »
  R=${M##*@}
  case "$M" in *i@*) R=$((R / 2)) ;; esac
  [ -n "$R" ] && [ "$R" -ge 1 ] 2>/dev/null && [ "$R" -le 60 ] || R=25
  echo "pxl-wb : cadence AUTO — sortie ${M:-inconnue} → $R img/s"
  FPS=$R
fi
DEBIT=${WB_DEBIT:-6000}
CODEC=${WB_CODEC:-h264}       # h264 | hevc
# Images entre deux images clés. /admin range la durée (WB_GOP_S, secondes) : en AUTO la cadence n'est connue qu'ici.
GOP=${WB_GOP:-$FPS}; [ -n "${WB_GOP_S:-}" ] && GOP=$(awk -v f="$FPS" -v s="$WB_GOP_S" 'BEGIN { g = int(f * s + 0.5); print (g < 1 ? 1 : g) }')
RC=${WB_RC:-cbr}              # cbr | vbr
HEVC=; [ "$CODEC" = hevc ] && HEVC=--hevc
# Clé d'accès d'un relais qui en exige une (?key=, PXL_THQ_KEY côté relais) : rangée À PART, dans /etc/pxl-kiosk/wb.cle
# (0640 root:pxl, posée par /admin) — pas dans pxl-kiosk.conf, que tout le système lit. Passée par l'environnement,
# jamais sur la ligne de commande (ps la montrerait), jamais écrite dans le journal.
CLE_F=/etc/pxl-kiosk/wb.cle
[ -s "$CLE_F" ] && THQ_KEY=$(cat "$CLE_F") && export THQ_KEY
AVEC_CLE=; [ -n "${THQ_KEY:-}" ] && AVEC_CLE=" (avec clé d'accès)"
echo "pxl-wb : sortie HDMI → $CODEC ${FPS} img/s ${DEBIT} kbit/s $RC GOP $GOP → $URL canal $CANAL$AVEC_CLE"
/usr/local/lib/pxl-kiosk/pxl-wb-enc --socket "$SOCK" --fps "$FPS" --debit "$DEBIT" --codec "$CODEC" --gop "$GOP" --rc "$RC" \
  | /opt/node/bin/node /usr/local/lib/pxl-kiosk/turbohq-client/bin/thq-publish.js \
      --url "$URL" --channel "$CANAL" --fps "$FPS" --pts arrivee $HEVC
