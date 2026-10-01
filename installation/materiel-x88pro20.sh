#!/bin/bash
# Le matériel propre à la X88 Pro 20, qui n'est PAS dans l'image ophub : Wi-Fi SeekWave et afficheur de façade.
#   materiel-x88pro20.sh <racine-cible> [racine-source]
# Copie depuis une box qui les a déjà (par défaut la machine où l'on tourne : la TurboNode, même modèle) :
#   - pilotes Wi-Fi skw_sdio_lite + swt6621s_wifi, compilés hors arbre (PXL-TurboHQ, TurboNode/WIFI_SEEKWAVE.md),
#     valables pour UN noyau exact — la cible doit porter le même `uname -r` que la source ;
#   - firmwares SeekWave DE CETTE BOX (ceux d'une autre carte ne marchent pas — même document) ;
#   - afficheur HT1628 : binaire `ht1628` (source PXL-TurboHQ, TurboNode/noeud/ht1628.c) et son service.
# Aucun binaire n'entre dans le dépôt : ils voyagent de box à box.
set -euo pipefail
CIBLE=${1:?racine cible (ex. /mnt/image, ou / sur une box installée)}; SRC=${2:-/}
dire() { echo "[$(date +%T)] $*"; }
NOYAU=$(ls "$CIBLE/lib/modules" | head -1)
[ -d "$SRC/lib/modules/$NOYAU/updates" ] || { dire "⚠️ pas de pilotes Wi-Fi pour $NOYAU sur la source — Wi-Fi non installé"; NOYAU=; }

if [ -n "$NOYAU" ]; then
  mkdir -p "$CIBLE/lib/modules/$NOYAU/updates"
  cp "$SRC/lib/modules/$NOYAU/updates/"skw*.ko "$SRC/lib/modules/$NOYAU/updates/"swt6621s*.ko "$CIBLE/lib/modules/$NOYAU/updates/" 2>/dev/null || true
  ls "$CIBLE/lib/modules/$NOYAU/updates/"swt6621s_wifi.ko >/dev/null
  # Firmwares : les fichiers SWT6621S_* / EA6621* à la racine de /lib/firmware, et le dossier seekwave/
  cp -a "$SRC"/lib/firmware/SWT6621S_* "$SRC"/lib/firmware/EA6621* "$CIBLE/lib/firmware/" 2>/dev/null || true
  [ -d "$SRC/lib/firmware/seekwave" ] && cp -a "$SRC/lib/firmware/seekwave" "$CIBLE/lib/firmware/"
  depmod -b "$CIBLE" "$NOYAU"
  # L'ordre compte (depmod ne voit pas la dépendance de swt6621s_wifi à skw_sdio_lite) — WIFI_SEEKWAVE.md
  printf 'skw_sdio_lite\nswt6621s_wifi\n' > "$CIBLE/etc/modules-load.d/seekwave.conf"
  dire "Wi-Fi SeekWave : pilotes et firmwares posés pour $NOYAU (connexion : nmcli device wifi connect <SSID> password <…>)"
fi

if [ -x "$SRC/usr/local/bin/ht1628" ]; then
  install -m 755 "$SRC/usr/local/bin/ht1628" "$CIBLE/usr/local/bin/ht1628"
  cat > "$CIBLE/etc/systemd/system/pxl-facade.service" <<'EOF'
[Unit]
Description=PXL — afficheur de façade (HT1628) : heure, pictogrammes LAN/Wi-Fi selon l'état réel
After=systemd-timesyncd.service

[Service]
Type=simple
# Un message écrit dans /run/turbohq-facade prend la main 6 s sur l'horloge.
ExecStart=/usr/local/bin/ht1628 --service 6
ExecStopPost=-/usr/local/bin/ht1628 --off
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  mkdir -p "$CIBLE/etc/systemd/system/multi-user.target.wants"
  ln -sfn /etc/systemd/system/pxl-facade.service "$CIBLE/etc/systemd/system/multi-user.target.wants/pxl-facade.service"
  dire "façade HT1628 : binaire et service posés (pxl-facade)"
else
  dire "⚠️ pas de ht1628 sur la source — façade non installée"
fi

# ── Télécommande : table des touches de CETTE box, puis les gestes (pxl-telecommande) ─────────────────────
ICI=$(cd "$(dirname "$0")" && pwd)
if [ -f "$SRC/etc/rc_keymaps/pxl-turbonode.toml" ]; then
  mkdir -p "$CIBLE/etc/rc_keymaps"
  cp "$SRC/etc/rc_keymaps/pxl-turbonode.toml" "$CIBLE/etc/rc_keymaps/"
  # Relevée dans le DTB Android d'origine ; remplace rc-beelink-gs1 que le DTS ophub pose faute de mieux.
  grep -q "pxl-turbonode.toml" "$CIBLE/etc/rc_maps.cfg" 2>/dev/null \
    || printf '# PXL : table de la X88 Pro 20 (en-tête de pxl-turbonode.toml)\n*\trc-beelink-gs1\tpxl-turbonode.toml\n' >> "$CIBLE/etc/rc_maps.cfg"
  dire "télécommande : table de touches pxl-turbonode posée"
fi
install -m 644 "$ICI/fichiers/telecommande.mjs" "$CIBLE/usr/local/lib/pxl-kiosk/telecommande.mjs"
# Les télécommandes (IR, TV par CEC) ne parlent plus à Weston/Chromium, et ne sont plus des « boutons d'arrêt »
# pour logind : « Retour » quittait la preview, « Power » (IR ou TV) éteignait la box.
cat > "$CIBLE/etc/udev/rules.d/90-pxl-telecommande.rules" <<'REGLE'
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="gpio_ir_recv|dw_hdmi|hdmi_cec_key|bt-powerkey", ENV{LIBINPUT_IGNORE_DEVICE}="1", TAG-="power-switch"
REGLE
mkdir -p "$CIBLE/etc/systemd/logind.conf.d"
printf '[Login]\nHandlePowerKey=ignore\nHandlePowerKeyLongPress=ignore\n' > "$CIBLE/etc/systemd/logind.conf.d/pxl-telecommande.conf"
cat > "$CIBLE/etc/systemd/system/pxl-telecommande.service" <<'UNITE'
[Unit]
Description=PXL — télécommande : OK recharge la preview, Menu montre l'IP, Power 3 s redémarre
After=systemd-udevd.service pxl-preview.service

[Service]
ExecStart=/opt/node/bin/node /usr/local/lib/pxl-kiosk/telecommande.mjs
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNITE
ln -sfn /etc/systemd/system/pxl-telecommande.service "$CIBLE/etc/systemd/system/multi-user.target.wants/pxl-telecommande.service"
dire "télécommande : gestes posés (pxl-telecommande), touches retirées à Weston/Chromium et à logind"
