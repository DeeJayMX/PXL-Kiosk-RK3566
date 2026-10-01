#!/bin/bash
# Une série du banc habillage sous Weston (chroot noble) à la cadence de sortie $1 (Hz).
HZ=$1; PAGE=${2:-overlay}; R=/opt/pxl-noble
systemctl stop pxl-noble 2>/dev/null; systemctl reset-failed pxl-noble 2>/dev/null; sleep 2
rm -f $R/tmp/xdg/wayland-*
sed -i "s/^mode=.*/mode=1920x1080@$HZ/" $R/etc/xdg/weston/weston.ini
systemctl is-active -q pxl-habillage-essai || { systemctl reset-failed pxl-habillage-essai 2>/dev/null; systemd-run -q --unit=pxl-habillage-essai --working-directory=/opt/pxl-kiosk/urban-trail-2026 -E PORT=8799 -E HOST=127.0.0.1 -E REJOUER=2025-10-11T19:50:00+02:00 -E VITESSE=1 /usr/bin/node serveur.js config.chaumont2025.json; sleep 15; }
systemd-run -q --unit=pxl-noble chroot $R /usr/local/bin/kiosque.sh "http://127.0.0.1:8799/$PAGE?fond=%23707880"
for i in $(seq 40); do curl -s -o /dev/null http://127.0.0.1:9222/json/version && break; sleep 1; done; sleep 5
echo "== sortie $(grep 'Display mode' /sys/kernel/debug/dri/0/summary)"
cd /opt/pxl-kiosk && SORTIE_HZ=$HZ PAGE=$PAGE node habillage.mjs 2>&1
