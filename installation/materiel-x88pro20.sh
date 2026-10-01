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
