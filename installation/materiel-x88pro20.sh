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
  printf 'skw_sdio_lite\nswt6621s_wifi\nskwbt\n' > "$CIBLE/etc/modules-load.d/seekwave.conf"
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
  # « boot » sur la façade dès l'initramfs (~9 s après le noyau au lieu de ~19 s) : archive COLLÉE à l'initramfs
  # d'origine, jamais reconstruit (voir fichiers/initramfs/facade-initramfs.sh). Le hook garde la façade si quelqu'un
  # lance un jour update-initramfs.
  install -m 755 "$(dirname "$0")/fichiers/initramfs/hook-pxl-facade" "$CIBLE/etc/initramfs-tools/hooks/pxl-facade"
  install -m 755 "$(dirname "$0")/fichiers/initramfs/init-top-pxl-facade" "$CIBLE/etc/initramfs-tools/scripts/init-top/pxl-facade"
  mkdir -p "$CIBLE/usr/local/lib/pxl-kiosk/initramfs"
  install -m 755 "$(dirname "$0")/fichiers/initramfs/facade-initramfs.sh" "$(dirname "$0")/fichiers/initramfs/init-top-pxl-facade" "$CIBLE/usr/local/lib/pxl-kiosk/initramfs/"
  if [ "$CIBLE" = / ]; then bash /usr/local/lib/pxl-kiosk/initramfs/facade-initramfs.sh
  else dire "⚠️ « boot » sur la façade : à poser SUR LA BOX (uname -r de l'hôte ≠ cible) — /usr/local/lib/pxl-kiosk/initramfs/facade-initramfs.sh"; fi
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

# ── L'heure sur la façade : « ntP » clignote tant que chrony n'est pas synchronisé ───────────────────────────
install -m 755 "$ICI/fichiers/ntp-facade.sh" "$CIBLE/usr/local/lib/pxl-kiosk/ntp-facade.sh"
cat > "$CIBLE/etc/systemd/system/pxl-ntp-facade.service" <<'UNITE'
[Unit]
Description=PXL — « ntP » clignote sur la façade tant que l'heure n'est pas synchronisée
After=pxl-facade.service chrony.service

[Service]
Type=simple
ExecStart=/usr/local/lib/pxl-kiosk/ntp-facade.sh

[Install]
WantedBy=multi-user.target
UNITE
ln -sfn /etc/systemd/system/pxl-ntp-facade.service "$CIBLE/etc/systemd/system/multi-user.target.wants/pxl-ntp-facade.service"
dire "heure : « ntP » clignotant sur la façade tant que non synchronisée (pxl-ntp-facade)"

# ── Services TurboNode repris (premier groupe : sans conflit avec la preview ni avec le réseau du car) ──────
lier() { ln -sfn "/etc/systemd/system/$1.service" "$CIBLE/etc/systemd/system/multi-user.target.wants/$1.service"; }
NOM=$(. "$CIBLE/etc/pxl-kiosk.conf" 2>/dev/null; echo "${NOM_MACHINE:-pxl-habillage}")

# Adresse de secours quand aucun DHCP ne répond. ⚠️ PAS celle de la TurboNode (.229) : .230, pour ne jamais se doubler.
if [ -x "$SRC/usr/local/bin/turbohq-secours-reseau" ]; then
  install -m 755 "$SRC/usr/local/bin/turbohq-secours-reseau" "$CIBLE/usr/local/bin/"
  printf 'SECOURS_IFACE=eth0\nSECOURS_ADR=192.168.55.230/24\nSECOURS_PERIODE=15\n' > "$CIBLE/etc/default/pxl-secours-reseau"
  sed -e 's|^ExecStart=.*|ExecStart=/usr/local/bin/turbohq-secours-reseau --veille|' "$SRC/etc/systemd/system/pxl-secours-reseau.service" > "$CIBLE/etc/systemd/system/pxl-secours-reseau.service"
  lier pxl-secours-reseau; dire "secours réseau : 192.168.55.230/24 sur eth0 quand aucun DHCP ne répond"
fi

# Nom annoncé à la TV par HDMI-CEC (14 caractères au plus), sans dépendre de turbohq (absent ici).
if [ -x "$SRC/usr/local/bin/pxl-cec-nom" ]; then
  sed 's|--osd-name "PXL TURBONODE"|--osd-name "PXL HABILLAGE"|' "$SRC/usr/local/bin/pxl-cec-nom" > "$CIBLE/usr/local/bin/pxl-cec-nom"; chmod 755 "$CIBLE/usr/local/bin/pxl-cec-nom"
  sed -e 's|^After=turbohq.service|After=pxl-preview.service|' -e '/^Wants=turbohq.service/d' "$SRC/etc/systemd/system/pxl-cec-nom.service" > "$CIBLE/etc/systemd/system/pxl-cec-nom.service"
  lier pxl-cec-nom; dire "CEC : la box s'annonce « PXL HABILLAGE »"
fi

# Relais TurboHQ (:8080). 🔴 La configuration de la TurboNode n'est PAS reprise : elle porte sa clé d'accès,
# ses certificats et son identité. Ici : le nom de la box, ni clé ni TLS (à poser plus tard : tailscale cert).
if [ -d "$SRC/usr/local/lib/turbohq-relay" ]; then
  mkdir -p "$CIBLE/usr/local/lib"; rm -rf "$CIBLE/usr/local/lib/turbohq-relay"; cp -a "$SRC/usr/local/lib/turbohq-relay" "$CIBLE/usr/local/lib/"
  printf '# Relais TurboHQ de %s — ni clé ni TLS (voir PXL-TurboHQ pxl-turbohq-relay/README.md)\nPXL_THQ_NAME=%s\n' "$NOM" "$NOM" > "$CIBLE/etc/default/pxl-relais"
  sed -e 's|/usr/bin/node|/opt/node/bin/node|' "$SRC/etc/systemd/system/pxl-relais.service" > "$CIBLE/etc/systemd/system/pxl-relais.service"
  lier pxl-relais; dire "relais TurboHQ :8080 (nom $NOM, sans clé ni TLS)"
fi

# Console web TurboHQ (:8088).
if [ -f "$SRC/usr/local/lib/turbohq/turbohq-console.mjs" ]; then
  mkdir -p "$CIBLE/usr/local/lib/turbohq"; install -m 644 "$SRC/usr/local/lib/turbohq/turbohq-console.mjs" "$CIBLE/usr/local/lib/turbohq/"
  sed -e 's|/usr/bin/node|/opt/node/bin/node|' "$SRC/etc/systemd/system/turbohq-console.service" > "$CIBLE/etc/systemd/system/turbohq-console.service"
  lier turbohq-console; dire "console TurboHQ :8088"
fi
