#!/bin/bash
# Premier démarrage d'une box née d'une image (pxl-premier-demarrage.service). Rejouable sans dommage.
#  - clés SSH propres à CETTE box (l'image n'en porte pas : sinon toutes les box auraient les mêmes) ;
#  - entrée dans le tailnet avec la clé posée dans l'image, puis effacement de la clé.
. /etc/pxl-kiosk.conf
ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || ssh-keygen -A
K=/etc/pxl-kiosk/ts-authkey
if [ -s "$K" ]; then
  for i in $(seq 30); do
    tailscale status >/dev/null 2>&1 && break
    tailscale up --auth-key="$(cat "$K")" --hostname="$NOM_MACHINE" --ssh ${TS_TAGS:+--advertise-tags=$TS_TAGS} && break
    # Une clé déjà taguée impose ses tags : demander un autre tag fait échouer l'inscription. On réessaie sans.
    [ -n "${TS_TAGS:-}" ] && tailscale up --auth-key="$(cat "$K")" --hostname="$NOM_MACHINE" --ssh && break
    sleep 10
  done
  tailscale status >/dev/null 2>&1 && shred -u "$K" && echo "tailnet rejoint, clé effacée"
fi
exit 0
