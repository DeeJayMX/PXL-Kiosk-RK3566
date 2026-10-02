#!/bin/bash
# Avant la preview (pxl-preview.service, ExecStartPre=+ : en root) : referme l'écran de démarrage PXL.
# Weston a besoin de l'affichage (DRM) que Plymouth tient : il faut le lâcher avant. On attend d'abord que le serveur
# d'habillage réponde (90 s au plus), pour que l'écran montre le démarrage jusqu'au bout au lieu d'un fond noir.
# --retain-splash : la dernière image reste à l'écran jusqu'à ce que Weston dessine — pas de flash noir.
# Sans écran de démarrage (relance de la preview en cours de journée) : rien à faire, sortie immédiate.
plymouth --ping 2>/dev/null || exit 0
. /etc/pxl-kiosk.conf 2>/dev/null
for i in $(seq 90); do curl -sf -m 1 -o /dev/null "http://127.0.0.1:${APP_PORT:-8765}/api/sante" && break; sleep 1; done
plymouth update --status="pxl|6|1|ouverture de l'affichage…" 2>/dev/null
sleep 0.4
# la console texte (tty1) réapparaît une fraction de seconde entre Plymouth et Weston : on la vide et on masque le curseur
printf '\033[H\033[2J\033[3J\033[?25l' > /dev/tty1 2>/dev/null
plymouth quit --retain-splash 2>/dev/null
exit 0
